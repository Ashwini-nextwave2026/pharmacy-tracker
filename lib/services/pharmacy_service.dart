import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/purchase_bill.dart';
import '../models/supplier_payment.dart';

// Everything about pharmacies, members and invite codes lives here,
// so the screens don't need to know how Firestore is organised.
class PharmacyService {
  static final _db = FirebaseFirestore.instance;

  static String get uid => FirebaseAuth.instance.currentUser!.uid;
  static String? get email => FirebaseAuth.instance.currentUser!.email;

  // ---- Where things are stored ----
  static DocumentReference<Map<String, dynamic>> userRef([String? id]) =>
      _db.collection('users').doc(id ?? uid);

  static DocumentReference<Map<String, dynamic>> pharmacyRef(String pharmacyId) =>
      _db.collection('pharmacies').doc(pharmacyId);

  static CollectionReference<Map<String, dynamic>> membersRef(String pharmacyId) =>
      pharmacyRef(pharmacyId).collection('members');

  static CollectionReference<Map<String, dynamic>> stockRef(String pharmacyId) =>
      pharmacyRef(pharmacyId).collection('stock');

  static CollectionReference<Map<String, dynamic>> billsRef(String pharmacyId) =>
      pharmacyRef(pharmacyId).collection('bills');

  static DocumentReference<Map<String, dynamic>> inviteRef(String code) =>
      _db.collection('inviteCodes').doc(code);

