import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/purchase_bill.dart';
import '../models/session.dart';
import '../models/stock_item.dart';
import '../models/supplier.dart';
import '../services/pharmacy_service.dart';
import '../utils/format.dart';
import '../widgets/gst_summary.dart';
import 'add_bill_item_page.dart';
import 'suppliers_page.dart' show SupplierFormPage;

export '../utils/format.dart' show rupees; // older screens import it from here

class AddBillPage extends StatefulWidget {
  final Session session;

  const AddBillPage({super.key, required this.session});

  @override
  State<AddBillPage> createState() => _AddBillPageState();
}

class _AddBillPageState extends State<AddBillPage> {
  final formKey = GlobalKey<FormState>();
  final supplierController = TextEditingController();
  final supplierFocus = FocusNode();
  List<Supplier> suppliers = []; // the saved supplier list, for picking
  final gstinController = TextEditingController();
  final billNumberController = TextEditingController();
  final creditDaysController = TextEditingController(text: '30');
  DateTime billDate = DateTime.now();
  bool interState = false;
  final List<BillLine> lines = [];
  bool saving = false;

  // The shared pharmacy folder: pharmacies/<pharmacy id>
  DocumentReference<Map<String, dynamic>> get pharmacyRef =>
      PharmacyService.pharmacyRef(widget.session.pharmacyId);

  // The bill as entered so far, so the totals stay live
  PurchaseBill get bill => PurchaseBill(
        supplier: supplierController.text.trim(),
        supplierGstin: gstinController.text.trim().toUpperCase(),
        billNumber: billNumberController.text.trim(),
        billDate: billDate,
        interState: interState,
        lines: lines,
        creditDays: int.tryParse(creditDaysController.text.trim()) ?? 30,
      );

  @override
  void dispose() {
    supplierController.dispose();
    supplierFocus.dispose();
    gstinController.dispose();
    billNumberController.dispose();
    creditDaysController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    loadSuppliers();
  }

  Future<void> loadSuppliers() async {
    final snap = await PharmacyService.suppliersRef(widget.session.pharmacyId)
        .orderBy('name')
        .get();
    if (mounted) {
      setState(() => suppliers = snap.docs.map(Supplier.fromFirestore).toList());
    }
  }

  // A supplier was picked: fill in their GSTIN, IGST and credit days
  void useSupplier(Supplier s) {
    setState(() {
      supplierController.text = s.name;
      gstinController.text = s.gstin;
      interState = s.interState;
      creditDaysController.text = '${s.creditDays}';
    });
  }

  // Open the Add supplier form with what's typed, then use the new supplier
  Future<void> addNewSupplier() async {
    final s = await Navigator.push<Supplier>(
      context,
      MaterialPageRoute(
        builder: (context) => SupplierFormPage(
          session: widget.session,
          initialName: supplierController.text.trim(),
        ),
      ),
    );
    if (s != null) {
      setState(() => suppliers = [...suppliers, s]);
      useSupplier(s);
    }
  }

