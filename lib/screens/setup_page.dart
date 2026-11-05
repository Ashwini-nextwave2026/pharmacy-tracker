import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/pharmacy_service.dart';

// First screen after sign-up: create a new pharmacy (owner)
// or join an existing one with an invite code (staff).
class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final pharmacyController = TextEditingController();
  final codeController = TextEditingController();

  bool isOwner = true; // true = create a pharmacy, false = join one
  bool working = false;
  String? error;

  @override
  void dispose() {
    nameController.dispose();
    pharmacyController.dispose();
    codeController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    setState(() {
      working = true;
      error = null;
    });

    try {
      if (isOwner) {
        await PharmacyService.createPharmacy(
          pharmacyName: pharmacyController.text.trim(),
          userName: nameController.text.trim(),
        );
      } else {
        await PharmacyService.joinPharmacy(
          code: codeController.text,
          userName: nameController.text.trim(),
        );
      }
      // No navigation needed: AccountGate sees the change and moves on
    } catch (e) {
      setState(() {
        error = e.toString().replaceFirst('Exception: ', '');
        working = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up your pharmacy'),
        actions: [
          TextButton(
            onPressed: () => FirebaseAuth.instance.signOut(),
            child: const Text('Log out'),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Owner or staff?
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                          value: true,
                          icon: Icon(Icons.storefront),
                          label: Text('I own a pharmacy')),
                      ButtonSegment(
                          value: false,
                          icon: Icon(Icons.badge),
                          label: Text('I am staff')),
                    ],
                    selected: {isOwner},
                    onSelectionChanged: (selection) => setState(() {
                      isOwner = selection.first;
                      error = null;
                    }),
                  ),
                  const SizedBox(height: 24),

                  // 2. Your name (both)
                  TextFormField(
                    controller: nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Your name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
                  ),
                  const SizedBox(height: 16),

                  // 3. Pharmacy name (owner) or invite code (staff)
                  if (isOwner)
                    TextFormField(
                      controller: pharmacyController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Pharmacy name',
                        hintText: 'e.g. Sri Sai Medicals',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter the pharmacy name'
                          : null,
                    )
                  else
                    TextFormField(
                      controller: codeController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Invite code from the owner',
                        hintText: 'e.g. K7Q2MX',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().length != 6)
                          ? 'The invite code has 6 characters'
                          : null,
                    ),
                  const SizedBox(height: 16),

                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 16),

                  ElevatedButton(
                    onPressed: working ? null : submit,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: working
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(isOwner ? 'Create pharmacy' : 'Join pharmacy'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
