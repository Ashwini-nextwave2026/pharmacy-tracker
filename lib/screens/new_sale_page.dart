import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/sale_bill.dart';
import '../models/session.dart';
import '../services/pharmacy_service.dart';
import '../utils/format.dart';
import '../widgets/gst_summary.dart';
import 'pick_stock_page.dart';
import 'sale_list_page.dart';

// Make a GST sale bill for a customer.
// Saving it gives it the next bill number and takes the items out of stock.
class NewSalePage extends StatefulWidget {
  final Session session;

  const NewSalePage({super.key, required this.session});

  @override
  State<NewSalePage> createState() => _NewSalePageState();
}

class _NewSalePageState extends State<NewSalePage> {
  final formKey = GlobalKey<FormState>();
  final customerController = TextEditingController();
  final phoneController = TextEditingController();
  final doctorController = TextEditingController();
  String paymentMode = 'Cash';
  final List<SaleLine> lines = [];
  bool saving = false;

  SaleBill get bill => SaleBill(
        date: DateTime.now(),
        customerName: customerController.text.trim().isEmpty
            ? 'Cash customer'
            : customerController.text.trim(),
        customerPhone: phoneController.text.trim(),
        doctorName: doctorController.text.trim(),
        paymentMode: paymentMode,
        lines: lines,
        soldBy: widget.session.userName,
      );

  @override
  void dispose() {
    customerController.dispose();
    phoneController.dispose();
    doctorController.dispose();
    super.dispose();
  }

  Future<void> addLine() async {
    // Tell the picker how much of each batch is already on this bill
    final onBill = <String, int>{};
    for (final l in lines) {
      onBill[l.stockId] = (onBill[l.stockId] ?? 0) + l.quantity;
    }
    final line = await Navigator.push<SaleLine>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            PickStockPage(session: widget.session, alreadyOnBill: onBill),
      ),
    );
    if (line != null) setState(() => lines.add(line));
  }

  // Change the quantity or discount of line [i]
  Future<void> editLine(int i) async {
    final line = lines[i];

    // How many of this batch are in stock, less what other lines already use
    final snap = await PharmacyService.stockRef(widget.session.pharmacyId)
        .doc(line.stockId)
        .get();
    if (!mounted) return;
    final inStock = (snap.data()?['quantity'] as num?)?.toInt() ?? 0;
    var otherLines = 0;
    for (var j = 0; j < lines.length; j++) {
      if (j != i && lines[j].stockId == line.stockId) otherLines += lines[j].quantity;
    }
    final max = inStock - otherLines;

    final qtyController = TextEditingController(text: '${line.quantity}');
    final discController = TextEditingController(text: '${line.discountPct}');

    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit ${line.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Batch ${line.batch} · MRP ${rupees.format(line.mrp)} · $max in stock'),
            const SizedBox(height: 16),
            TextField(
              controller: qtyController,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Quantity', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: discController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Discount',
                  suffixText: '%',
                  border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final qty = int.tryParse(qtyController.text.trim()) ?? 0;
              final disc = double.tryParse(discController.text.trim()) ?? -1;
              String? problem;
              if (qty <= 0) problem = 'Enter a quantity';
              if (qty > max) problem = 'Only $max in stock';
              if (disc < 0 || disc > 100) problem = 'Discount must be 0 to 100';
              if (problem != null) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(problem)));
                return;
              }
              line.quantity = qty;
              line.discountPct = disc;
              Navigator.pop(context, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // (controllers are left for Dart to clean up: disposing them here can
    //  crash while the dialog is still sliding away)
    if (changed == true) setState(() {}); // redraw totals
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one medicine')),
      );
      return;
    }
    setState(() => saving = true);

    final bill = this.bill;
    try {
      final saleId = await PharmacyService.saveSale(
        widget.session.pharmacyId,
        {
          ...bill.toMap(),
          'soldByUid': widget.session.uid,
        },
        lines.map((l) => {'stockId': l.stockId, 'quantity': l.quantity}).toList(),
      );
      if (!mounted) return;
      // Swap this screen for the finished bill, ready to share
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              SaleDetailPage(session: widget.session, saleId: saleId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bill = this.bill;

    return Scaffold(
      appBar: AppBar(title: const Text('New sale')),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // 1. Customer
            TextFormField(
              controller: customerController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Customer name',
                hintText: 'Leave empty for "Cash customer"',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    decoration: const InputDecoration(
                      labelText: 'Mobile (for WhatsApp)',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                    validator: (v) {
                      final t = v?.trim() ?? '';
                      if (t.isNotEmpty && !RegExp(r'^[6-9]\d{9}$').hasMatch(t)) {
                        return '10-digit mobile';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: doctorController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Doctor',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 2. Medicines
            Row(
              children: [
                Text('Medicines (${lines.length})',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add medicine'),
                  onPressed: addLine,
                ),
              ],
            ),
            if (lines.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Tap "Add medicine" to pick from stock.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey)),
              ),
            for (int i = 0; i < lines.length; i++)
              Card(
                child: ListTile(
                  title: Text(lines[i].name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    'Batch ${lines[i].batch} · Exp ${DateFormat('MM/yy').format(lines[i].expiry)}\n'
                    '${lines[i].quantity} × ${rupees.format(lines[i].mrp)}'
                    '${lines[i].discountPct > 0 ? ' − ${pct(lines[i].discountPct)}' : ''}'
                    ' · GST ${pct(lines[i].gstPct)}',
                  ),
                  isThreeLine: true,
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(rupees.format(lines[i].amount),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: () => editLine(i),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 4),
                              child: Text('Edit',
                                  style: TextStyle(color: Colors.teal, fontSize: 12)),
                            ),
                          ),
                          const Text('  ·  ',
                              style: TextStyle(fontSize: 12, color: Colors.grey)),
                          InkWell(
                            onTap: () => setState(() => lines.removeAt(i)),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 4),
                              child: Text('Remove',
                                  style: TextStyle(color: Colors.red, fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),

            // 3. Totals (prices include GST; the summary shows the GST inside)
            if (lines.isNotEmpty)
              GstSummary(
                slabs: bill.slabs,
                discount: bill.discountTotal,
                taxable: bill.taxableTotal,
                gst: bill.gstTotal,
                roundOff: bill.roundOff,
                total: bill.total,
                totalLabel: 'To collect',
              ),
            const SizedBox(height: 16),

            // 4. Payment
            Text('Payment', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: [
                for (final mode in paymentModes)
                  ButtonSegment(value: mode, label: Text(mode)),
              ],
              selected: {paymentMode},
              onSelectionChanged: (s) => setState(() => paymentMode = s.first),
            ),
            const SizedBox(height: 20),

            // 5. Save
            ElevatedButton.icon(
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_circle),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Save sale bill'),
              ),
              onPressed: saving ? null : save,
            ),
          ],
        ),
      ),
    );
  }
}
