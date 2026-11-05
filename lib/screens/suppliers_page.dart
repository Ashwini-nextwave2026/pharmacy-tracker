import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/session.dart';
import '../models/supplier.dart';
import '../services/pharmacy_service.dart';
import 'supplier_dues_page.dart' show SupplierAccountPage;

// The list of suppliers / distributors. Tap one to edit it.
class SuppliersPage extends StatelessWidget {
  final Session session;

  const SuppliersPage({super.key, required this.session});

  // Make supplier entries from names already typed on old purchase bills
  Future<void> addFromBills(BuildContext context, List<Supplier> existing) async {
    final pid = session.pharmacyId;
    final bills = await PharmacyService.billsRef(pid).get();
    final have = existing.map((s) => nameKey(s.name)).toSet();
    final toAdd = <String, Supplier>{};
    for (final doc in bills.docs) {
      final d = doc.data();
      final name = (d['supplier'] as String? ?? '').trim();
      final key = nameKey(name);
      if (name.isEmpty || have.contains(key) || toAdd.containsKey(key)) continue;
      toAdd[key] = Supplier(
        name: name,
        gstin: (d['supplierGstin'] as String?) ?? '',
        creditDays: (d['creditDays'] as num?)?.toInt() ?? 30,
      );
    }
    if (toAdd.isNotEmpty) {
      final batch = FirebaseFirestore.instance.batch();
      for (final s in toAdd.values) {
        batch.set(PharmacyService.suppliersRef(pid).doc(), s.toMap());
      }
      await batch.commit();
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(toAdd.isEmpty
            ? 'No new supplier names found on old bills'
            : 'Added ${toAdd.length} supplier${toAdd.length == 1 ? '' : 's'} from old bills'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: PharmacyService.suppliersRef(session.pharmacyId).orderBy('name').snapshots(),
      builder: (context, snapshot) {
        final suppliers = snapshot.hasData
            ? snapshot.data!.docs.map(Supplier.fromFirestore).toList()
            : <Supplier>[];

        return Scaffold(
          appBar: AppBar(
            title: const Text('Suppliers'),
            actions: [
              IconButton(
                icon: const Icon(Icons.playlist_add),
                tooltip: 'Add suppliers from old bills',
                onPressed: snapshot.hasData ? () => addFromBills(context, suppliers) : null,
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.add_business),
            label: const Text('Add supplier'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => SupplierFormPage(session: session)),
            ),
          ),
          body: snapshot.hasError
              ? Center(child: Text('Could not load: ${snapshot.error}'))
              : !snapshot.hasData
                  ? const Center(child: CircularProgressIndicator())
                  : suppliers.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('No suppliers yet.',
                                    style: TextStyle(fontSize: 18, color: Colors.grey)),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.playlist_add),
                                  label: const Text('Add from old purchase bills'),
                                  onPressed: () => addFromBills(context, suppliers),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 88, top: 8),
                          children: [
                            for (final s in suppliers)
                              Card(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.indigo.withValues(alpha: 0.12),
                                    child: Text(s.name.isEmpty ? '?' : s.name[0].toUpperCase(),
                                        style: const TextStyle(
                                            color: Colors.indigo, fontWeight: FontWeight.bold)),
                                  ),
                                  title: Text(s.name,
                                      style: const TextStyle(fontWeight: FontWeight.w600)),
                                  subtitle: Text([
                                    if (s.gstin.isNotEmpty) 'GSTIN ${s.gstin}',
                                    if (s.phone.isNotEmpty) s.phone,
                                    '${s.creditDays} days credit',
                                    if (s.interState) 'IGST',
                                  ].join(' · ')),
                                  trailing: session.isOwner
                                      ? IconButton(
                                          icon: const Icon(Icons.account_balance_wallet),
                                          tooltip: 'Account & dues',
                                          onPressed: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => SupplierAccountPage(
                                                  session: session, supplier: s.name),
                                            ),
                                          ),
                                        )
                                      : null,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          SupplierFormPage(session: session, supplier: s),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
        );
      },
    );
  }
}

