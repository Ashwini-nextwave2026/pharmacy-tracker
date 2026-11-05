import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/expense.dart';
import '../models/profit_report.dart';
import '../models/purchase_bill.dart';
import '../models/sale_bill.dart';
import '../models/session.dart';
import '../models/stock_item.dart';
import '../services/pharmacy_service.dart';
import '../utils/format.dart';

// Owner only: one month's profit
// (sales - cost of medicines sold - expenses).
class ProfitPage extends StatefulWidget {
  final Session session;

  const ProfitPage({super.key, required this.session});

  @override
  State<ProfitPage> createState() => _ProfitPageState();
}

class _ProfitPageState extends State<ProfitPage> {
  // Start on THIS month (so far)
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  Future<ProfitReport>? report;

  @override
  void initState() {
    super.initState();
    load();
  }

  void changeMonth(int by) {
    final next = DateTime(month.year, month.month + by);
    if (next.isAfter(DateTime.now())) return;
    setState(() => month = next);
    load();
  }

  void load() {
    final pid = widget.session.pharmacyId;
    final start = Timestamp.fromDate(month);
    final end = Timestamp.fromDate(DateTime(month.year, month.month + 1));

    setState(() {
      report = () async {
        final results = await Future.wait([
          PharmacyService.salesRef(pid)
              .where('date', isGreaterThanOrEqualTo: start)
              .where('date', isLessThan: end)
              .get(),
          PharmacyService.expensesRef(pid)
              .where('date', isGreaterThanOrEqualTo: start)
              .where('date', isLessThan: end)
              .get(),
          PharmacyService.billsRef(pid)
              .where('billDate', isGreaterThanOrEqualTo: start)
              .where('billDate', isLessThan: end)
              .get(),
        ]);
        final sales = results[0].docs.map(SaleBill.fromFirestore).toList();

        // Older sale lines don't carry their cost: look it up from stock
        final missing = <String>{
          for (final s in sales)
            for (final l in s.lines)
              if (l.costRate == null && l.stockId.isNotEmpty) l.stockId,
        };
        final stockCosts = <String, double>{};
        final snaps = await Future.wait(
            missing.map((id) => PharmacyService.stockRef(pid).doc(id).get()));
        for (final snap in snaps) {
          if (!snap.exists) continue;
          final cost = StockItem.fromFirestore(snap).unitCost;
          if (cost != null) stockCosts[snap.id] = cost;
        }

        return ProfitReport(
          month: month,
          sales: sales,
          expenses: results[1].docs.map(Expense.fromFirestore).toList(),
          purchases: results[2].docs.map(PurchaseBill.fromFirestore).toList(),
          stockCosts: stockCosts,
        );
      }();
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrent = month.year == now.year && month.month == now.month;
    final canGoNext = !isCurrent;

    return Scaffold(
      appBar: AppBar(title: const Text('Monthly profit')),
      body: FutureBuilder<ProfitReport>(
        future: report,
        builder: (context, snapshot) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 1. Month picker
              Card(
                child: Row(children: [
                  IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => changeMonth(-1)),
                  Expanded(
                    child: Column(children: [
                      Text(DateFormat('MMMM yyyy').format(month),
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      if (isCurrent)
                        Text('So far, up to ${DateFormat('d MMM').format(now)}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ]),
                  ),
                  IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: canGoNext ? () => changeMonth(1) : null),
                ]),
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

  List<Widget> _report(ProfitReport r) {
    final positive = r.netProfit >= 0;
    final color = positive ? Colors.green.shade700 : Colors.red;
    final top = r.topMedicines.take(5).toList();

    return [
      // 2. The answer first
      Card(
        color: color.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Text(positive ? 'Net profit' : 'Net loss'),
            Text(rupees.format(r.netProfit.abs()),
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: color)),
            Text('${r.sales.length} sale bills · gross margin '
                '${r.grossMarginPct.toStringAsFixed(1)}%',
                style: const TextStyle(color: Colors.grey)),
          ]),
        ),
      ),

      // 3. How it's worked out
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            _row('Sales (without GST)', r.salesValue),
            _row('Less: cost of medicines sold', -r.costOfSales),
            const Divider(),
            _row('Gross profit', r.grossProfit, bold: true),
            const SizedBox(height: 8),
            _row('Less: expenses', -r.expensesTotal),
            const Divider(),
            _row(positive ? 'Net profit' : 'Net loss', r.netProfit, bold: true, color: color),
          ]),
        ),
      ),

      // 4. Warning if some sales have no cost price
      if (r.linesWithoutCost > 0)
        Card(
          color: Colors.orange.withValues(alpha: 0.10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              '${r.linesWithoutCost} sold item${r.linesWithoutCost == 1 ? '' : 's'} '
              '(${rupees.format(r.salesWithoutCost)} of sales) had no purchase rate, '
              'so they are left out of profit. Add the purchase rate to those stock '
              'batches, or enter stock through purchase bills, for a full picture.',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),

      // 5. Expenses by category
      if (r.expenses.isNotEmpty)
        _section('Expenses', [
          for (final e in r.expensesByCat) _row(e.key, e.value),
        ]),

      // 6. Best-earning medicines
      if (top.isNotEmpty)
        _section('Top medicines by profit', [
          for (final m in top) _row(m.key, m.value),
        ]),

      // 7. For information
      _section('For information', [
        _row('Sales including GST (collected)', r.salesWithGst),
        _row('GST collected (not profit)', r.gstCollected),
        _row('Stock bought this month (without GST)', r.purchasesValue),
      ]),
      const Padding(
        padding: EdgeInsets.fromLTRB(4, 8, 4, 24),
        child: Text(
          'Profit counts only the medicines SOLD this month at their purchase cost. '
          'Stock bought but still on the shelf is not a cost yet. Expired or '
          'damaged stock written off is not included yet.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ),
    ];
  }

  Widget _section(String title, List<Widget> rows) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              ...rows,
            ],
          ),
        ),
      );

  Widget _row(String label, double value, {bool bold = false, Color? color}) {
    final style = TextStyle(
        fontSize: bold ? 17 : 14,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(label, style: style)),
        Text(rupees.format(value), style: style),
      ]),
    );
  }
}
