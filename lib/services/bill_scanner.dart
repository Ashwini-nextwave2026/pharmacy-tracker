import 'dart:math' as math;

import '../models/purchase_bill.dart';

// Turns the text read from a photo of a supplier's paper bill (by Google
// ML Kit, on the phone) into a DRAFT purchase bill: supplier, bill number,
// date and the item lines.
//
// ML Kit only gives words and where they sit on the photo. This file
// rebuilds the table from that:
//   1. find the header row (QTY, FREE, PACK, PRODUCT, MRP, BATCH, EXP, RATE...)
//   2. straighten a tilted photo using that header row
//   3. put every word under the nearest column, row by row
//   4. stop at the totals (GROSS, TAXABLE, CGST, BILL AMOUNT...)
// Bills differ, so the result is always checked on the New Bill screen
// before Save.

// One word ML Kit found, with its box on the photo (pixels)
class OcrWord {
  final String text;
  final double left, top, right, bottom;

  const OcrWord(this.text, this.left, this.top, this.right, this.bottom);

  double get cx => (left + right) / 2;
  double get cy => (top + bottom) / 2;
  double get height => bottom - top;
}

// A word as ML Kit gives it: its text and the 4 corners of its box, in
// reading order (top-left, top-right, bottom-right, bottom-left of the
// TEXT, even when the text is turned).
typedef RawWord = ({String text, List<math.Point<num>> corners});

// A bill photographed or a PDF page saved sideways or upside down: ML Kit
// still reads the words, but their boxes come out turned. Find which way
// the text runs and turn every box back, so the bill is upright.
List<OcrWord> uprightWords(List<RawWord> raw) {
  if (raw.isEmpty) return const [];
  // direction of each word's top edge, in degrees (0 = upright)
  final angles = <double>[];
  for (final r in raw) {
    if (r.corners.length < 2 || r.text.trim().length < 3) continue;
    final a = r.corners[0], b = r.corners[1];
    angles.add(math.atan2((b.y - a.y).toDouble(), (b.x - a.x).toDouble()) * 180 / math.pi);
  }
  var turn = 0.0;
  if (angles.isNotEmpty) {
    // the quarter turn most words agree on (0, 90, 180 or -90)...
    int quarter(double a) => ((a / 90).round() % 4 + 4) % 4;
    final votes = List.filled(4, 0);
    for (final a in angles) {
      votes[quarter(a)]++;
    }
    var q = 0;
    for (var i = 1; i < 4; i++) {
      if (votes[i] > votes[q]) q = i;
    }
    // ...plus the small tilt (median), the header straightening does the rest
    final rest = [
      for (final a in angles)
        if (quarter(a) == q) ((a - q * 90 + 540) % 360) - 180,
    ]..sort();
    turn = (q * 90).toDouble() + rest[rest.length ~/ 2];
  }
  if (turn.abs() < 0.5) {
    // already upright: plain boxes
    return [
      for (final r in raw)
        if (r.corners.isNotEmpty) _box(r.text, r.corners.map((p) => (p.x.toDouble(), p.y.toDouble()))),
    ];
  }
  final t = -turn * math.pi / 180, c = math.cos(t), s = math.sin(t);
  return [
    for (final r in raw)
      if (r.corners.isNotEmpty)
        _box(r.text, r.corners.map((p) => (
            (p.x * c - p.y * s).toDouble(), (p.x * s + p.y * c).toDouble()))),
  ];
}

OcrWord _box(String text, Iterable<(double, double)> pts) {
  var l = double.infinity, tp = double.infinity;
  var rt = double.negativeInfinity, bt = double.negativeInfinity;
  for (final (x, y) in pts) {
    l = math.min(l, x);
    rt = math.max(rt, x);
    tp = math.min(tp, y);
    bt = math.max(bt, y);
  }
  return OcrWord(text, l, tp, rt, bt);
}

class ScannedBill {
  final String supplier;
  final String supplierGstin;
  final String billNumber;
  final DateTime? billDate;
  final List<BillLine> lines;
  final double? printedTotal; // NET / bill amount printed on the bill
  final List<String> warnings; // things to check by hand
  // What ML Kit read, row by row with x positions: shared with the
  // developer when a bill doesn't read well, so the reader can be tuned
  final String debugText;

  ScannedBill({
    this.debugText = '',
    required this.supplier,
    required this.supplierGstin,
    required this.billNumber,
    required this.billDate,
    required this.lines,
    required this.printedTotal,
    required this.warnings,
  });
}

