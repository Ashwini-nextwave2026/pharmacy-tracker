import 'purchase_bill.dart';
import 'sale_bill.dart';

// Everything needed for one month's GST returns, worked out from that
// month's sale bills and purchase bills.
//
//   GSTR-1  (sales):  rate-wise B2C sales, HSN summary, bills issued
//   GSTR-3B (summary): tax on sales, input tax credit on purchases,
//                      and the net tax to pay in cash
//
// Assumes the pharmacy is a regular GST taxpayer in Telangana selling
// to customers within the state (so sales have CGST + SGST, never IGST).

class RateRow {
  final double rate;
  double taxable = 0;
  double cgst = 0;
  double sgst = 0;
  double igst = 0;

  RateRow(this.rate);

  double get tax => cgst + sgst + igst;
}

class HsnRow {
  final String hsn;
  final double rate;
  int quantity = 0;
  double taxable = 0;
  double tax = 0;

  HsnRow(this.hsn, this.rate);

  double get value => taxable + tax; // total value incl. GST
}

class GstReport {
  final DateTime month; // any day in the month
  final List<SaleBill> sales;
  final List<PurchaseBill> purchases;

  GstReport({required this.month, required this.sales, required this.purchases});

  // ---- Sales (output tax) ----

  // GSTR-1 B2C (small) and GSTR-3B 3.1(a): sales grouped by GST rate
  List<RateRow> get salesByRate {
    final map = <double, RateRow>{};
    for (final sale in sales) {
      for (final l in sale.lines) {
        final row = map.putIfAbsent(l.gstPct, () => RateRow(l.gstPct));
        row.taxable += l.taxable;
        row.cgst += l.gstAmount / 2;
        row.sgst += l.gstAmount / 2;
      }
    }
    return map.values.toList()..sort((a, b) => a.rate.compareTo(b.rate));
  }

  // GSTR-1 Table 12: HSN-wise summary of sales
  List<HsnRow> get salesByHsn {
    final map = <String, HsnRow>{};
    for (final sale in sales) {
      for (final l in sale.lines) {
        final hsn = l.hsn.isEmpty ? '3004' : l.hsn; // 3004 = medicines
        final key = '$hsn@${l.gstPct}';
        final row = map.putIfAbsent(key, () => HsnRow(hsn, l.gstPct));
        row.quantity += l.quantity;
        row.taxable += l.taxable;
        row.tax += l.gstAmount;
      }
    }
    return map.values.toList()
      ..sort((a, b) => a.hsn == b.hsn ? a.rate.compareTo(b.rate) : a.hsn.compareTo(b.hsn));
  }

  double get salesTaxable => sales.fold(0, (s, b) => s + b.taxableTotal);
  double get outputCgst => sales.fold(0, (s, b) => s + b.cgst);
  double get outputSgst => sales.fold(0, (s, b) => s + b.sgst);
  double get salesTotal => sales.fold(0, (s, b) => s + b.total);

  // GSTR-1 Table 13: first and last bill numbers issued this month
  String get firstBill => sales.isEmpty ? '-' : _sortedNumbers.first;
  String get lastBill => sales.isEmpty ? '-' : _sortedNumbers.last;
  List<String> get _sortedNumbers =>
      sales.map((s) => s.billNumber).toList()..sort();

  // ---- Purchases (input tax credit, ITC) ----

  // GSTR-3B Table 4: tax paid on purchases, grouped by rate
  List<RateRow> get purchasesByRate {
    final map = <double, RateRow>{};
    for (final bill in purchases) {
      for (final l in bill.lines) {
        final row = map.putIfAbsent(l.gstPct, () => RateRow(l.gstPct));
        row.taxable += l.taxable;
        if (bill.interState) {
          row.igst += l.gstAmount;
        } else {
          row.cgst += l.gstAmount / 2;
          row.sgst += l.gstAmount / 2;
        }
      }
    }
    return map.values.toList()..sort((a, b) => a.rate.compareTo(b.rate));
  }

  double get purchasesTaxable => purchases.fold(0, (s, b) => s + b.taxableTotal);
  double get itcCgst => purchases.fold(0, (s, b) => s + b.cgst);
  double get itcSgst => purchases.fold(0, (s, b) => s + b.sgst);
  double get itcIgst => purchases.fold(0, (s, b) => s + b.igst);

  // ---- Set-off: how much tax is left to pay in cash ----
  // Rules: IGST credit is used first (against CGST, then SGST here, since
  // sales have no IGST). CGST credit only against CGST, SGST only against
  // SGST. CGST and SGST credit can never be swapped.
  // Anything left over is carried forward to next month.
  ({double cgstCash, double sgstCash, double cgstCarry, double sgstCarry, double igstCarry})
      get setOff {
    var igstLeft = itcIgst;

    var cgstDue = outputCgst;
    final useIgstOnCgst = igstLeft < cgstDue ? igstLeft : cgstDue;
    cgstDue -= useIgstOnCgst;
    igstLeft -= useIgstOnCgst;

    var sgstDue = outputSgst;
    final useIgstOnSgst = igstLeft < sgstDue ? igstLeft : sgstDue;
    sgstDue -= useIgstOnSgst;
    igstLeft -= useIgstOnSgst;

    final cgstCash = cgstDue > itcCgst ? cgstDue - itcCgst : 0.0;
    final cgstCarry = itcCgst > cgstDue ? itcCgst - cgstDue : 0.0;
    final sgstCash = sgstDue > itcSgst ? sgstDue - itcSgst : 0.0;
    final sgstCarry = itcSgst > sgstDue ? itcSgst - sgstDue : 0.0;

    return (
      cgstCash: round2(cgstCash),
      sgstCash: round2(sgstCash),
      cgstCarry: round2(cgstCarry),
      sgstCarry: round2(sgstCarry),
      igstCarry: round2(igstLeft),
    );
  }

  double get cashToPay => setOff.cgstCash + setOff.sgstCash;
}
