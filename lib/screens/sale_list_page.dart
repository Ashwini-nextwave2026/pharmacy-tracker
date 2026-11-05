import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../models/sale_bill.dart';
import '../models/session.dart';
import '../models/shop_details.dart';
import '../services/invoice_pdf.dart';
import '../services/pharmacy_service.dart';
import '../utils/format.dart';
import '../widgets/gst_summary.dart';
import 'new_sale_page.dart';

// The periods you can pick at the top of the Sales list
enum SalePeriod { today, yesterday, thisMonth, custom }

// Sale bills for a chosen period (Today, Yesterday, This month or any
// dates you pick), newest first, with totals at the top
class SaleListPage extends StatefulWidget {
  final Session session;

  const SaleListPage({super.key, required this.session});

  @override
  State<SaleListPage> createState() => _SaleListPageState();
}

class _SaleListPageState extends State<SaleListPage> {
  SalePeriod period = SalePeriod.today;
  DateTimeRange? customRange; // only used when period is custom

  DateTime get todayStart {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  // Start (included) and end (not included) of the chosen period
  ({DateTime start, DateTime end}) get range {
    final t = todayStart;
    switch (period) {
      case SalePeriod.today:
        return (start: t, end: t.add(const Duration(days: 1)));
      case SalePeriod.yesterday:
        return (start: t.subtract(const Duration(days: 1)), end: t);
      case SalePeriod.thisMonth:
        return (
          start: DateTime(t.year, t.month, 1),
          end: t.add(const Duration(days: 1)),
        );
      case SalePeriod.custom:
        final r = customRange!;
        return (
          start: DateTime(r.start.year, r.start.month, r.start.day),
          end: DateTime(r.end.year, r.end.month, r.end.day + 1),
        );
    }
  }

  // Words for the summary card, e.g. "Today" or "1 Nov – 15 Nov 2026"
  String get rangeLabel {
    final f = DateFormat('d MMM yyyy');
    switch (period) {
      case SalePeriod.today:
        return 'Today, ${f.format(todayStart)}';
      case SalePeriod.yesterday:
        return 'Yesterday, ${f.format(range.start)}';
      case SalePeriod.thisMonth:
        return DateFormat('MMMM yyyy').format(todayStart);
      case SalePeriod.custom:
        final r = customRange!;
        final same = DateUtils.isSameDay(r.start, r.end);
        return same
            ? f.format(r.start)
            : '${DateFormat('d MMM').format(r.start)} – ${f.format(r.end)}';
    }
  }

  // Open the calendar to choose one day or a range of days
  Future<void> pickDates() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: todayStart,
      initialDateRange: customRange ??
          DateTimeRange(
              start: todayStart.subtract(const Duration(days: 6)), end: todayStart),
      helpText: 'Choose sale dates',
      saveText: 'Show',
    );
    if (picked != null) {
      setState(() {
        customRange = picked;
        period = SalePeriod.custom;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = range;

    return Scaffold(
      appBar: AppBar(title: const Text('Sales')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.point_of_sale),
        label: const Text('New sale'),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => NewSalePage(session: widget.session)),
        ),
      ),
      body: Column(
        children: [
          // 1. Period buttons
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                periodChip('Today', SalePeriod.today),
                periodChip('Yesterday', SalePeriod.yesterday),
                periodChip('This month', SalePeriod.thisMonth),
                ActionChip(
                  avatar: const Icon(Icons.date_range, size: 18),
                  label: Text(period == SalePeriod.custom ? rangeLabel : 'Pick dates'),
                  backgroundColor: period == SalePeriod.custom
                      ? Colors.teal.withValues(alpha: 0.2)
                      : null,
                  onPressed: pickDates,
                ),
              ],
            ),
          ),

