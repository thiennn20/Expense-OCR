import 'package:flutter/material.dart';

import '../navigation.dart';
import 'dashboard_screen.dart';
import 'history_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialTab = 0, this.now});

  final int initialTab;
  final DateTime? now;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0 ? 'Expense-OCR' : 'History'),
        actions: [
          IconButton(
            tooltip: 'Add manually',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => openManualEntry(context),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          DashboardScreen(
            now: widget.now,
            onSeeAll: () => setState(() => _tab = 1),
          ),
          const HistoryScreen(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openCamera(context),
        icon: const Icon(Icons.document_scanner_rounded),
        label: const Text('Scan receipt'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.pie_chart_outline_rounded),
            selectedIcon: Icon(Icons.pie_chart_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'History',
          ),
        ],
      ),
    );
  }
}
