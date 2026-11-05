import 'package:cloud_firestore/cloud_firestore.dart';

// Round money to paise (2 decimals), so 10.004999 shows and adds as 10.00
double round2(double value) => (value * 100).roundToDouble() / 100;

// GST rates offered in the app. Most medicines are 5% since Sept 2025,
// some life-saving drugs are 0%, and 12% is kept for older bills.
const gstRates = [0.0, 5.0, 12.0, 18.0];

// One line on a purchase bill: a single medicine batch, laid out like
// the paper bill: HSN, pack, batch, expiry, qty, free, rate, disc %, GST %, MRP
class BillLine {
  String name;
  String hsn; // HSN code printed on the bill, e.g. 3004
  String pack; // pack size, e.g. "10's" or "100ml"
  String batch;
  DateTime expiry;
  int quantity; // units charged for
  int free; // free units given by the supplier (not charged)
  double rate; // purchase rate per unit, before GST, in ₹
  double discountPct; // trade discount %
  double gstPct; // GST % (CGST + SGST together)
  double mrp; // maximum retail price per unit (includes GST), in ₹

  BillLine({
    required this.name,
    this.hsn = '',
    this.pack = '',
    required this.batch,
    required this.expiry,
    required this.quantity,
    this.free = 0,
    required this.rate,
    this.discountPct = 0,
    this.gstPct = 0,
    required this.mrp,
  });

  // The maths, step by step
  double get gross => quantity * rate; // qty × rate
  double get discount => gross * discountPct / 100; // less discount
  double get taxable => gross - discount; // value GST is charged on
  double get gstAmount => taxable * gstPct / 100; // the GST itself
  double get amount => taxable + gstAmount; // line total with GST

  int get unitsIn => quantity + free; // what actually goes into stock

  Map<String, dynamic> toMap() => {
        'name': name,
        'hsn': hsn,
        'pack': pack,
        'batch': batch,
        'expiry': Timestamp.fromDate(expiry),
        'quantity': quantity,
        'free': free,
        'rate': rate,
        'discountPct': discountPct,
        'gstPct': gstPct,
        'mrp': mrp,
      };

  // Old bills (saved before GST was added) simply get 0 for the new fields
  factory BillLine.fromMap(Map<String, dynamic> map) => BillLine(
        name: map['name'] ?? '',
        hsn: map['hsn'] ?? '',
        pack: map['pack'] ?? '',
        batch: map['batch'] ?? '',
        expiry: (map['expiry'] as Timestamp).toDate(),
        quantity: (map['quantity'] as num?)?.toInt() ?? 0,
        free: (map['free'] as num?)?.toInt() ?? 0,
        rate: (map['rate'] as num?)?.toDouble() ?? 0,
        discountPct: (map['discountPct'] as num?)?.toDouble() ?? 0,
        gstPct: (map['gstPct'] as num?)?.toDouble() ?? 0,
        mrp: (map['mrp'] as num?)?.toDouble() ?? 0,
      );
}

// Taxable value and GST for one GST rate, used for the summary table
class GstSlab {
  final double rate;
  double taxable = 0;
  double tax = 0;

  GstSlab(this.rate);
}

// Group lines by GST rate: {5.0: slab, 12.0: slab, ...}, lowest rate first
List<GstSlab> slabsFor(Iterable<({double rate, double taxable, double tax})> parts) {
  final map = <double, GstSlab>{};
  for (final p in parts) {
    final slab = map.putIfAbsent(p.rate, () => GstSlab(p.rate));
    slab.taxable += p.taxable;
    slab.tax += p.tax;
  }
  final list = map.values.toList()..sort((a, b) => a.rate.compareTo(b.rate));
  return list;
}

// A whole purchase bill from a supplier
class PurchaseBill {
  String? id;
  String supplier;
  String supplierGstin; // supplier's GST number (optional)
  String billNumber;
  DateTime billDate;
  bool interState; // supplier in another state: IGST instead of CGST + SGST
  List<BillLine> lines;
  int creditDays; // days the supplier gives to pay; 0 = pay on delivery
  double paid; // how much has been paid against this bill so far

  PurchaseBill({
    this.id,
    required this.supplier,
    this.supplierGstin = '',
    required this.billNumber,
    required this.billDate,
    this.interState = false,
    required this.lines,
    this.creditDays = 30,
    this.paid = 0,
  });

  // ---- Payment status ----
  DateTime get dueDate => billDate.add(Duration(days: creditDays));
  double get balance => round2(total - paid) < 0 ? 0 : round2(total - paid);
  bool get isPaid => balance <= 0.5; // allow a few paise of rounding
  bool get isPartPaid => !isPaid && paid > 0;

  // Days past the due date (0 if not overdue or already paid)
  int overdueDays([DateTime? today]) {
    if (isPaid) return 0;
    final now = today ?? DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(dueDate.year, dueDate.month, dueDate.day))
        .inDays;
    return days > 0 ? days : 0;
  }

  String get statusLabel => isPaid ? 'Paid' : (isPartPaid ? 'Part paid' : 'Unpaid');

  double get grossTotal => lines.fold(0, (total, l) => total + l.gross);
  double get discountTotal => lines.fold(0, (total, l) => total + l.discount);
  double get taxableTotal => lines.fold(0, (total, l) => total + l.taxable);
  double get gstTotal => lines.fold(0, (total, l) => total + l.gstAmount);

  // Within Telangana GST splits half-half; from another state it's all IGST
  double get cgst => interState ? 0 : gstTotal / 2;
  double get sgst => interState ? 0 : gstTotal / 2;
  double get igst => interState ? gstTotal : 0;

  // Bills are paid in whole rupees: round off to the nearest rupee
  double get exactTotal => taxableTotal + gstTotal;
  double get total => exactTotal.roundToDouble(); // net amount payable
  double get roundOff => round2(total - exactTotal);

  int get totalUnits => lines.fold(0, (total, l) => total + l.quantity);
  int get totalFree => lines.fold(0, (total, l) => total + l.free);

  List<GstSlab> get slabs => slabsFor(lines.map(
      (l) => (rate: l.gstPct, taxable: l.taxable, tax: l.gstAmount)));

  Map<String, dynamic> toMap() => {
        'supplier': supplier,
        'supplierGstin': supplierGstin,
        'billNumber': billNumber,
        'billDate': Timestamp.fromDate(billDate),
        'interState': interState,
        'lines': lines.map((line) => line.toMap()).toList(),
        'taxable': round2(taxableTotal),
        'gst': round2(gstTotal),
        'total': total,
        'creditDays': creditDays,
        'dueDate': Timestamp.fromDate(dueDate),
        'paid': paid,
        'createdAt': FieldValue.serverTimestamp(),
      };

  factory PurchaseBill.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final rawLines = (data['lines'] as List?) ?? [];
    return PurchaseBill(
      id: doc.id,
      supplier: data['supplier'] ?? '',
      supplierGstin: data['supplierGstin'] ?? '',
      billNumber: data['billNumber'] ?? '',
      billDate: (data['billDate'] as Timestamp).toDate(),
      interState: data['interState'] ?? false,
      lines: rawLines
          .map((line) => BillLine.fromMap(Map<String, dynamic>.from(line)))
          .toList(),
      // Bills saved before payments existed count as unpaid, 30 days credit
      creditDays: (data['creditDays'] as num?)?.toInt() ?? 30,
      paid: (data['paid'] as num?)?.toDouble() ?? 0,
    );
  }
}