  Future<void> pickBillDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: billDate,
      firstDate: DateTime(DateTime.now().year - 2),
      lastDate: DateTime.now(),
      helpText: 'Select bill date',
    );
    if (picked != null) setState(() => billDate = picked);
  }

  // Open the item form and wait for it to hand a line back
  Future<void> addLine() async {
    final line = await Navigator.push<BillLine>(
      context,
      MaterialPageRoute(builder: (context) => const AddBillItemPage()),
    );
    if (line != null) setState(() => lines.add(line));
  }

  // Open the item form filled in with line [i], and put the changed line back
  Future<void> editLine(int i) async {
    final line = await Navigator.push<BillLine>(
      context,
      MaterialPageRoute(builder: (context) => AddBillItemPage(line: lines[i])),
    );
    if (line != null) setState(() => lines[i] = line);
  }

  Future<void> saveBill() async {
    if (!formKey.currentState!.validate()) return;
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one item to the bill')),
      );
      return;
    }

    setState(() => saving = true);
    final bill = this.bill;

    try {
      // A batch saves the bill AND every stock item together:
      // either all of it is saved, or none of it is.
      final batch = FirebaseFirestore.instance.batch();
      final billRef = pharmacyRef.collection('bills').doc(); // new bill ID
      final who = {
        'name': widget.session.userName,
        'uid': widget.session.uid,
      };
      batch.set(billRef, {...bill.toMap(), 'addedBy': who});

      for (final line in lines) {
        final stockRef = pharmacyRef.collection('stock').doc();
        final item = StockItem(
          name: line.name,
          batch: line.batch,
          quantity: line.unitsIn, // free units go into stock too
          expiry: line.expiry,
          rate: line.rate,
          mrp: line.mrp,
          supplier: bill.supplier,
          billId: billRef.id,
          hsn: line.hsn,
          pack: line.pack,
          gstPct: line.gstPct,
          // real cost per unit: after discount, spread over free units too
          costRate: line.unitsIn > 0 ? round2(line.taxable / line.unitsIn) : line.rate,
        );
        batch.set(stockRef, {
          ...item.toMap(),
          'addedBy': who,
          'addedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      // First bill from a supplier not in the list yet? Save them to the list.
      final key = nameKey(bill.supplier);
      if (!suppliers.any((s) => nameKey(s.name) == key)) {
        try {
          await PharmacyService.suppliersRef(widget.session.pharmacyId).add(Supplier(
            name: bill.supplier,
            gstin: bill.supplierGstin,
            creditDays: bill.creditDays,
          ).toMap());
        } catch (_) {
          // not important enough to stop: the bill is already saved
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Bill saved, ${lines.length} item${lines.length == 1 ? '' : 's'} added to stock')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save the bill: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bill = this.bill;

    return Scaffold(
      appBar: AppBar(title: const Text('New purchase bill')),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // 1. Supplier details
            // Type to search the supplier list; pick one to fill GSTIN etc.
            RawAutocomplete<Supplier>(
              textEditingController: supplierController,
              focusNode: supplierFocus,
              displayStringForOption: (s) => s.name,
              optionsBuilder: (value) =>
                  searchSuppliers(suppliers, value.text).take(8),
              onSelected: useSupplier,
              fieldViewBuilder: (context, controller, focusNode, onSubmit) =>
                  TextFormField(
                controller: controller,
                focusNode: focusNode,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Supplier / distributor',
                  hintText: suppliers.isEmpty ? null : 'Type to search your suppliers',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add_business),
                    tooltip: 'Add a new supplier',
                    onPressed: addNewSupplier,
                  ),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter the supplier name' : null,
                onFieldSubmitted: (_) => onSubmit(),
              ),
              optionsViewBuilder: (context, onSelected, options) => Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280, maxWidth: 480),
                    child: ListView(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      children: [
                        for (final s in options)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.local_shipping, color: Colors.indigo),
                            title: Text(s.name),
                            subtitle: Text([
                              if (s.gstin.isNotEmpty) s.gstin,
                              '${s.creditDays} days credit',
                            ].join(' · ')),
                            onTap: () => onSelected(s),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: gstinController,
              textCapitalization: TextCapitalization.characters,
              maxLength: 15,
              decoration: const InputDecoration(
                labelText: 'Supplier GSTIN (optional)',
                hintText: '36ABCDE1234F1Z5',
                border: OutlineInputBorder(),
                counterText: '',
              ),
              validator: (v) {
                final text = v?.trim() ?? '';
                if (text.isNotEmpty && text.length != 15) {
                  return 'A GSTIN has 15 characters';
                }
                return null;
              },
              // Telangana GSTINs start with 36; any other state means IGST
              onChanged: (v) {
                final text = v.trim();
                if (text.length >= 2) {
                  setState(() => interState = !text.startsWith('36'));
                }
              },
            ),
            const SizedBox(height: 14),

            // 2. Bill number and date
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: billNumberController,
                    decoration: const InputDecoration(
                      labelText: 'Bill number',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Enter the bill number' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(DateFormat('d MMM yyyy').format(billDate)),
                    ),
                    onPressed: pickBillDate,
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Supplier from another state (IGST)'),
              subtitle: const Text('Off = CGST + SGST (within Telangana)'),
              value: interState,
              onChanged: (v) => setState(() => interState = v),
            ),
            // How long the supplier gives to pay (0 = pay on delivery)
            TextFormField(
              controller: creditDaysController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Credit days',
                helperText: 'Payment due by ${DateFormat('d MMM yyyy').format(billDate.add(Duration(days: int.tryParse(creditDaysController.text.trim()) ?? 0)))}',
                suffixText: 'days',
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
              validator: (v) {
                final n = int.tryParse(v?.trim() ?? '');
                if (n == null || n < 0 || n > 365) return '0 to 365 days';
                return null;
              },
            ),
            const SizedBox(height: 8),
            const SizedBox(height: 8),

            // 3. Items on the bill
            Row(
              children: [
                Text('Items (${lines.length})',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add item'),
                  onPressed: addLine,
                ),
              ],
            ),
            if (lines.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No items yet. Tap "Add item" for each medicine on the bill.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey)),
              ),
            for (int i = 0; i < lines.length; i++)
              Card(
                child: ListTile(
                  title: Text(
                      '${lines[i].name}${lines[i].pack.isNotEmpty ? '  ·  ${lines[i].pack}' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    'Batch ${lines[i].batch} · Exp ${DateFormat('MM/yy').format(lines[i].expiry)}'
                    '${lines[i].hsn.isNotEmpty ? ' · HSN ${lines[i].hsn}' : ''}\n'
                    '${lines[i].quantity}${lines[i].free > 0 ? ' + ${lines[i].free} free' : ''}'
                    ' × ${rupees.format(lines[i].rate)}'
                    '${lines[i].discountPct > 0 ? ' − ${pct(lines[i].discountPct)}' : ''}'
                    ' · GST ${pct(lines[i].gstPct)} · MRP ${rupees.format(lines[i].mrp)}',
                  ),
                  isThreeLine: true,
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(rupees.format(lines[i].amount),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      _EditRemove(
                        onEdit: () => editLine(i),
                        onRemove: () => setState(() => lines.removeAt(i)),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),

            // 4. GST summary and net amount
            if (lines.isNotEmpty)
              GstSummary(
                slabs: bill.slabs,
                discount: bill.discountTotal,
                taxable: bill.taxableTotal,
                gst: bill.gstTotal,
                interState: interState,
                roundOff: bill.roundOff,
                total: bill.total,
              ),
            const SizedBox(height: 20),

            // 5. Save
            ElevatedButton.icon(
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Save bill and add to stock'),
              ),
              onPressed: saving ? null : saveBill,
            ),
          ],
        ),
      ),
    );
  }
}

// The small "Edit · Remove" links under each line's amount
class _EditRemove extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const _EditRemove({required this.onEdit, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onEdit,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('Edit', style: TextStyle(color: Colors.teal, fontSize: 12)),
          ),
        ),
        const Text('  ·  ', style: TextStyle(fontSize: 12, color: Colors.grey)),
        InkWell(
          onTap: onRemove,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('Remove', style: TextStyle(color: Colors.red, fontSize: 12)),
          ),
        ),
      ],
    );
  }
}