// Add a supplier, or edit one (pass [supplier]).
// Returns the saved supplier with Navigator.pop, so New Bill can use it.
class SupplierFormPage extends StatefulWidget {
  final Session session;
  final Supplier? supplier;
  final String? initialName; // when adding from the New Bill screen

  const SupplierFormPage({super.key, required this.session, this.supplier, this.initialName});

  @override
  State<SupplierFormPage> createState() => _SupplierFormPageState();
}

class _SupplierFormPageState extends State<SupplierFormPage> {
  final formKey = GlobalKey<FormState>();
  late final old = widget.supplier;
  late final name = TextEditingController(text: old?.name ?? widget.initialName);
  late final gstin = TextEditingController(text: old?.gstin);
  late final phone = TextEditingController(text: old?.phone);
  late final contact = TextEditingController(text: old?.contactPerson);
  late final address = TextEditingController(text: old?.address);
  late final licence = TextEditingController(text: old?.drugLicence);
  late final credit = TextEditingController(text: '${old?.creditDays ?? 30}');
  bool saving = false;

  @override
  void dispose() {
    for (final c in [name, gstin, phone, contact, address, licence, credit]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => saving = true);
    final ref = PharmacyService.suppliersRef(widget.session.pharmacyId);
    final s = Supplier(
      id: old?.id,
      name: name.text.trim(),
      gstin: gstin.text.trim().toUpperCase(),
      phone: phone.text.trim(),
      contactPerson: contact.text.trim(),
      address: address.text.trim(),
      drugLicence: licence.text.trim(),
      creditDays: int.parse(credit.text.trim()),
    );
    try {
      // Don't allow two suppliers with the same name
      final same = await ref.where('nameKey', isEqualTo: nameKey(s.name)).get();
      if (same.docs.any((d) => d.id != old?.id)) {
        throw Exception('A supplier called "${s.name}" already exists');
      }
      if (old == null) {
        final doc = await ref.add(s.toMap());
        s.id = doc.id;
      } else {
        await ref.doc(old!.id).update(s.toMap());
      }
      if (mounted) Navigator.pop(context, s);
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  InputDecoration box(String label, {String? hint, String? suffix}) => InputDecoration(
        labelText: label,
        hintText: hint,
        suffixText: suffix,
        border: const OutlineInputBorder(),
        counterText: '',
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(old == null ? 'Add supplier' : 'Edit supplier')),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: name,
              autofocus: old == null && widget.initialName == null,
              textCapitalization: TextCapitalization.words,
              decoration: box('Supplier / distributor name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter the name' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: gstin,
              textCapitalization: TextCapitalization.characters,
              maxLength: 15,
              decoration: box('GSTIN (optional)', hint: '36ABCDE1234F1Z5'),
              validator: (v) {
                final t = v?.trim() ?? '';
                return t.isNotEmpty && t.length != 15 ? 'A GSTIN has 15 characters' : null;
              },
            ),
            const SizedBox(height: 14),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: TextFormField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: box('Phone'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: credit,
                  keyboardType: TextInputType.number,
                  decoration: box('Credit', suffix: 'days'),
                  validator: (v) {
                    final n = int.tryParse(v?.trim() ?? '');
                    return n == null || n < 0 || n > 365 ? '0 to 365' : null;
                  },
                ),
              ),
            ]),
            const SizedBox(height: 14),
            TextFormField(
              controller: contact,
              textCapitalization: TextCapitalization.words,
              decoration: box('Contact person (optional)', hint: 'e.g. Ramesh, sales rep'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: address,
              maxLines: 2,
              decoration: box('Address (optional)'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: licence,
              decoration: box('Drug licence no. (optional)'),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: saving
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Save supplier'),
              ),
              onPressed: saving ? null : save,
            ),
          ],
        ),
      ),
    );
  }
}
