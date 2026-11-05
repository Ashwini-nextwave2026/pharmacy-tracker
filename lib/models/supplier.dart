import 'package:cloud_firestore/cloud_firestore.dart';

// A supplier / distributor, saved once and picked on every purchase bill
class Supplier {
  String? id;
  String name;
  String gstin;
  String phone;
  String address;
  String drugLicence;
  int creditDays; // usual days they give to pay
  String contactPerson;

  Supplier({
    this.id,
    required this.name,
    this.gstin = '',
    this.phone = '',
    this.address = '',
    this.drugLicence = '',
    this.creditDays = 30,
    this.contactPerson = '',
  });

  // Telangana GSTINs start with 36; a supplier from any other state charges IGST
  bool get interState => gstin.length >= 2 && !gstin.startsWith('36');

  Map<String, dynamic> toMap() => {
        'name': name,
        'nameKey': nameKey(name),
        'gstin': gstin,
        'phone': phone,
        'address': address,
        'drugLicence': drugLicence,
        'creditDays': creditDays,
        'contactPerson': contactPerson,
      };

  factory Supplier.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Supplier(
      id: doc.id,
      name: d['name'] ?? '',
      gstin: d['gstin'] ?? '',
      phone: d['phone'] ?? '',
      address: d['address'] ?? '',
      drugLicence: d['drugLicence'] ?? '',
      creditDays: (d['creditDays'] as num?)?.toInt() ?? 30,
      contactPerson: d['contactPerson'] ?? '',
    );
  }
}

// "Sri Ram Pharma", "SRI RAM PHARMA " and "Sri  Ram Pharma." count as one
String nameKey(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

// Suppliers whose name contains what's typed, best matches first
List<Supplier> searchSuppliers(List<Supplier> all, String typed) {
  final q = nameKey(typed);
  if (q.isEmpty) return all;
  final starts = all.where((s) => nameKey(s.name).startsWith(q));
  final contains =
      all.where((s) => !nameKey(s.name).startsWith(q) && nameKey(s.name).contains(q));
  return [...starts, ...contains];
}