          // 2. The sales for that period, live
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              // key: start a fresh stream whenever the dates change
              key: ValueKey('${r.start}-${r.end}'),
              stream: PharmacyService.salesRef(widget.session.pharmacyId)
                  .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(r.start))
                  .where('date', isLessThan: Timestamp.fromDate(r.end))
                  .orderBy('date', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Could not load sales: ${snapshot.error}',
                          style: const TextStyle(color: Colors.red)),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final sales =
                    snapshot.data!.docs.map(SaleBill.fromFirestore).toList();
                return ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    summaryCard(sales),
                    if (sales.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('No sales in this period.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, color: Colors.grey)),
                      ),
                    for (final sale in sales) saleCard(sale),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget periodChip(String label, SalePeriod value) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: period == value,
          onSelected: (_) => setState(() => period = value),
        ),
      );

  // Total, bill count, and how much came in by Cash / UPI / Card / Credit
  Widget summaryCard(List<SaleBill> sales) {
    final total = sales.fold<double>(0, (t, s) => t + s.total);
    final gst = sales.fold<double>(0, (t, s) => t + s.gstTotal);
    final byMode = <String, double>{};
    for (final s in sales) {
      byMode[s.paymentMode] = (byMode[s.paymentMode] ?? 0) + s.total;
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: Colors.teal.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(rangeLabel, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(rupees.format(total),
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal)),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${sales.length} bill${sales.length == 1 ? '' : 's'}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('GST ${rupees.format(gst)}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ],
            ),
            if (byMode.isNotEmpty) ...[
              const Divider(height: 20),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  for (final mode in paymentModes)
                    if (byMode[mode] != null)
                      Text('$mode ${rupees.format(byMode[mode])}',
                          style: TextStyle(
                              fontSize: 13,
                              color: mode == 'Credit' ? Colors.orange : null,
                              fontWeight: FontWeight.w500)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget saleCard(SaleBill sale) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.teal.withValues(alpha: 0.15),
            child: const Icon(Icons.receipt, color: Colors.teal),
          ),
          title: Text('${sale.billNumber}  ·  ${sale.customerName}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${DateFormat('d MMM, h:mm a').format(sale.date)} · '
              '${sale.lines.length} item${sale.lines.length == 1 ? '' : 's'} · '
              '${sale.paymentMode}'),
          trailing: Text(rupees.format(sale.total),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  SaleDetailPage(session: widget.session, saleId: sale.id!),
            ),
          ),
        ),
      );
}

// One sale bill, laid out like a printed bill, with Share buttons
class SaleDetailPage extends StatelessWidget {
  final Session session;
  final String saleId;

  const SaleDetailPage({super.key, required this.session, required this.saleId});

  // The bill as plain text, for WhatsApp or copying
  String billText(SaleBill sale) {
    final b = StringBuffer()
      ..writeln('*${session.pharmacyName}*')
      ..writeln('Bill ${sale.billNumber}  ·  ${DateFormat('d MMM yyyy, h:mm a').format(sale.date)}')
      ..writeln('Customer: ${sale.customerName}');
    if (sale.doctorName.isNotEmpty) b.writeln('Doctor: ${sale.doctorName}');

    // ---- Items table ----
    // WhatsApp shows text between ``` in a fixed-width font,
    // so padded columns line up. 35 characters fits a phone screen.
    String left(String s, int w) => s.length > w ? s.substring(0, w) : s.padRight(w);
    String right(String s, int w) => s.padLeft(w);
    String money(double v) => v.toStringAsFixed(2);
    const line = '-----------------------------------';

    // One row: Batch(9) Exp(6) Qty(4) MRP(8) Amount(8) = 35 characters
    String row(String batch, String exp, String qty, String mrp, String amt) =>
        '${left(batch, 8)} ' + left(exp, 6) + right(qty, 4) + right(mrp, 8) + right(amt, 8);

    b
      ..writeln('```')
      ..writeln('Item')
      ..writeln(row('Batch', 'Exp', 'Qty', 'MRP', 'Amount'))
      ..writeln(line);
    for (var i = 0; i < sale.lines.length; i++) {
      final l = sale.lines[i];
      b
        ..writeln('${i + 1}. ${l.name}')
        ..writeln(row(l.batch, DateFormat('MM/yy').format(l.expiry),
            '${l.quantity}', money(l.mrp), money(l.amount)));
      if (l.discountPct > 0) {
        b.writeln(right('Less ${pct(l.discountPct)} discount: -${money(l.discount)}', 35));
      }
    }
    b
      ..writeln(line)
      ..writeln(left('Taxable value', 27) + right(money(sale.taxableTotal), 8))
      ..writeln(left('CGST', 27) + right(money(sale.cgst), 8))
      ..writeln(left('SGST', 27) + right(money(sale.sgst), 8))
      ..writeln(line)
      ..writeln('```')
      ..writeln('*Total: ${rupees.format(sale.total)}*  (${sale.paymentMode})')
      ..writeln()
      ..writeln('Thank you! Get well soon.');
    return b.toString();
  }

