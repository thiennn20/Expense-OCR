import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/expense.dart';

abstract interface class ExpenseRepository {
  Future<List<Expense>> fetchAll();
  Future<Expense> insert(Expense expense);
  Future<void> update(Expense expense);
  Future<void> delete(int id);
}

/// SQLite persistence via `sqflite`.
class SqfliteExpenseRepository implements ExpenseRepository {
  SqfliteExpenseRepository._(this._db);

  final Database _db;

  static const _table = 'expenses';

  static Future<SqfliteExpenseRepository> open() async {
    final path = p.join(await getDatabasesPath(), 'expenses.db');
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            merchant    TEXT    NOT NULL,
            amount      REAL    NOT NULL,
            category    TEXT    NOT NULL,
            date        INTEGER NOT NULL,
            note        TEXT    NOT NULL DEFAULT '',
            image_file  TEXT,
            thumb_file  TEXT,
            raw_text    TEXT    NOT NULL DEFAULT '',
            created_at  INTEGER NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX idx_expenses_date ON $_table(date)');
        await db.execute(
          'CREATE INDEX idx_expenses_category ON $_table(category)',
        );
      },
    );
    return SqfliteExpenseRepository._(db);
  }

  @override
  Future<List<Expense>> fetchAll() async {
    final rows = await _db.query(_table, orderBy: 'date DESC, id DESC');
    return rows.map(Expense.fromMap).toList();
  }

  @override
  Future<Expense> insert(Expense expense) async {
    final map = expense.toMap()..remove('id');
    final id = await _db.insert(_table, map);
    return expense.copyWith(id: id);
  }

  @override
  Future<void> update(Expense expense) async {
    await _db.update(
      _table,
      expense.toMap(),
      where: 'id = ?',
      whereArgs: [expense.id],
    );
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }
}

/// Non-persistent repository used by widget tests and screenshot rendering.
class InMemoryExpenseRepository implements ExpenseRepository {
  InMemoryExpenseRepository([List<Expense> seed = const []]) {
    for (final e in seed) {
      _rows[++_nextId] = e.copyWith(id: _nextId);
    }
  }

  final Map<int, Expense> _rows = {};
  int _nextId = 0;

  @override
  Future<List<Expense>> fetchAll() async =>
      _rows.values.toList()..sort((a, b) => b.date.compareTo(a.date));

  @override
  Future<Expense> insert(Expense expense) async {
    final saved = expense.copyWith(id: ++_nextId);
    _rows[_nextId] = saved;
    return saved;
  }

  @override
  Future<void> update(Expense expense) async => _rows[expense.id!] = expense;

  @override
  Future<void> delete(int id) async => _rows.remove(id);
}