class BillScanner {
  // Header word -> which column it names. ML Kit often misreads small
  // print ("HSNCodo", "E.X.E", "P.T.B", "MOUNT", "Dísa"), so this is loose.
  static String? _columnOf(String word) {
    final k = _key(word);
    if (k.isEmpty) return null;
    if (k.startsWith('HSN')) return 'hsn';
    if (k == 'QTY' || k == 'QIY' || k == 'OTY' || k == 'QUANTITY') return 'qty';
    if (k == 'FREE' || k == 'FREEQTY') return 'free';
    if (k == 'PACK' || k == 'PACKING' || k == 'PKG') return 'pack';
    if (k.startsWith('PROD') || k.startsWith('DESC') ||
        k.startsWith('PARTIC') || k == 'ITEM' || k == 'ITEMNAME') {
      return 'name';
    }
    if (k == 'MRP' || k == 'MRF' || k == 'NRP' || k == 'RP') return 'mrp';
    if (k.startsWith('BATC')) return 'batch';
    if (k == 'EXPIRY' || k == 'EXPDT' || (k.startsWith('EX') && k.length <= 4)) {
      return 'expiry';
    }
    if (k == 'PTR' || k == 'PTB' || k == 'PTA' || k == 'PIR') return 'ptr';
    if (k == 'RATE' || k == 'RAIE' || k == 'RATF') return 'rate';
    if ((k.contains('MOUNT') || k.contains('AMOUN') || k == 'AMT') &&
        !k.contains('NET') && !k.contains('BILL')) {
      return 'amount';
    }
    if (k.startsWith('DIS')) return 'disc';
    if (k == 'GST' || k == 'GSTPCT' || k == 'TAX') return 'gst';
    if (k.startsWith('MFG') || k.startsWith('MFR') || k == 'COMPANY' ||
        k == 'SNO' || k == 'SR' || k == 'FG' || k == 'PTS' || k == 'MAKE') {
      return 'mfg'; // read but not used: keeps its words out of other columns
    }
    return null;
  }

  // Second words of two-word headings ("PRODUCT NAME", "BATCH NO.")
  // ("M.R.P" and "MFG" are sometimes cut: "M" + "RP", "M" + "FG")
  static const _headerTails = {'NAME', 'NO', 'CODE', 'BY', 'NUMBER', 'E', 'M', 'NAM'};

  // A row with any of these is the totals area: the item table has ended
  static const _stopWords = [
    'GROSS', 'SUBTOTAL', 'TAXABLE', 'CGST', 'SGST', 'BILLAMOUNT', 'NETAMOUNT', 'TOTAL',
    'SOFTWARE', 'SCANPAY', 'BANKDETAILS', 'INWORDS',
  ];

  // "______" / "------" ruled lines printed across the table
  static bool _isRule(String t) => RegExp(r'^[_\-=.~*]+$').hasMatch(t.trim());

  static String _key(String s) => _plain(s).toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  // "Dísa" -> "Disa": ML Kit sometimes adds accents to plain print
  static String _plain(String s) {
    const from = 'áàâäãéèêëíìîïóòôöõúùûüÁÀÂÄÉÈÊËÍÌÎÏÓÒÔÖÚÙÛÜ';
    const to = 'aaaaaeeeeiiiiooooouuuuAAAAEEEEIIIIOOOOUUUU';
    final b = StringBuffer();
    for (final ch in s.split('')) {
      final i = from.indexOf(ch);
      b.write(i < 0 ? ch : to.substring(i, i + 1));
    }
    return b.toString();
  }

