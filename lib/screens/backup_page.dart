import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../models/session.dart';
import '../services/backup_service.dart';
import '../services/pharmacy_service.dart';

// Owner only: save a copy of ALL the pharmacy's data to a file.
class BackupPage extends StatefulWidget {
  final Session session;

  const BackupPage({super.key, required this.session});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool working = false;
  BackupResult? last; // the backup made in this visit

  static const labels = {
    'stock': 'Stock batches',
    'bills': 'Purchase bills',
    'sales': 'Sale bills',
    'payments': 'Supplier payments',
    'expenses': 'Expenses',
    'suppliers': 'Suppliers',
    'adjustments': 'Returns & write-offs',
    'members': 'Owner & staff',
    'counters': 'Bill number counters',
  };

  // ---- Restore: pick a backup file, show what it would do, then do it ----
  Future<void> restore() async {
    // file_picker 13: pickFile() returns one file, or null if cancelled
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    setState(() => working = true);
    try {
      final backup = parseBackup(bytes);
      if (backup.pharmacyId != widget.session.pharmacyId) {
        throw FormatException('This backup is from another pharmacy '
            '("${backup.pharmacyName}"), not ${widget.session.pharmacyName}.');
      }
      final plan = await RestoreService.plan(widget.session.pharmacyId, backup);
      if (!mounted) return;
      setState(() => working = false);

      final overwrite = await showDialog<bool>(
        context: context,
        builder: (context) => _RestoreDialog(backup: backup, plan: plan, labels: labels),
      );
      if (overwrite == null || !mounted) return; // cancelled

      setState(() => working = true);
      final written = await RestoreService.restore(
        pharmacyId: widget.session.pharmacyId,
        backup: backup,
        plan: plan,
        overwriteExisting: overwrite,
      );
      if (!mounted) return;
      setState(() => working = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(written == 0
              ? 'Nothing to restore: everything in the backup is already in the app.'
              : 'Restore done: $written record${written == 1 ? '' : 's'} written back.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => working = false);
      final msg = e is FormatException ? e.message : '$e';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Restore stopped: $msg')));
    }
  }

  Future<void> backup() async {
    setState(() => working = true);
    try {
      final result = await BackupService.create(
        pharmacyId: widget.session.pharmacyId,
        pharmacyName: widget.session.pharmacyName,
      );
      // Phone: opens Share (pick Google Drive, Files, WhatsApp...).
      // PC browser: downloads the file (or offers Share where supported).
      await SharePlus.instance.share(ShareParams(
        files: [
          XFile.fromData(result.bytes, mimeType: 'application/json', name: result.fileName),
        ],
        fileNameOverrides: [result.fileName],
        subject: 'Pharmacy Tracker backup',
        text: 'Pharmacy Tracker backup, ${DateFormat('d MMM yyyy, h:mm a').format(DateTime.now())}',
      ));
      if (!mounted) return;
      setState(() {
        last = result;
        working = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => working = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Backup failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: PharmacyService.pharmacyRef(widget.session.pharmacyId).snapshots(),
        builder: (context, snap) {
          final lastAt = (snap.data?.data()?['lastBackupAt'] as Timestamp?)?.toDate();
          final days = lastAt == null ? null : DateTime.now().difference(lastAt).inDays;
          final overdue = days == null || days >= 7;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 1. When was the last backup?
              Card(
                color: (overdue ? Colors.orange : Colors.green).withValues(alpha: 0.10),
                child: ListTile(
                  leading: Icon(overdue ? Icons.warning_amber : Icons.verified,
                      color: overdue ? Colors.orange : Colors.green, size: 32),
                  title: Text(lastAt == null
                      ? 'No backup made yet'
                      : 'Last backup: ${DateFormat('d MMM yyyy, h:mm a').format(lastAt)}'),
                  subtitle: Text(lastAt == null
                      ? 'Make your first backup now.'
                      : (overdue
                          ? '$days days ago. Make a new backup (once a week is good).'
                          : (days == 0 ? 'Today. You\'re up to date.' : '$days days ago.'))),
                ),
              ),
              const SizedBox(height: 12),

              // 2. The button
              FilledButton.icon(
                icon: working
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.backup),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(working ? 'Making backup...' : 'Make backup now',
                      style: const TextStyle(fontSize: 16)),
                ),
                onPressed: working ? null : backup,
              ),
              const SizedBox(height: 8),
              Text(
                kIsWeb
                    ? 'The backup file downloads to your Downloads folder. '
                        'Copy it to Google Drive or a "Pharmacy Backups" folder.'
                    : 'The Share screen opens: choose Google Drive (best), Files, or '
                        'WhatsApp to yourself.',
                style: const TextStyle(color: Colors.grey),
              ),

              // 3. What was saved
              if (last != null) ...[
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Saved in this backup',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(last!.fileName,
                            style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        const Divider(),
                        for (final e in last!.counts.entries)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(children: [
                              Text(labels[e.key] ?? e.key),
                              const Spacer(),
                              Text('${e.value}',
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        const Divider(),
                        Row(children: [
                          const Text('Total records',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const Spacer(),
                          Text('${last!.total}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ]),
                        Text('Size: ${(last!.bytes.length / 1024).toStringAsFixed(0)} KB',
                            style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
              ],

              // 4. Restore
              const SizedBox(height: 20),
              OutlinedButton.icon(
                icon: const Icon(Icons.settings_backup_restore),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Restore from a backup file'),
                ),
                onPressed: working ? null : restore,
              ),
              const SizedBox(height: 4),
              const Text(
                'Brings back records that are missing now. Nothing is deleted, and you '
                'see what will happen before anything changes.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),

              // 5. Tips
              const SizedBox(height: 20),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Good habits', style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 6),
                      Text('• Make a backup once a week, and before big changes.\n'
                          '• Keep the last 4-5 backups; delete older ones.\n'
                          '• The file has all your shop data. Keep it private.\n'
                          '• Your data is also always in the Firebase cloud; this file '
                          'protects against mistakes like deleting the wrong thing.'),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// Shows what a restore would do; returns false (add missing only),
// true (also overwrite existing), or null (cancel)
class _RestoreDialog extends StatefulWidget {
  final BackupFile backup;
  final List<RestorePlanItem> plan;
  final Map<String, String> labels;

  const _RestoreDialog({required this.backup, required this.plan, required this.labels});

  @override
  State<_RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends State<_RestoreDialog> {
  bool overwrite = false;

  @override
  Widget build(BuildContext context) {
    final missing = widget.plan.fold<int>(0, (t, p) => t + p.missing.length);
    final existing = widget.plan.fold<int>(0, (t, p) => t + p.existing.length);
    final toWrite = missing + (overwrite ? existing : 0);

    return AlertDialog(
      title: const Text('Restore this backup?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Backup from ${DateFormat('d MMM yyyy, h:mm a').format(widget.backup.createdAt)}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Row(children: const [
              Expanded(child: Text('', style: TextStyle(fontSize: 12))),
              SizedBox(width: 60, child: Text('Missing', textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
              SizedBox(width: 70, child: Text('Already in', textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
            ]),
            const Divider(height: 8),
            for (final p in widget.plan)
              if (p.missing.isNotEmpty || p.existing.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Expanded(child: Text(widget.labels[p.collection] ?? p.collection)),
                    SizedBox(
                      width: 60,
                      child: Text('${p.missing.length}',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: p.missing.isEmpty ? Colors.grey : Colors.green)),
                    ),
                    SizedBox(
                      width: 70,
                      child: Text('${p.existing.length}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(color: Colors.grey)),
                    ),
                  ]),
                ),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: overwrite,
              onChanged: (v) => setState(() => overwrite = v ?? false),
              title: const Text('Also overwrite records that are already in the app'),
              subtitle: const Text(
                  'Only if today\'s data is wrong. Changes made after the backup '
                  '(sales, stock quantities, payments) would be replaced by the old values.',
                  style: TextStyle(fontSize: 12)),
            ),
            const Text('Owner & staff are never restored. Bill numbers never go back.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: overwrite ? FilledButton.styleFrom(backgroundColor: Colors.orange) : null,
          onPressed: toWrite == 0 ? null : () => Navigator.pop(context, overwrite),
          child: Text(toWrite == 0 ? 'Nothing to restore' : 'Restore $toWrite records'),
        ),
      ],
    );
  }
}
