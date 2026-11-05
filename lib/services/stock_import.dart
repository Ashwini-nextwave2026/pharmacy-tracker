import '../models/stock_item.dart';

// Turns rows copied from Excel (or a CSV file) into stock items.
//
// Column order (same as the template):
//   1 Medicine name   2 Batch   3 Expiry   4 Qty   5 MRP
//   6 GST %           7 HSN     8 Pack     9 Purchase rate   10 Supplier
// Columns 1-5 are required; 6-10 can be left empty.
//
// Expiry can be written as 08/27, 08/2027, 31/08/2027 or 2027-08-31.
// Month-only expiry (08/27) means the LAST day of that month.

class ImportRow {
  final int lineNumber; // row number as the user sees it
  final StockItem? item; // null when the row has a problem
  final String? error; // what's wrong with this row

  ImportRow(this.lineNumber, {this.item, this.error});

  bool get ok => item != null;
}

const importColumns = [
  'Medicine name', 'Batch', 'Expiry', 'Qty', 'MRP',
  'GST %', 'HSN', 'Pack', 'Purchase rate', 'Supplier',
];

// Excel copies cells separated by TABs; CSV files use commas
List<String> _splitCells(String line) {
  if (line.contains('\t')) return line.split('\t');
  // simple CSV: handles "quoted, values"
  final cells = <String>[];
  final buf = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      quoted = !quoted;
    } else if (ch == ',' && !quoted) {
      cells.add(buf.toString());
      buf.clear();
    } else {
      buf.write(ch);
    }
  }
  cells.add(buf.toString());
  return cells;
}

DateTime? parseExpiry(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;

  // 2027-08-31
  final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(t);
  if (iso != null) {
    return _validDate(int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));
  }

  final parts = t.split(RegExp(r'[/\-. ]+'));
  if (parts.length == 2) {
    // 08/27 or 08/2027 -> last day of that month
    final m = int.tryParse(parts[0]);
    var y = int.tryParse(parts[1]);
    if (m == null || y == null || m < 1 || m > 12) return null;
    if (y < 100) y += 2000;
    return DateTime(y, m + 1, 0);
  }
  if (parts.length == 3) {
    // 31/08/2027 or 31/08/27 (day first, as written in India)
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    var y = int.tryParse(parts[2]);
    if (d == null || m == null || y == null) return null;
    if (y < 100) y += 2000;
    return _validDate(y, m, d);
  }
  return null;
}

DateTime? _validDate(int y, int m, int d) {
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  final date = DateTime(y, m, d);
  return date.month == m ? date : null; // rejects 31/02
}

double? _money(String s) {
  final t = s.replaceAll(RegExp(r'[₹,\s]|Rs\.?', caseSensitive: false), '');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

List<ImportRow> parseStockRows(String text) {
  final rows = <ImportRow>[];
  final lines = text.split(RegExp(r'\r?\n'));

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) continue;
    final c = _splitCells(line).map((s) => s.trim()).toList();
    while (c.length < importColumns.length) {
      c.add('');
    }
    final n = i + 1;

    // Skip the heading row if it was copied too
    if (i == 0 && c[0].toLowerCase().contains('medicine')) continue;

    final name = c[0];
    final batch = c[1].toUpperCase();
    final expiry = parseExpiry(c[2]);
    final qty = int.tryParse(c[3].replaceAll(',', ''));
    final mrp = _money(c[4]);
    final gstText = c[5].replaceAll('%', '').trim();
    final gst = gstText.isEmpty ? 5.0 : double.tryParse(gstText);
    final rate = _money(c[8]);

    String? error;
    if (name.isEmpty) {
      error = 'Medicine name is empty';
    } else if (batch.isEmpty) {
      error = 'Batch is empty';
    } else if (expiry == null) {
      error = 'Expiry "${c[2]}" not understood (use 08/27)';
    } else if (qty == null || qty <= 0) {
      error = 'Qty "${c[3]}" must be a whole number above 0';
    } else if (mrp == null || mrp <= 0) {
      error = 'MRP "${c[4]}" must be a number';
    } else if (gst == null || gst < 0 || gst > 28) {
      error = 'GST "${c[5]}" must be 0, 5, 12 or 18';
    } else if (c[8].isNotEmpty && rate == null) {
      error = 'Purchase rate "${c[8]}" must be a number';
    }

    if (error != null) {
      rows.add(ImportRow(n, error: error));
      continue;
    }

    rows.add(ImportRow(
      n,
      item: StockItem(
        name: name,
        batch: batch,
        expiry: expiry!,
        quantity: qty!,
        mrp: mrp,
        gstPct: gst,
        hsn: c[6].isEmpty ? '3004' : c[6],
        pack: c[7].isEmpty ? null : c[7],
        rate: rate,
        costRate: rate,
        supplier: c[9].isEmpty ? null : c[9],
      ),
    ));
  }
  return rows;
}
