import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/purchase_bill.dart' show gstRates;
import '../models/session.dart';
import '../models/stock_item.dart';
import '../services/pharmacy_service.dart';

// One screen for both adding a new batch and editing an existing one.
// Pass an [item] to edit it; leave it out to add a new one.
class AddStockPage extends StatefulWidget {
  final Session session;
  final StockItem? item;

  const AddStockPage({super.key, required this.session, this.item});

  @override
  State<AddStockPage> createState() => _AddStockPageState();
}

class _AddStockPageState extends State<AddStockPage> {
  final formKey = GlobalKey<FormState>(); // lets us validate all fields at once
  late final nameController = TextEditingController(text: widget.item?.name);
  late final batchController = TextEditingController(text: widget.item?.batch);
  late final quantityController =
      TextEditingController(text: widget.item?.quantity.toString());
  late final mrpController =
      TextEditingController(text: widget.item?.mrp?.toString());
  late DateTime? expiry = widget.item?.expiry;
  late double gstPct = widget.item?.gstPct ?? 5;

  bool saving = false;
  bool get isEditing => widget.item != null;

  // The shared stock folder for this pharmacy
  CollectionReference<Map<String, dynamic>> get stockRef =>
      PharmacyService.stockRef(widget.session.pharmacyId);

  @override
  void dispose() {
    nameController.dispose();
    batchController.dispose();
    quantityController.dispose();
    mrpController.dispose();
    super.dispose();
  }

  // Open the calendar to pick the expiry date
  Future<void> pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: expiry ?? DateTime(now.year, now.month + 6, now.day),
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 10),
      helpText: 'Select expiry date',
    );
    if (picked != null) {
      setState(() {
        expiry = picked;
      });
    }
  }

  Future<void> save() async {
    // Run every field's validator; stop if any fails
    final formOk = formKey.currentState!.validate();
    if (!formOk || expiry == null) {
      if (expiry == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please choose an expiry date')),
        );
      }
      return;
    }

    setState(() {
      saving = true;
    });

    final item = StockItem(
      name: nameController.text.trim(),
      batch: batchController.text.trim(),
      quantity: int.parse(quantityController.text.trim()),
      expiry: expiry!,
      mrp: double.parse(mrpController.text.trim()),
      gstPct: gstPct,
    );

    try {
      // Record who made the change
      final who = {
        'name': widget.session.userName,
        'uid': widget.session.uid,
      };
      if (isEditing) {
        await stockRef.doc(widget.item!.id).update({
          ...item.toMap(),
          'updatedBy': who,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await stockRef.add({
          ...item.toMap(),
          'addedBy': who,
          'addedAt': FieldValue.serverTimestamp(),
        });
      }
      if (mounted) Navigator.pop(context); // back to the list
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit stock' : 'Add stock'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Medicine name
              TextFormField(
                controller: nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Medicine name',
                  hintText: 'e.g. Paracetamol 650',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter the medicine name';
                  }
                  return null; // null means "this field is OK"
                },
              ),
              const SizedBox(height: 16),

              // 2. Batch number
              TextFormField(
                controller: batchController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Batch number',
                  hintText: 'e.g. B2041',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter the batch number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // 3. Quantity
              TextFormField(
                controller: quantityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Quantity',
                  hintText: 'Number of strips, boxes or bottles',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final number = int.tryParse(value?.trim() ?? '');
                  if (number == null) return 'Quantity must be a whole number';
                  if (number <= 0) return 'Quantity must be more than 0';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // 4. Expiry date (tap to open the calendar)
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    expiry == null
                        ? 'Choose expiry date'
                        : 'Expiry: ${DateFormat('d MMM yyyy').format(expiry!)}',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                onPressed: pickExpiry,
              ),
              const SizedBox(height: 16),

              // 5. MRP and GST, needed to sell this batch
              TextFormField(
                controller: mrpController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'MRP per unit (incl. GST)',
                  prefixText: '₹ ',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final number = double.tryParse(value?.trim() ?? '');
                  if (number == null) return 'Enter the MRP, e.g. 32.50';
                  if (number <= 0) return 'MRP must be more than 0';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Text('GST', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              SegmentedButton<double>(
                segments: [
                  for (final rate in gstRates)
                    ButtonSegment(
                        value: rate, label: Text('${rate.toStringAsFixed(0)}%')),
                ],
                selected: {gstPct},
                onSelectionChanged: (s) => setState(() => gstPct = s.first),
              ),
              const SizedBox(height: 32),

              // 6. Save button
              ElevatedButton.icon(
                icon: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(isEditing ? 'Save changes' : 'Add to stock'),
                ),
                onPressed: saving ? null : save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
