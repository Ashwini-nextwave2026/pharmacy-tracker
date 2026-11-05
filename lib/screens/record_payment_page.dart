import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/purchase_bill.dart';
import '../models/session.dart';
import '../models/supplier_payment.dart';
import '../services/pharmacy_service.dart';
import '../utils/format.dart';

// Record a payment to a supplier.
// With [bill], the payment goes against that one bill.
// Without it, it's spread over the supplier's unpaid bills, oldest first.
class RecordPaymentPage extends StatefulWidget {
  final Session session;
  final String supplier;
  final PurchaseBill? bill;

  const RecordPaymentPage(
      {super.key, required this.session, required this.supplier, this.bill});

  @override
  State<RecordPaymentPage> createState() => _RecordPaymentPageState();
}

class _RecordPaymentPageState extends State<RecordPaymentPage> {
  final formKey = GlobalKey<FormState>();
  final amountController = TextEditingController();
  final referenceController = TextEditingController();
  final noteController = TextEditingController();
  DateTime date = DateTime.now();
  String mode = 'Cash';
  List<PurchaseBill> bills = [];
  bool loading = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    amountController.addListener(() => setState(() {}));
    load();
  }

  @override
  void dispose() {
    amountController.dispose();
    referenceController.dispose();
    noteController.dispose();
    super.dispose();
  }

  // Load the bills this payment can go against, and fill in the balance
  Future<void> load() async {
    var list = await PharmacyService.supplierBills(
        widget.session.pharmacyId, widget.supplier);
    if (widget.bill != null) list = list.where((b) => b.id == widget.bill!.id).toList();
    if (!mounted) return;
    final due = list.fold<double>(0, (t, b) => t + b.balance);
    setState(() {
      bills = list;
      if (due > 0) amountController.text = due.toStringAsFixed(2);
      loading = false;
    });
  }

  double get outstanding => bills.fold(0, (t, b) => t + b.balance);

  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(DateTime.now().year - 2),
      lastDate: DateTime.now(),
      helpText: 'Payment date',
    );
    if (picked != null) setState(() => date = picked);
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      final payment = await PharmacyService.recordSupplierPayment(
        pharmacyId: widget.session.pharmacyId,
        onlyBillId: widget.bill?.id,
        payment: SupplierPayment(
          supplier: widget.supplier,
          amount: double.parse(amountController.text.trim()),
          date: date,
          mode: mode,
          reference: referenceController.text.trim(),
          note: noteController.text.trim(),
          addedBy: widget.session.userName,
        ),
      );
      if (!mounted) return;
      final n = payment.allocations.length;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Payment saved: ${rupees.format(payment.amount)} '
            'against $n bill${n == 1 ? '' : 's'}'
            '${payment.advance > 0 ? ', ${rupees.format(payment.advance)} as advance' : ''}'),
      ));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = double.tryParse(amountController.text.trim()) ?? 0;
    final preview = allocatePayment(amount, bills);

    return Scaffold(
      appBar: AppBar(title: const Text('Record payment')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // 1. Who and how much is due
                  Text(widget.supplier,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  Text(
                    widget.bill != null
                        ? 'Bill ${widget.bill!.billNumber} · balance ${rupees.format(outstanding)}'
                        : 'Balance due ${rupees.format(outstanding)} on '
                            '${bills.where((b) => !b.isPaid).length} bills',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 20),

                  // 2. Amount and date
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: amountController,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Amount paid',
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
                  const SizedBox(height: 16),

                  // 3. How it was paid
                  Text('Paid by', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final m in supplierPayModes)
                        ChoiceChip(
                          label: Text(m),
                          selected: mode == m,
                          onSelected: (_) => setState(() => mode = m),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: referenceController,
                    decoration: InputDecoration(
                      labelText: mode == 'Cheque'
                          ? 'Cheque number'
                          : (mode == 'Cash' ? 'Receipt number (optional)' : 'UTR / reference (optional)'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 4. Which bills it will clear
                  if (amount > 0)
                    Card(
                      color: Colors.teal.withValues(alpha: 0.08),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('This payment will go to',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            for (final a in preview.allocations)
                              Row(children: [
                                Text('Bill ${a.billNumber}'),
                                const Spacer(),
                                Text(rupees.format(a.amount)),
                              ]),
                            if (preview.advance > 0)
                              Row(children: [
                                const Text('Advance (extra)',
                                    style: TextStyle(color: Colors.orange)),
                                const Spacer(),
                                Text(rupees.format(preview.advance),
                                    style: const TextStyle(color: Colors.orange)),
                              ]),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),

                  ElevatedButton.icon(
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check_circle),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Save payment'),
                    ),
                    onPressed: saving ? null : save,
                  ),
                ],
              ),
            ),
    );
  }
}
