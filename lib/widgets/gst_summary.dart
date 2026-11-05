import 'package:flutter/material.dart';
import '../models/purchase_bill.dart' show GstSlab;
import '../utils/format.dart';

// The totals block at the bottom of a bill, like the paper one:
//
//   GST %   Taxable    CGST    SGST          (or IGST for another state)
//   5%      1,000.00   25.00   25.00
//   12%       500.00   30.00   30.00
//   -----------------------------------
//   Discount, Taxable, CGST, SGST, Round off, NET AMOUNT
class GstSummary extends StatelessWidget {
  final List<GstSlab> slabs;
  final double? discount;
  final double taxable;
  final double gst;
  final bool interState;
  final double roundOff;
  final double total;
  final String totalLabel;

  const GstSummary({
    super.key,
    required this.slabs,
    this.discount,
    required this.taxable,
    required this.gst,
    this.interState = false,
    required this.roundOff,
    required this.total,
    this.totalLabel = 'Net amount',
  });

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(fontSize: 12, fontWeight: FontWeight.bold);
    const cell = TextStyle(fontSize: 12);

    Widget numCell(String text, TextStyle style) =>
        Expanded(child: Text(text, textAlign: TextAlign.right, style: style));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. GST table, one row per rate
            Row(children: [
              const SizedBox(width: 48, child: Text('GST', style: head)),
              numCell('Taxable', head),
              if (interState) numCell('IGST', head) else ...[
                numCell('CGST', head),
                numCell('SGST', head),
              ],
            ]),
            const Divider(),
            for (final s in slabs)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  SizedBox(width: 48, child: Text(pct(s.rate), style: cell)),
                  numCell(rupees.format(s.taxable), cell),
                  if (interState)
                    numCell(rupees.format(s.tax), cell)
                  else ...[
                    numCell(rupees.format(s.tax / 2), cell),
                    numCell(rupees.format(s.tax / 2), cell),
                  ],
                ]),
              ),
            const Divider(height: 24),

            // 2. Totals
            if (discount != null && discount! > 0) row('Discount', -discount!),
            row('Taxable value', taxable),
            if (interState)
              row('IGST', gst)
            else ...[
              row('CGST', gst / 2),
              row('SGST', gst / 2),
            ],
            row('Round off', roundOff),
            const Divider(),
            Row(
              children: [
                Text(totalLabel,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(rupees.format(total),
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget row(String label, double value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Text(label),
          const Spacer(),
          Text(rupees.format(value)),
        ]),
      );
}