  static ScannedBill parse(List<OcrWord> words) {
    words = [for (final w in words) if (!_isRule(w.text)) w];
    final warnings = <String>[];
    if (words.isEmpty) {
      return ScannedBill(
          supplier: '', supplierGstin: '', billNumber: '', billDate: null,
          lines: const [], printedTotal: null,
          warnings: ['No text found. Take the photo flat, in good light.']);
    }
    final h = _median(words.map((w) => w.height).toList());

    // 1. The header row: the row with the most column names
    final headerWords = words.where((w) => _columnOf(w.text) != null).toList();
    var slope = 0.0;
    var header = <OcrWord>[];
    if (headerWords.isNotEmpty) {
      // The header row is where the MOST different column names sit
      // together. (Not just "QTY": "Total Qty" near the bottom also
      // reads as QTY.) Ties: the one with QTY.
      List<OcrWord> near(OcrWord a) =>
          headerWords.where((w) => (w.cy - a.cy).abs() < h * 2.5).toList();
      int score(OcrWord a) =>
          near(a).map((w) => _columnOf(w.text)).toSet().length * 2 +
          (_columnOf(a.text) == 'qty' ? 1 : 0);
      var anchor = headerWords.first;
      for (final w in headerWords) {
        if (score(w) > score(anchor)) anchor = w;
      }
      // 2. tilt left after turning the photo upright: the middle value
      // of the slopes between header words (one odd word can't skew it)
      final nearAnchor = near(anchor)..sort((a, b) => a.cx.compareTo(b.cx));
      final slopes = <double>[
        for (var i = 0; i < nearAnchor.length; i++)
          for (final b in nearAnchor.skip(i + 1))
            if (b.cx - nearAnchor[i].cx > h * 3)
              (b.cy - nearAnchor[i].cy) / (b.cx - nearAnchor[i].cx),
      ]..sort();
      if (slopes.isNotEmpty) slope = slopes[slopes.length ~/ 2];
      if (slope.abs() > 0.1) slope = 0; // more than ~6°: not a real tilt
      double y(OcrWord w) => w.cy - slope * w.cx; // straightened
      header = headerWords
          .where((w) => (y(w) - y(anchor)).abs() < h * 1.6)
          .toList();
    }

    double y(OcrWord w) => w.cy - slope * w.cx;

    // Column positions from the header (one per field, leftmost wins)
    final cols = <String, double>{};
    for (final w in header..sort((a, b) => a.cx.compareTo(b.cx))) {
      cols.putIfAbsent(_columnOf(w.text)!, () => w.cx);
    }
    // 3. Group words into rows (straightened)
    final rows = _rows(words, y, h);

    // The table starts below the header line (the row with QTY). Headings
    // printed a little lower ("PRODUCT NAME", "M.R.P") are taken out by
    // name, not by position. Cells ML Kit joined are split first.
    final qtyWord = header.isEmpty
        ? null
        : header.firstWhere((w) => _columnOf(w.text) == 'qty',
            orElse: () => header.first);
    final headerRow = qtyWord == null
        ? <OcrWord>[]
        : rows.firstWhere((r) => r.contains(qtyWord), orElse: () => [qtyWord]);
    final headerBottom = headerRow.isEmpty
        ? double.negativeInfinity
        : headerRow.map(y).reduce((a, b) => a > b ? a : b);
    final headerSet = {...header, ...headerRow};
    final dataRows = _joinSplitRows(
        _rows(
            [
              for (final w in words)
                if (y(w) > headerBottom + h * 0.2 &&
                    !headerSet.contains(w) &&
                    !_headerTails.contains(_key(w.text)))
                  ..._split(w),
            ],
            y,
            h * 0.85),
        y,
        h);

    // 4. Item rows: below the header, above the totals
    final lines = <BillLine>[];
    if (cols.length < 3 || !cols.containsKey('name')) {
      warnings.add('Could not find the item table. Enter the items by hand.');
    } else {
      final order = cols.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
      String colOf(OcrWord w) {
        var best = order.first.key;
        var dist = double.infinity;
        for (final c in order) {
          final d = (w.cx - c.value).abs();
          if (d < dist) {
            dist = d;
            best = c.key;
          }
        }
        return best;
      }

      double? lastY; // where the last item line sat
      // maker names seen in the MFG column (or stuck to the HSN), e.g. EVVAI
      final makers = <String>{};
      for (final row in dataRows) {
        final rowKey = _key(row.map((w) => w.text).join());
        if (_stopWords.any(rowKey.contains)) break;
        // the header again (top of page 2 of a PDF): skip it
        if (row.where((w) => _columnOf(w.text) != null).length >= 3) continue;

        final cells = <String, List<String>>{};
        for (final w in row) {
          cells.putIfAbsent(colOf(w), () => []).add(w.text);
        }
        String cell(String c) => (cells[c] ?? const []).join(' ').trim();
        for (final t in [...?cells['mfg'], ...?cells['hsn']]) {
          final word = t.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
          if (word.length >= 3 && word == t.toUpperCase()) makers.add(word);
        }
        final name = cell('name');
        final qty = _num(cell('qty'));
        final amount = _num(cell('amount'));

        if (name.isEmpty) continue;
        if (qty == 0 && amount == 0) {
          // a second line of a long product name, right under it and
          // short: add it to the line above. Anything else (bank details,
          // notes) is not an item.
          if (lines.isNotEmpty && row.length <= 4 && lastY != null &&
              y(row.first) - lastY < h * 1.5) {
            lines.last.name = '${lines.last.name} $name';
          }
          continue;
        }

        // Rate: the RATE column; else amount / qty (that amount is after
        // any discount, so the discount is then already in the rate);
        // else the PTR column
        var rate = _num(cell('rate'));
        var rateFromAmount = false;
        if (rate == 0 && qty > 0 && amount > 0) {
          rate = amount / qty;
          rateFromAmount = true;
        }
        if (rate == 0) rate = _num(cell('ptr'));
        final expiry = parseExpiry(cell('expiry'));
        // Disc and GST sit very close together: if both landed under GST,
        // the last number is the GST % and any before it is the discount
        final gstWords = cells['gst'] ?? const <String>[];
        // (the last word with a digit: a table line can read as "|")
        final gstNums = gstWords.where((t) => RegExp(r'\d').hasMatch(t)).toList();
        final gstText = gstNums.isEmpty ? '' : gstNums.last;
        final discText = cell('disc').isNotEmpty
            ? cell('disc')
            : gstNums.length > 1 ? gstNums.first : '';
        final line = BillLine(
          name: name,
          hsn: cell('hsn').replaceAll(RegExp(r'[^0-9]'), ''),
          pack: cell('pack'),
          batch: cell('batch').replaceAll(' ', ''),
          expiry: expiry ?? DateTime(DateTime.now().year + 1, 12, 31),
          quantity: qty.round(),
          free: _num(cell('free')).round(),
          rate: round2(rate),
          mrp: _num(cell('mrp')),
          discountPct: rateFromAmount ? 0 : _num(discText),
          gstPct: nearestGst(gstText.isEmpty ? 5 : _num(gstText)),
        );
        lines.add(line);
        lastY = y(row.first);
        if (expiry == null) warnings.add('$name: expiry not read');
        if (line.batch.isEmpty) warnings.add('$name: batch not read');
        if (line.quantity <= 0) warnings.add('$name: quantity not read');
        if (line.rate <= 0) warnings.add('$name: rate not read');
        if (gstText.isEmpty) warnings.add('$name: GST % not read, 5% assumed');
      }
      if (lines.isEmpty) warnings.add('No item lines read. Enter them by hand.');
      // ML Kit sometimes reads maker + batch as one word ("EVVAI126009A1"):
      // take the maker off the batch
      for (final l in lines) {
        for (final m in makers) {
          if (l.batch.toUpperCase().startsWith(m) && l.batch.length > m.length + 2) {
            l.batch = l.batch.substring(m.length);
          }
        }
      }
    }

    // Header details from the whole page
    final allLines = rows.map((r) => r.map((w) => w.text).join(' ')).toList();
    final text = allLines.join('\n');

    // GSTINs: the first (highest on the page) is the supplier's
    final gstRe = RegExp(r'\d{2}[A-Z]{5}\d{4}[A-Z][A-Z0-9]Z[A-Z0-9]');
    final gstin = gstRe.firstMatch(text.toUpperCase().replaceAll(' ', ''))?.group(0) ?? '';

    // "InvNo : VN25121" (the number may come after another label that
    // ML Kit put on the same line, e.g. "InvNo InvDate: : VN25121")
    final billNo = RegExp(
            r'(?:INV(?:OICE)?\.?\s*NO|BILL\s*NO)\.?[\s:\-]*(?:[A-Za-z]+\s*:[\s:]*)?'
            r'([A-Z0-9][A-Z0-9/\-]*\d[A-Z0-9/\-]*|\d[A-Z0-9/\-]*)',
            caseSensitive: false)
        .firstMatch(text)
        ?.group(1) ?? '';

    DateTime? billDate;
    final dateLine = allLines.firstWhere((l) => l.toUpperCase().contains('DATE'),
        orElse: () => text);
    billDate = parseDate(dateLine) ?? parseDate(text);

    // Supplier: the first line near the top, on the left, that is mostly
    // CAPITAL letters (bills print the seller's name that way). Skips
    // things caught in the photo, like a keyboard ("Ctrl Insert Delete").
    final minX = words.map((w) => w.left).reduce((a, b) => a < b ? a : b);
    final maxX = words.map((w) => w.right).reduce((a, b) => a > b ? a : b);
    var supplier = '';
    for (final r in rows) {
      final left = r.where((w) => w.cx < minX + (maxX - minX) * 0.55);
      final s = left.map((w) => w.text).join(' ').trim();
      final letters = s.replaceAll(RegExp(r'[^A-Za-z]'), '');
      final caps = s.replaceAll(RegExp(r'[^A-Z]'), '');
      if (letters.length >= 6 && caps.length >= letters.length * 0.8) {
        supplier = s;
        break;
      }
    }

    // Printed total: the money amount printed under (or beside) the
    // "NET AMOUNT" / "BILL AMOUNT" label: the nearest one in that column
    double? printed;
    final rowList = rows.toList();
    final money = RegExp(r'^\d[\d,]*\.\d{2}$');
    for (var i = 0; i < rowList.length && printed == null; i++) {
      final r = rowList[i];
      final k = _key(r.map((w) => w.text).join());
      if (!k.contains('NETAMOUNT') && !k.contains('BILLAMOUNT') &&
          !k.contains('NETPAYABLE') && !k.contains('GRANDTOTAL')) {
        continue;
      }
      // the label's last word ("AMOUNT"); the number sits right of it or below
      final label = r.lastWhere(
          (w) => RegExp(r'AMOUNT|PAYABLE|TOTAL').hasMatch(_key(w.text)),
          orElse: () => r.last);
      for (final rr in rowList.skip(i).take(10)) {
        final found = rr
            .where((w) => money.hasMatch(w.text) && _num(w.text) > 0)
            .where((w) => rr == r
                ? w.cx > label.cx && w.cx - label.cx < h * 30 // same line, to the right
                : (w.cx - label.cx).abs() < h * 10) // below, same column
            .toList();
        if (found.isNotEmpty) {
          printed = _num(found.first.text);
          break;
        }
      }
    }
    if (printed != null && lines.isNotEmpty) {
      final ours = lines.fold<double>(0, (t, l) => t + l.amount);
      if ((ours - printed).abs() > 1.5) {
        warnings.add('Lines add up to ${ours.toStringAsFixed(2)} but the bill says '
            '${printed.toStringAsFixed(2)}: check each line');
      }
    }

    final debug = StringBuffer()
      ..writeln('words=${words.length} h=${h.toStringAsFixed(1)} '
          'slope=${slope.toStringAsFixed(4)} headerBottom=${headerBottom.toStringAsFixed(0)}')
      ..writeln('columns: ${cols.entries.map((e) => '${e.key}@${e.value.round()}').join(' ')}');
    for (final r in rows) {
      debug.writeln('y=${y(r.first).round()}: '
          '${r.map((w) => '${w.text}@${w.cx.round()}').join(' ')}');
    }

    return ScannedBill(
      debugText: debug.toString(),
      supplier: supplier,
      supplierGstin: gstin,
      billNumber: billNo,
      billDate: billDate,
      lines: lines,
      printedTotal: printed,
      warnings: warnings,
    );
  }

