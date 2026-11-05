import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/expense.dart';
import '../models/session.dart';
import '../services/pharmacy_service.dart';
import '../utils/format.dart';
import '../widgets/period_filter.dart';

// Owner only: the shop's expenses for a chosen period, with totals
// by category. Tap one to edit it, swipe left to delete.
class ExpensePage extends StatefulWidget {
  final Session session;

  const ExpensePage({super.key, required this.session});

  @override
  State<ExpensePage> createState() => _ExpensePageState();
}

class _ExpensePageState extends State<ExpensePage> {
  DatePeriod period = DatePeriod.thisMonth();

  CollectionReference<Map<String, dynamic>> get ref =>
      PharmacyService.expensesRef(widget.session.pharmacyId);

  void openForm([Expense? expense]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ExpenseFormPage(session: widget.session, expense: expense),
      ),
    );
  }

  Future<bool> confirmDelete(Expense e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this expense?'),
        content: Text('${e.category}, ${rupees.format(e.amount)} on '
            '${DateFormat('d MMM yyyy').format(e.date)}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Expenditure')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
        onPressed: () => openForm(),
      ),
      body: Column(
        children: [
          PeriodChips(
            value: period,
            pickHelpText: 'Choose expense dates',
            onChanged: (p) => setState(() => period = p),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              key: ValueKey('${period.start}-${period.end}'),
              stream: ref
                  .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(period.start))
                  .where('date', isLessThan: Timestamp.fromDate(period.end))
                  .orderBy('date', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Could not load: ${snapshot.error}',
                          style: const TextStyle(color: Colors.red)),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list = snapshot.data!.docs.map(Expense.fromFirestore).toList();
                final total = list.fold<double>(0, (t, e) => t + e.amount);
                final byCategory = expensesByCategory(list);

                return ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    // 1. Total and split by category
                    Card(
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      color: Colors.deepOrange.withValues(alpha: 0.08),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(period.label, style: const TextStyle(color: Colors.grey)),
                            Row(children: [
                              Text(rupees.format(total),
                                  style: const TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.deepOrange)),
                              const Spacer(),
                              Text('${list.length} expense${list.length == 1 ? '' : 's'}',
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                            ]),
                            if (byCategory.isNotEmpty) ...[
                              const Divider(height: 20),
                              for (final c in byCategory)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(children: [
                                    Expanded(child: Text(c.key)),
                                    // simple bar showing the share of the total
                                    SizedBox(
                                      width: 80,
                                      child: LinearProgressIndicator(
                                        value: total == 0 ? 0 : c.value / total,
                                        color: Colors.deepOrange,
                                        backgroundColor:
                                            Colors.deepOrange.withValues(alpha: 0.1),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 100,
                                      child: Text(rupees.format(c.value),
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(fontWeight: FontWeight.w500)),
                                    ),
                                  ]),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (list.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('No expenses in this period.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, color: Colors.grey)),
                      ),

                    // 2. Each expense
                    for (final e in list)
                      Dismissible(
                        key: ValueKey(e.id),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) => confirmDelete(e),
                        onDismissed: (_) => ref.doc(e.id).delete(),
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        child: Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.deepOrange.withValues(alpha: 0.12),
                              child: Icon(iconFor(e.category), color: Colors.deepOrange),
                            ),
                            title: Text(e.category,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                                '${DateFormat('d MMM yyyy').format(e.date)} · ${e.mode}'
                                '${e.note.isNotEmpty ? '\n${e.note}' : ''}'),
                            isThreeLine: e.note.isNotEmpty,
                            trailing: Text(rupees.format(e.amount),
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            onTap: () => openForm(e),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

IconData iconFor(String category) {
  switch (category) {
    case 'Rent':
      return Icons.home_work;
    case 'Electricity':
      return Icons.bolt;
    case 'Salary':
      return Icons.badge;
    case 'Tea & snacks':
      return Icons.local_cafe;
    case 'Transport':
      return Icons.two_wheeler;
    case 'Phone & internet':
      return Icons.wifi;
    case 'Repairs':
      return Icons.build;
    case 'Stationery':
      return Icons.edit_note;
    case 'Licence & fees':
      return Icons.verified;
    default:
      return Icons.receipt;
  }
}

// Add a new expense, or edit one (pass [expense])
class ExpenseFormPage extends StatefulWidget {
  final Session session;
  final Expense? expense;

  const ExpenseFormPage({super.key, required this.session, this.expense});

  @override
  State<ExpenseFormPage> createState() => _ExpenseFormPageState();
}

class _ExpenseFormPageState extends State<ExpenseFormPage> {
  final formKey = GlobalKey<FormState>();
  late final old = widget.expense;
  late final amountController =
      TextEditingController(text: old == null ? '' : old!.amount.toStringAsFixed(2));
  late final noteController = TextEditingController(text: old?.note);
  late DateTime date = old?.date ?? DateTime.now();
  late String category = old?.category ?? expenseCategories.first;
  late String mode = old?.mode ?? 'Cash';
  bool saving = false;

  @override
  void dispose() {
    amountController.dispose();
    noteController.dispose();
    super.dispose();
  }

  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(DateTime.now().year - 2),
      lastDate: DateTime.now(),
      helpText: 'Expense date',
    );
    if (picked != null) setState(() => date = picked);
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => saving = true);
    final expense = Expense(
      date: DateTime(date.year, date.month, date.day, 12), // midday: safe for any filter
      category: category,
      amount: double.parse(amountController.text.trim()),
      mode: mode,
      note: noteController.text.trim(),
      addedBy: widget.session.userName,
    );
    try {
      final ref = PharmacyService.expensesRef(widget.session.pharmacyId);
      if (old == null) {
        await ref.add({...expense.toMap(), 'createdAt': FieldValue.serverTimestamp()});
      } else {
        await ref.doc(old!.id).update(expense.toMap());
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(old == null ? 'Add expense' : 'Edit expense')),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // 1. What for
            Text('Category', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final c in expenseCategories)
                  ChoiceChip(
                    avatar: Icon(iconFor(c), size: 18),
                    label: Text(c),
                    selected: category == c,
                    onSelected: (_) => setState(() => category = c),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            // 2. Amount and date
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: amountController,
                    autofocus: old == null,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      prefixText: '₹ ',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final n = double.tryParse(v?.trim() ?? '');
                      if (n == null || n <= 0) return 'Enter the amount';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(DateFormat('d MMM yyyy').format(date)),
                    ),
                    onPressed: pickDate,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 3. How it was paid
            Text('Paid by', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final m in expensePayModes)
                  ChoiceChip(
                    label: Text(m),
                    selected: mode == m,
                    onSelected: (_) => setState(() => mode = m),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            // 4. Note
            TextFormField(
              controller: noteController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'e.g. October bill, Ravi salary, auto to distributor',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),

            ElevatedButton.icon(
              icon: saving
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(old == null ? 'Save expense' : 'Save changes'),
              ),
              onPressed: saving ? null : save,
            ),
          ],
        ),
      ),
    );
  }
}
