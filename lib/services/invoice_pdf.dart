import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/sale_bill.dart';
import '../models/shop_details.dart';
import '../utils/format.dart' show rupeesInWords;

// Builds the printable TAX INVOICE for one sale, as an A4 PDF.
//
//  +--------------------------------------------------------------+
//  | Page 1 of 1          TAX INVOICE               Original Copy |
//  |             SHOP NAME / address / phone / GSTIN / DL         |
//  | Billing details (customer, doctor) | Invoice no, date, ...   |
//  | Sr | Item | HSN | Batch | Exp | Qty | MRP | Disc | GST | Amt |
//  | Totals ...                                    NET AMOUNT     |
//  | Amount in words / GST summary by rate                        |
//  | Terms        | Scan-to-pay UPI QR         | For SHOP / Sign  |
//  +--------------------------------------------------------------+
//
// Uses the PDF's built-in Helvetica font, which has no ₹ sign,
// so money is shown as plain numbers with "Rs." where needed.

final _money = NumberFormat('#,##,##0.00', 'en_IN');
String _m(double v) => _money.format(v);
String _pct(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

const _line = PdfColors.grey700;
const _shade = PdfColor.fromInt(0xFFE0F2F1); // light teal, like the app

Future<Uint8List> buildInvoicePdf({
  required SaleBill sale,
  required String shopName,
  required ShopDetails shop,
}) async {
  final doc = pw.Document(title: 'Tax Invoice ${sale.billNumber}', author: shopName);

  pw.Widget text(String t,
          {double size = 8,
          bool bold = false,
          pw.TextAlign align = pw.TextAlign.left,
          PdfColor? color}) =>
      pw.Text(t,
          textAlign: align,
          style: pw.TextStyle(
              fontSize: size,
              color: color,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal));

  pw.Widget cell(String t,
          {bool bold = false, pw.TextAlign align = pw.TextAlign.left, double size = 8}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        child: text(t, bold: bold, align: align, size: size),
      );

  pw.Widget labelValue(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(children: [
          pw.SizedBox(width: 70, child: text(label, bold: true)),
          pw.Expanded(child: text(': $value')),
        ]),
      );

  final box = pw.BoxDecoration(border: pw.Border.all(color: _line, width: 0.6));

  // ---- 1. Title bar ----
  final titleBar = pw.Container(
    decoration: box,
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    child: pw.Row(children: [
      pw.Expanded(child: text(sale.billNumber)),
      text('TAX INVOICE', size: 12, bold: true),
      pw.Expanded(child: text('Original Copy', align: pw.TextAlign.right)),
    ]),
  );

  // ---- 2. Shop header ----
  final header = pw.Container(
    decoration: box,
    padding: const pw.EdgeInsets.all(8),
    child: pw.Column(children: [
      text(shopName, size: 16, bold: true),
      if (shop.address.isNotEmpty) text(shop.address, size: 9, align: pw.TextAlign.center),
      if (shop.phone.isNotEmpty) text('Mobile: ${shop.phone}', size: 9),
      if (shop.gstin.isNotEmpty) text('GSTIN: ${shop.gstin}', size: 9, bold: true),
      if (shop.drugLicence.isNotEmpty)
        text('D.L. No: ${shop.drugLicence}', size: 8, align: pw.TextAlign.center),
    ]),
  );

  // ---- 3. Billing details | invoice details ----
  // A table row keeps both boxes the same height, with one line between
  final details = pw.Table(
    border: pw.TableBorder.all(color: _line, width: 0.6),
    columnWidths: const {0: pw.FlexColumnWidth(5), 1: pw.FlexColumnWidth(4)},
    children: [
      pw.TableRow(children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            text('Billing Details', bold: true, size: 9),
            pw.SizedBox(height: 3),
            text(sale.customerName, size: 9),
            if (sale.customerPhone.isNotEmpty) text('Mobile: ${sale.customerPhone}'),
            if (sale.doctorName.isNotEmpty) text('Doctor: ${sale.doctorName}'),
          ]),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Column(children: [
            labelValue('Invoice No.', sale.billNumber),
            labelValue('Invoice Date', DateFormat('dd-MMM-yy, h:mm a').format(sale.date)),
            labelValue('Place of Supply', '36 - Telangana'),
            labelValue('Reverse Charge', 'No'),
            labelValue('Payment', sale.paymentMode),
          ]),
        ),
      ]),
    ],
  );

  // ---- 4. Items table ----
  final itemsTable = pw.Table(
    border: const pw.TableBorder(
      left: pw.BorderSide(color: _line, width: 0.6),
      right: pw.BorderSide(color: _line, width: 0.6),
      bottom: pw.BorderSide(color: _line, width: 0.6),
      verticalInside: pw.BorderSide(color: _line, width: 0.6),
    ),
    columnWidths: const {
      0: pw.FixedColumnWidth(22), // Sr
      1: pw.FlexColumnWidth(4), // Item
      2: pw.FixedColumnWidth(38), // HSN
      3: pw.FixedColumnWidth(48), // Batch
      4: pw.FixedColumnWidth(34), // Exp
      5: pw.FixedColumnWidth(26), // Qty
      6: pw.FixedColumnWidth(46), // MRP
      7: pw.FixedColumnWidth(30), // Disc
      8: pw.FixedColumnWidth(30), // GST
      9: pw.FixedColumnWidth(56), // Amount
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(
          color: _shade,
          border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.6)),
        ),
        children: [
          cell('Sr.', bold: true, align: pw.TextAlign.center),
          cell('Item Description', bold: true),
          cell('HSN', bold: true, align: pw.TextAlign.center),
          cell('Batch No.', bold: true, align: pw.TextAlign.center),
          cell('Expiry', bold: true, align: pw.TextAlign.center),
          cell('Qty', bold: true, align: pw.TextAlign.center),
          cell('MRP', bold: true, align: pw.TextAlign.right),
          cell('Disc %', bold: true, align: pw.TextAlign.center),
          cell('GST %', bold: true, align: pw.TextAlign.center),
          cell('Amount', bold: true, align: pw.TextAlign.right),
        ],
      ),
      for (var i = 0; i < sale.lines.length; i++)
        pw.TableRow(children: [
          cell('${i + 1}', align: pw.TextAlign.center),
          cell(sale.lines[i].name),
          cell(sale.lines[i].hsn.isEmpty ? '3004' : sale.lines[i].hsn,
              align: pw.TextAlign.center),
          cell(sale.lines[i].batch, align: pw.TextAlign.center),
          cell(DateFormat('MM/yy').format(sale.lines[i].expiry), align: pw.TextAlign.center),
          cell('${sale.lines[i].quantity}', align: pw.TextAlign.center),
          cell(_m(sale.lines[i].mrp), align: pw.TextAlign.right),
          cell(_pct(sale.lines[i].discountPct), align: pw.TextAlign.center),
          cell(_pct(sale.lines[i].gstPct), align: pw.TextAlign.center),
          cell(_m(sale.lines[i].amount), align: pw.TextAlign.right),
        ]),
    ],
  );

  // ---- 5. Totals (right) and GST summary (left) ----
  pw.Widget totalRow(String label, String value, {bool bold = false, double size = 8.5}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(children: [
          pw.Expanded(child: text(label, bold: bold, size: size)),
          text(value, bold: bold, size: size),
        ]),
      );

  final gstTable = pw.Table(
    border: pw.TableBorder.all(color: _line, width: 0.4),
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _shade),
        children: [
          cell('GST %', bold: true, size: 7.5),
          cell('Taxable', bold: true, align: pw.TextAlign.right, size: 7.5),
          cell('CGST', bold: true, align: pw.TextAlign.right, size: 7.5),
          cell('SGST', bold: true, align: pw.TextAlign.right, size: 7.5),
          cell('Total tax', bold: true, align: pw.TextAlign.right, size: 7.5),
        ],
      ),
      for (final s in sale.slabs)
        pw.TableRow(children: [
          cell('${_pct(s.rate)}%', size: 7.5),
          cell(_m(s.taxable), align: pw.TextAlign.right, size: 7.5),
          cell(_m(s.tax / 2), align: pw.TextAlign.right, size: 7.5),
          cell(_m(s.tax / 2), align: pw.TextAlign.right, size: 7.5),
          cell(_m(s.tax), align: pw.TextAlign.right, size: 7.5),
        ]),
    ],
  );

  final totals = pw.Container(
    decoration: box,
    padding: const pw.EdgeInsets.all(6),
    child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Expanded(
        flex: 6,
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          text('Amount in words', bold: true),
          text(rupeesInWords(sale.total), size: 9),
          pw.SizedBox(height: 6),
          gstTable,
          pw.SizedBox(height: 3),
          text('Prices are MRP, inclusive of GST. Total items: ${sale.lines.length}, '
              'units: ${sale.totalUnits}.',
              size: 7, color: PdfColors.grey700),
        ]),
      ),
      pw.SizedBox(width: 12),
      pw.Expanded(
        flex: 4,
        child: pw.Column(children: [
          totalRow('MRP value', _m(sale.mrpTotal)),
          if (sale.discountTotal > 0) totalRow('Less discount', '-${_m(sale.discountTotal)}'),
          totalRow('Taxable value', _m(sale.taxableTotal)),
          totalRow('CGST', _m(sale.cgst)),
          totalRow('SGST', _m(sale.sgst)),
          totalRow('Round off', _m(sale.roundOff)),
          pw.Divider(color: _line, thickness: 0.6, height: 6),
          totalRow('NET AMOUNT (Rs.)', _m(sale.total), bold: true, size: 11),
        ]),
      ),
    ]),
  );

  // ---- 6. Terms | UPI | Signature ----
  final termsBox = pw.Padding(
    padding: const pw.EdgeInsets.all(6),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      text('Terms and Conditions', bold: true, size: 9),
      text('E & O.E', size: 7.5),
      for (var i = 0; i < shop.termLines.length; i++)
        text('${i + 1}. ${shop.termLines[i]}', size: 7.5),
    ]),
  );
  // Scan-to-pay QR: any UPI app (GPay, PhonePe, Paytm) opens with the
  // shop's UPI ID and this bill's amount already filled in
  // (spaces written as %20, not +, which some UPI apps show as a plus sign)
  String enc(String v) => Uri.encodeComponent(v);
  final upiLink = 'upi://pay?pa=${enc(shop.upiId)}&pn=${enc(shopName)}'
      '&am=${sale.total.toStringAsFixed(2)}&cu=INR&tn=${enc('Bill ${sale.billNumber}')}';
  final upiBox = pw.Padding(
    padding: const pw.EdgeInsets.all(6),
    child: pw.Column(children: [
      text('Scan to pay', bold: true, size: 9),
      pw.SizedBox(height: 3),
      pw.BarcodeWidget(
        barcode: pw.Barcode.qrCode(),
        data: upiLink,
        width: 62,
        height: 62,
      ),
      pw.SizedBox(height: 3),
      text(shop.upiId, size: 7),
    ]),
  );
  final signBox = pw.Container(
    height: 80,
    padding: const pw.EdgeInsets.all(6),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        text('For $shopName', bold: true, align: pw.TextAlign.right),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          text('Authorised Signatory', bold: true),
          if (sale.soldBy.isNotEmpty) text('Billed by: ${sale.soldBy}', size: 7),
        ]),
      ],
    ),
  );
  final footer = pw.Table(
    border: pw.TableBorder.all(color: _line, width: 0.6),
    columnWidths: shop.hasUpi
        ? const {0: pw.FlexColumnWidth(4), 1: pw.FlexColumnWidth(3), 2: pw.FlexColumnWidth(3)}
        : const {0: pw.FlexColumnWidth(6), 1: pw.FlexColumnWidth(4)},
    children: [
      pw.TableRow(children: [
        termsBox,
        if (shop.hasUpi) upiBox,
        signBox,
      ]),
    ],
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (context) => [
        titleBar,
        header,
        details,
        itemsTable,
        totals,
        footer,
        pw.SizedBox(height: 6),
        pw.Center(
          child: text('This is a computer-generated invoice.  Get well soon!',
              size: 7, color: PdfColors.grey700),
        ),
      ],
    ),
  );

  return doc.save();
}
