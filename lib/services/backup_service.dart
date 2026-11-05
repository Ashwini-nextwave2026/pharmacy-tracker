import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'pharmacy_service.dart';

// Makes one backup file (JSON) with ALL of a pharmacy's data.
//
// {
//   "app": "Pharmacy Tracker", "backupVersion": 1,
//   "pharmacyName": "...", "createdAt": "2026-11-05T15:10:00",
//   "pharmacy": { ...shop details... },
//   "collections": {
//     "stock":    { "<doc id>": { ...fields... }, ... },
//     "bills":    { ... }, "sales": { ... }, ...
//   }
// }
//
// Dates are saved as {"__timestamp": "2026-11-05T15:10:00.000"} so a
// restore can turn them back into Firestore dates.

// Every collection inside pharmacies/<id>/ that holds shop data
const backupCollections = [
  'stock',
  'bills',
  'sales',
  'payments',
  'expenses',
  'suppliers',
  'members',
  'counters',
];

// Turn Firestore values into plain JSON values
Object? toJsonValue(Object? v) {
  if (v is Timestamp) return {'__timestamp': v.toDate().toIso8601String()};
  if (v is DateTime) return {'__timestamp': v.toIso8601String()};
  if (v is GeoPoint) return {'__geo': [v.latitude, v.longitude]};
  if (v is DocumentReference) return {'__ref': v.path};
  if (v is Map) return v.map((k, val) => MapEntry('$k', toJsonValue(val)));
  if (v is List) return v.map(toJsonValue).toList();
  return v; // String, num, bool, null
}

class BackupResult {
  final Uint8List bytes;
  final String fileName;
  final Map<String, int> counts; // collection -> number of records

  BackupResult(this.bytes, this.fileName, this.counts);

  int get total => counts.values.fold(0, (a, b) => a + b);
}

// Build the file name, e.g. "PharmacyBackup-Cals-Medical-2026-11-05-1510.json"
String backupFileName(String pharmacyName, DateTime when) {
  final safe = pharmacyName
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp = '${when.year}-${two(when.month)}-${two(when.day)}-'
      '${two(when.hour)}${two(when.minute)}';
  return 'PharmacyBackup-${safe.isEmpty ? 'Shop' : safe}-$stamp.json';
}

class BackupService {
  // Read everything and pack it into one JSON file
  static Future<BackupResult> create({
    required String pharmacyId,
    required String pharmacyName,
  }) async {
    final now = DateTime.now();
    final pharmacySnap = await PharmacyService.pharmacyRef(pharmacyId).get();

    final collections = <String, Object?>{};
    final counts = <String, int>{};
    for (final name in backupCollections) {
      final snap = await PharmacyService.pharmacyRef(pharmacyId).collection(name).get();
      collections[name] = {
        for (final doc in snap.docs) doc.id: toJsonValue(doc.data()),
      };
      counts[name] = snap.docs.length;
    }

    final data = {
      'app': 'Pharmacy Tracker',
      'backupVersion': 1,
      'pharmacyId': pharmacyId,
      'pharmacyName': pharmacyName,
      'createdAt': now.toIso8601String(),
      'counts': counts,
      'pharmacy': toJsonValue(pharmacySnap.data()),
      'collections': collections,
    };

    final bytes = Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent(' ').convert(data)));

    // Remember when the last backup was made (shown on the Backup page)
    await PharmacyService.pharmacyRef(pharmacyId).update({
      'lastBackupAt': FieldValue.serverTimestamp(),
      'lastBackupRecords': counts.values.fold<int>(0, (a, b) => a + b),
    });

    return BackupResult(bytes, backupFileName(pharmacyName, now), counts);
  }
}
