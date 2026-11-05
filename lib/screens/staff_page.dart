import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/session.dart';
import '../services/pharmacy_service.dart';

// Owner-only: the invite code and the list of people in the pharmacy
class StaffPage extends StatelessWidget {
  final Session session;

  const StaffPage({super.key, required this.session});

  Future<void> confirmRemove(
      BuildContext context, String memberUid, String name) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove $name?'),
        content: const Text(
            'They will lose access to this pharmacy straight away. You can invite them again later.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (yes == true) {
      await PharmacyService.removeMember(session.pharmacyId, memberUid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Staff')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Invite code card
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text('Invite code for new staff',
                      style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 8),
                  SelectableText(
                    session.inviteCode,
                    style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 6),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy code'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: session.inviteCode));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Invite code copied')),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Staff sign up with their own email, choose "I am staff", and enter this code.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text('People in this pharmacy',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),

          // 2. Member list, owner first
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: PharmacyService.membersRef(session.pharmacyId).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text('Could not load staff: ${snapshot.error}',
                    style: const TextStyle(color: Colors.red));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final members = snapshot.data!.docs.toList()
                ..sort((a, b) => (a.data()['role'] == 'owner' ? 0 : 1)
                    .compareTo(b.data()['role'] == 'owner' ? 0 : 1));

              return Column(
                children: [
                  for (final m in members)
                    Card(
                      child: ListTile(
                        leading: Icon(m.data()['role'] == 'owner'
                            ? Icons.storefront
                            : Icons.badge),
                        title: Text(m.data()['name'] ?? ''),
                        subtitle: Text(
                            '${m.data()['email'] ?? ''}  ·  ${m.data()['role'] == 'owner' ? 'Owner' : 'Staff'}'),
                        trailing: m.data()['role'] == 'owner'
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.person_remove,
                                    color: Colors.red),
                                tooltip: 'Remove',
                                onPressed: () => confirmRemove(
                                    context, m.id, m.data()['name'] ?? 'this person'),
                              ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
