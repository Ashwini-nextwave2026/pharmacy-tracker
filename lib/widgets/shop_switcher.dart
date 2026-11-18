import 'package:flutter/material.dart';
import '../models/session.dart';
import '../services/pharmacy_service.dart';

// Owner only: tap the shop name at the top of the home screen to
// switch to another shop, or add a new one.
//
// Each shop keeps its own stock, sales, bills, staff and drug licence.
// All shops share the owner's GSTIN.
Future<void> showShopSwitcher(BuildContext context, Session session) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => FutureBuilder(
      future: PharmacyService.shops(session.shopIds),
      builder: (_, snap) {
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load your shops: ${snap.error}'),
          );
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final shops = snap.data!;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('Your shops',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              for (final s in shops)
                ListTile(
                  leading: const Icon(Icons.storefront),
                  title: Text(s.name),
                  subtitle: Text([
                    if ((s.shop['drugLicence'] ?? '').toString().isNotEmpty)
                      'D.L. ${s.shop['drugLicence']}',
                    'Bills ${s.shop['billPrefix'] ?? 'S'}-0001…',
                  ].join('  ·  ')),
                  trailing: s.id == session.pharmacyId
                      ? const Icon(Icons.check_circle, color: Colors.teal)
                      : null,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    if (s.id != session.pharmacyId) {
                      await PharmacyService.switchShop(s.id);
                    }
                  },
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.add_business),
                title: const Text('Add another shop'),
                subtitle: const Text('Same GSTIN, its own drug licence and stock'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  // the home screen's context: the sheet's is gone once closed
                  showDialog<void>(
                    context: context,
                    builder: (_) => _AddShopDialog(session: session, shops: shops),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    ),
  );
}

class _AddShopDialog extends StatefulWidget {
  final Session session;
  final List<({String id, String name, Map<String, dynamic> shop})> shops;

  const _AddShopDialog({required this.session, required this.shops});

  @override
  State<_AddShopDialog> createState() => _AddShopDialogState();
}

class _AddShopDialogState extends State<_AddShopDialog> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  late final prefix = TextEditingController(text: _freePrefix());
  bool saving = false;
  String? error;

  Set<String> get usedPrefixes => {
        for (final s in widget.shops)
          ((s.shop['billPrefix'] as String?) ?? 'S').toUpperCase(),
      };

  // First letter not used by another shop: S, B, C, D...
  String _freePrefix() {
    for (final p in ['S', 'B', 'C', 'D', 'E', 'F', 'G', 'H']) {
      if (!usedPrefixes.contains(p)) return p;
    }
    return 'X';
  }

  @override
  void dispose() {
    name.dispose();
    prefix.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    // Start the new shop with the same GSTIN and terms as the open shop
    final current = widget.shops
        .firstWhere((s) => s.id == widget.session.pharmacyId,
            orElse: () => widget.shops.first)
        .shop;
    final shopName = name.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await PharmacyService.createPharmacy(
        pharmacyName: shopName,
        userName: widget.session.userName,
        alsoKeep: widget.session.pharmacyId,
        shop: {
          'gstin': current['gstin'] ?? '',
          if (current['terms'] != null) 'terms': current['terms'],
          'billPrefix': prefix.text.trim().toUpperCase(),
        },
      );
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text('$shopName added and opened. '
            'Next: Shop details 🏪 → enter its address and drug licence.'),
        duration: const Duration(seconds: 6),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = 'Could not add the shop: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add another shop'),
      content: Form(
        key: formKey,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(
            controller: name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Shop name',
              hintText: 'e.g. Sri Sai Medicals - Branch 2',
              border: OutlineInputBorder(),
            ),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the shop name' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: prefix,
            textCapitalization: TextCapitalization.characters,
            maxLength: 3,
            decoration: const InputDecoration(
              labelText: 'Bill number prefix',
              helperText: 'Bills will be numbered like B-0001',
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              final p = (v ?? '').trim().toUpperCase();
              if (!RegExp(r'^[A-Z]{1,3}$').hasMatch(p)) return '1 to 3 letters';
              if (usedPrefixes.contains(p)) return 'Another shop uses $p';
              return null;
            },
          ),
          const SizedBox(height: 4),
          const Text(
            'The GSTIN is copied from your current shop. Staff join this shop '
            'with its own invite code.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: saving ? null : save,
          child: Text(saving ? 'Adding…' : 'Add shop'),
        ),
      ],
    );
  }
}
