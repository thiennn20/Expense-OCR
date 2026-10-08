import 'package:flutter/foundation.dart';

import '../core/dates.dart';
import '../data/expense_repository.dart';
import '../data/receipt_image_store.dart';
import '../models/expense.dart';
import '../models/expense_category.dart';

/// Single source of truth for saved expenses.
///
/// Screens listen through `AppScope` and rebuild when [notifyListeners] fires.
/// All writes go to the repository first; the in-memory list is only updated
/// after the database call succeeds, so the UI never shows unsaved data.
class ExpenseStore extends ChangeNotifier {
  ExpenseStore(this._repository, {this.images});

  final ExpenseRepository _repository;
  final ReceiptImageStore? images;

  List<Expense> _expenses = const [];
  bool _loading = true;
  Object? _error;

  List<Expense> get expenses => _expenses;
  bool get isLoading => _loading;
  Object? get error => _error;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      _expenses = await _repository.fetchAll();
      _error = null;
    } catch (e, st) {
      debugPrint('Failed to load expenses: $e\n$st');
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<Expense> add(Expense expense) async {
    final saved = await _repository.insert(expense);
    _expenses = [..._expenses, saved]..sort(_byDateDesc);
    notifyListeners();
    return saved;
  }

  Future<void> update(Expense expense) async {
    await _repository.update(expense);
    _expenses = [for (final e in _expenses) e.id == expense.id ? expense : e]
      ..sort(_byDateDesc);
    notifyListeners();
  }

  /// Removes the row but keeps its image files so the deletion can be undone.
  /// Call [purgeImages] once the undo window has passed.
  Future<void> remove(Expense expense) async {
    await _repository.delete(expense.id!);
    _expenses = _expenses.where((e) => e.id != expense.id).toList();
    notifyListeners();
  }

  Future<void> restore(Expense expense) => add(expense.copyWith());

  Future<void> purgeImages(Expense expense) async =>
      images?.delete(expense.imageFile, expense.thumbFile);

  static int _byDateDesc(Expense a, Expense b) {
    final byDate = b.date.compareTo(a.date);
    return byDate != 0 ? byDate : (b.id ?? 0).compareTo(a.id ?? 0);
  }

  // ------------------------------------------------------------ aggregates

  Iterable<Expense> inRange(DateTime? from, DateTime? to) => _expenses.where(
    (e) =>
        (from == null || !e.date.isBefore(from)) &&
        (to == null || e.date.isBefore(to)),
  );

  double totalIn(DateTime? from, DateTime? to) =>
      inRange(from, to).fold(0, (sum, e) => sum + e.amount);

  /// Category → total, ordered by the enum so chart colours stay stable.
  Map<ExpenseCategory, double> totalsByCategory(DateTime? from, DateTime? to) {
    final totals = {for (final c in ExpenseCategory.values) c: 0.0};
    for (final e in inRange(from, to)) {
      totals[e.category] = totals[e.category]! + e.amount;
    }
    return totals;
  }

  /// Seven daily totals (Monday → Sunday) for the week starting at
  /// [weekStart].
  List<double> dailyTotals(DateTime weekStart) {
    final start = startOfDay(weekStart);
    final days = List<double>.filled(7, 0);
    for (final e in inRange(start, addDays(start, 7))) {
      final index = startOfDay(e.date).difference(start).inDays;
      if (index >= 0 && index < 7) days[index] += e.amount;
    }
    return days;
  }
}
