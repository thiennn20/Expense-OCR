import 'package:flutter/material.dart';

import '../../models/expense_category.dart';

class CategoryPicker extends StatelessWidget {
  const CategoryPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final ExpenseCategory selected;
  final ValueChanged<ExpenseCategory> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in ExpenseCategory.values)
          ChoiceChip(
            avatar: Icon(
              c.icon,
              size: 18,
              color: c == selected ? Colors.black87 : c.color,
            ),
            label: Text(c.label),
            selected: c == selected,
            selectedColor: c.color,
            labelStyle: c == selected
                ? const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                  )
                : null,
            onSelected: (_) => onChanged(c),
          ),
      ],
    );
  }
}

class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar(this.category, {super.key, this.size = 44});

  final ExpenseCategory category;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: category.color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(category.icon, color: category.color, size: size * 0.5),
    );
  }
}
