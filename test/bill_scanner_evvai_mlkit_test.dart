import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_tracker/services/bill_scanner.dart';

// What ML Kit really read from the EVVAI PDF on the phone (19 Nov 2026),
// from "Send scan details": each row is "y=<row>: word@x word@x ...".
// That debug was drawn with a wrong tilt (0.1198) taken from "Total Qty"
// near the bottom; it is undone here to get the words as ML Kit gave them.
const debugRows = [
  'y=-73: HOSPITAL)@955',
  'y=-63: OF@869 CALS@899',
  'y=-58: PREMISES@824',
  'y=-49: IN@749 THE@773',
  'y=-44: MEDICAL(@707',
  'y=-33: To:@615 CALS@654',
  'y=-21: INVOICE@543',
  'y=-10: LIMITED@397 GST@485',
  'y=-1: PRIVATE@318 HYDERABAD@638',
  'y=7: EWO0617@541 PO.No:@928',
  'y=16: PHARMACEUTICALS@182 INV.NO@470 :,7799110616@679 19/11/2026@985',
  'y=22: GAGANMAHAL,@304 Phone@621 Date@922',
  'y=30: EVVAI@61 FLOOR,@237 STATE@337 19/11/2026@544',
  'y=39: NO.1,@160 FIRST@196 DATE@476 AMOUNT@1022',
  'y=46: 50,@99 SHOP@125 TELANGANA@277 OL.No\'s@624 |GST@954',
  'y=51: #12-593/@62 HYDERABAD-500029.@176 Credit@529 36AQTPNO537C1ZT@701 P.T.R@913',
  'y=57: TYPE@476 GST@614 NO@632 :@646 P.T.S@860',
  'y=65: DOMALGUDA,@73 website:www.ewaipharma.com@335 M.R.P@796 2750.00@1028',
  'y=75: 7075730616@119 DINESH@534 oTY@705 FREE@735 406.118.0@940',
  'y=82: PHONE:@57 2024-116046@317 SMan@474 EXPIRY@643 55.00@867 2750.00@1028',
  'y=89: Email-ID:sales@evvaipharma.com@131 TS@238 HYDI@264 U51909TG20220PC168799@353 599.00@800 608.8|@931 5.0|@966',
  'y=96: 2024-116046,@191 BATCHNO@550 0.0@744 1750.00@1028',
  'y=104: TSHYD@123 CIN@234 NO:@260 HSNCODE@446 MFG@495 50.0@699 55.00@867 |@973',
  'y=113: DL.No\'s@54 :@87 8/2028|@649 799.00@800 1564@924 5.0@960',
  'y=117: :36AAHCE3474C1ZS@137 PACK@388 0.0@744 35.00@868',
  'y=126: 21069091EVVAIOSUO19@485 8/2028@647 50.0@700 205.31@799',
  'y=127: GSTIN@49',
  'y=139: PN-2812@540 50.0@702 0.0@744',
  'y=145: NAME@122 1@375 EVVAI@492 12/2027@644',
  'y=149: ITEM@90 21069099@444',
  'y=155: S.No@44 30\'S@388',
  'y=165: SPRAY@185 30049099EVVAI126009A1@493',
  'y=170: MELATONIN@132',
  'y=176: ZENE@84 10@379',
  'y=191: HEPRAMAX@105 GOLD@155',
  'y=200: 2@42 GAS@121 TAB@145',
  'y=210: ERASE@89',
  'y=286: EV)@588',
  'y=363: PHARMAĻEUCL@620',
  'y=410: our@632 Mcine@672',
  'y=419: Your@553 Cure@589',
  'y=427: HYDERABAD@920',
  'y=436: BRANCH,@850',
  'y=446: HIMAYATHNAGAR@767',
  'y=455: BANK,@689 7250.00@1014',
  'y=466: 000081,@601 HDFc@649 Subtotal:@942',
  'y=471: HDFCO@556 0.00@849 0.00@1022',
  'y=483: 3554,@452 IFsc:@501 0%Taxable@766 Less@924 Disc@950',
  'y=490: 5020007661@397 NOTE@541 0.00@849 720.00@1016',
  'y=497: No:@336 IGSTAMT@484 23190.00@668 GST@932 Amt:@959',
  'y=504: :@283 A/c@306 Amt@612 :@626 Adjust@752 (-+)@783 0.00@1022',
  'y=508: DETAILS@245 SGSTAMT@399 Total@564 Due@590 2.0@685 0.00@849',
  'y=514: BANK@195 CGSTAMT@317 0.00@495 :@627 Ca/Dr@751 Amt@777 Rounding@937',
  'y=524: PAY@113 Total@562 Due@589 Invs@612 0.00@849',
  'y=528: SCAN@78 &@97 TAXABLE@249 112.50@410 3.0@686 Amt@783',
  'y=532: GST%@189 112.50@324 0.00@494 Items@593 Freight@752',
  'y=542: 0.00@416 Total@562 150.0@679',
  'y=545: 4500.00@255 0.00@495',
  'y=552: 5:@194 0.00@331 Total@565 Oty@589 AMOUNT@985',
  'y=560: 0.00@264 247.50@409 0.00@495 NET@936',
  'y=569: 12@187 247.50@324 PRIVATE@780 LIMITED@822',
  'y=577: 2750.00@255 0.00@416',
  'y=585: 18@187 :@200 0.00@330 0.00@494 PHARMACEUTICALS@708',
  'y=591: 0.00@264 360.00@407 For@618 EVVAI@643',
  'y=601: 28@186 :@200 360.00@322',
  'y=613: 7250.00@250 7970.00@964',
  'y=620: Total:@189',
  'y=736: InWords@54',
];

List<OcrWord> wordsFromDebug() {
  final words = <OcrWord>[];
  for (final line in debugRows) {
    final m = RegExp(r'^y=(-?\d+): (.*)$').firstMatch(line)!;
    final y = double.parse(m.group(1)!);
    for (final token in m.group(2)!.split(' ')) {
      final at = token.lastIndexOf('@');
      final text = token.substring(0, at);
      final cx = double.parse(token.substring(at + 1));
      final cy = y + 0.1198 * cx;
      final half = text.length * 2.6;
      words.add(OcrWord(text, cx - half, cy - 5, cx + half, cy + 5));
    }
  }
  return words;
}

void main() {
  test('EVVAI PDF as read by ML Kit on the phone', () {
    final b = BillScanner.parse(wordsFromDebug());
    expect(b.supplierGstin, '36AAHCE3474C1ZS');
    expect(b.billDate, DateTime(2026, 11, 19));
    expect(b.printedTotal, 7970.0);
    expect(b.lines.map((l) => l.name).toList(),
        ['ZENE MELATONIN SPRAY', 'HEPRAMAX GOLD', 'ERASE GAS TAB']);
    expect(b.lines.map((l) => l.quantity).toList(), [50, 50, 50]);
    expect(b.lines.map((l) => l.rate).toList(), [55, 55, 35]);
    expect(b.lines.map((l) => l.gstPct).toList(), [18, 5, 5]);
    expect(b.lines.map((l) => l.batch).toList(), ['OSUO19', 'PN-2812', '126009A1']);
    expect(b.lines.map((l) => l.mrp).toList(), [599, 799, 205.31]);
    expect(b.lines.map((l) => l.hsn).toList(), ['21069091', '21069099', '30049099']);
  });
}
