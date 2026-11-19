import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_tracker/services/bill_scanner.dart';

// A word as ML Kit reports it: a box around its centre (the photo is
// already straight here, so rows are level).
OcrWord w(String text, double cx, double cy) {
  final half = text.length * 4.0;
  return OcrWord(text, cx - half, cy - 9, cx + half, cy + 9);
}

void main() {
  // REAL ML Kit output for the Varada Medical Devices bill VN25121,
  // photographed on the phone (19 Nov 2026), misreadings and all.
  final words = [
    w('Ctrl', 497, 58),
    w('Insert', 890, 58),
    w('Delete', 1062, 58),
    w('ARADA', 139, 106),
    w('MEDTCH', 238, 106),
    w('RNO', 100, 118),
    w('12-13-452,', 202, 118),
    w('ROAD', 289, 118),
    w('NO', 333, 118),
    w('KRISHNA', 422, 118),
    w('TARNAKA,', 112, 135),
    w('HYDERABAD', 223, 135),
    w('-', 291, 135),
    w('500017,', 345, 135),
    w('GIRI', 491, 135),
    w('ENCLAVEGROUND', 594, 135),
    w('XRECE', 957, 135),
    w('362012G', 1019, 135),
    w('Contact:', 117, 151),
    w('sC:36', 425, 151),
    w('FLOOR.', 701, 151),
    w('No', 822, 151),
    w('TX', 864, 151),
    w('7207599517,', 223, 153),
    w('9177716905,', 356, 153),
    w('9247664527', 485, 153),
    w('STREET', 772, 153),
    w('tAAMEV13620', 949, 153),
    w('FoodLíCNO:', 121, 169),
    w('Era', 237, 169),
    w('1l:', 267, 169),
    w('varada', 333, 169),
    w('vmd@', 389, 169),
    w('gnail.', 443, 169),
    w('com', 491, 169),
    w('PAN', 853, 169),
    w('TG/HYD/2022-98312', 983, 169),
    w('CALS', 88, 185),
    w('MEDICAL', 163, 185),
    w('(IN', 239, 185),
    w('THE', 278, 185),
    w('DLNO1', 862, 185),
    w(':TG/HYD/2022-98312', 985, 185),
    w('#3-6-386,', 111, 203),
    w('PREMISES', 354, 203),
    w('OF', 420, 203),
    w('CALS', 463, 203),
    w('HOSPITA', 535, 203),
    w('(CA2)', 600, 203),
    w('DINO2', 869, 203),
    w('467-62487', 942, 203),
    w('InvNo', 1166, 203),
    w(':', 1213, 203),
    w('VN25121', 1259, 203),
    w('FLAT', 189, 205),
    w('NO', 235, 205),
    w('301,', 280, 205),
    w('302,', 326, 205),
    w('3RD', 368, 205),
    w('FLOOR', 424, 205),
    w('DÌNO1', 716, 205),
    w('InvDate:', 1181, 205),
    w('17-Nov-2026', 1282, 205),
    w('HIMAYATH', 106, 221),
    w('NAGAR,', 197, 221),
    w('HIMAYATHNAGAR', 309, 221),
    w(':', 743, 221),
    w('TS/HYD/2020-6', 823, 221),
    w('2487-62487', 940, 221),
    w('HYDERABAD,', 121, 238),
    w('DINo2:', 721, 238),
    w('2.', 745, 238),
    w('me', 774, 238),
    w('uyn/2020-62', 848, 238),
    w('PAN:', 958, 238),
    w('AQTPNO537c', 1037, 238),
    w('RepName:', 1183, 238),
    w('OWNER', 1256, 238),
    w('()', 1290, 238),
    w('TELANGANA', 231, 241),
    w('SC:36', 320, 241),
    w('GSTIN:', 719, 241),
    w('36A0TPNO537C1zT', 838, 241),
    w('Time', 1167, 241),
    w(':', 1220, 241),
    w('11:30', 1262, 241),
    w('(1),', 1304, 241),
    w('P:1l:30', 1365, 241),
    w('Ph:', 70, 255),
    w('779911', 137, 255),
    w('61', 201, 255),
    w('6,', 219, 255),
    w('8688512817,', 295, 255),
    w('8801520249', 416, 255),
    w('Y', 708, 255),
    w('Page', 1168, 255),
    w('No:', 1210, 255),
    w('1', 1241, 255),
    w('/1', 1270, 255),
    w('RemBy:', 1322, 255),
    w('MFGBY', 80, 273),
    w('HSNCodo', 183, 273),
    w('QTY', 274, 273),
    w('FREE', 341, 273),
    w('PACK', 405, 273),
    w('IRNNO:', 721, 273),
    w('BATCH', 946, 273),
    w('NO.', 990, 273),
    w('E.X.E', 1091, 273),
    w('P.T.B', 1174, 273),
    w('RATE', 1256, 273),
    w('MOUNT', 1349, 273),
    w('Dísa', 1404, 273),
    w('GST', 1441, 273),
    w('H-ROMSo901683990', 135, 291),
    w('PRODUCT', 488, 291),
    w('NAME', 553, 291),
    w('M.R.P', 866, 291),
    w('067311', 1091, 291),
    w('16.00', 1257, 291),
    w('80.00', 1348, 291),
    w('0.005', 1431, 291),
    w('5', 288, 297),
    w('1', 386, 297),
    w('PC', 400, 297),
    w('ROMOLINE', 500, 297),
    w('EG', 562, 297),
    w('14', 592, 297),
    w('86.00', 893, 297),
    w('K26G010544', 966, 297),
    w('SRCNAmt', 1344, 865),
    w('NETAmount', 1512, 865),
    w('Bill', 1103, 879),
    w('Amount', 1162, 879),
    w('84.00', 1529, 879),
    w('SubTotals', 877, 894),
    w('0.00', 1359, 894),
    w('CGST', 606, 907),
    w('SGST', 736, 907),
    w('80.00', 980, 907),
    w('84.00', 1166, 907),
    w('Discount', 301, 920),
    w('Taxable|', 452, 920),
    w('Gross:', 859, 920),
    w(':', 1108, 920),
    w('HDEC', 1145, 920),
    w('BANK', 1200, 920),
    w('Gross', 165, 931),
    w('0.00', 465, 931),
    w('0.00', 605, 931),
    w('0.00', 734, 931),
    w('0.00', 988, 931),
    w('Bank', 1044, 931),
    w('0.00', 326, 941),
    w('2.00', 736, 941),
    w('Disc', 851, 941),
    w(':', 890, 941),
    w('ACCNO', 1051, 941),
    w(':', 1109, 941),
    w('50200009257801', 1202, 941),
    w('sT', 27, 956),
    w('0:', 54, 956),
    w('0.00', 181, 956),
    w('80.00', 461, 956),
    w('2.00', 603, 956),
    w('4.00', 990, 956),
  ];

  test('reads the real Varada scan', () {
    final b = BillScanner.parse(words);
    expect(b.billNumber, 'VN25121');
    expect(b.billDate, DateTime(2026, 11, 17));
    expect(b.lines.length, 1);
    final l = b.lines.first;
    expect(l.name, 'ROMOLINE EG 14'); // ML Kit read "FG" as "EG"
    expect(l.quantity, 5);
    expect(l.pack, '1 PC');
    expect(l.batch, 'K26G010544');
    expect(l.expiry, DateTime(2031, 6, 30)); // read as "067311"
    expect(l.rate, 16.0);
    expect(l.mrp, 86.0);
    expect(l.gstPct, 5.0); // "0.005" split into disc 0.00 + GST 5
    expect(b.printedTotal, 84.0);
    expect(b.supplier, isNot(contains('Ctrl'))); // keyboard in the photo
  });

  test('expiry and date formats', () {
    expect(BillScanner.parseExpiry('06/31'), DateTime(2031, 6, 30));
    expect(BillScanner.parseExpiry('067311'), DateTime(2031, 6, 30));
    expect(BillScanner.parseExpiry('2/2028'), DateTime(2028, 2, 29));
    expect(BillScanner.parseExpiry('13/28'), isNull);
    expect(BillScanner.parseDate('Date 05/01/2027'), DateTime(2027, 1, 5));
    expect(BillScanner.parseDate('InvDate: 17-Nov-2026'), DateTime(2026, 11, 17));
  });

  test('no text gives a clear warning', () {
    expect(BillScanner.parse(const []).warnings.single, contains('No text'));
  });
}
