import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/gst_report.dart';
import '../models/purchase_bill.dart';
import '../models/sale_bill.dart';
import '../models/session.dart';
import '../services/pharmacy_service.dart';
import '../utils/format.dart';

// Monthly GST filing report (owner only).
// Pick a month; the app adds up that month's sales and purchases and lays
// the figures out in the order of the GSTR-1 and GSTR-3B forms.
class GstReportPage extends StatefulWidget {
  final Session session;

  const GstReportPage({super.key, required this.session});

  @override
  State<GstReportPage> createState() => _GstReportPageState();
}

class _GstReportPageState extends State<GstReportPage> {
  // Start on LAST month: that's the one you usually file for
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month - 1);
  Future<GstReport>? report;

  @override
  void initState() {
    super.initState();
    load();
  }

  void changeMonth(int by) {
    final next = DateTime(month.year, month.month + by);
    if (next.isAfter(DateTime.now())) return; // no future months
    setState(() => month = next);
    load();
  }

  // Fetch the month's sale bills and purchase bills
  void load() {
    final start = Timestamp.fromDate(DateTime(month.year, month.month));
    final end = Timestamp.fromDate(DateTime(month.year, month.month + 1));
    final pid = widget.session.pharmacyId;

    setState(() {
      report = () async {
        final results = await Future.wait([
          PharmacyService.salesRef(pid)
              .where('date', isGreaterThanOrEqualTo: start)
              .where('date', isLessThan: end)
              .get(),
          PharmacyService.billsRef(pid)
              .where('billDate', isGreaterThanOrEqualTo: start)
              .where('billDate', isLessThan: end)
              .get(),
        ]);
        return GstReport(
          month: month,
          sales: results[0].docs.map(SaleBill.fromFirestore).toList(),
          purchases: results[1].docs.map(PurchaseBill.fromFirestore).toList(),
        );
      }();
    });
  }

  String get monthName => DateFormat('MMMM yyyy').format(month);

  // Filing due dates for the month after
  String get gstr1Due =>
      DateFormat('d MMM yyyy').format(DateTime(month.year, month.month + 1, 11));
  String get gstr3bDue =>
      DateFormat('d MMM yyyy').format(DateTime(month.year, month.month + 1, 20));

  // ---- The report as text, to send to your CA on WhatsApp ----
  String reportText(GstReport r) {
    String m(double v) => v.toStringAsFixed(2);
    String left(String s, int w) => s.length > w ? s.substring(0, w) : s.padRight(w);
    String right(String s, int w) => s.padLeft(w);
    const line = '-----------------------------------';
    final so = r.setOff;

    final b = StringBuffer()
      ..writeln('*GST report: $monthName*')
      ..writeln(widget.session.pharmacyName)
      ..writeln('```')
      ..writeln('GSTR-1  B2C sales by rate')
      ..writeln(left('Rate', 6) + right('Taxable', 11) + right('CGST', 9) + right('SGST', 9))
      ..writeln(line);
    for (final row in r.salesByRate) {
      b.writeln(left(pct(row.rate), 6) + right(m(row.taxable), 11) +
          right(m(row.cgst), 9) + right(m(row.sgst), 9));
    }
    b
      ..writeln(line)
      ..writeln()
      ..writeln('GSTR-1  HSN summary')
      ..writeln(left('HSN', 6) + left('Rate', 5) + right('Qty', 5) +
          right('Taxable', 10) + right('Tax', 9))
      ..writeln(line);
    for (final h in r.salesByHsn) {
      b.writeln(left(h.hsn, 6) + left(pct(h.rate), 5) + right('${h.quantity}', 5) +
          right(m(h.taxable), 10) + right(m(h.tax), 9));
    }
    b
      ..writeln(line)
      ..writeln('Bills: ${r.firstBill} to ${r.lastBill} (${r.sales.length})')
      ..writeln()
      ..writeln('GSTR-3B')
      ..writeln(left('3.1(a) Taxable sales', 24) + right(m(r.salesTaxable), 11))
      ..writeln(left('  CGST', 24) + right(m(r.outputCgst), 11))
      ..writeln(left('  SGST', 24) + right(m(r.outputSgst), 11))
      ..writeln(left('4 ITC  IGST', 24) + right(m(r.itcIgst), 11))
      ..writeln(left('       CGST', 24) + right(m(r.itcCgst), 11))
      ..writeln(left('       SGST', 24) + right(m(r.itcSgst), 11))
      ..writeln(line)
      ..writeln(left('Cash to pay  CGST', 24) + right(m(so.cgstCash), 11))
      ..writeln(left('             SGST', 24) + right(m(so.sgstCash), 11))
      ..writeln(left('Credit carried forward', 24) +
          right(m(so.cgstCarry + so.sgstCarry + so.igstCarry), 11))
      ..writeln('```')
      ..writeln('*Total cash to pay: ${rupees.format(r.cashToPay)}*')
      ..writeln('GSTR-1 due $gstr1Due · GSTR-3B due $gstr3bDue');
    return b.toString();
  }

  // ---- The report as CSV, to paste into Excel / give to your CA ----
  String reportCsv(GstReport r) {
    String m(double v) => v.toStringAsFixed(2);
    final b = StringBuffer()
      ..writeln('GST report,$monthName')
      ..writeln()
      ..writeln('GSTR-1 B2C sales by rate')
      ..writeln('Rate %,Taxable value,CGST,SGST');
    for (final row in r.salesByRate) {
      b.writeln('${row.rate},${m(row.taxable)},${m(row.cgst)},${m(row.sgst)}');
    }
    b
      ..writeln()
      ..writeln('GSTR-1 HSN summary')
      ..writeln('HSN,Rate %,Quantity,Taxable value,CGST,SGST,Total value');
    for (final h in r.salesByHsn) {
      b.writeln('${h.hsn},${h.rate},${h.quantity},${m(h.taxable)},'
          '${m(h.tax / 2)},${m(h.tax / 2)},${m(h.value)}');
    }
    b
      ..writeln()
      ..writeln('GSTR-1 documents issued,From,To,Count')
      ..writeln('Invoices,${r.firstBill},${r.lastBill},${r.sales.length}')
      ..writeln()
      ..writeln('GSTR-3B,IGST,CGST,SGST')
      ..writeln('3.1(a) Output tax (taxable ${m(r.salesTaxable)}),0.00,'
          '${m(r.outputCgst)},${m(r.outputSgst)}')
      ..writeln('4(A)(5) Input tax credit (purchases ${m(r.purchasesTaxable)}),'
          '${m(r.itcIgst)},${m(r.itcCgst)},${m(r.itcSgst)}')
      ..writeln('Cash to pay,0.00,${m(r.setOff.cgstCash)},${m(r.setOff.sgstCash)}')
      ..writeln('Credit carried forward,${m(r.setOff.igstCarry)},'
          '${m(r.setOff.cgstCarry)},${m(r.setOff.sgstCarry)}');
    return b.toString();
  }

  Future<void> shareWhatsApp(GstReport r) async {
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(reportText(r))}');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not open WhatsApp')));
    }
  }

  void copyCsv(GstReport r) {
    Clipboard.setData(ClipboardData(text: reportCsv(r)));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Copied. Paste into Excel or Google Sheets (Ctrl+V).')));
  }

  @override
  Widget build(BuildContext context) {
    final canGoNext = DateTime(month.year, month.month + 1).isBefore(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('GST filing report')),
      body: FutureBuilder<GstReport>(
        future: report,
        builder: (context, snapshot) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 1. Month picker
              Card(
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => changeMonth(-1),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(monthName,
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold)),
                          Text('GSTR-1 due $gstr1Due · GSTR-3B due $gstr3bDue',
                              style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: canGoNext ? () => changeMonth(1) : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (snapshot.hasError)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Could not load: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red)),
                )
              else if (!snapshot.hasData)
                const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                ..._report(snapshot.data!),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _report(GstReport r) {
    final so = r.setOff;
    return [
      // 2. The answer first: how much to pay
      Card(
        color: Colors.teal.withValues(alpha: 0.12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text('GST to pay in cash'),
              Text(rupees.format(r.cashToPay),
                  style: const TextStyle(
                      fontSize: 30, fontWeight: FontWeight.bold, color: Colors.teal)),
              Text('${r.sales.length} sale bills · ${r.purchases.length} purchase bills',
                  style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366)),
                      icon: const Icon(Icons.share),
                      label: const Text('Send to CA'),
                      onPressed: () => shareWhatsApp(r),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.table_chart),
                      label: const Text('Copy for Excel'),
                      onPressed: () => copyCsv(r),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),

      // 3. GSTR-1
      _heading('GSTR-1  ·  Sales', 'Due $gstr1Due'),
      _table(
        'B2C sales by GST rate (Table 7)',
        ['Rate', 'Taxable', 'CGST', 'SGST'],
        [
          for (final row in r.salesByRate)
            [pct(row.rate), _m(row.taxable), _m(row.cgst), _m(row.sgst)],
        ],
        total: ['Total', _m(r.salesTaxable), _m(r.outputCgst), _m(r.outputSgst)],
      ),
      _table(
        'HSN summary (Table 12)',
        ['HSN', 'Rate', 'Qty', 'Taxable', 'Tax'],
        [
          for (final h in r.salesByHsn)
            [h.hsn, pct(h.rate), '${h.quantity}', _m(h.taxable), _m(h.tax)],
        ],
      ),
      _table(
        'Documents issued (Table 13)',
        ['Type', 'From', 'To', 'Count'],
        [
          ['Invoices', r.firstBill, r.lastBill, '${r.sales.length}'],
        ],
      ),

      // 4. GSTR-3B
      _heading('GSTR-3B  ·  Summary', 'Due $gstr3bDue'),
      _table(
        'Tax on sales (3.1 a) and credit on purchases (4 A 5)',
        ['', 'IGST', 'CGST', 'SGST'],
        [
          ['Sales tax', '0.00', _m(r.outputCgst), _m(r.outputSgst)],
          ['Purchase ITC', _m(r.itcIgst), _m(r.itcCgst), _m(r.itcSgst)],
        ],
      ),
      _table(
        'Payment (set-off)',
        ['', 'IGST', 'CGST', 'SGST'],
        [
          ['Cash to pay', '0.00', _m(so.cgstCash), _m(so.sgstCash)],
          ['Carry forward', _m(so.igstCarry), _m(so.cgstCarry), _m(so.sgstCarry)],
        ],
      ),
      _table(
        'Purchases by GST rate',
        ['Rate', 'Taxable', 'IGST', 'CGST', 'SGST'],
        [
          for (final row in r.purchasesByRate)
            [pct(row.rate), _m(row.taxable), _m(row.igst), _m(row.cgst), _m(row.sgst)],
        ],
        total: ['Total', _m(r.purchasesTaxable), _m(r.itcIgst), _m(r.itcCgst), _m(r.itcSgst)],
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(4, 12, 4, 24),
        child: Text(
          'Worked out from the bills entered in this app. Before filing, '
          'match the purchase ITC with GSTR-2B on the GST portal and check '
          'the figures with your CA. Credit carried forward from earlier '
          'months is not included.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ),
    ];
  }

  String _m(double v) => NumberFormat('#,##,##0.00', 'en_IN').format(v);

  Widget _heading(String title, String sub) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 6),
        child: Row(
          children: [
            Text(title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text(sub, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      );

  // A simple table card: first column on the left, numbers on the right
  Widget _table(String title, List<String> head, List<List<String>> rows,
      {List<String>? total}) {
    Widget cells(List<String> values, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              for (var i = 0; i < values.length; i++)
                Expanded(
                  flex: i == 0 ? 3 : 4,
                  child: Text(
                    values[i],
                    textAlign: i == 0 ? TextAlign.left : TextAlign.right,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: bold ? FontWeight.bold : FontWeight.normal),
                  ),
                ),
            ],
          ),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            cells(head, bold: true),
            const Divider(height: 8),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Nothing this month', style: TextStyle(color: Colors.grey)),
              ),
            for (final r in rows) cells(r),
            if (total != null && rows.isNotEmpty) ...[
              const Divider(height: 8),
              cells(total, bold: true),
            ],
          ],
        ),
      ),
    );
  }
}
