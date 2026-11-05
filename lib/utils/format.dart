import 'package:intl/intl.dart';

// Indian money format: ₹1,23,456.00
final rupees = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

// "5%" for 5.0, "2.5%" for 2.5
String pct(double value) =>
    '${value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString()}%';

// ---- Amount in words, Indian style (lakh, crore) ----
// 231    -> "Rupees Two Hundred Thirty One Only"
// 125000 -> "Rupees One Lakh Twenty Five Thousand Only"
const _ones = [
  '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine',
  'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen',
  'Seventeen', 'Eighteen', 'Nineteen',
];
const _tens = [
  '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety',
];

String _upTo99(int n) {
  if (n < 20) return _ones[n];
  final rest = _ones[n % 10];
  return rest.isEmpty ? _tens[n ~/ 10] : '${_tens[n ~/ 10]} $rest';
}

String _upTo999(int n) {
  final hundreds = n ~/ 100;
  final rest = n % 100;
  final parts = <String>[
    if (hundreds > 0) '${_ones[hundreds]} Hundred',
    if (rest > 0) _upTo99(rest),
  ];
  return parts.join(' ');
}

String _numberWords(int n) {
  if (n == 0) return 'Zero';
  final parts = <String>[];
  final crore = n ~/ 10000000;
  n %= 10000000;
  final lakh = n ~/ 100000;
  n %= 100000;
  final thousand = n ~/ 1000;
  n %= 1000;
  if (crore > 0) parts.add('${_numberWords(crore)} Crore');
  if (lakh > 0) parts.add('${_upTo99(lakh)} Lakh');
  if (thousand > 0) parts.add('${_upTo99(thousand)} Thousand');
  if (n > 0) parts.add(_upTo999(n));
  return parts.join(' ');
}

String rupeesInWords(double amount) {
  final paiseTotal = (amount * 100).round();
  final rupeesPart = paiseTotal ~/ 100;
  final paise = paiseTotal % 100;
  final words = 'Rupees ${_numberWords(rupeesPart)}';
  return paise > 0 ? '$words and ${_upTo99(paise)} Paise Only' : '$words Only';
}
