import 'expense.dart';
import 'purchase_bill.dart';
import 'sale_bill.dart';
import 'stock_adjustment.dart';

// One month's profit, worked out from that month's sales and expenses.
//
//   Sales (excluding GST)
// - Cost of the medicines sold (purchase cost, excluding GST)
// = Gross profit
// - Expenses (rent, salary, electricity...)
// - Stock written off (expired, damaged, lost), at cost
// = Net profit
//
// GST is left out on both sides: it's collected for the government,
// not the shop's income. Purchases of stock that is still on the shelf
// are not a cost yet; they become cost when sold.
class ProfitReport {
  final DateTime month;
  final List<SaleBill> sales;
  final List<Expense> expenses;
  final List<PurchaseBill> purchases; // shown for information only
  final List<StockAdjustment> adjustments; // returns and write-offs this month

  // Cost per unit for sale lines saved before costs were recorded,
  // looked up from the stock batch: stockId -> cost
  final Map<String, double> stockCosts;

  ProfitReport({
    required this.month,
    required this.sales,
    required this.expenses,
    this.purchases = const [],
    this.adjustments = const [],
    this.stockCosts = const {},
  });

  Iterable<SaleLine> get _lines => sales.expand((s) => s.lines);

  double? _costOf(SaleLine l) {
    final rate = l.costRate ?? stockCosts[l.stockId];
    return rate == null ? null : rate * l.quantity;
  }

  // Sales value excluding GST (after customer discounts)
  double get salesValue => _lines.fold(0, (t, l) => t + l.taxable);
  double get gstCollected => _lines.fold(0, (t, l) => t + l.gstAmount);
  double get salesWithGst => sales.fold(0, (t, s) => t + s.total);

  // Only lines whose cost is known count towards profit
  Iterable<SaleLine> get _costed => _lines.where((l) => _costOf(l) != null);
  int get linesWithoutCost => _lines.length - _costed.length;
  double get salesWithoutCost =>
      _lines.where((l) => _costOf(l) == null).fold(0, (t, l) => t + l.taxable);

  double get costOfSales => _costed.fold(0, (t, l) => t + _costOf(l)!);
  double get costedSalesValue => _costed.fold(0, (t, l) => t + l.taxable);
  double get grossProfit => costedSalesValue - costOfSales;
  double get grossMarginPct =>
      costedSalesValue == 0 ? 0 : grossProfit / costedSalesValue * 100;

  double get expensesTotal => expenses.fold(0, (t, e) => t + e.amount);
  // Expired / damaged stock thrown away is a loss (at what it cost).
  // Returns aren't: the supplier gives the money back as credit.
  Iterable<StockAdjustment> get _writeOffs => adjustments.where((a) => !a.isReturn);
  double get writeOffsTotal => _writeOffs.fold(0, (t, a) => t + a.value);
  int get writeOffCount => _writeOffs.length;
  double get returnsTotal =>
      adjustments.where((a) => a.isReturn).fold(0, (t, a) => t + a.value);

  double get netProfit => grossProfit - expensesTotal - writeOffsTotal;

  List<MapEntry<String, double>> get expensesByCat => expensesByCategory(expenses);

  double get purchasesValue => purchases.fold(0, (t, b) => t + b.taxableTotal);

  // Best-earning medicines this month: name -> gross profit, highest first
  List<MapEntry<String, double>> get topMedicines {
    final map = <String, double>{};
    for (final l in _costed) {
      map[l.name] = (map[l.name] ?? 0) + l.taxable - _costOf(l)!;
    }
    return map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }
}
