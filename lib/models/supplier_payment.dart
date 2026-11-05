import 'package:cloud_firestore/cloud_firestore.dart';
import 'purchase_bill.dart' show PurchaseBill, round2;

// Ways the pharmacy pays a supplier
const supplierPayModes = ['Cash', 'UPI', 'Bank transfer', 'Cheque'];

// How much of one payment went to one bill
class Allocation {
  final String billId;
  final String billNumber;
  final double amount;

  Allocation(this.billId, this.billNumber, this.amount);

  Map<String, dynamic> toMap() =>
      {'billId': billId, 'billNumber': billNumber, 'amount': amount};

  factory Allocation.fromMap(Map<String, dynamic> m) => Allocation(
        m['billId'] ?? '',
        m['billNumber'] ?? '',
        (m['amount'] as num?)?.toDouble() ?? 0,
      );
}

// One payment made to a supplier (can cover several bills)
class SupplierPayment {
  String? id;
  String supplier;
  double amount;
  DateTime date;
  String mode; // Cash, UPI, Bank transfer, Cheque
  String reference; // UTR / cheque number
  String note;
  List<Allocation> allocations;
  double advance; // part of the payment not matched to any bill
  String addedBy;

  SupplierPayment({
    this.id,
    required this.supplier,
    required this.amount,
    required this.date,
    this.mode = 'Cash',
    this.reference = '',
    this.note = '',
    this.allocations = const [],
    this.advance = 0,
    this.addedBy = '',
  });

  Map<String, dynamic> toMap() => {
        'supplier': supplier,
        'amount': amount,
        'date': Timestamp.fromDate(date),
        'mode': mode,
        'reference': reference,
        'note': note,
        'allocations': allocations.map((a) => a.toMap()).toList(),
        'advance': advance,
        'addedBy': addedBy,
        'createdAt': FieldValue.serverTimestamp(),
      };

  factory SupplierPayment.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return SupplierPayment(
      id: doc.id,
      supplier: d['supplier'] ?? '',
      amount: (d['amount'] as num?)?.toDouble() ?? 0,
      date: (d['date'] as Timestamp).toDate(),
      mode: d['mode'] ?? 'Cash',
      reference: d['reference'] ?? '',
      note: d['note'] ?? '',
      allocations: ((d['allocations'] as List?) ?? [])
          .map((a) => Allocation.fromMap(Map<String, dynamic>.from(a)))
          .toList(),
      advance: (d['advance'] as num?)?.toDouble() ?? 0,
      addedBy: d['addedBy'] ?? '',
    );
  }
}

// Split [amount] across unpaid [bills], OLDEST bill first (how suppliers
// usually adjust payments). Whatever is left over is an advance.
({List<Allocation> allocations, double advance}) allocatePayment(
    double amount, List<PurchaseBill> bills) {
  final unpaid = bills.where((b) => !b.isPaid).toList()
    ..sort((a, b) => a.billDate.compareTo(b.billDate));
  var left = round2(amount);
  final result = <Allocation>[];
  for (final bill in unpaid) {
    if (left <= 0) break;
    final pay = left < bill.balance ? left : bill.balance;
    result.add(Allocation(bill.id ?? '', bill.billNumber, round2(pay)));
    left = round2(left - pay);
  }
  return (allocations: result, advance: left);
}

// Everything owed to one supplier, worked out from their bills
class SupplierDue {
  final String supplier;
  final List<PurchaseBill> bills;

  SupplierDue(this.supplier, this.bills);

  double get billed => bills.fold(0, (t, b) => t + b.total);
  double get paid => bills.fold(0, (t, b) => t + b.paid);
  double get outstanding => bills.fold(0, (t, b) => t + b.balance);
  int get unpaidCount => bills.where((b) => !b.isPaid).length;
  int get maxOverdueDays =>
      bills.fold(0, (m, b) => b.overdueDays() > m ? b.overdueDays() : m);
  double get overdueAmount =>
      bills.where((b) => b.overdueDays() > 0).fold(0, (t, b) => t + b.balance);
}

// Group bills by supplier, most owed first
List<SupplierDue> groupBySupplier(List<PurchaseBill> bills) {
  final map = <String, List<PurchaseBill>>{};
  for (final b in bills) {
    map.putIfAbsent(b.supplier.trim(), () => []).add(b);
  }
  final list = map.entries.map((e) => SupplierDue(e.key, e.value)).toList()
    ..sort((a, b) => b.outstanding.compareTo(a.outstanding));
  return list;
}
