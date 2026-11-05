import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/purchase_bill.dart';
import '../models/session.dart';
import '../services/pharmacy_service.dart';
import '../utils/format.dart';
import '../widgets/gst_summary.dart';
import '../widgets/period_filter.dart';
import 'add_bill_page.dart';
import 'record_payment_page.dart';

// Purchase bills for a chosen period (Today, Yesterday, This month or
// dates you pick), by bill date, newest first, with totals at the top.
// Staff see the bills but not the money: rates and totals are owner-only.
class BillListPage extends StatefulWidget {
  final Session session;

  const BillListPage({super.key, required this.session});

  @override
  State<BillListPage> createState() => _BillListPageState();
}

class _BillListPageState extends State<BillListPage> {
  DatePeriod period = DatePeriod.today();

  Session get session => widget.session;

  CollectionReference<Map<String, dynamic>> get billsRef =>
      PharmacyService.billsRef(session.pharmacyId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Purchase bills')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.receipt_long),
        label: const Text('New bill'),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => AddBillPage(session: session)),
        ),
      ),
      body: Column(
        children: [
          // 1. Period buttons
          PeriodChips(
            value: period,
            pickHelpText: 'Choose bill dates',
            onChanged: (p) => setState(() => period = p),
          ),

          // 2. Bills dated in that period, live
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              key: ValueKey('${period.start}-${period.end}'),
              stream: billsRef
                  .where('billDate',
                      isGreaterThanOrEqualTo: Timestamp.fromDate(period.start))
                  .where('billDate', isLessThan: Timestamp.fromDate(period.end))
                  .orderBy('billDate', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Could not load bills: ${snapshot.error}',
                          style: const TextStyle(color: Colors.red)),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;
                final bills = docs.map(PurchaseBill.fromFirestore).toList();

                return ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    summaryCard(bills),
                    if (bills.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('No purchase bills dated in this period.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, color: Colors.grey)),
                      ),
                    for (var i = 0; i < bills.length; i++)
                      billCard(bills[i],
                          (docs[i].data()['addedBy'] as Map?)?['name'] as String?),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Owner: total, GST credit and top suppliers. Staff: counts only.
  Widget summaryCard(List<PurchaseBill> bills) {
    final total = bills.fold<double>(0, (t, b) => t + b.total);
    final gst = bills.fold<double>(0, (t, b) => t + b.gstTotal);
    final items = bills.fold<int>(0, (t, b) => t + b.lines.length);
    final bySupplier = <String, double>{};
    for (final b in bills) {
      bySupplier[b.supplier] = (bySupplier[b.supplier] ?? 0) + b.total;
    }
    final top = bySupplier.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: Colors.indigo.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(period.label, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  session.isOwner
                      ? rupees.format(total)
                      : '${bills.length} bill${bills.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo),
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (session.isOwner)
                      Text('${bills.length} bill${bills.length == 1 ? '' : 's'}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('$items item${items == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    if (session.isOwner)
                      Text('GST credit ${rupees.format(gst)}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ],
            ),
            if (session.isOwner && top.isNotEmpty) ...[
              const Divider(height: 20),
              for (final e in top.take(3))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(e.key,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13)),
                      ),
                      Text(rupees.format(e.value),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              if (top.length > 3)
                Text('+ ${top.length - 3} more supplier${top.length - 3 == 1 ? '' : 's'}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ],
        ),
      ),
    );
  }

  Widget billCard(PurchaseBill bill, String? addedBy) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: ListTile(
          leading: const Icon(Icons.receipt_long, size: 32),
          title: Text(bill.supplier,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
              'Bill ${bill.billNumber} · ${DateFormat('d MMM yyyy').format(bill.billDate)} · ${bill.lines.length} items'
              '${addedBy != null ? '\nEntered by $addedBy' : ''}'),
          isThreeLine: addedBy != null,
          trailing: session.isOwner
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(rupees.format(bill.total),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    PaymentBadge(bill: bill),
                  ],
                )
              : null,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) =>
                    BillDetailPage(bill: bill, session: session)),
          ),
        ),
      );
}

// Small coloured label: Paid (green), Part paid (orange), Unpaid / Overdue (red)
class PaymentBadge extends StatelessWidget {
  final PurchaseBill bill;

  const PaymentBadge({super.key, required this.bill});