  // Build the Tax Invoice PDF, with the shop's latest details
  Future<Uint8List> invoicePdf(SaleBill sale) async {
    final snap = await PharmacyService.pharmacyRef(session.pharmacyId).get();
    final shop = ShopDetails.fromMap(
        (snap.data()?['shop'] as Map?)?.cast<String, dynamic>());
    return buildInvoicePdf(sale: sale, shopName: session.pharmacyName, shop: shop);
  }

  // Print: opens the phone's / browser's print screen (also "Save as PDF")
  Future<void> printInvoice(BuildContext context, SaleBill sale) async {
    try {
      await Printing.layoutPdf(
        name: 'Invoice ${sale.billNumber}',
        onLayout: (format) => invoicePdf(sale),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not print: $e')));
      }
    }
  }

  // Share the PDF file: on a phone this offers WhatsApp, email, Drive...
  Future<void> sharePdf(BuildContext context, SaleBill sale) async {
    try {
      final bytes = await invoicePdf(sale);
      await Printing.sharePdf(
          bytes: bytes, filename: 'Invoice-${sale.billNumber}.pdf');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not share PDF: $e')));
      }
    }
  }

  // WhatsApp: send the Tax Invoice PDF itself, not a text message.
  // On a phone the share screen opens: tap WhatsApp, then the customer.
  // (WhatsApp can't open a chosen chat with a file attached.)
  // In a browser the PDF downloads, ready to attach in WhatsApp.
  Future<void> shareWhatsApp(BuildContext context, SaleBill sale) async {
    try {
      final bytes = await invoicePdf(sale);
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'Invoice-${sale.billNumber}.pdf',
        subject: 'Tax Invoice ${sale.billNumber} - ${session.pharmacyName}',
        body: 'Tax Invoice ${sale.billNumber}, total ${rupees.format(sale.total)}. '
            'Thank you! Get well soon.',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not send invoice: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: PharmacyService.salesRef(session.pharmacyId).doc(saleId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Scaffold(
            appBar: AppBar(title: const Text('Sale bill')),
            body: Center(
              child: snapshot.hasError
                  ? Text('Could not load: ${snapshot.error}')
                  : const CircularProgressIndicator(),
            ),
          );
        }
        final sale = SaleBill.fromFirestore(snapshot.data!);

        return Scaffold(
          appBar: AppBar(
            title: Text('Bill ${sale.billNumber}'),
            actions: [
              IconButton(
                icon: const Icon(Icons.print),
                tooltip: 'Print invoice',
                onPressed: () => printInvoice(context, sale),
              ),
              IconButton(
                icon: const Icon(Icons.picture_as_pdf),
                tooltip: 'Share invoice PDF',
                onPressed: () => sharePdf(context, sale),
              ),
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: 'Copy bill',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: billText(sale)));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Bill copied')),
                  );
                },
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: const Color(0xFF25D366), // WhatsApp green
            icon: const Icon(Icons.share),
            label: const Text('WhatsApp'),
            onPressed: () => shareWhatsApp(context, sale),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              // 1. Header
              Text(session.pharmacyName,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              Text(DateFormat('d MMMM yyyy, h:mm a').format(sale.date),
                  style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Customer: ${sale.customerName}'),
                      if (sale.customerPhone.isNotEmpty)
                        Text('Mobile: ${sale.customerPhone}'),
                      if (sale.doctorName.isNotEmpty)
                        Text('Doctor: ${sale.doctorName}'),
                      Text('Payment: ${sale.paymentMode}  ·  Sold by ${sale.soldBy}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // 2. Items
              for (final l in sale.lines)
                Card(
                  child: ListTile(
                    title: Text(l.name),
                    subtitle: Text(
                      'Batch ${l.batch} · Exp ${DateFormat('MM/yy').format(l.expiry)}'
                      '${l.hsn.isNotEmpty ? ' · HSN ${l.hsn}' : ''}\n'
                      '${l.quantity} × ${rupees.format(l.mrp)}'
                      '${l.discountPct > 0 ? ' − ${pct(l.discountPct)}' : ''}'
                      ' · GST ${pct(l.gstPct)}',
                    ),
                    isThreeLine: true,
                    trailing: Text(rupees.format(l.amount)),
                  ),
                ),
              const SizedBox(height: 8),

              // 3. GST summary
              GstSummary(
                slabs: sale.slabs,
                discount: sale.discountTotal,
                taxable: sale.taxableTotal,
                gst: sale.gstTotal,
                roundOff: sale.roundOff,
                total: sale.total,
                totalLabel: 'Total',
              ),
            ],
          ),
        );
      },
    );
  }
}
