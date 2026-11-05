import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// A date period: Today, Yesterday, This month, or dates you pick.
// [start] is included, [end] is not (so "Today" = today 00:00 to tomorrow 00:00).
class DatePeriod {
  final String kind; // 'today', 'yesterday', 'month' or 'custom'
  final DateTime start;
  final DateTime end;
  final String label; // e.g. "Today, 3 Nov 2026" or "1 Nov – 15 Nov 2026"

  const DatePeriod._(this.kind, this.start, this.end, this.label);

  static DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static final _f = DateFormat('d MMM yyyy');

  factory DatePeriod.today() {
    final t = _today;
    return DatePeriod._('today', t, t.add(const Duration(days: 1)),
        'Today, ${_f.format(t)}');
  }

  factory DatePeriod.yesterday() {
    final t = _today;
    final y = t.subtract(const Duration(days: 1));
    return DatePeriod._('yesterday', y, t, 'Yesterday, ${_f.format(y)}');
  }

  factory DatePeriod.thisMonth() {
    final t = _today;
    return DatePeriod._('month', DateTime(t.year, t.month, 1),
        t.add(const Duration(days: 1)), DateFormat('MMMM yyyy').format(t));
  }

  factory DatePeriod.custom(DateTimeRange r) {
    final start = DateTime(r.start.year, r.start.month, r.start.day);
    final end = DateTime(r.end.year, r.end.month, r.end.day + 1);
    final label = DateUtils.isSameDay(r.start, r.end)
        ? _f.format(r.start)
        : '${DateFormat('d MMM').format(r.start)} – ${_f.format(r.end)}';
    return DatePeriod._('custom', start, end, label);
  }

  // The picked range again, to reopen the calendar on it
  DateTimeRange get asRange =>
      DateTimeRange(start: start, end: end.subtract(const Duration(days: 1)));
}

// The row of buttons: [Today] [Yesterday] [This month] [📅 Pick dates]
class PeriodChips extends StatelessWidget {
  final DatePeriod value;
  final ValueChanged<DatePeriod> onChanged;
  final String pickHelpText;

  const PeriodChips({
    super.key,
    required this.value,
    required this.onChanged,
    this.pickHelpText = 'Choose dates',
  });

  Future<void> _pick(BuildContext context) async {
    final today = DatePeriod.today().start;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: today,
      initialDateRange: value.kind == 'custom'
          ? value.asRange
          : DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today),
      helpText: pickHelpText,
      saveText: 'Show',
    );
    if (picked != null) onChanged(DatePeriod.custom(picked));
  }

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, String kind, DatePeriod Function() make) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(label),
            selected: value.kind == kind,
            onSelected: (_) => onChanged(make()),
          ),
        );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          chip('Today', 'today', DatePeriod.today),
          chip('Yesterday', 'yesterday', DatePeriod.yesterday),
          chip('This month', 'month', DatePeriod.thisMonth),
          ActionChip(
            avatar: const Icon(Icons.date_range, size: 18),
            label: Text(value.kind == 'custom' ? value.label : 'Pick dates'),
            backgroundColor:
                value.kind == 'custom' ? Colors.teal.withValues(alpha: 0.2) : null,
            onPressed: () => _pick(context),
          ),
        ],
      ),
    );
  }
}
