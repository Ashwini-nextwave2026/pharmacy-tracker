import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/sale_bill.dart';
import '../models/session.dart';
import '../models/stock_item.dart';
import '../services/pharmacy_service.dart';
import '../utils/format.dart';

// Search stock and pick a batch to sell.
// Only batches that are in stock and NOT expired are shown,
// soonest expiry first, so the oldest stock is sold first.
class PickStockPage extends StatefulWidget {
  final Session session;
  final Map<String, int> alreadyOnBill; // stockId -> qty already on this bill

  const PickStockPage(
      {super.key, required this.session, this.alreadyOnBill = const {}});

  @override
  State<PickStockPage> createState() => _PickStockPageState();
}

class _PickStockPageState extends State<PickStockPage> {
  String search = '';

  int available(StockItem item) =>
      item.quantity - (widget.alreadyOnBill[item.id] ?? 0);

  // Ask how many, and any discount, then hand the line back
  Future<void> choose(StockItem item) async {
    final qtyController = TextEditingController(text: '1');
    final discController = TextEditingController(text: '0');
    final max = available(item);

    final line = await showDialog<SaleLine>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Batch ${item.batch} · Exp ${DateFormat('MM/yy').format(item.expiry)}\n'
                'MRP ${rupees.format(item.mrp ?? 0)} · $max in stock'),
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
            onPressed: () => Navigator.pop(context),
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
              Navigator.pop(
                context,
                SaleLine(
                  stockId: item.id!,
                  name: item.name,
                  hsn: item.hsn ?? '',
                  batch: item.batch,
                  expiry: item.expiry,
                  quantity: qty,
                  mrp: item.mrp ?? 0,
                  discountPct: disc,
                  gstPct: item.gstPct ?? 0,
                  costRate: item.unitCost, // remembered for the profit report
                ),
              );
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (line != null && mounted) Navigator.pop(context, line);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose medicine')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Type medicine name',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => search = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: PharmacyService.stockRef(widget.session.pharmacyId)
                  .orderBy('expiry')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Could not load stock: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snapshot.data!.docs
                    .map(StockItem.fromFirestore)
                    .where((i) =>
                        i.status() != ExpiryStatus.expired && available(i) > 0)
                    .where((i) => i.name.toLowerCase().contains(search))
                    .toList();

                if (items.isEmpty) {
                  return const Center(
                    child: Text('No matching medicine in stock',
                        style: TextStyle(color: Colors.grey)),
                  );
                }
                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final soon = item.status() == ExpiryStatus.soon;
                    return ListTile(
                      leading: const Icon(Icons.medication, color: Colors.teal),
                      title: Text(item.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        'Batch ${item.batch} · Exp ${DateFormat('MM/yy').format(item.expiry)}'
                        ' · ${available(item)} in stock',
                        style: TextStyle(color: soon ? Colors.orange : null),
                      ),
                      trailing: Text(rupees.format(item.mrp ?? 0),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      onTap: () => choose(item),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
