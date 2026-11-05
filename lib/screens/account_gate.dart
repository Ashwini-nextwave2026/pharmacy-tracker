import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/session.dart';
import '../services/pharmacy_service.dart';
import 'setup_page.dart';
import 'home_page.dart';

// After login, decide where the user goes:
//   no pharmacy yet          -> SetupPage (create or join)
//   removed by the owner      -> "You've been removed" screen
//   member of a pharmacy      -> HomePage
class AccountGate extends StatelessWidget {
  const AccountGate({super.key});

  Widget loading() =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));

  Widget problem(String message) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  child: const Text('Log out'),
                ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    // 1. Watch this user's profile
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: PharmacyService.userRef().snapshots(),
      builder: (context, userSnap) {
        if (userSnap.hasError) return problem('Could not load your account: ${userSnap.error}');
        if (!userSnap.hasData) return loading();

        final user = userSnap.data!.data();
        final pharmacyId = user?['pharmacyId'] as String?;
        if (pharmacyId == null) return const SetupPage();

        // 2. Check they are still a member of that pharmacy
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: PharmacyService.membersRef(pharmacyId)
              .doc(PharmacyService.uid)
              .snapshots(),
          builder: (context, memberSnap) {
            if (memberSnap.hasError) return problem('Could not check your access: ${memberSnap.error}');
            if (!memberSnap.hasData) return loading();
            if (!memberSnap.data!.exists) return const RemovedPage();

            final member = memberSnap.data!.data()!;

            // 3. Load the pharmacy's name and invite code
            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: PharmacyService.pharmacyRef(pharmacyId).snapshots(),
              builder: (context, pharmacySnap) {
                if (pharmacySnap.hasError) return problem('Could not load the pharmacy: ${pharmacySnap.error}');
                if (!pharmacySnap.hasData) return loading();

                final pharmacy = pharmacySnap.data!.data() ?? {};
                final session = Session(
                  uid: PharmacyService.uid,
                  userName: member['name'] ?? '',
                  pharmacyId: pharmacyId,
                  pharmacyName: pharmacy['name'] ?? 'Pharmacy',
                  inviteCode: pharmacy['inviteCode'] ?? '',
                  role: member['role'] ?? 'staff',
                );
                return HomePage(session: session);
              },
            );
          },
        );
      },
    );
  }
}

// Shown when the owner has removed this staff member
class RemovedPage extends StatelessWidget {
  const RemovedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.block, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('You no longer have access to this pharmacy.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: PharmacyService.leavePharmacy,
                child: const Text('Join another pharmacy'),
              ),
              TextButton(
                onPressed: () => FirebaseAuth.instance.signOut(),
                child: const Text('Log out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
