import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/session.dart';
import '../models/stock_item.dart';
import '../providers/theme_provider.dart';
import '../services/pharmacy_service.dart';
import 'add_bill_page.dart';
import 'add_stock_page.dart';
import 'bill_list_page.dart';
import 'expense_page.dart';
import 'gst_report_page.dart';
import 'import_stock_page.dart';
import 'new_sale_page.dart';
import 'sale_list_page.dart';
import 'shop_details_page.dart';
import 'staff_page.dart';
import 'supplier_dues_page.dart';
import 'stock_list_page.dart';

// The home screen, laid out like My Apps:
// a teal welcome card, then Sale, Purchase and Reports sections,
// then today's expiry summary.
class HomePage extends StatelessWidget {
  final Session session;

  const HomePage({super.key, required this.session});

  void open(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => page));
  }

  // For parts we haven't built yet
  void comingSoon(BuildContext context, String what) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$what is coming soon')),
    );
  }

  // A heading (e.g. "Sale") with its row of tiles underneath
  Widget _section(
      BuildContext context, String title, IconData icon, List<_Tile> tiles) {
    final wide = MediaQuery.of(context).size.width > 700;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.teal),
              const SizedBox(width: 8),
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: wide ? 4 : 3,
            shrinkWrap: true, // let the grid sit inside the ListView
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: wide ? 1.4 : 0.8,
            children: [for (final tile in tiles) _TileCard(tile: tile)],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    // Three sections, top to bottom: Sale, Purchase, Reports
    final sale = <_Tile>[
      _Tile('New Sale', 'GST bill for a customer', Icons.point_of_sale,
          Colors.teal, () => open(context, NewSalePage(session: session))),
      _Tile('Sales List', 'Today\'s sales', Icons.list_alt, Colors.green,
          () => open(context, SaleListPage(session: session))),
    ];
    final purchase = <_Tile>[
      _Tile('New Bill', 'Enter a purchase bill', Icons.post_add,
          Colors.purple, () => open(context, AddBillPage(session: session))),
      _Tile('Purchase Bills', 'Bills from suppliers', Icons.receipt_long,
          Colors.indigo, () => open(context, BillListPage(session: session))),
      _Tile('Add Stock', 'One batch by hand', Icons.add_box,
          Colors.orange, () => open(context, AddStockPage(session: session))),
      if (session.isOwner)
        _Tile('Import Stock', 'Many from Excel', Icons.upload_file,
            Colors.green, () => open(context, ImportStockPage(session: session))),
      if (session.isOwner)
        _Tile('Supplier Dues', 'Pay suppliers', Icons.payments,
            Colors.teal, () => open(context, SupplierDuesPage(session: session))),
      if (session.isOwner)
        _Tile('Expenditure', 'Rent, salary, bills', Icons.account_balance_wallet,
            Colors.deepOrange, () => open(context, ExpensePage(session: session))),
    ];
    final reports = <_Tile>[
      _Tile('Stock & Expiry', 'Every batch, soonest first', Icons.inventory_2,
          Colors.red, () => open(context, StockListPage(session: session))),
      _Tile('Stock Position', 'Coming soon', Icons.assessment,
          Colors.blueGrey, () => comingSoon(context, 'Stock position report')),
      if (session.isOwner)
        _Tile('GST Report', 'Monthly GSTR-1 & 3B', Icons.account_balance,
            Colors.brown, () => open(context, GstReportPage(session: session))),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pharmacy Tracker'),
        actions: [
          if (session.isOwner)
            IconButton(
              icon: const Icon(Icons.storefront),
              tooltip: 'Shop details for invoice',
              onPressed: () => open(context, ShopDetailsPage(session: session)),
            ),
          if (session.isOwner)
            IconButton(
              icon: const Icon(Icons.group),
              tooltip: 'Staff (invite code ${session.inviteCode})',
              onPressed: () => open(context, StaffPage(session: session)),
            ),
          IconButton(
            icon: Icon(themeProvider.isDark ? Icons.light_mode : Icons.dark_mode),
            tooltip: themeProvider.isDark ? 'Light mode' : 'Dark mode',
            onPressed: themeProvider.toggle,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _WelcomeCard(session: session),
          _section(context, 'Sale', Icons.shopping_cart, sale),
          _section(context, 'Purchase', Icons.local_shipping, purchase),
          _section(context, 'Reports', Icons.bar_chart, reports),
          const SizedBox(height: 20),
          _ExpirySummary(
            session: session,
            onTap: () => open(context, StockListPage(session: session)),
          ),
        ],
      ),
    );
  }
}

// Teal card at the top: pharmacy name, who is logged in, and their role
class _WelcomeCard extends StatelessWidget {
  final Session session;

  const _WelcomeCard({required this.session});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.teal.shade600, Colors.teal.shade300],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white,
            child: Text(
              session.userName.isEmpty ? '?' : session.userName[0].toUpperCase(),
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal.shade700),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hello, ${session.userName}',
                    style: const TextStyle(color: Colors.white, fontSize: 15)),
                const SizedBox(height: 2),
                Text(session.pharmacyName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Chip(
            label: Text(session.isOwner ? 'Owner' : 'Staff'),
            avatar: Icon(session.isOwner ? Icons.star : Icons.badge, size: 18),
            backgroundColor: Colors.white,
            labelStyle: TextStyle(color: Colors.teal.shade800),
            side: BorderSide.none,
          ),
        ],
      ),
    );
  }
}

// Live count of expired / expiring soon / safe batches
class _ExpirySummary extends StatelessWidget {
  final Session session;
  final VoidCallback onTap;

  const _ExpirySummary({required this.session, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: PharmacyService.stockRef(session.pharmacyId).snapshots(),
      builder: (context, snapshot) {
        final items = snapshot.hasData
            ? snapshot.data!.docs.map(StockItem.fromFirestore).toList()
            : <StockItem>[];
        int count(ExpiryStatus s) => items.where((i) => i.status() == s).length;

        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.event_busy, color: Colors.teal),
                      const SizedBox(width: 8),
                      Text('Expiry check',
                          style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (!snapshot.hasData)
                    const LinearProgressIndicator()
                  else
                    Row(
                      children: [
                        _count('Expired', count(ExpiryStatus.expired), Colors.red),
                        const SizedBox(width: 8),
                        _count('Within $soonDays days',
                            count(ExpiryStatus.soon), Colors.orange),
                        const SizedBox(width: 8),
                        _count('Safe', count(ExpiryStatus.safe), Colors.green),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _count(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text('$value',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// The data for one tile on the home grid
class _Tile {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  _Tile(this.title, this.subtitle, this.icon, this.color, this.onTap);
}

// How one tile looks: coloured round icon, title, small grey line
class _TileCard extends StatelessWidget {
  final _Tile tile;

  const _TileCard({required this.tile});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: tile.onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: tile.color.withValues(alpha: 0.15),
                child: Icon(tile.icon, color: tile.color),
              ),
              const Spacer(),
              Text(tile.title,
                  maxLines: 2,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              Text(tile.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}
