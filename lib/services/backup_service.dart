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
  'adjustments',
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

// =====================================================================
// RESTORE
// =====================================================================
//
// Safe by design:
// - Default: only records MISSING now are added back (nothing you have
//   now is changed). Optionally, records that exist can be overwritten
//   with the backup's version.
// - Nothing is ever deleted.
// - Owner & staff (members) are NOT restored, so a removed staff member
//   can't come back through an old backup.
// - Bill-number counters only ever go UP, so no S-number is used twice.
// - Shop details come back only if none are set now.

// Collections a restore writes back (members left out on purpose)
const restoreCollections = [
  'stock',
  'bills',
  'sales',
  'payments',
  'expenses',
  'suppliers',
  'adjustments',
];

// Turn the backup's JSON values back into Firestore values
Object? fromJsonValue(Object? v) {
  if (v is Map) {
    if (v.length == 1 && v['__timestamp'] is String) {
      return Timestamp.fromDate(DateTime.parse(v['__timestamp'] as String));
    }
    if (v.length == 1 && v['__geo'] is List) {
      final g = v['__geo'] as List;
      return GeoPoint((g[0] as num).toDouble(), (g[1] as num).toDouble());
    }
    if (v.length == 1 && v['__ref'] is String) {
      return FirebaseFirestore.instance.doc(v['__ref'] as String);
    }
    return v.map((k, val) => MapEntry('$k', fromJsonValue(val)));
  }
  if (v is List) return v.map(fromJsonValue).toList();
  return v;
}

// What's inside a backup file, after checking it really is one
class BackupFile {
  final String pharmacyId;
  final String pharmacyName;
  final DateTime createdAt;
  final Map<String, dynamic>? pharmacy;
  final Map<String, Map<String, dynamic>> collections; // name -> id -> data (JSON)

  BackupFile(this.pharmacyId, this.pharmacyName, this.createdAt, this.pharmacy,
      this.collections);

  int count(String name) => collections[name]?.length ?? 0;
}

// Read and check a backup file; throws a clear message if it isn't one
BackupFile parseBackup(Uint8List bytes) {
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } catch (_) {
    throw const FormatException('This file is not a Pharmacy Tracker backup (not JSON).');
  }
  if (decoded is! Map || decoded['app'] != 'Pharmacy Tracker' || decoded['collections'] is! Map) {
    throw const FormatException('This file is not a Pharmacy Tracker backup.');
  }
  if ((decoded['backupVersion'] as num? ?? 0) > 1) {
    throw const FormatException('This backup was made by a newer version of the app. Update the app first.');
  }
  final cols = <String, Map<String, dynamic>>{};
  (decoded['collections'] as Map).forEach((name, docs) {
    if (docs is Map) cols['$name'] = Map<String, dynamic>.from(docs);
  });
  return BackupFile(
    decoded['pharmacyId'] as String? ?? '',
    decoded['pharmacyName'] as String? ?? '',
    DateTime.tryParse(decoded['createdAt'] as String? ?? '') ?? DateTime(2000),
    decoded['pharmacy'] is Map ? Map<String, dynamic>.from(decoded['pharmacy']) : null,
    cols,
  );
}

// For one collection: which backup records are missing now, which exist
class RestorePlanItem {
  final String collection;
  final List<String> missing; // in the backup, not in the app now
  final List<String> existing; // in both

  RestorePlanItem(this.collection, this.missing, this.existing);
}

RestorePlanItem planCollection(String name, Map<String, dynamic> backupDocs, Set<String> nowIds) {
  final missing = <String>[];
  final existing = <String>[];
  for (final id in backupDocs.keys) {
    (nowIds.contains(id) ? existing : missing).add(id);
  }
  return RestorePlanItem(name, missing, existing);
}

class RestoreService {
  // Compare the backup with what's in the app now
  static Future<List<RestorePlanItem>> plan(String pharmacyId, BackupFile backup) async {
    final items = <RestorePlanItem>[];
    for (final name in restoreCollections) {
      final docs = backup.collections[name] ?? {};
      final snap = await PharmacyService.pharmacyRef(pharmacyId).collection(name).get();
      items.add(planCollection(name, docs, snap.docs.map((d) => d.id).toSet()));
    }
    return items;
  }

  // Write the records back. Returns how many were written.
  static Future<int> restore({
    required String pharmacyId,
    required BackupFile backup,
    required List<RestorePlanItem> plan,
    required bool overwriteExisting,
    void Function(int done, int total)? onProgress,
  }) async {
    final db = FirebaseFirestore.instance;
    final pharmacy = PharmacyService.pharmacyRef(pharmacyId);

    // Everything to write: (collection, id)
    final jobs = <(String, String)>[
      for (final p in plan) ...[
        for (final id in p.missing) (p.collection, id),
        if (overwriteExisting) for (final id in p.existing) (p.collection, id),
      ],
    ];

    var done = 0;
    for (var start = 0; start < jobs.length; start += 400) {
      final batch = db.batch();
      for (final (col, id) in jobs.skip(start).take(400)) {
        final data = fromJsonValue(backup.collections[col]![id]) as Map<String, dynamic>;
        batch.set(pharmacy.collection(col).doc(id), data);
      }
      await batch.commit();
      done = (start + 400).clamp(0, jobs.length);
      onProgress?.call(done, jobs.length);
    }

    // Bill-number counters: only ever move up
    final counters = backup.collections['counters'] ?? {};
    for (final entry in counters.entries) {
      final backupLast = ((entry.value as Map)['last'] as num?)?.toInt() ?? 0;
      final ref = pharmacy.collection('counters').doc(entry.key);
      final now = await ref.get();
      final nowLast = (now.data()?['last'] as num?)?.toInt() ?? 0;
      if (backupLast > nowLast) await ref.set({'last': backupLast}, SetOptions(merge: true));
    }

    // Shop details: only if none are set now
    final shop = backup.pharmacy?['shop'];
    if (shop is Map) {
      final now = await pharmacy.get();
      if (now.data()?['shop'] == null) {
        await pharmacy.update({'shop': fromJsonValue(shop)});
      }
    }

    await pharmacy.update({'lastRestoreAt': FieldValue.serverTimestamp()});
    return jobs.length;
  }
}
