import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/session.dart';
import '../models/stock_item.dart';
import '../services/pharmacy_service.dart';
import '../utils/format.dart';
import 'add_stock_page.dart';

class StockListPage extends StatelessWidget {
  final Session session;

  const StockListPage({super.key, required this.session});

  // The shared stock folder for this pharmacy: pharmacies/<pharmacy id>/stock
  CollectionReference<Map<String, dynamic>> get stockRef =>
      PharmacyService.stockRef(session.pharmacyId);

  // Colour and icon for each warning level
  Color colorFor(ExpiryStatus status) {
    switch (status) {
      case ExpiryStatus.expired:
        return Colors.red;
      case ExpiryStatus.soon:
        return Colors.orange;
      case ExpiryStatus.safe:
        return Colors.green;
    }
  }

  IconData iconFor(ExpiryStatus status) {
    switch (status) {
      case ExpiryStatus.expired:
        return Icons.error;
      case ExpiryStatus.soon:
        return Icons.warning_amber;
      case ExpiryStatus.safe:
        return Icons.check_circle;
    }
  }

  // Friendly text like "in 12 days" or "expired 3 days ago"
  String daysText(StockItem item) {
    final days = item.daysLeft();
    if (days < 0) return 'Expired ${-days} day${days == -1 ? '' : 's'} ago';
    if (days == 0) return 'Expires today';
    return 'in $days day${days == 1 ? '' : 's'}';
  }

  // Ask before deleting, so a slip of the finger doesn't lose data
  Future<bool> confirmDelete(BuildContext context, StockItem item) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this batch?'),
        content: Text('${item.name}, batch ${item.batch}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stock & Expiry')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add stock'),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => AddStockPage(session: session)),
          );
        },
      ),
      // Live list from Firestore, soonest expiry first
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stockRef.orderBy('expiry').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load stock: ${snapshot.error}',
                    style: const TextStyle(color: Colors.red)),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final items =
              snapshot.data!.docs.map(StockItem.fromFirestore).toList();

          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No stock yet.\nTap "Add stock" to add your first medicine batch.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              ),
            );
          }

          // Count each warning level for the summary at the top
          final expired =
              items.where((i) => i.status() == ExpiryStatus.expired).length;
          final soon =
              items.where((i) => i.status() == ExpiryStatus.soon).length;
          final safe =
              items.where((i) => i.status() == ExpiryStatus.safe).length;

          return Column(
            children: [
              // 1. Summary row
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    summaryBox('Expired', expired, Colors.red),
                    const SizedBox(width: 8),
                    summaryBox('Within $soonDays days', soon, Colors.orange),
                    const SizedBox(width: 8),
                    summaryBox('Safe', safe, Colors.green),
                  ],
                ),
              ),

              // 2. The stock list
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 88), // room for the button
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final status = item.status();
                    final color = colorFor(status);

                    return Dismissible(
                      key: ValueKey(item.id),
                      // Only the owner can swipe to delete
                      direction: session.isOwner
                          ? DismissDirection.endToStart
                          : DismissDirection.none,
                      confirmDismiss: (direction) =>
                          confirmDelete(context, item),
                      onDismissed: (direction) =>
                          stockRef.doc(item.id).delete(),
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      child: Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: ListTile(
                          leading: Icon(iconFor(status), color: color, size: 32),
                          title: Text(item.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                              'Batch ${item.batch}  ·  Qty ${item.quantity}'
                              '${item.mrp != null ? '  ·  MRP ${rupees.format(item.mrp)}' : ''}'),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(DateFormat('d MMM yyyy').format(item.expiry)),
                              Text(daysText(item),
                                  style: TextStyle(
                                      color: color,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                          // Tap a row to edit it
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    AddStockPage(session: session, item: item),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // A small coloured box showing a count, used in the summary row
  Widget summaryBox(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color),
        ),
        child: Column(
          children: [
            Text('$count',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
