import 'package:cloud_firestore/cloud_firestore.dart';

// The three warning levels shown in the app
enum ExpiryStatus { expired, soon, safe }

// How many days before expiry counts as "expiring soon"
const int soonDays = 30;

class StockItem {
  String? id; // Firestore document ID
  String name; // e.g. "Paracetamol 650"
  String batch; // batch number printed on the strip/box
  int quantity; // how many strips/boxes/bottles
  DateTime expiry; // expiry date

  // Filled in when the stock came from a purchase bill (optional)
  double? rate; // purchase rate per unit, in ₹
  double? mrp; // maximum retail price per unit, in ₹
  String? supplier; // who supplied it
  String? billId; // which purchase bill it came from
  String? hsn; // HSN code, printed on the sale bill
  String? pack; // pack size, e.g. "10's"
  double? gstPct; // GST %, used to split GST out of the MRP on a sale
  // Real cost of ONE unit before GST, after trade discount and free goods
  // (e.g. 10 bought at Rs.20 + 2 free = Rs.200 / 12 = Rs.16.67). Used for profit.
  double? costRate;

  StockItem({
    this.id,
    required this.name,
    required this.batch,
    required this.quantity,
    required this.expiry,
    this.rate,
    this.mrp,
    this.supplier,
    this.billId,
    this.hsn,
    this.pack,
    this.gstPct,
    this.costRate,
  });

  // Cost per unit for profit: the real cost if known, else the bill rate
  double? get unitCost => costRate ?? rate;

  // Days from [today] until expiry (negative = already expired)
  int daysLeft([DateTime? today]) {
    final now = today ?? DateTime.now();
    final from = DateTime(now.year, now.month, now.day);
    final to = DateTime(expiry.year, expiry.month, expiry.day);
    return to.difference(from).inDays;
  }

  // Which warning level this batch is at
  ExpiryStatus status([DateTime? today]) {
    final days = daysLeft(today);
    if (days < 0) return ExpiryStatus.expired;
    if (days <= soonDays) return ExpiryStatus.soon;
    return ExpiryStatus.safe;
  }

  // Value of this batch at purchase rate (0 if no rate was recorded)
  double get stockValue => (rate ?? 0) * quantity;

  // Convert to what Firestore stores (optional fields only when present)
  Map<String, dynamic> toMap() => {
        'name': name,
        'batch': batch,
        'quantity': quantity,
        'expiry': Timestamp.fromDate(expiry),
        if (rate != null) 'rate': rate,
        if (mrp != null) 'mrp': mrp,
        if (supplier != null) 'supplier': supplier,
        if (billId != null) 'billId': billId,
        if (hsn != null) 'hsn': hsn,
        if (pack != null) 'pack': pack,
        if (gstPct != null) 'gstPct': gstPct,
        if (costRate != null) 'costRate': costRate,
      };

  // Build a StockItem from a Firestore document
  factory StockItem.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return StockItem(
      id: doc.id,
      name: data['name'] ?? '',
      batch: data['batch'] ?? '',
      quantity: (data['quantity'] as num?)?.toInt() ?? 0,
      expiry: (data['expiry'] as Timestamp).toDate(),
      rate: (data['rate'] as num?)?.toDouble(),
      mrp: (data['mrp'] as num?)?.toDouble(),
      supplier: data['supplier'] as String?,
      billId: data['billId'] as String?,
      hsn: data['hsn'] as String?,
      pack: data['pack'] as String?,
      gstPct: (data['gstPct'] as num?)?.toDouble(),
      costRate: (data['costRate'] as num?)?.toDouble(),
    );
  }
}
