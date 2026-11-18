import 'package:flutter/material.dart';

// "This shop / All shops" switch for owner reports, shown only when the
// owner has more than one shop. All shops share one GSTIN, so GST is
// filed for all of them together.
class ShopScopeToggle extends StatelessWidget {
  final bool allShops;
  final ValueChanged<bool> onChanged;

  const ShopScopeToggle({super.key, required this.allShops, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, icon: Icon(Icons.storefront), label: Text('This shop')),
          ButtonSegment(value: true, icon: Icon(Icons.store_mall_directory), label: Text('All shops')),
        ],
        selected: {allShops},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}
