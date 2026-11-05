import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
    'members': 'Owner & staff',
    'counters': 'Bill number counters',
  };

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

              // 4. Tips
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
