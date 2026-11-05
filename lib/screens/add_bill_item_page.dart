import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/purchase_bill.dart';
import '../utils/format.dart';

// A form for ONE line of a purchase bill, in the order of the paper bill.
// It doesn't save anything itself: it hands the line back to the bill screen
// with Navigator.pop(context, line).
class AddBillItemPage extends StatefulWidget {
  final BillLine? line; // pass a line to edit it; leave out to add a new one

  const AddBillItemPage({super.key, this.line});

  @override
  State<AddBillItemPage> createState() => _AddBillItemPageState();
}

class _AddBillItemPageState extends State<AddBillItemPage> {
  final formKey = GlobalKey<FormState>();
  // When editing, every box starts filled in with the line's current values
  late final BillLine? old = widget.line;
  bool get isEditing => old != null;
  late final nameController = TextEditingController(text: old?.name);
  late final hsnController = TextEditingController(text: old?.hsn ?? '3004');
  late final packController = TextEditingController(text: old?.pack);
  late final batchController = TextEditingController(text: old?.batch);
  late final quantityController =
      TextEditingController(text: old?.quantity.toString());
  late final freeController =
      TextEditingController(text: (old?.free ?? 0).toString());
  late final rateController = TextEditingController(text: old?.rate.toString());
  late final discountController =
      TextEditingController(text: (old?.discountPct ?? 0).toString());
  late final mrpController = TextEditingController(text: old?.mrp.toString());
  late DateTime? expiry = old?.expiry;
  late double gstPct = old?.gstPct ?? 5; // most medicines are 5% GST

  @override
  void initState() {
    super.initState();
    // Re-draw the live preview whenever a number changes
    for (final c in [quantityController, rateController, discountController]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [
      nameController, hsnController, packController, batchController,
      quantityController, freeController, rateController,
      discountController, mrpController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: expiry ?? DateTime(now.year + 1, now.month, now.day),
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 10),
      helpText: 'Select expiry (any day in the month)',
    );
    // Bills print expiry as MM/YY: treat it as the LAST day of that month
    if (picked != null) {
      setState(() => expiry = DateTime(picked.year, picked.month + 1, 0));
    }
  }

  // Shared check for number fields
  String? validateNumber(String? value, String label, {bool whole = false}) {
    final text = value?.trim() ?? '';
    final number = whole ? int.tryParse(text) : double.tryParse(text);
    if (number == null) {
      return whole ? '$label must be a whole number' : '$label must be a number';
    }
    if (number < 0) return '$label can\'t be negative';
    return null;
  }

  // The line as typed so far (null if numbers are missing)
  BillLine? get preview {
    final qty = int.tryParse(quantityController.text.trim());
    final rate = double.tryParse(rateController.text.trim());
    if (qty == null || rate == null) return null;
    return BillLine(
      name: '',
      batch: '',
      expiry: DateTime.now(),
      quantity: qty,
      rate: rate,
      discountPct: double.tryParse(discountController.text.trim()) ?? 0,
      gstPct: gstPct,
      mrp: 0,
    );
  }

  void done() {
    final formOk = formKey.currentState!.validate();
    if (expiry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose an expiry date')),
      );
      return;
    }
    if (!formOk) return;

    final line = BillLine(
      name: nameController.text.trim(),
      hsn: hsnController.text.trim(),
      pack: packController.text.trim(),
      batch: batchController.text.trim().toUpperCase(),
      expiry: expiry!,
      quantity: int.parse(quantityController.text.trim()),
      free: int.parse(freeController.text.trim()),
      rate: double.parse(rateController.text.trim()),
      discountPct: double.parse(discountController.text.trim()),
      gstPct: gstPct,
      mrp: double.parse(mrpController.text.trim()),
    );
    Navigator.pop(context, line); // send the line back to the bill screen
  }

  InputDecoration box(String label, {String? prefix, String? suffix, String? hint}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefix,
        suffixText: suffix,
        border: const OutlineInputBorder(),
        isDense: true,
      );

  Widget pair(Widget a, Widget b) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)],
      );

  @override
  Widget build(BuildContext context) {
    final p = preview;

    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Edit item' : 'Add item to bill')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Product
              TextFormField(
                controller: nameController,
                textCapitalization: TextCapitalization.words,
                decoration: box('Medicine name', hint: 'e.g. Dolo 650'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter the medicine name' : null,
              ),
              const SizedBox(height: 14),
              pair(
                TextFormField(
                  controller: hsnController,
                  keyboardType: TextInputType.number,
                  decoration: box('HSN code'),
                ),
                TextFormField(
                  controller: packController,
                  decoration: box('Pack', hint: "10's / 100ml"),
                ),
              ),
              const SizedBox(height: 14),

              // 2. Batch and expiry
              pair(
                TextFormField(
                  controller: batchController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: box('Batch no.'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter the batch' : null,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(expiry == null
                        ? 'Expiry'
                        : 'Exp ${DateFormat('MM/yy').format(expiry!)}'),
                  ),
                  onPressed: pickExpiry,
                ),
              ),
              const SizedBox(height: 14),

              // 3. Quantity and free
              pair(
                TextFormField(
                  controller: quantityController,
                  keyboardType: TextInputType.number,
                  decoration: box('Qty'),
                  validator: (v) {
                    final n = int.tryParse(v?.trim() ?? '');
                    if (n == null) return 'Whole number';
                    if (n <= 0) return 'More than 0';
                    return null;
                  },
                ),
                TextFormField(
                  controller: freeController,
                  keyboardType: TextInputType.number,
                  decoration: box('Free'),
                  validator: (v) => validateNumber(v, 'Free', whole: true),
                ),
              ),
              const SizedBox(height: 14),

              // 4. Rate and discount
              pair(
                TextFormField(
                  controller: rateController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: box('Rate (before GST)', prefix: '₹ '),
                  validator: (v) => validateNumber(v, 'Rate'),
                ),
                TextFormField(
                  controller: discountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: box('Discount', suffix: '%'),
                  validator: (v) {
                    final error = validateNumber(v, 'Discount');
                    if (error != null) return error;
                    if (double.parse(v!.trim()) > 100) return 'Max 100%';
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 14),

              // 5. GST %
              Text('GST', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              SegmentedButton<double>(
                segments: [
                  for (final rate in gstRates)
                    ButtonSegment(value: rate, label: Text('${rate.toStringAsFixed(0)}%')),
                ],
                selected: {gstPct},
                onSelectionChanged: (s) => setState(() => gstPct = s.first),
              ),
              const SizedBox(height: 14),

              // 6. MRP
              TextFormField(
                controller: mrpController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: box('MRP per unit (incl. GST)', prefix: '₹ '),
                validator: (v) => validateNumber(v, 'MRP'),
              ),
              const SizedBox(height: 16),

              // 7. Live working, so the user can match it with the paper bill
              if (p != null)
                Card(
                  color: Colors.teal.withValues(alpha: 0.08),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        moneyRow('Qty × rate', p.gross),
                        if (p.discount > 0) moneyRow('Less discount', -p.discount),
                        moneyRow('Taxable value', p.taxable),
                        moneyRow('GST ${p.gstPct.toStringAsFixed(0)}%', p.gstAmount),
                        const Divider(),
                        moneyRow('Line amount', p.amount, bold: true),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.check),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(isEditing ? 'Save changes' : 'Add to bill'),
                ),
                onPressed: done,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget moneyRow(String label, double value, {bool bold = false}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: style),
          const Spacer(),
          Text(rupees.format(value), style: style),
        ],
      ),
    );
  }
}