  // A curved photo can cut one bill line into two rows: the left part a
  // little lower than the right part. Two rows next to each other whose
  // words sit in DIFFERENT columns are one line: join them.
  static List<List<OcrWord>> _joinSplitRows(
      List<List<OcrWord>> rows, double Function(OcrWord) y, double h) {
    // which header column each word is nearest is decided later; here it's
    // enough to compare positions: overlapping x = same column
    bool overlap(List<OcrWord> a, List<OcrWord> b) => a.any((p) => b.any((q) =>
        p.left < q.right && q.left < p.right));
    final out = <List<OcrWord>>[];
    for (final r in rows) {
      if (out.isNotEmpty &&
          (y(r.first) - y(out.last.first)).abs() < h * 1.5 &&
          !overlap(out.last, r)) {
        out.last
          ..addAll(r)
          ..sort((a, b) => a.cx.compareTo(b.cx));
      } else {
        out.add(r);
      }
    }
    return out;
  }

  // Words -> rows, top to bottom, each row left to right
  static List<List<OcrWord>> _rows(
      List<OcrWord> words, double Function(OcrWord) y, double h) {
    final sorted = [...words]..sort((a, b) => y(a).compareTo(y(b)));
    final rows = <List<OcrWord>>[];
    for (final w in sorted) {
      if (rows.isNotEmpty && (y(w) - y(rows.last.first)).abs() < h * 0.6) {
        rows.last.add(w);
      } else {
        rows.add([w]);
      }
    }
    for (final r in rows) {
      r.sort((a, b) => a.cx.compareTo(b.cx));
    }
    return rows;
  }

