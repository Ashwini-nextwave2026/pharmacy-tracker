import 'package:cloud_firestore/cloud_firestore.dart';

// Taking stock OUT without a sale:
//   return  = sent back to the supplier (they give a credit note)
//   writeoff = thrown away: expired, damaged, lost or stolen
const adjustmentReturn = 'return';
const adjustmentWriteOff = 'writeoff';

const writeOffReasons = ['Expired', 'Damaged', 'Lost / stolen', 'Other'];
const returnReasons = ['Expired', 'Near expiry', 'Damaged', 'Wrong item sent', 'Other'];

// Has the supplier's credit for a return been used against their dues yet?
const creditPending = 'pending';
const creditAdjusted = 'adjusted';

class StockAdjustment {
  String? id;
  String type; // adjustmentReturn or adjustmentWriteOff
  String stockId;
  String name;
  String batch;
  DateTime expiry;
  int quantity;
  double costRate; // cost of ONE unit (before GST), 0 if unknown
  double mrp;
  String supplier; // for returns
  String reason;
  String note;
  String creditNoteNumber; // supplier's credit note no., if given
  String creditStatus; // returns only: pending / adjusted
  DateTime date;
  String addedBy;

  StockAdjustment({
    this.id,
    required this.type,
    required this.stockId,
    required this.name,
    required this.batch,
    required this.expiry,
    required this.quantity,
    this.costRate = 0,
    this.mrp = 0,
    this.supplier = '',
    this.reason = '',
    this.note = '',
    this.creditNoteNumber = '',
    this.creditStatus = creditPending,
    required this.date,
    this.addedBy = '',
  });

  bool get isReturn => type == adjustmentReturn;

  // Value of the stock taken out, at cost (what the shop paid)
  double get value => costRate * quantity;

  Map<String, dynamic> toMap() => {
        'type': type,
        'stockId': stockId,
        'name': name,
        'batch': batch,
        'expiry': Timestamp.fromDate(expiry),
        'quantity': quantity,
        'costRate': costRate,
        'mrp': mrp,
        'value': value,
        'supplier': supplier,
        'reason': reason,
        'note': note,
        'creditNoteNumber': creditNoteNumber,
        if (isReturn) 'creditStatus': creditStatus,
        'date': Timestamp.fromDate(date),
        'addedBy': addedBy,
      };

  factory StockAdjustment.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return StockAdjustment(
      id: doc.id,
      type: d['type'] ?? adjustmentWriteOff,
      stockId: d['stockId'] ?? '',
      name: d['name'] ?? '',
      batch: d['batch'] ?? '',
      expiry: (d['expiry'] as Timestamp).toDate(),
      quantity: (d['quantity'] as num?)?.toInt() ?? 0,
      costRate: (d['costRate'] as num?)?.toDouble() ?? 0,
      mrp: (d['mrp'] as num?)?.toDouble() ?? 0,
      supplier: d['supplier'] ?? '',
      reason: d['reason'] ?? '',
      note: d['note'] ?? '',
      creditNoteNumber: d['creditNoteNumber'] ?? '',
      creditStatus: d['creditStatus'] ?? creditPending,
      date: (d['date'] as Timestamp).toDate(),
      addedBy: d['addedBy'] ?? '',
    );
  }
}
