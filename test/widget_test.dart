// Tests for the expiry logic. Run them with:  flutter test
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_tracker/models/expense.dart';
import 'package:pharmacy_tracker/models/gst_report.dart';
import 'package:pharmacy_tracker/models/profit_report.dart';
import 'package:pharmacy_tracker/models/purchase_bill.dart';
import 'package:pharmacy_tracker/models/sale_bill.dart';
import 'package:pharmacy_tracker/models/stock_adjustment.dart';
import 'package:pharmacy_tracker/models/stock_item.dart';
import 'package:pharmacy_tracker/models/supplier.dart';
import 'package:pharmacy_tracker/models/supplier_payment.dart';
import 'package:pharmacy_tracker/services/backup_service.dart';
import 'package:pharmacy_tracker/services/stock_import.dart';
import 'package:pharmacy_tracker/utils/format.dart';

void main() {
  final today = DateTime(2026, 10, 29);

  StockItem itemExpiring(DateTime date) =>
      StockItem(name: 'Test', batch: 'B1', quantity: 1, expiry: date);

  test('a batch past its expiry date is expired', () {
    final item = itemExpiring(DateTime(2026, 10, 28));
    expect(item.daysLeft(today), -1);
    expect(item.status(today), ExpiryStatus.expired);
  });

  test('a batch expiring today counts as soon, not expired', () {
    final item = itemExpiring(DateTime(2026, 10, 29));
    expect(item.daysLeft(today), 0);
    expect(item.status(today), ExpiryStatus.soon);
  });

  test('a batch expiring in exactly 30 days is soon', () {
    final item = itemExpiring(DateTime(2026, 11, 28));
    expect(item.daysLeft(today), 30);
    expect(item.status(today), ExpiryStatus.soon);
  });

  test('a batch expiring in 31 days is safe', () {
    final item = itemExpiring(DateTime(2026, 11, 29));
    expect(item.status(today), ExpiryStatus.safe);
  });

  test('bill total adds up quantity × rate for every line', () {
    final bill = PurchaseBill(
      supplier: 'Test Distributors',
      billNumber: 'INV-1',
      billDate: today,
      lines: [
        BillLine(name: 'A', batch: 'B1', expiry: today, quantity: 10, rate: 12.5, mrp: 20),
        BillLine(name: 'B', batch: 'B2', expiry: today, quantity: 4, rate: 30, mrp: 45),
      ],
    );
    expect(bill.total, 245.0); // 10 × 12.50 + 4 × 30
    expect(bill.totalUnits, 14);
  });

  test('purchase line: discount, then GST on the taxable value', () {
    final line = BillLine(
        name: 'Dolo 650', batch: 'B1', expiry: today,
        quantity: 10, free: 2, rate: 20, discountPct: 10, gstPct: 5, mrp: 33);
    expect(line.gross, 200); // 10 × 20
    expect(line.discount, 20); // 10% of 200
    expect(line.taxable, 180);
    expect(line.gstAmount, 9); // 5% of 180
    expect(line.amount, 189);
    expect(line.unitsIn, 12); // 10 bought + 2 free go into stock
  });

  test('purchase bill: CGST/SGST split, slabs and round off', () {
    final bill = PurchaseBill(
      supplier: 'Test', billNumber: 'INV-2', billDate: today,
      lines: [
        BillLine(name: 'A', batch: 'B1', expiry: today, quantity: 10, rate: 20, discountPct: 10, gstPct: 5, mrp: 33),
        BillLine(name: 'B', batch: 'B2', expiry: today, quantity: 3, rate: 33.33, gstPct: 12, mrp: 50),
      ],
    );
    // B: 99.99 taxable + 12.00 GST (11.9988) = 111.9888
    expect(round2(bill.taxableTotal), 279.99);
    expect(round2(bill.cgst), round2(bill.sgst));
    expect(bill.igst, 0);
    expect(bill.slabs.map((s) => s.rate).toList(), [5, 12]);
    expect(bill.total, 301); // 189 + 111.9888 = 300.9888 -> 301
    expect(bill.roundOff, 0.01);
  });

  test('inter-state purchase bill uses IGST only', () {
    final bill = PurchaseBill(
      supplier: 'Test', billNumber: 'INV-3', billDate: today, interState: true,
      lines: [BillLine(name: 'A', batch: 'B1', expiry: today, quantity: 1, rate: 100, gstPct: 12, mrp: 150)],
    );
    expect(bill.igst, 12);
    expect(bill.cgst, 0);
  });

  test('sale: MRP includes GST, so GST is taken out of the price', () {
    final sale = SaleBill(
      date: today, customerName: 'Test',
      lines: [
        SaleLine(stockId: 's1', name: 'A', batch: 'B1', expiry: today,
            quantity: 2, mrp: 105, gstPct: 5), // 210 = 200 + 10 GST
      ],
    );
    expect(sale.total, 210);
    expect(round2(sale.taxableTotal), 200);
    expect(round2(sale.gstTotal), 10);
    expect(round2(sale.cgst), 5);
  });

  test('sale discount comes off the MRP before GST is worked out', () {
    final line = SaleLine(stockId: 's1', name: 'A', batch: 'B1', expiry: today,
        quantity: 1, mrp: 112, discountPct: 10, gstPct: 12);
    expect(round2(line.amount), 100.8); // 112 − 10%
    expect(round2(line.taxable), 90); // 100.8 / 1.12
    expect(round2(line.gstAmount), 10.8);
  });

  test('GST report: sales tax minus purchase credit = cash to pay', () {
    final report = GstReport(
      month: today,
      sales: [
        SaleBill(date: today, customerName: 'A', billNumber: 'S-0002', lines: [
          SaleLine(stockId: 's1', name: 'A', hsn: '3004', batch: 'B1', expiry: today,
              quantity: 10, mrp: 105, gstPct: 5), // 1000 taxable + 50 GST
        ]),
        SaleBill(date: today, customerName: 'B', billNumber: 'S-0001', lines: [
          SaleLine(stockId: 's1', name: 'A', hsn: '3004', batch: 'B1', expiry: today,
              quantity: 2, mrp: 105, gstPct: 5), // 200 taxable + 10 GST
        ]),
      ],
      purchases: [
        PurchaseBill(supplier: 'X', billNumber: 'P1', billDate: today, lines: [
          BillLine(name: 'A', batch: 'B1', expiry: today, quantity: 10,
              rate: 80, gstPct: 5, mrp: 105), // 800 taxable + 40 GST
        ]),
      ],
    );
    expect(round2(report.outputCgst), 30); // 60 GST on sales, half each
    expect(round2(report.itcCgst), 20); // 40 GST on purchases, half each
    expect(report.setOff.cgstCash, 10);
    expect(report.setOff.sgstCash, 10);
    expect(report.cashToPay, 20);
    expect(report.firstBill, 'S-0001');
    expect(report.lastBill, 'S-0002');
    expect(report.salesByHsn.single.quantity, 12);
  });

  test('GST report: IGST credit is used first, extra credit carries forward', () {
    final report = GstReport(
      month: today,
      sales: [
        SaleBill(date: today, customerName: 'A', lines: [
          SaleLine(stockId: 's1', name: 'A', batch: 'B1', expiry: today,
              quantity: 1, mrp: 112, gstPct: 12), // 12 GST: CGST 6, SGST 6
        ]),
      ],
      purchases: [
        PurchaseBill(supplier: 'X', billNumber: 'P1', billDate: today,
            interState: true, lines: [
          BillLine(name: 'A', batch: 'B1', expiry: today, quantity: 1,
              rate: 100, gstPct: 12, mrp: 112), // IGST 12
        ]),
        PurchaseBill(supplier: 'Y', billNumber: 'P2', billDate: today, lines: [
          BillLine(name: 'B', batch: 'B2', expiry: today, quantity: 1,
              rate: 100, gstPct: 5, mrp: 105), // CGST 2.5, SGST 2.5
        ]),
      ],
    );
    final so = report.setOff;
    expect(so.cgstCash, 0); // IGST 12 covers CGST 6 and SGST 6
    expect(so.sgstCash, 0);
    expect(so.igstCarry, 0);
    expect(so.cgstCarry, 2.5); // own credit not needed, carried forward
    expect(so.sgstCarry, 2.5);
  });

  test('amount in words, Indian style', () {
    expect(rupeesInWords(231), 'Rupees Two Hundred Thirty One Only');
    expect(rupeesInWords(125000), 'Rupees One Lakh Twenty Five Thousand Only');
    expect(rupeesInWords(1121), 'Rupees One Thousand One Hundred Twenty One Only');
    expect(rupeesInWords(10.50), 'Rupees Ten and Fifty Paise Only');
  });

  PurchaseBill billOf(String id, DateTime date, double rate, {double paid = 0}) =>
      PurchaseBill(
        id: id, supplier: 'Sri Ram Pharma', billNumber: id, billDate: date,
        creditDays: 30, paid: paid,
        lines: [BillLine(name: 'A', batch: 'B', expiry: date, quantity: 1, rate: rate, mrp: rate)],
      );

  test('supplier payment clears the oldest bills first', () {
    final bills = [
      billOf('P3', DateTime(2026, 10, 20), 500),
      billOf('P1', DateTime(2026, 9, 1), 1000, paid: 400), // 600 left
      billOf('P2', DateTime(2026, 9, 15), 800),
    ];
    final r = allocatePayment(1000, bills);
    expect(r.allocations.map((a) => a.billId).toList(), ['P1', 'P2']);
    expect(r.allocations[0].amount, 600); // P1 fully cleared
    expect(r.allocations[1].amount, 400); // P2 part paid
    expect(r.advance, 0);
  });

  test('paying more than owed leaves an advance', () {
    final r = allocatePayment(1500, [billOf('P1', today, 1000)]);
    expect(r.allocations.single.amount, 1000);
    expect(r.advance, 500);
  });

  test('bill status and overdue days', () {
    final bill = billOf('P1', DateTime(2026, 9, 1), 1000, paid: 250);
    expect(bill.balance, 750);
    expect(bill.isPartPaid, true);
    expect(bill.dueDate, DateTime(2026, 10, 1));
    expect(bill.overdueDays(DateTime(2026, 10, 29)), 28);
    final paid = billOf('P2', DateTime(2026, 9, 1), 1000, paid: 1000);
    expect(paid.isPaid, true);
    expect(paid.overdueDays(DateTime(2026, 10, 29)), 0);
  });

  test('supplier dues are grouped and totalled', () {
    final dues = groupBySupplier([
      billOf('P1', DateTime(2026, 10, 1), 1000, paid: 1000),
      billOf('P2', DateTime(2026, 10, 5), 700),
    ]);
    expect(dues.single.outstanding, 700);
    expect(dues.single.unpaidCount, 1);
  });

  test('expenses are totalled by category, biggest first', () {
    final list = [
      Expense(date: today, category: 'Electricity', amount: 2450),
      Expense(date: today, category: 'Rent', amount: 15000),
      Expense(date: today, category: 'Tea & snacks', amount: 120),
      Expense(date: today, category: 'Tea & snacks', amount: 80),
    ];
    final byCat = expensesByCategory(list);
    expect(byCat.first.key, 'Rent');
    expect(byCat.last.value, 200);
  });

  test('expiry formats from Excel', () {
    expect(parseExpiry('08/27'), DateTime(2027, 8, 31)); // last day of month
    expect(parseExpiry('02/2028'), DateTime(2028, 2, 29)); // leap year
    expect(parseExpiry('15/03/2027'), DateTime(2027, 3, 15));
    expect(parseExpiry('2027-12-01'), DateTime(2027, 12, 1));
    expect(parseExpiry('31/02/2027'), null);
    expect(parseExpiry('soon'), null);
  });

  test('rows pasted from Excel become stock, bad rows are reported', () {
    const pasted = 'Medicine name\tBatch\tExpiry\tQty\tMRP\tGST %\n'
        'Dolo 650\tb2041\t08/27\t50\t33.00\t5\n'
        'Azithral 500\tAZ1\t03/27\t10\t₹118.50\t12\t3004\t5\'s\t80\tSri Ram Pharma\n'
        'Cough syrup\tC9\tlater\t5\t95\n'
        '\n';
    final rows = parseStockRows(pasted);
    expect(rows.length, 3); // heading and blank line skipped
    expect(rows[0].item!.batch, 'B2041');
    expect(rows[0].item!.gstPct, 5);
    expect(rows[1].item!.mrp, 118.5);
    expect(rows[1].item!.supplier, 'Sri Ram Pharma');
    expect(rows[2].ok, false);
    expect(rows[2].error, contains('Expiry'));
  });

  test('CSV with commas works too', () {
    final rows = parseStockRows('Pan 40,P77,11/26,30,"1,200.00",12');
    expect(rows.single.item!.mrp, 1200);
  });

  test('monthly profit: sales minus cost of what was sold minus expenses', () {
    final report = ProfitReport(
      month: today,
      sales: [
        SaleBill(date: today, customerName: 'A', lines: [
          // 10 × 105 incl. 5% GST = 1000 sales value; cost 70 each = 700
          SaleLine(stockId: 's1', name: 'Dolo 650', batch: 'B1', expiry: today,
              quantity: 10, mrp: 105, gstPct: 5, costRate: 70),
          // old line without cost: looked up from stock (60 × 2 = 120)
          SaleLine(stockId: 's2', name: 'Pan 40', batch: 'P1', expiry: today,
              quantity: 2, mrp: 112, gstPct: 12),
          // no cost anywhere: left out of profit
          SaleLine(stockId: 's3', name: 'Syrup', batch: 'S1', expiry: today,
              quantity: 1, mrp: 105, gstPct: 5),
        ]),
      ],
      expenses: [Expense(date: today, category: 'Rent', amount: 150)],
      stockCosts: {'s2': 60},
    );
    expect(round2(report.salesValue), 1300); // 1000 + 200 + 100
    expect(report.costOfSales, 820); // 700 + 120
    expect(round2(report.grossProfit), 380); // (1000 + 200) - 820
    expect(round2(report.netProfit), 230); // 380 - 150 rent
    expect(report.linesWithoutCost, 1);
    expect(report.topMedicines.first.key, 'Dolo 650'); // 300 vs 80
  });

  test('purchase bill line cost spreads over free units after discount', () {
    final line = BillLine(name: 'A', batch: 'B', expiry: today,
        quantity: 10, free: 2, rate: 20, discountPct: 10, mrp: 33);
    expect(round2(line.taxable / line.unitsIn), 15); // 180 / 12
  });

  test('supplier names match however they are typed', () {
    expect(nameKey('Sri Ram Pharma'), nameKey(' SRI  RAM PHARMA. '));
    final all = [
      Supplier(name: 'Medplus Distributors'),
      Supplier(name: 'Sri Ram Pharma', gstin: '29ABCDE1234F1Z5'),
      Supplier(name: 'Ram Medical Agencies'),
    ];
    final found = searchSuppliers(all, 'ram');
    expect(found.first.name, 'Ram Medical Agencies'); // starts with "ram" first
    expect(found.length, 2);
    expect(all[1].interState, true); // 29 = Karnataka, so IGST
    expect(all[0].interState, false); // no GSTIN
  });

  test('backup turns Firestore dates into plain JSON', () {
    final value = toJsonValue({
      'name': 'Dolo 650',
      'expiry': Timestamp.fromDate(DateTime(2027, 8, 31)),
      'lines': [
        {'qty': 2, 'when': Timestamp.fromDate(DateTime(2026, 11, 5, 10, 30))},
      ],
    }) as Map;
    expect(value['name'], 'Dolo 650');
    expect(value['expiry'], {'__timestamp': '2027-08-31T00:00:00.000'});
    expect((value['lines'] as List).first['when'],
        {'__timestamp': '2026-11-05T10:30:00.000'});
  });

  test('backup file name has the shop and date', () {
    expect(backupFileName('Cals Medical', DateTime(2026, 11, 5, 15, 7)),
        'PharmacyBackup-Cals-Medical-2026-11-05-1507.json');
  });

  test('write-offs are a loss in profit, returns are not', () {
    final report = ProfitReport(
      month: today,
      sales: [
        SaleBill(date: today, customerName: 'A', lines: [
          SaleLine(stockId: 's1', name: 'Dolo 650', batch: 'B1', expiry: today,
              quantity: 10, mrp: 105, gstPct: 5, costRate: 70), // profit 300
        ]),
      ],
      expenses: [],
      adjustments: [
        StockAdjustment(type: adjustmentWriteOff, stockId: 's2', name: 'Syrup',
            batch: 'S1', expiry: today, quantity: 2, costRate: 40, date: today), // -80
        StockAdjustment(type: adjustmentReturn, stockId: 's3', name: 'Pan',
            batch: 'P1', expiry: today, quantity: 5, costRate: 20, date: today),
      ],
    );
    expect(report.writeOffsTotal, 80);
    expect(report.returnsTotal, 100);
    expect(round2(report.netProfit), 220); // 300 - 80, the return isn't a loss
  });

  test('restore turns backup dates back into Firestore dates', () {
    final original = {
      'name': 'Dolo 650',
      'expiry': Timestamp.fromDate(DateTime(2027, 8, 31)),
      'lines': [{'qty': 2}],
    };
    final back = fromJsonValue(jsonDecode(jsonEncode(toJsonValue(original)))) as Map;
    expect(back['expiry'], Timestamp.fromDate(DateTime(2027, 8, 31)));
    expect(back['name'], 'Dolo 650');
    expect((back['lines'] as List).first['qty'], 2);
  });

  test('restore refuses files that are not backups', () {
    Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));
    expect(() => parseBackup(bytesOf('hello')), throwsFormatException);
    expect(() => parseBackup(bytesOf('{"app":"Other"}')), throwsFormatException);
    final ok = parseBackup(bytesOf(
        '{"app":"Pharmacy Tracker","backupVersion":1,"pharmacyId":"p1",'
        '"pharmacyName":"Cals Medical","createdAt":"2026-11-05T15:10:00",'
        '"collections":{"stock":{"a":{},"b":{}}}}'));
    expect(ok.count('stock'), 2);
    expect(ok.pharmacyName, 'Cals Medical');
  });

  test('restore plan: only missing records are added by default', () {
    final plan = planCollection('stock', {'a': {}, 'b': {}, 'c': {}}, {'b', 'x'});
    expect(plan.missing, ['a', 'c']);
    expect(plan.existing, ['b']);
  });
}
