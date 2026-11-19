import 'bill_scanner.dart';

// Chrome / web: ML Kit isn't available here
bool get billScanSupported => false;

enum BillSource { camera, gallery, pdf }

Future<ScannedBill?> scanBill(BillSource source) async => throw UnsupportedError(
    'Bill scanning works in the Android app (APK), not in Chrome.');
