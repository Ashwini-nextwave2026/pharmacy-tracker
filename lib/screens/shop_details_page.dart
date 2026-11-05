import 'package:flutter/material.dart';
import '../models/session.dart';
import '../models/shop_details.dart';
import '../services/pharmacy_service.dart';

// Owner only: the shop details printed on every Tax Invoice
// (address, phone, GSTIN, drug licence, UPI ID, terms).
class ShopDetailsPage extends StatefulWidget {
  final Session session;

  const ShopDetailsPage({super.key, required this.session});

  @override
  State<ShopDetailsPage> createState() => _ShopDetailsPageState();
}

class _ShopDetailsPageState extends State<ShopDetailsPage> {
  final formKey = GlobalKey<FormState>();
  final c = <String, TextEditingController>{};
  bool loading = true;
  bool saving = false;

  // Each box: key in Firestore, label, hint, how many lines
  static const fields = [
    ('address', 'Shop address', 'Shop no, street, area, Hyderabad, Telangana - 500008', 3),
    ('phone', 'Phone / mobile', '+91 98xxxxxxxx', 1),
    ('gstin', 'GSTIN', '36ABCDE1234F1Z5', 1),
    ('drugLicence', 'Drug licence numbers', '20B: TS/HYD/2024/xxxx, 21B: TS/HYD/2024/xxxx', 2),
    ('upiId', 'UPI ID for the scan-to-pay QR (optional)', 'shopname@okhdfcbank', 1),
    ('terms', 'Terms & conditions (one per line)', '', 4),
  ];

  @override
  void initState() {
    super.initState();
    for (final f in fields) {
      c[f.$1] = TextEditingController();
    }
    load();
  }

  @override
  void dispose() {
    for (final controller in c.values) {
      controller.dispose();
    }
    super.dispose();
  }

  // Fill the boxes with what's saved
  Future<void> load() async {
    final snap = await PharmacyService.pharmacyRef(widget.session.pharmacyId).get();
    final shop = ShopDetails.fromMap(
        (snap.data()?['shop'] as Map?)?.cast<String, dynamic>());
    final map = shop.toMap();
    if (!mounted) return;
    setState(() {
      for (final f in fields) {
        c[f.$1]!.text = map[f.$1] as String? ?? '';
      }
      loading = false;
    });
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => saving = true);
    final shop = ShopDetails.fromMap({
      for (final f in fields) f.$1: c[f.$1]!.text.trim(),
    });
    shop.gstin = shop.gstin.toUpperCase();
    try {
      await PharmacyService.pharmacyRef(widget.session.pharmacyId)
          .update({'shop': shop.toMap()});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shop details saved. They will show on every invoice.')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shop details for invoice')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(widget.session.pharmacyName,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const Text('These details print on every Tax Invoice.',
                      style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 16),
                  for (final f in fields) ...[
                    TextFormField(
                      controller: c[f.$1],
                      maxLines: f.$4,
                      textCapitalization: f.$1 == 'gstin'
                          ? TextCapitalization.characters
                          : TextCapitalization.sentences,
                      keyboardType: f.$1 == 'phone' ? TextInputType.phone : null,
                      decoration: InputDecoration(
                        labelText: f.$2,
                        hintText: f.$3.isEmpty ? null : f.$3,
                        border: const OutlineInputBorder(),
                        alignLabelWithHint: f.$4 > 1,
                      ),
                      validator: (v) {
                        final t = v?.trim() ?? '';
                        if (f.$1 == 'gstin' && t.isNotEmpty && t.length != 15) {
                          return 'A GSTIN has 15 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                  ],
                  ElevatedButton.icon(
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Save shop details'),
                    ),
                    onPressed: saving ? null : save,
                  ),
                ],
              ),
            ),
    );
  }
}
