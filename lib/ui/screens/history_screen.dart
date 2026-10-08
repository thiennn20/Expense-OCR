import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/dates.dart';
import '../../core/formatters.dart';
import '../../models/expense.dart';
import '../../models/expense_category.dart';
import '../../services/text_utils.dart';
import '../navigation.dart';
import '../widgets/expense_tile.dart';

/// Full transaction list grouped by day, with search, category filter and
/// swipe-to-delete (with undo).
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _search = TextEditingController();
  ExpenseCategory? _filter;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Expense> _visible(List<Expense> all) {
    final query = fold(_search.text.trim());
    return all
        .where((e) => _filter == null || e.category == _filter)
        .where(
          (e) =>
              query.isEmpty ||
              fold(e.merchant).contains(query) ||
              fold(e.note).contains(query),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store;
    final theme = Theme.of(context);
    final items = _visible(store.expenses);

    // Flatten into [header, tile, tile, header, ...] for a lazy ListView.
    final rows = <Object>[];
    DateTime? currentDay;
    for (final e in items) {
      if (currentDay == null || !isSameDay(currentDay, e.date)) {
        currentDay = startOfDay(e.date);
        rows.add(currentDay);
      }
      rows.add(e);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search merchant or note',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () => setState(_search.clear),
                    ),
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              FilterChip(
                label: const Text('All'),
                selected: _filter == null,
                onSelected: (_) => setState(() => _filter = null),
              ),
              for (final c in ExpenseCategory.values)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: FilterChip(
                    avatar: Icon(c.icon, size: 16, color: c.color),
                    label: Text(c.label),
                    selected: _filter == c,
                    onSelected: (on) => setState(() => _filter = on ? c : null),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Text(
                '${items.length} transactions',
                style: theme.textTheme.bodySmall,
              ),
              const Spacer(),
              Text(
                formatVnd(items.fold<double>(0, (s, e) => s + e.amount)),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    store.expenses.isEmpty
                        ? 'No expenses yet'
                        : 'No matching expenses',
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    if (row is DateTime) {
                      final dayTotal = items
                          .where((e) => isSameDay(e.date, row))
                          .fold<double>(0, (s, e) => s + e.amount);
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Row(
                          children: [
                            Text(
                              weekdayDayMonth.format(row),
                              style: theme.textTheme.labelLarge,
                            ),
                            const Spacer(),
                            Text(
                              formatVnd(dayTotal),
                              style: theme.textTheme.labelLarge,
                            ),
                          ],
                        ),
                      );
                    }
                    final e = row as Expense;
                    return Dismissible(
                      key: ValueKey('expense-${e.id}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: theme.colorScheme.errorContainer,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                      onDismissed: (_) => deleteWithUndo(context, e),
                      child: ExpenseTile(
                        expense: e,
                        onTap: () => openEdit(context, e),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
