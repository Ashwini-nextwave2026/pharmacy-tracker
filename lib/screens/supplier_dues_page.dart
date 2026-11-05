import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/purchase_bill.dart';
import '../models/session.dart';
import '../models/supplier_payment.dart';
import '../services/pharmacy_service.dart';
import '../utils/format.dart';
import 'bill_list_page.dart' show BillDetailPage;
import 'record_payment_page.dart';

// Owner only: how much the pharmacy owes each supplier.
class SupplierDuesPage extends StatelessWidget {
  final Session session;

  const SupplierDuesPage({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Supplier dues')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: PharmacyService.billsRef(session.pharmacyId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Could not load: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final bills = snapshot.data!.docs.map(PurchaseBill.fromFirestore).toList();
          final suppliers = groupBySupplier(bills);
          final owing = suppliers.where((s) => s.outstanding > 0.5).toList();
          final settled = suppliers.where((s) => s.outstanding <= 0.5).toList();
          final total = owing.fold<double>(0, (t, s) => t + s.outstanding);
          final overdue = owing.fold<double>(0, (t, s) => t + s.overdueAmount);

          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              // 1. Total owed
              Card(
                margin: const EdgeInsets.all(16),
                color: Colors.indigo.withValues(alpha: 0.10),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total you owe suppliers',
                          style: TextStyle(color: Colors.grey)),
                      Text(rupees.format(total),
                          style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo)),
                      const SizedBox(height: 4),
                      Text(
                        overdue > 0
                            ? '${rupees.format(overdue)} is past its due date'
                            : 'Nothing overdue',
                        style: TextStyle(
                            color: overdue > 0 ? Colors.red : Colors.green,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),

              // 2. Suppliers you owe, most first
              if (owing.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('All supplier bills are paid.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.grey)),
                ),
              for (final s in owing) _supplierTile(context, s),

              // 3. Fully paid suppliers
              if (settled.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Text('Fully paid', style: TextStyle(color: Colors.grey)),
                ),
                for (final s in settled) _supplierTile(context, s),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _supplierTile(BuildContext context, SupplierDue s) {
    final overdue = s.maxOverdueDays;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              (overdue > 0 ? Colors.red : Colors.indigo).withValues(alpha: 0.12),
          child: Icon(Icons.local_shipping,
              color: overdue > 0 ? Colors.red : Colors.indigo),
        ),
        title: Text(s.supplier, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(s.outstanding > 0.5
            ? '${s.unpaidCount} unpaid bill${s.unpaidCount == 1 ? '' : 's'}'
                '${overdue > 0 ? ' · oldest $overdue days overdue' : ''}'
            : '${s.bills.length} bill${s.bills.length == 1 ? '' : 's'}, all paid'),
        trailing: Text(
          s.outstanding > 0.5 ? rupees.format(s.outstanding) : 'Paid',
          style: TextStyle(
              fontWeight: FontWeight.bold,
              color: s.outstanding > 0.5
                  ? (overdue > 0 ? Colors.red : null)
                  : Colors.green),
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                SupplierAccountPage(session: session, supplier: s.supplier),
          ),
        ),
      ),
    );
  }
}

// One supplier: what's owed, the unpaid bills, and payments made
class SupplierAccountPage extends StatelessWidget {
  final Session session;
  final String supplier;

  const SupplierAccountPage({super.key, required this.session, required this.supplier});

  @override
  Widget build(BuildContext context) {
    final pid = session.pharmacyId;

    return Scaffold(
      appBar: AppBar(title: Text(supplier)),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.payments),
        label: const Text('Record payment'),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                RecordPaymentPage(session: session, supplier: supplier),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: PharmacyService.billsRef(pid).where('supplier', isEqualTo: supplier).snapshots(),
        builder: (context, billSnap) {
          if (billSnap.hasError) {
            return Center(child: Text('Could not load: ${billSnap.error}'));
          }
          if (!billSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final bills = billSnap.data!.docs.map(PurchaseBill.fromFirestore).toList()
            ..sort((a, b) => a.billDate.compareTo(b.billDate)); // oldest first
          final due = SupplierDue(supplier, bills);
          final unpaid = bills.where((b) => !b.isPaid).toList();

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: PharmacyService.paymentsRef(pid)
                .where('supplier', isEqualTo: supplier)
                .snapshots(),
            builder: (context, paySnap) {
              final payments = paySnap.hasData
                  ? (paySnap.data!.docs.map(SupplierPayment.fromFirestore).toList()
                    ..sort((a, b) => b.date.compareTo(a.date))) // newest first
                  : <SupplierPayment>[];

              return ListView(
                padding: const EdgeInsets.only(bottom: 96),
                children: [
                  // 1. Summary
                  Card(
                    margin: const EdgeInsets.all(16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _row('Total billed', due.billed),
                          _row('Paid', due.paid),
                          const Divider(),
                          _row('Balance due', due.outstanding, bold: true,
                              color: due.outstanding > 0.5 ? Colors.indigo : Colors.green),
                          if (due.overdueAmount > 0)
                            _row('Overdue', due.overdueAmount, color: Colors.red),
                        ],
                      ),
                    ),
                  ),

                  // 2. Unpaid bills, oldest first
                  _heading('Unpaid bills (${unpaid.length})'),
                  if (unpaid.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Text('Nothing due.', style: TextStyle(color: Colors.grey)),
                    ),
                  for (final b in unpaid) _billTile(context, b),

                  // 3. Payments made
                  _heading('Payments made (${payments.length})'),
                  if (payments.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Text('No payments recorded yet.',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  for (final p in payments) _paymentTile(p),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _heading(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      );

  Widget _row(String label, double value, {bool bold = false, Color? color}) {
    final style = TextStyle(
        fontSize: bold ? 18 : 14,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Text(label, style: style),
        const Spacer(),
        Text(rupees.format(value), style: style),
      ]),
    );
  }

  Widget _billTile(BuildContext context, PurchaseBill b) {
    final overdue = b.overdueDays();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: ListTile(
        title: Text('Bill ${b.billNumber}  ·  ${DateFormat('d MMM yyyy').format(b.billDate)}'),
        subtitle: Text(
          '${b.statusLabel} · total ${rupees.format(b.total)}'
          '${b.paid > 0 ? ', paid ${rupees.format(b.paid)}' : ''}\n'
          '${overdue > 0 ? 'Overdue by $overdue days' : 'Due ${DateFormat('d MMM yyyy').format(b.dueDate)}'}',
          style: TextStyle(color: overdue > 0 ? Colors.red : null),
        ),
        isThreeLine: true,
        trailing: Text(rupees.format(b.balance),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => BillDetailPage(bill: b, session: session)),
        ),
      ),
    );
  }

  Widget _paymentTile(SupplierPayment p) {
    final bills = p.allocations.map((a) => a.billNumber).join(', ');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: ListTile(
        leading: const Icon(Icons.payments, color: Colors.green),
        title: Text(
            '${rupees.format(p.amount)}  ·  ${DateFormat('d MMM yyyy').format(p.date)}'),
        subtitle: Text(
          '${p.mode}${p.reference.isNotEmpty ? ' · Ref ${p.reference}' : ''}'
          '${bills.isNotEmpty ? '\nFor bill${p.allocations.length == 1 ? '' : 's'} $bills' : ''}'
          '${p.advance > 0 ? '\nAdvance (not matched to a bill): ${rupees.format(p.advance)}' : ''}'
          '${p.note.isNotEmpty ? '\n${p.note}' : ''}',
        ),
      ),
    );
  }
}
