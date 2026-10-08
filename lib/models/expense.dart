import 'expense_category.dart';

/// A single saved transaction.
///
/// Receipt images are stored as file *names* relative to the app's receipt
/// directory (see `ReceiptImageStore`), never as absolute paths, because the
/// iOS sandbox path changes between installs/updates.
class Expense {
  const Expense({
    this.id,
    required this.merchant,
    required this.amount,
    required this.category,
    required this.date,
    this.note = '',
    this.imageFile,
    this.thumbFile,
    this.rawText = '',
    required this.createdAt,
  });

  final int? id;
  final String merchant;
  final double amount;
  final ExpenseCategory category;
  final DateTime date;
  final String note;
  final String? imageFile;
  final String? thumbFile;
  final String rawText;
  final DateTime createdAt;

  bool get hasReceipt => imageFile != null;

  Expense copyWith({
    int? id,
    String? merchant,
    double? amount,
    ExpenseCategory? category,
    DateTime? date,
    String? note,
    String? imageFile,
    String? thumbFile,
    String? rawText,
    DateTime? createdAt,
  }) {
    return Expense(
      id: id ?? this.id,
      merchant: merchant ?? this.merchant,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      date: date ?? this.date,
      note: note ?? this.note,
      imageFile: imageFile ?? this.imageFile,
      thumbFile: thumbFile ?? this.thumbFile,
      rawText: rawText ?? this.rawText,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'merchant': merchant,
    'amount': amount,
    'category': category.name,
    'date': date.millisecondsSinceEpoch,
    'note': note,
    'image_file': imageFile,
    'thumb_file': thumbFile,
    'raw_text': rawText,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory Expense.fromMap(Map<String, Object?> map) => Expense(
    id: map['id'] as int?,
    merchant: map['merchant'] as String? ?? '',
    amount: (map['amount'] as num?)?.toDouble() ?? 0,
    category: ExpenseCategory.fromName(map['category'] as String?),
    date: DateTime.fromMillisecondsSinceEpoch(map['date'] as int),
    note: map['note'] as String? ?? '',
    imageFile: map['image_file'] as String?,
    thumbFile: map['thumb_file'] as String?,
    rawText: map['raw_text'] as String? ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
  );
}
