import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/session.dart';
import '../models/stock_item.dart';
import '../services/pharmacy_service.dart';
import '../services/stock_import.dart';
import '../utils/format.dart';

// Add many medicines at once: copy rows from Excel, paste here, check, import.
class ImportStockPage extends StatefulWidget {
  final Session session;

  const ImportStockPage({super.key, required this.session});

  @override
  State<ImportStockPage> createState() => _ImportStockPageState();
}

class _ImportStockPageState extends State<ImportStockPage> {
  final pasteController = TextEditingController();
  List<ImportRow>? rows; // null until "Check" is tapped
  Set<String> existing = {}; // "NAME|BATCH" already in stock
  bool checking = false;
  bool importing = false;
  int done = 0;

  @override
  void dispose() {
    pasteController.dispose();
    super.dispose();
  }

  String keyOf(StockItem i) => '${i.name.toLowerCase()}|${i.batch.toUpperCase()}';

  List<ImportRow> get good =>
      (rows ?? []).where((r) => r.ok && !existing.contains(keyOf(r.item!))).toList();
  List<ImportRow> get duplicates =>
      (rows ?? []).where((r) => r.ok && existing.contains(keyOf(r.item!))).toList();
  List<ImportRow> get bad => (rows ?? []).where((r) => !r.ok).toList();

  // Read the pasted rows, and find batches that are already in stock
  Future<void> check() async {
    FocusScope.of(context).unfocus();
    setState(() => checking = true);
    final parsed = parseStockRows(pasteController.text);
    final snap = await PharmacyService.stockRef(widget.session.pharmacyId).get();
    if (!mounted) return;
    setState(() {
      existing = snap.docs.map((d) => keyOf(StockItem.fromFirestore(d))).toSet();
      rows = parsed;
      checking = false;
    });
  }

  // Save all good rows. Firestore takes up to 500 writes per batch.
  Future<void> importRows() async {
    final toAdd = good;
    if (toAdd.isEmpty) return;
    setState(() {
      importing = true;
      done = 0;
    });
    final ref = PharmacyService.stockRef(widget.session.pharmacyId);
    final who = {'name': widget.session.userName, 'uid': widget.session.uid};
    try {
      for (var start = 0; start < toAdd.length; start += 400) {
        final chunk = toAdd.skip(start).take(400);
        final batch = FirebaseFirestore.instance.batch();
        for (final r in chunk) {
          batch.set(ref.doc(), {
            ...r.item!.toMap(),
            'addedBy': who,
            'addedAt': FieldValue.serverTimestamp(),
            'source': 'import',
          });
        }
        await batch.commit();
        if (mounted) setState(() => done += chunk.length);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${toAdd.length} medicine batches added to stock')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => importing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Stopped after $done rows: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import stock')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. How to
          Card(
            color: Colors.teal.withValues(alpha: 0.08),
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('How to import', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 6),
                  Text('1. Fill the Excel template, one row per batch.\n'
                      '2. Select the rows in Excel (you can include the heading row) and press Ctrl+C.\n'
                      '3. Click in the box below and press Ctrl+V (on a phone: long-press, Paste).\n'
                      '4. Tap Check, fix any red rows, then tap Import.'),
                  SizedBox(height: 8),
                  Text('Columns, in this order:',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  Text('Medicine name · Batch · Expiry · Qty · MRP · GST % · HSN · Pack · '
                      'Purchase rate · Supplier\n'
                      'The first 5 are required. Expiry like 08/27. GST % blank = 5%.',
                      style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 2. Paste box
          TextField(
            controller: pasteController,
            minLines: 6,
            maxLines: 12,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(
              hintText: 'Paste rows from Excel here\n\n'
                  'Dolo 650\tB2041\t08/27\t50\t33.00\t5\t3004\t15\'s\t22.50\tSri Ram Pharma',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() => rows = null),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: checking
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.fact_check),
            label: const Text('Check rows'),
            onPressed: checking || pasteController.text.trim().isEmpty ? null : check,
          ),

          // 3. Results
          if (rows != null) ...[
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _chip('${good.length} ready', Colors.green),
              if (duplicates.isNotEmpty)
                _chip('${duplicates.length} already in stock (skipped)', Colors.orange),
              if (bad.isNotEmpty) _chip('${bad.length} with problems', Colors.red),
            ]),
            const SizedBox(height: 8),
            for (final r in bad)
              Card(
                color: Colors.red.withValues(alpha: 0.06),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.error, color: Colors.red),
                  title: Text('Row ${r.lineNumber}'),
                  subtitle: Text(r.error!),
                ),
              ),
            for (final r in duplicates)
              Card(
                color: Colors.orange.withValues(alpha: 0.06),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.content_copy, color: Colors.orange),
                  title: Text('Row ${r.lineNumber}: ${r.item!.name}'),
                  subtitle: Text('Batch ${r.item!.batch} is already in stock. '
                      'Edit that batch\'s quantity instead.'),
                ),
              ),
            for (final r in good)
              Card(
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: Text(r.item!.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      'Batch ${r.item!.batch} · Exp ${DateFormat('MM/yy').format(r.item!.expiry)} · '
                      'Qty ${r.item!.quantity} · GST ${pct(r.item!.gstPct ?? 0)}'),
                  trailing: Text(rupees.format(r.item!.mrp ?? 0)),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: importing
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download_done),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(importing
                    ? 'Importing... $done of ${good.length}'
                    : 'Import ${good.length} medicine batch${good.length == 1 ? '' : 'es'}'),
              ),
              onPressed: importing || good.isEmpty ? null : importRows,
            ),
            if (bad.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Rows with problems are not imported. Fix them in Excel, '
                    'paste again and tap Check.',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) => Chip(
        label: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        backgroundColor: color.withValues(alpha: 0.1),
        side: BorderSide.none,
      );
}
