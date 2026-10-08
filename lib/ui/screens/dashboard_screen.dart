import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/dates.dart';
import '../../core/formatters.dart';
import '../../models/expense_category.dart';
import '../navigation.dart';
import '../widgets/donut_chart.dart';
import '../widgets/expense_tile.dart';
import '../widgets/weekly_bar_chart.dart';

enum Period { week, month, all }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.onSeeAll, this.now});

  final VoidCallback onSeeAll;

  /// Injectable clock for deterministic screenshots/tests.
  final DateTime? now;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Period _period = Period.month;
  ExpenseCategory? _selected;
  late DateTime _weekStart = startOfWeek(_now);

  DateTime get _now => widget.now ?? DateTime.now();

  (DateTime?, DateTime?) get _range => switch (_period) {
    Period.week => (startOfWeek(_now), addDays(startOfWeek(_now), 7)),
    Period.month => (startOfMonth(_now), startOfNextMonth(_now)),
    Period.all => (null, null),
  };

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store;
    final theme = Theme.of(context);

    if (store.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (store.expenses.isEmpty) {
      return const _EmptyDashboard();
    }

    final now = _now;
    final monthTotal = store.totalIn(startOfMonth(now), startOfNextMonth(now));
    final monthCount = store
        .inRange(startOfMonth(now), startOfNextMonth(now))
        .length;
    final (from, to) = _range;
    final byCategory = store.totalsByCategory(from, to);
    final periodTotal = byCategory.values.fold<double>(0, (a, b) => a + b);
    final daily = store.dailyTotals(_weekStart);
    final weekTotal = daily.fold<double>(0, (a, b) => a + b);
    final todayIndex = startOfDay(now).difference(_weekStart).inDays;
    final selected = (byCategory[_selected] ?? 0) > 0 ? _selected : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      children: [
        _SummaryCard(
          monthLabel: monthYear.format(now),
          monthTotal: monthTotal,
          receipts: monthCount,
          weekTotal: store.totalIn(
            startOfWeek(now),
            addDays(startOfWeek(now), 7),
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Spending by category',
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<Period>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: Period.week, label: Text('Week')),
                    ButtonSegment(value: Period.month, label: Text('Month')),
                    ButtonSegment(value: Period.all, label: Text('All time')),
                  ],
                  selected: {_period},
                  onSelectionChanged: (s) => setState(() {
                    _period = s.first;
                    _selected = null;
                  }),
                ),
              ),
              const SizedBox(height: 20),
              DonutChart(
                values: byCategory,
                selected: selected,
                onSelected: (c) => setState(() => _selected = c),
                center: _DonutCenter(
                  label: selected?.label ?? 'Total',
                  amount: selected == null
                      ? periodTotal
                      : byCategory[selected]!,
                  percent: selected == null || periodTotal == 0
                      ? null
                      : byCategory[selected]! / periodTotal,
                ),
              ),
              const SizedBox(height: 16),
              if (periodTotal == 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'No expenses in this period',
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              else
                for (final c in ExpenseCategory.values)
                  if (byCategory[c]! > 0)
                    _LegendRow(
                      category: c,
                      amount: byCategory[c]!,
                      share: byCategory[c]! / periodTotal,
                      selected: c == selected,
                      onTap: () =>
                          setState(() => _selected = c == selected ? null : c),
                    ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Weekly spending',
          subtitle:
              '${dayMonth.format(_weekStart)} – ${dayMonth.format(addDays(_weekStart, 6))}',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Previous week',
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: () =>
                    setState(() => _weekStart = addDays(_weekStart, -7)),
              ),
              IconButton(
                tooltip: 'Next week',
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: _weekStart.isBefore(startOfWeek(now))
                    ? () => setState(() => _weekStart = addDays(_weekStart, 7))
                    : null,
              ),
            ],
          ),
          child: Column(
            children: [
              WeeklyBarChart(
                values: daily,
                labels: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
                highlightIndex: todayIndex >= 0 && todayIndex < 7
                    ? todayIndex
                    : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _Stat(
                      label: 'Week total',
                      value: formatVnd(weekTotal),
                    ),
                  ),
                  Expanded(
                    child: _Stat(
                      label: 'Daily average',
                      value: formatVnd(weekTotal / 7),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text('Recent', style: theme.textTheme.titleMedium),
            const Spacer(),
            TextButton(
              onPressed: widget.onSeeAll,
              child: const Text('See all'),
            ),
          ],
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final e in store.expenses.take(5))
                ExpenseTile(expense: e, onTap: () => openEdit(context, e)),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.monthLabel,
    required this.monthTotal,
    required this.receipts,
    required this.weekTotal,
  });

  final String monthLabel;
  final double monthTotal;
  final int receipts;
  final double weekTotal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onPrimary = scheme.onPrimary;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            scheme.primary,
            Color.lerp(scheme.primary, scheme.tertiary, 0.6)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Spent in $monthLabel',
            style: TextStyle(color: onPrimary.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatVnd(monthTotal),
              style: TextStyle(
                color: onPrimary,
                fontSize: 34,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Pill(
                icon: Icons.receipt_long_rounded,
                text: '$receipts receipts',
                color: onPrimary,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: _Pill(
                  icon: Icons.date_range_rounded,
                  text: 'This week ${formatCompact(weekTotal)}',
                  color: onPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null)
                        Text(subtitle!, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _DonutCenter extends StatelessWidget {
  const _DonutCenter({required this.label, required this.amount, this.percent});

  final String label;
  final double amount;
  final double? percent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Column(
        key: ValueKey('$label$amount'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: theme.textTheme.labelLarge),
          const SizedBox(height: 2),
          Text(
            formatCompact(amount),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (percent != null)
            Text(
              '${(percent! * 100).toStringAsFixed(1)}%',
              style: theme.textTheme.labelMedium,
            ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.category,
    required this.amount,
    required this.share,
    required this.selected,
    required this.onTap,
  });

  final ExpenseCategory category;
  final double amount;
  final double share;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? category.color.withValues(alpha: 0.15) : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: category.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Icon(category.icon, size: 18, color: category.color),
            const SizedBox(width: 8),
            Expanded(child: Text(category.label)),
            Text(
              '${(share * 100).toStringAsFixed(0)}%',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(width: 12),
            Text(
              formatVnd(amount),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _EmptyDashboard extends StatelessWidget {
  const _EmptyDashboard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.document_scanner_outlined,
              size: 88,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('No expenses yet', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(
              'Scan a supermarket receipt and the total, merchant and date '
              'are filled in for you — fully offline.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => openCamera(context),
              icon: const Icon(Icons.camera_alt_rounded),
              label: const Text('Scan first receipt'),
            ),
            TextButton(
              onPressed: () => openManualEntry(context),
              child: const Text('or add one manually'),
            ),
          ],
        ),
      ),
    );
  }
}
