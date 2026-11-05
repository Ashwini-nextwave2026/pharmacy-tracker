import 'package:cloud_firestore/cloud_firestore.dart';

// Kinds of shop expenses (shown as buttons when adding one)
const expenseCategories = [
  'Rent',
  'Electricity',
  'Salary',
  'Tea & snacks',
  'Transport',
  'Phone & internet',
  'Repairs',
  'Stationery',
  'Licence & fees',
  'Other',
];

// Ways an expense was paid
const expensePayModes = ['Cash', 'UPI', 'Bank transfer', 'Card'];

// One shop expense, e.g. "Electricity, ₹2,450, paid by UPI on 3 Nov"
class Expense {
  String? id;
  DateTime date;
  String category;
  double amount;
  String mode;
  String note;
  String addedBy;

  Expense({
    this.id,
    required this.date,
    required this.category,
    required this.amount,
    this.mode = 'Cash',
    this.note = '',
    this.addedBy = '',
  });

  Map<String, dynamic> toMap() => {
        'date': Timestamp.fromDate(date),
        'category': category,
        'amount': amount,
        'mode': mode,
        'note': note,
        'addedBy': addedBy,
      };

  factory Expense.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Expense(
      id: doc.id,
      date: (d['date'] as Timestamp).toDate(),
      category: d['category'] ?? 'Other',
      amount: (d['amount'] as num?)?.toDouble() ?? 0,
      mode: d['mode'] ?? 'Cash',
      note: d['note'] ?? '',
      addedBy: d['addedBy'] ?? '',
    );
  }
}

// Total per category, biggest first
List<MapEntry<String, double>> expensesByCategory(List<Expense> list) {
  final map = <String, double>{};
  for (final e in list) {
    map[e.category] = (map[e.category] ?? 0) + e.amount;
  }
  return map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}
