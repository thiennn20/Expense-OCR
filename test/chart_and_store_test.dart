import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_ocr/core/formatters.dart';
import 'package:expense_ocr/data/expense_repository.dart';
import 'package:expense_ocr/models/expense.dart';
import 'package:expense_ocr/models/expense_category.dart';
import 'package:expense_ocr/state/expense_store.dart';
import 'package:expense_ocr/ui/widgets/chart_math.dart';
import 'package:expense_ocr/ui/widgets/donut_chart.dart';
import 'package:expense_ocr/ui/widgets/weekly_bar_chart.dart';

Expense _e(double amount, ExpenseCategory c, DateTime date) => Expense(
    merchant: 'M', amount: amount, category: c, date: date, createdAt: date);

void main() {
  group('donut geometry', () {
    test('slices are proportional and cover the circle', () {
      final slices = computeSlices({'a': 1.0, 'b': 3.0, 'zero': 0.0}.entries,
          gap: 0);
      expect(slices.map((s) => s.key), ['a', 'b']);
      expect(slices[0].sweep, closeTo(math.pi / 2, 1e-9));
      expect(slices[1].sweep, closeTo(3 * math.pi / 2, 1e-9));
      expect(slices.first.start, closeTo(-math.pi / 2, 1e-9));
    });

    test('hit-testing by angle', () {
      final slices = computeSlices({'a': 1.0, 'b': 1.0}.entries, gap: 0);
      // Right side of the ring (3 o'clock) is in the first half → 'a'.
      expect(sliceAtAngle(slices, 0)?.key, 'a');
      // Left side (9 o'clock) → 'b'.
      expect(sliceAtAngle(slices, math.pi)?.key, 'b');
      expect(sliceAtAngle(<DonutSlice<String>>[], 0), isNull);
    });
  });

  test('niceStep produces readable axis steps', () {
    expect(niceStep(380000, 4), 100000);
    expect(niceStep(90000, 4), 25000);
    expect(niceStep(0, 4), 1);
  });

  test('formatters', () {
    expect(formatVnd(150000), '150.000 ₫');
    expect(formatCompact(1250000), '1.3M');
    expect(formatCompact(45000), '45K');
    expect(parseTypedAmount('1.250.000'), 1250000);
  });

  group('ExpenseStore aggregates', () {
    late ExpenseStore store;
    final monday = DateTime(2026, 10, 5);

    setUp(() async {
      store = ExpenseStore(InMemoryExpenseRepository([
        _e(100000, ExpenseCategory.food, monday),
        _e(50000, ExpenseCategory.food, monday.add(const Duration(hours: 5))),
        _e(200000, ExpenseCategory.gear, DateTime(2026, 10, 11, 23)),
        _e(70000, ExpenseCategory.travel, DateTime(2026, 9, 30)),
      ]));
      await store.load();
    });

    test('daily totals for a Monday-based week', () {
      expect(store.dailyTotals(monday),
          [150000, 0, 0, 0, 0, 0, 200000]);
    });

    test('category totals within range', () {
      final totals =
          store.totalsByCategory(DateTime(2026, 10), DateTime(2026, 11));
      expect(totals[ExpenseCategory.food], 150000);
      expect(totals[ExpenseCategory.gear], 200000);
      expect(totals[ExpenseCategory.travel], 0);
    });

    test('add, update, remove and restore', () async {
      final saved = await store.add(_e(1000, ExpenseCategory.study, monday));
      expect(store.expenses, contains(predicate<Expense>((e) => e.id == saved.id)));
      await store.update(saved.copyWith(amount: 2000));
      expect(store.expenses.firstWhere((e) => e.id == saved.id).amount, 2000);
      await store.remove(saved);
      expect(store.expenses.length, 4);
      await store.restore(saved);
      expect(store.expenses.length, 5);
    });
  });

  testWidgets('donut selects a slice on tap', (tester) async {
    ExpenseCategory? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: StatefulBuilder(
            builder: (context, setState) => DonutChart(
              values: const {
                ExpenseCategory.food: 100,
                ExpenseCategory.gear: 100,
              },
              selected: selected,
              onSelected: (c) => setState(() => selected = c),
              center: const Text('Total'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final box = tester.getRect(find.byType(DonutChart));
    // Tap on the ring at 3 o'clock → first slice (food).
    await tester.tapAt(Offset(box.right - 30, box.center.dy));
    await tester.pumpAndSettle();
    expect(selected, ExpenseCategory.food);

    // Tapping the centre clears the selection.
    await tester.tapAt(box.center);
    await tester.pumpAndSettle();
    expect(selected, isNull);
  });

  testWidgets('bar chart shows tooltip for tapped bar', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: WeeklyBarChart(
            values: [10000, 0, 50000, 0, 0, 0, 0],
            labels: ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byType(WeeklyBarChart));
    // Third slot centre.
    final slot = (rect.width - 44) / 7;
    await tester.tapAt(Offset(rect.left + 40 + slot * 2.5, rect.center.dy));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
