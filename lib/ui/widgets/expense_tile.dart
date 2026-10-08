import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/formatters.dart';
import '../../models/expense.dart';
import 'category_picker.dart';

class ExpenseTile extends StatelessWidget {
  const ExpenseTile({super.key, required this.expense, this.onTap});

  final Expense expense;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final images = AppScope.read(context).images;
    final thumb = expense.thumbFile;

    final fallback = CategoryAvatar(expense.category);
    final leading = thumb == null
        ? fallback
        : ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Image.file(
              images.resolve(thumb),
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              // Decode at display size: keeps the image cache small even with
              // hundreds of receipts in the list.
              cacheWidth: 132,
              errorBuilder: (_, _, _) => fallback,
            ),
          );

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: leading,
      title: Text(
        expense.merchant,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Row(
        children: [
          Icon(expense.category.icon, size: 14, color: expense.category.color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '${expense.category.label} · ${dayMonthYear.format(expense.date)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (expense.hasReceipt) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.receipt_long_rounded,
              size: 14,
              color: theme.colorScheme.outline,
            ),
          ],
        ],
      ),
      trailing: Text(
        '-${formatVnd(expense.amount)}',
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
