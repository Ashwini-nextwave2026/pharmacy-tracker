import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/session.dart';
import '../models/stock_adjustment.dart';
import '../models/stock_item.dart';
import '../models/supplier.dart';
import '../services/pharmacy_service.dart';
import '../utils/format.dart';
import '../widgets/period_filter.dart';

// Returns to supplier and write-offs.
// Tab 1: batches that are expired or expire within 30 days -> act on them.
// Tab 2: everything returned or written off, for a chosen period.
class ReturnsPage extends StatelessWidget {
  final Session session;

  const ReturnsPage({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Returns & write-offs'),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(icon: Icon(Icons.event_busy), text: 'Expiring stock'),
              Tab(icon: Icon(Icons.history), text: 'History'),
            ],
          ),
        ),
        body: TabBarView(children: [
          _ExpiringTab(session: session),
          _HistoryTab(session: session),
        ]),
      ),
    );
  }
}

// ---- Tab 1: expired and expiring batches ----
class _ExpiringTab extends StatelessWidget {
  final Session session;

  const _ExpiringTab({required this.session});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: PharmacyService.stockRef(session.pharmacyId).orderBy('expiry').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Could not load: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final items = snapshot.data!.docs
            .map(StockItem.fromFirestore)
            .where((i) => i.quantity > 0 && i.status() != ExpiryStatus.safe)
            .toList();
        final expired = items.where((i) => i.status() == ExpiryStatus.expired).toList();
        final soon = items.where((i) => i.status() == ExpiryStatus.soon).toList();

        if (items.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Nothing expired or expiring in the next 30 days.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey)),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (expired.isNotEmpty) _heading('Expired (${expired.length})', Colors.red),
            for (final i in expired) _ItemCard(session: session, item: i),
            if (soon.isNotEmpty) _heading('Expiring within $soonDays days (${soon.length})', Colors.orange),
            for (final i in soon) _ItemCard(session: session, item: i),
          ],
        );
      },
    );
  }

  Widget _heading(String text, Color color) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
        child: Text(text,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
      );
}

class _ItemCard extends StatelessWidget {
  final Session session;
  final StockItem item;

  const _ItemCard({required this.session, required this.item});

  @override
  Widget build(BuildContext context) {
    final days = item.daysLeft();
    final expired = days < 0;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(item.name,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              ),
              Text(
                expired ? 'Expired ${-days}d ago' : (days == 0 ? 'Expires today' : 'In $days days'),
                style: TextStyle(
                    color: expired ? Colors.red : Colors.orange, fontWeight: FontWeight.w600),
              ),
            ]),
            Text(
              'Batch ${item.batch} · Exp ${DateFormat('MM/yy').format(item.expiry)} · '
              'Qty ${item.quantity}'
              '${item.supplier != null ? ' · ${item.supplier}' : ''}',
              style: const TextStyle(color: Colors.grey),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.undo),
                  label: const Text('Return'),
                  onPressed: () => openAdjust(context, session, item, adjustmentReturn),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.delete_sweep, color: Colors.red),
                  label: const Text('Write off', style: TextStyle(color: Colors.red)),
                  onPressed: () => openAdjust(context, session, item, adjustmentWriteOff),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Open the Return / Write-off form for a batch (used here and on Edit stock)
void openAdjust(BuildContext context, Session session, StockItem item, String type) {
  Navigator.push(
    context,
    MaterialPageRoute(
        builder: (context) => AdjustStockPage(session: session, item: item, type: type)),
  );
}

// ---- Tab 2: history ----
class _HistoryTab extends StatefulWidget {
  final Session session;

  const _HistoryTab({required this.session});

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  DatePeriod period = DatePeriod.thisMonth();