  static double _median(List<double> v) {
    v.sort();
    return v.isEmpty ? 10 : v.elementAt(v.length ~/ 2);
  }

  // "1,234.50" -> 1234.5 ; anything else -> 0
  static double _num(String s) {
    final m = RegExp(r'-?\d[\d,]*\.?\d*').firstMatch(s);
    return m == null ? 0 : double.tryParse(m.group(0)!.replaceAll(',', '')) ?? 0;
  }

  // "06/31" or "06/2031" -> 30 Jun 2031 (medicines expire at month end).
  // Also "067311": ML Kit read the "/" as "7" (and a table line as "1").
  static DateTime? parseExpiry(String text) {
    final m = RegExp(r'(\d{1,2})\s*[/\-.]\s*(\d{4}|\d{2})').firstMatch(text);
    if (m != null) return _monthEnd(int.parse(m.group(1)!), int.parse(m.group(2)!));
    final d = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length >= 4 && d.length <= 6) {
      final month = int.parse(d.substring(0, 2));
      // year right after the month, or one digit later (the misread "/")
      for (final start in [2, 3]) {
        if (start + 2 > d.length) continue;
        final yy = int.parse(d.substring(start, start + 2));
        final year = 2000 + yy;
        final now = DateTime.now().year;
        if (year >= now - 1 && year <= now + 10) return _monthEnd(month, yy);
      }
    }
    return null;
  }

  static DateTime? _monthEnd(int month, int year) {
    if (year < 100) year += 2000;
    if (month < 1 || month > 12) return null;
    return DateTime(year, month + 1, 0); // day 0 = last day of the month
  }

  // ML Kit sometimes joins two neighbouring cells into one word:
  //   "0.005"            -> "0.00" + "5"            (disc + GST)
  //   "H-ROMSo901683990" -> "H-ROMSo" + "901683990" (maker + HSN)
  // Each part gets its share of the word's width, so it lands in its column.
  static List<OcrWord> _split(OcrWord w) {
    final t = w.text;
    final money = RegExp(r'^(\d+\.\d{2})(\d{1,2})$').firstMatch(t);
    final lettersDigits = RegExp(r'^(.*[A-Za-z].*?)(\d{8,})$').firstMatch(t); // HSN = 8 digits
    final digitsLetters = RegExp(r'^(\d{8})([A-Za-z].*)$').firstMatch(t); // HSN + maker/batch
    final m = money ?? lettersDigits ?? digitsLetters;
    if (m == null) return [w];
    final a = m.group(1)!, b = m.group(2)!;
    final cut = w.left + (w.right - w.left) * a.length / t.length;
    return [
      OcrWord(a, w.left, w.top, cut, w.bottom),
      OcrWord(b, cut, w.top, w.right, w.bottom),
    ];
  }

  // "17-Nov-2026", "17/11/2026", "17-11-26" -> a date
  static DateTime? parseDate(String text) {
    const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
        'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    for (final named in RegExp(
            r'(\d{1,2})[\s\-/.]*([A-Za-z]{3})[A-Za-z]*[\s\-/.,]*(\d{4}|\d{2})')
        .allMatches(text)) {
      final mon = months.indexOf(named.group(2)!.toUpperCase());
      if (mon >= 0) {
        var year = int.parse(named.group(3)!);
        if (year < 100) year += 2000;
        return DateTime(year, mon + 1, int.parse(named.group(1)!));
      }
    }
    final num = RegExp(r'(\d{1,2})\s*[/\-.]\s*(\d{1,2})\s*[/\-.]\s*(\d{4}|\d{2})').firstMatch(text);
    if (num != null) {
      var year = int.parse(num.group(3)!);
      if (year < 100) year += 2000;
      final month = int.parse(num.group(2)!);
      if (month >= 1 && month <= 12) {
        return DateTime(year, month, int.parse(num.group(1)!));
      }
    }
    return null;
  }

  // Snap to a GST rate the app offers (0, 5, 12, 18)
  static double nearestGst(double v) {
    var best = gstRates.first;
    for (final r in gstRates) {
      if ((r - v).abs() < (best - v).abs()) best = r;
    }
    return best;
  }
}
