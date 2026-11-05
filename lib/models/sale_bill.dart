import 'package:cloud_firestore/cloud_firestore.dart';
import 'purchase_bill.dart' show round2, GstSlab, slabsFor;

// Ways a customer can pay
const paymentModes = ['Cash', 'UPI', 'Card', 'Credit'];

// One medicine on a sale bill, sold from one stock batch.
// Medicines are sold at MRP, and MRP already INCLUDES GST,
// so GST is worked out backwards from the price.
class SaleLine {
  String stockId; // which stock batch this came from (to reduce its quantity)
  String name;
  String hsn;
  String batch;
  DateTime expiry;
  int quantity;
  double mrp; // per unit, including GST
  double discountPct; // discount given to the customer
  double gstPct;
  double? costRate; // what ONE unit cost the pharmacy (before GST), for profit

  SaleLine({
    required this.stockId,
    required this.name,
    this.hsn = '',
    required this.batch,
    required this.expiry,
    required this.quantity,
    required this.mrp,
    this.discountPct = 0,
    this.gstPct = 0,
    this.costRate,
  });

  // What these units cost the pharmacy (null if the cost isn't known)
  double? get cost => costRate == null ? null : costRate! * quantity;

  double get mrpValue => quantity * mrp; // before discount
  double get discount => mrpValue * discountPct / 100;
  double get amount => mrpValue - discount; // what the customer pays
  // amount = taxable + GST, and GST = taxable × rate, so:
  double get taxable => amount / (1 + gstPct / 100);
  double get gstAmount => amount - taxable;

  Map<String, dynamic> toMap() => {
        'stockId': stockId,
        'name': name,
        'hsn': hsn,
        'batch': batch,
        'expiry': Timestamp.fromDate(expiry),
        'quantity': quantity,
        'mrp': mrp,
        'discountPct': discountPct,
        'gstPct': gstPct,
        if (costRate != null) 'costRate': costRate,
      };

  factory SaleLine.fromMap(Map<String, dynamic> map) => SaleLine(
        stockId: map['stockId'] ?? '',
        name: map['name'] ?? '',
        hsn: map['hsn'] ?? '',
        batch: map['batch'] ?? '',
        expiry: (map['expiry'] as Timestamp).toDate(),
        quantity: (map['quantity'] as num?)?.toInt() ?? 0,
        mrp: (map['mrp'] as num?)?.toDouble() ?? 0,
        discountPct: (map['discountPct'] as num?)?.toDouble() ?? 0,
        gstPct: (map['gstPct'] as num?)?.toDouble() ?? 0,
        costRate: (map['costRate'] as num?)?.toDouble(),
      );
}

// A whole sale bill for one customer
class SaleBill {
  String? id;
  String billNumber; // given when saved, e.g. S-0001
  DateTime date;
  String customerName;
  String customerPhone;
  String doctorName;
  String paymentMode;
  List<SaleLine> lines;
  String soldBy; // staff or owner name

  SaleBill({
    this.id,
    this.billNumber = '',
    required this.date,
    required this.customerName,
    this.customerPhone = '',
    this.doctorName = '',
    this.paymentMode = 'Cash',
    required this.lines,
    this.soldBy = '',
  });

  double get mrpTotal => lines.fold(0, (total, l) => total + l.mrpValue);
  double get discountTotal => lines.fold(0, (total, l) => total + l.discount);
  double get taxableTotal => lines.fold(0, (total, l) => total + l.taxable);
  double get gstTotal => lines.fold(0, (total, l) => total + l.gstAmount);
  double get cgst => gstTotal / 2; // a shop sale is always within the state
  double get sgst => gstTotal / 2;

  double get exactTotal => lines.fold(0, (total, l) => total + l.amount);
  double get total => exactTotal.roundToDouble(); // whole rupees
  double get roundOff => round2(total - exactTotal);

  int get totalUnits => lines.fold(0, (total, l) => total + l.quantity);

  List<GstSlab> get slabs => slabsFor(lines.map(
      (l) => (rate: l.gstPct, taxable: l.taxable, tax: l.gstAmount)));

  Map<String, dynamic> toMap() => {
        'billNumber': billNumber,
        'date': Timestamp.fromDate(date),
        'customerName': customerName,
        'customerPhone': customerPhone,
        'doctorName': doctorName,
        'paymentMode': paymentMode,
        'lines': lines.map((l) => l.toMap()).toList(),
        'taxable': round2(taxableTotal),
        'gst': round2(gstTotal),
        'total': total,
        'soldBy': soldBy,
        'createdAt': FieldValue.serverTimestamp(),
      };

  factory SaleBill.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final rawLines = (data['lines'] as List?) ?? [];
    return SaleBill(
      id: doc.id,
      billNumber: data['billNumber'] ?? '',
      date: (data['date'] as Timestamp).toDate(),
      customerName: data['customerName'] ?? '',
      customerPhone: data['customerPhone'] ?? '',
      doctorName: data['doctorName'] ?? '',
      paymentMode: data['paymentMode'] ?? 'Cash',
      lines: rawLines
          .map((l) => SaleLine.fromMap(Map<String, dynamic>.from(l)))
          .toList(),
      soldBy: data['soldBy'] ?? '',
    );
  }
}