  @override
  Widget build(BuildContext context) {
    final showMoney = widget.session.isOwner;
    return Column(
      children: [
        PeriodChips(
          value: period,
          onChanged: (p) => setState(() => period = p),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            key: ValueKey('${period.start}-${period.end}'),
            stream: PharmacyService.adjustmentsRef(widget.session.pharmacyId)
                .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(period.start))
                .where('date', isLessThan: Timestamp.fromDate(period.end))
                .orderBy('date', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Could not load: ${snapshot.error}'));
              }
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final list = snapshot.data!.docs.map(StockAdjustment.fromFirestore).toList();
              final returns = list.where((a) => a.isReturn).toList();
              final writeOffs = list.where((a) => !a.isReturn).toList();
              double sum(List<StockAdjustment> l) => l.fold(0, (t, a) => t + a.value);

              return ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  Card(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(period.label, style: const TextStyle(color: Colors.grey)),
                          const SizedBox(height: 6),
                          Row(children: [
                            const Icon(Icons.undo, color: Colors.indigo),
                            const SizedBox(width: 8),
                            Expanded(child: Text('Returned: ${returns.length}')),
                            if (showMoney) Text(rupees.format(sum(returns))),
                          ]),
                          const SizedBox(height: 4),
                          Row(children: [
                            const Icon(Icons.delete_sweep, color: Colors.red),
                            const SizedBox(width: 8),
                            Expanded(child: Text('Written off: ${writeOffs.length}')),
                            if (showMoney)
                              Text(rupees.format(sum(writeOffs)),
                                  style: const TextStyle(color: Colors.red)),
                          ]),
                          if (showMoney)
                            const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Text('Values at purchase cost. Write-offs are a loss '
                                  'in Monthly Profit; returns come back as supplier credit.',
                                  style: TextStyle(fontSize: 12, color: Colors.grey)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (list.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Nothing returned or written off in this period.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey)),
                    ),
                  for (final a in list)
                    Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                      child: ListTile(
                        leading: Icon(a.isReturn ? Icons.undo : Icons.delete_sweep,
                            color: a.isReturn ? Colors.indigo : Colors.red),
                        title: Text('${a.name} × ${a.quantity}',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${a.isReturn ? 'Returned to ${a.supplier}' : 'Written off'} · ${a.reason}\n'
                          'Batch ${a.batch} · ${DateFormat('d MMM yyyy').format(a.date)} · by ${a.addedBy}'
                          '${a.isReturn ? (a.creditStatus == creditAdjusted ? ' · credit adjusted' : ' · credit pending') : ''}',
                        ),
                        isThreeLine: true,
                        trailing: showMoney ? Text(rupees.format(a.value)) : null,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---- The form: return or write off some units of one batch ----
class AdjustStockPage extends StatefulWidget {
  final Session session;
  final StockItem item;
  final String type; // adjustmentReturn or adjustmentWriteOff

  const AdjustStockPage(
      {super.key, required this.session, required this.item, required this.type});

  @override
  State<AdjustStockPage> createState() => _AdjustStockPageState();
}

class _AdjustStockPageState extends State<AdjustStockPage> {
  final formKey = GlobalKey<FormState>();
  late final qtyController = TextEditingController(text: '${widget.item.quantity}');
  late final supplierController = TextEditingController(text: widget.item.supplier ?? '');
  final noteController = TextEditingController();
  final supplierFocus = FocusNode();
  late String reason = widget.item.status() == ExpiryStatus.expired
      ? 'Expired'
      : (isReturn ? 'Near expiry' : 'Damaged');
  List<Supplier> suppliers = [];
  bool saving = false;

  bool get isReturn => widget.type == adjustmentReturn;

  @override
  void initState() {
    super.initState();
    if (isReturn) {
      PharmacyService.suppliersRef(widget.session.pharmacyId).orderBy('name').get().then((s) {
        if (mounted) setState(() => suppliers = s.docs.map(Supplier.fromFirestore).toList());
      });
    }
  }

  @override
  void dispose() {
    qtyController.dispose();
    supplierController.dispose();
    noteController.dispose();
    supplierFocus.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => saving = true);
    final i = widget.item;
    try {
      await PharmacyService.recordAdjustment(
        widget.session.pharmacyId,
        StockAdjustment(
          type: widget.type,
          stockId: i.id!,
          name: i.name,
          batch: i.batch,
          expiry: i.expiry,
          quantity: int.parse(qtyController.text.trim()),
          costRate: i.unitCost ?? 0,
          mrp: i.mrp ?? 0,
          supplier: isReturn ? supplierController.text.trim() : '',
          reason: reason,
          note: noteController.text.trim(),
          date: DateTime.now(),
          addedBy: widget.session.userName,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isReturn
              ? 'Return saved. Stock reduced; credit is waiting in Supplier Dues.'
              : 'Write-off saved. Stock reduced.')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.item;
    final reasons = isReturn ? returnReasons : writeOffReasons;
    final qty = int.tryParse(qtyController.text.trim()) ?? 0;
    final cost = (i.unitCost ?? 0) * qty;

    return Scaffold(
      appBar: AppBar(title: Text(isReturn ? 'Return to supplier' : 'Write off stock')),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(i.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            Text('Batch ${i.batch} · Exp ${DateFormat('MM/yy').format(i.expiry)} · '
                '${i.quantity} in stock',
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 20),
            TextFormField(
              controller: qtyController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: isReturn ? 'Quantity to return' : 'Quantity to write off',
                border: const OutlineInputBorder(),
                helperText: widget.session.isOwner && i.unitCost != null
                    ? 'Value at cost: ${rupees.format(cost)}'
                    : null,
              ),
              onChanged: (_) => setState(() {}),
              validator: (v) {
                final n = int.tryParse(v?.trim() ?? '');
                if (n == null || n <= 0) return 'Enter a quantity';
                if (n > i.quantity) return 'Only ${i.quantity} in stock';
                return null;
              },
            ),
            const SizedBox(height: 16),
            if (isReturn) ...[
              RawAutocomplete<Supplier>(
                textEditingController: supplierController,
                focusNode: supplierFocus,
                displayStringForOption: (s) => s.name,
                optionsBuilder: (v) => searchSuppliers(suppliers, v.text).take(6),
                fieldViewBuilder: (context, controller, focusNode, onSubmit) => TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Return to supplier',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Which supplier is it going back to?' : null,
                ),
                optionsViewBuilder: (context, onSelected, options) => Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240, maxWidth: 420),
                      child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
                        for (final s in options)
                          ListTile(dense: true, title: Text(s.name), onTap: () => onSelected(s)),
                      ]),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text('Reason', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              for (final r in reasons)
                ChoiceChip(
                  label: Text(r),
                  selected: reason == r,
                  onSelected: (_) => setState(() => reason = r),
                ),
            ]),
            const SizedBox(height: 16),
            TextFormField(
              controller: noteController,
              decoration: InputDecoration(
                labelText: 'Note (optional)',
                hintText: isReturn ? 'e.g. given to sales rep Ramesh' : 'e.g. broken bottle',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: isReturn ? null : FilledButton.styleFrom(backgroundColor: Colors.red),
              icon: saving
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(isReturn ? Icons.undo : Icons.delete_sweep),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(isReturn ? 'Save return' : 'Write off'),
              ),
              onPressed: saving ? null : save,
            ),
          ],
        ),
      ),
    );
  }
}