  @override
  Widget build(BuildContext context) {
    final overdue = bill.overdueDays();
    final color = bill.isPaid
        ? Colors.green
        : (overdue > 0 ? Colors.red : (bill.isPartPaid ? Colors.orange : Colors.blueGrey));
    final label = bill.isPaid
        ? 'Paid'
        : (overdue > 0 ? 'Overdue ${overdue}d' : bill.statusLabel);
    return Container(
      margin: const EdgeInsets.only(top: 3),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

// Read-only view of one bill
class BillDetailPage extends StatelessWidget {
  final PurchaseBill bill;
  final Session session;

  const BillDetailPage({super.key, required this.bill, required this.session});

  @override
  Widget build(BuildContext context) {
    // Watch the bill live, so "paid" updates right after a payment
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: PharmacyService.billsRef(session.pharmacyId).doc(bill.id).snapshots(),
      builder: (context, snap) {
        final live = (snap.hasData && snap.data!.exists)
            ? PurchaseBill.fromFirestore(snap.data!)
            : bill;
        return _page(context, live);
      },
    );
  }

  Widget _page(BuildContext context, PurchaseBill bill) {
    final showMoney = session.isOwner;

    return Scaffold(
      appBar: AppBar(title: Text('Bill ${bill.billNumber}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (showMoney) _paymentCard(context, bill),
          Text(bill.supplier,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          if (bill.supplierGstin.isNotEmpty)
            Text('GSTIN ${bill.supplierGstin}'),
          Text(
              '${DateFormat('d MMMM yyyy').format(bill.billDate)}'
              '${bill.interState ? '  ·  Inter-state (IGST)' : ''}',
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          for (final line in bill.lines)
            Card(
              child: ListTile(
                title: Text(
                    '${line.name}${line.pack.isNotEmpty ? '  ·  ${line.pack}' : ''}'),
                subtitle: Text(
                  'Batch ${line.batch} · Exp ${DateFormat('MM/yy').format(line.expiry)}'
                  '${line.hsn.isNotEmpty ? ' · HSN ${line.hsn}' : ''}\n'
                  '${showMoney ? '${line.quantity} × ${rupees.format(line.rate)}' : 'Qty ${line.quantity}'}'
                  '${line.free > 0 ? ' + ${line.free} free' : ''}'
                  '${showMoney && line.discountPct > 0 ? ' − ${pct(line.discountPct)}' : ''}'
                  ' · GST ${pct(line.gstPct)} · MRP ${rupees.format(line.mrp)}',
                ),
                isThreeLine: true,
                trailing: showMoney ? Text(rupees.format(line.amount)) : null,
              ),
            ),
          const SizedBox(height: 12),
          if (showMoney)
            GstSummary(
              slabs: bill.slabs,
              discount: bill.discountTotal,
              taxable: bill.taxableTotal,
              gst: bill.gstTotal,
              interState: bill.interState,
              roundOff: bill.roundOff,
              total: bill.total,
            )
          else
            Text(
                'Total ${bill.totalUnits} units'
                '${bill.totalFree > 0 ? ' + ${bill.totalFree} free' : ''}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // Owner: paid / balance / due date, and a button to pay this bill
  Widget _paymentCard(BuildContext context, PurchaseBill bill) {
    final overdue = bill.overdueDays();
    final color = bill.isPaid ? Colors.green : (overdue > 0 ? Colors.red : Colors.indigo);
    return Card(
      color: color.withValues(alpha: 0.08),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(bill.isPaid ? Icons.check_circle : Icons.schedule, color: color),
              const SizedBox(width: 8),
              Text(bill.isPaid ? 'Fully paid' : bill.statusLabel,
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: color, fontSize: 16)),
              const Spacer(),
              PaymentBadge(bill: bill),
            ]),
            const SizedBox(height: 8),
            Text('Total ${rupees.format(bill.total)} · paid ${rupees.format(bill.paid)}'
                '${bill.isPaid ? '' : ' · balance ${rupees.format(bill.balance)}'}'),
            Text(
              bill.creditDays == 0
                  ? 'Payment on delivery'
                  : '${bill.creditDays} days credit · due ${DateFormat('d MMM yyyy').format(bill.dueDate)}',
              style: const TextStyle(color: Colors.grey),
            ),
            if (!bill.isPaid) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                icon: const Icon(Icons.payments),
                label: Text('Pay this bill (${rupees.format(bill.balance)})'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RecordPaymentPage(
                        session: session, supplier: bill.supplier, bill: bill),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