  // A 6-character code without look-alike letters (no O/0, I/1)
  static String _newCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }

  // ---- Owner creates a pharmacy ----
  static Future<void> createPharmacy({
    required String pharmacyName,
    required String userName,
  }) async {
    // Pick a code nobody else is using
    String code;
    do {
      code = _newCode();
    } while ((await inviteRef(code).get()).exists);

    final pRef = _db.collection('pharmacies').doc(); // new pharmacy ID
    final batch = _db.batch();
    batch.set(pRef, {
      'name': pharmacyName,
      'ownerId': uid,
      'inviteCode': code,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(membersRef(pRef.id).doc(uid), {
      'name': userName,
      'email': email,
      'role': 'owner',
      'joinedAt': FieldValue.serverTimestamp(),
    });
    batch.set(inviteRef(code), {'pharmacyId': pRef.id});
    batch.set(userRef(), {
      'name': userName,
      'email': email,
      'pharmacyId': pRef.id,
    });
    await batch.commit(); // all four saved together, or none
  }

  // ---- Staff joins with an invite code ----
  static Future<void> joinPharmacy({
    required String code,
    required String userName,
  }) async {
    final cleanCode = code.trim().toUpperCase();
    final codeDoc = await inviteRef(cleanCode).get();
    if (!codeDoc.exists) {
      throw Exception('Invite code not found. Please check it with the owner.');
    }
    final pharmacyId = codeDoc.data()!['pharmacyId'] as String;

    final batch = _db.batch();
    batch.set(membersRef(pharmacyId).doc(uid), {
      'name': userName,
      'email': email,
      'role': 'staff',
      'inviteCode': cleanCode, // the security rules check this matches
      'joinedAt': FieldValue.serverTimestamp(),
    });
    batch.set(userRef(), {
      'name': userName,
      'email': email,
      'pharmacyId': pharmacyId,
    });
    await batch.commit();
  }

  // ---- Leave (used after being removed, to join another pharmacy) ----
  static Future<void> leavePharmacy() =>
      userRef().update({'pharmacyId': FieldValue.delete()});

  // ---- Owner removes a staff member ----
  static Future<void> removeMember(String pharmacyId, String memberUid) =>
      membersRef(pharmacyId).doc(memberUid).delete();

  // ---- Shop expenses (rent, electricity, salary...) ----
  static CollectionReference<Map<String, dynamic>> expensesRef(String pharmacyId) =>
      pharmacyRef(pharmacyId).collection('expenses');

  // ---- Supplier payments ----
  static CollectionReference<Map<String, dynamic>> paymentsRef(String pharmacyId) =>
      pharmacyRef(pharmacyId).collection('payments');

  // All bills from one supplier
  static Future<List<PurchaseBill>> supplierBills(String pharmacyId, String supplier) async {
    final snap =
        await billsRef(pharmacyId).where('supplier', isEqualTo: supplier).get();
    return snap.docs.map(PurchaseBill.fromFirestore).toList();
  }

  // Record a payment to a supplier and mark bills paid, oldest first.
  // Pass [onlyBillId] to put the whole payment against one bill.
  // Runs as a transaction, so bills and the payment are saved together.
  static Future<SupplierPayment> recordSupplierPayment({
    required String pharmacyId,
    required SupplierPayment payment,
    String? onlyBillId,
  }) async {
    // 1. Find this supplier's bills (queries can't run inside a transaction)
    var bills = await supplierBills(pharmacyId, payment.supplier);
    if (onlyBillId != null) bills = bills.where((b) => b.id == onlyBillId).toList();

    return _db.runTransaction<SupplierPayment>((tx) async {
      // 2. Re-read each unpaid bill inside the transaction, for fresh "paid"
      final fresh = <PurchaseBill>[];
      for (final b in bills.where((b) => !b.isPaid)) {
        final snap = await tx.get(billsRef(pharmacyId).doc(b.id));
        if (snap.exists) fresh.add(PurchaseBill.fromFirestore(snap));
      }

      // 3. Split the amount across them, oldest first
      final split = allocatePayment(payment.amount, fresh);
      payment.allocations = split.allocations;
      payment.advance = split.advance;

      // 4. Write: each bill's paid amount, then the payment itself
      for (final a in split.allocations) {
        tx.update(billsRef(pharmacyId).doc(a.billId), {
          'paid': FieldValue.increment(a.amount),
        });
      }
      final ref = paymentsRef(pharmacyId).doc();
      tx.set(ref, payment.toMap());
      payment.id = ref.id;
      return payment;
    });
  }

  // ---- Sales ----
  static CollectionReference<Map<String, dynamic>> salesRef(String pharmacyId) =>
      pharmacyRef(pharmacyId).collection('sales');

  // Holds the last sale bill number, so numbers go S-0001, S-0002, ...
  static DocumentReference<Map<String, dynamic>> saleCounterRef(
          String pharmacyId) =>
      pharmacyRef(pharmacyId).collection('counters').doc('sales');

  // Save a sale AND reduce stock, all in one transaction.
  // If two people sell the same batch at once, Firestore re-runs it,
  // so stock can never go below zero. Returns the new sale's ID.
  static Future<String> saveSale(
      String pharmacyId, Map<String, dynamic> sale, List<Map<String, dynamic>> lines) {
    return _db.runTransaction<String>((tx) async {
      // 1. Read everything first (Firestore requires reads before writes)
      final counterRef = saleCounterRef(pharmacyId);
      final counterSnap = await tx.get(counterRef);

      // Add up quantity per batch, in case the same batch is on two lines
      final needed = <String, int>{};
      for (final line in lines) {
        final id = line['stockId'] as String;
        needed[id] = (needed[id] ?? 0) + (line['quantity'] as int);
      }
      final stockSnaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final id in needed.keys) {
        stockSnaps[id] = await tx.get(stockRef(pharmacyId).doc(id));
      }

      // 2. Check there is enough stock of every batch
      for (final entry in needed.entries) {
        final snap = stockSnaps[entry.key]!;
        if (!snap.exists) {
          throw Exception('A batch on this bill was deleted from stock.');
        }
        final have = (snap.data()!['quantity'] as num?)?.toInt() ?? 0;
        if (have < entry.value) {
          throw Exception(
              'Only $have left of ${snap.data()!['name']} (batch ${snap.data()!['batch']}).');
        }
      }

      // 3. Next bill number
      final last = (counterSnap.data()?['last'] as num?)?.toInt() ?? 0;
      final number = last + 1;
      final billNumber = 'S-${number.toString().padLeft(4, '0')}';

      // 4. Write: counter, stock, and the sale itself
      tx.set(counterRef, {'last': number});
      for (final entry in needed.entries) {
        tx.update(stockRef(pharmacyId).doc(entry.key), {
          'quantity': FieldValue.increment(-entry.value),
        });
      }
      final saleRef = salesRef(pharmacyId).doc();
      tx.set(saleRef, {...sale, 'billNumber': billNumber});
      return saleRef.id;
    });
  }
}
