import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

final NumberFormat _grouped = NumberFormat('#,##0', 'en_US');

/// `150000` → `150.000 ₫` (Vietnamese grouping with dots).
String formatVnd(double amount) => '${groupThousands(amount)} ₫';

String groupThousands(double amount) =>
    _grouped.format(amount.round()).replaceAll(',', '.');

/// Short axis/legend label: `1.250.000` → `1.3M`, `45.000` → `45K`.
String formatCompact(double amount) {
  if (amount >= 1e9) return '${_trim(amount / 1e9)}B';
  if (amount >= 1e6) return '${_trim(amount / 1e6)}M';
  if (amount >= 1e3) return '${_trim(amount / 1e3)}K';
  return amount.round().toString();
}

String _trim(double v) {
  final s = v >= 100 ? v.round().toString() : v.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

final DateFormat dayMonthYear = DateFormat('dd/MM/yyyy');
final DateFormat dayMonth = DateFormat('dd/MM');
final DateFormat weekdayDayMonth = DateFormat('EEE, dd/MM/yyyy');
final DateFormat monthYear = DateFormat('MMMM yyyy');

/// Parses text typed in the amount field (`150.000` → 150000).
double? parseTypedAmount(String text) {
  final digits = text.replaceAll(RegExp(r'[^\d]'), '');
  return digits.isEmpty ? null : double.parse(digits);
}

/// Groups digits with dots while the user types: `150000` → `150.000`.
class ThousandsInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final trimmed = digits.length > 12 ? digits.substring(0, 12) : digits;
    final formatted = groupThousands(double.parse(trimmed));

    // Keep the caret at the same number of digits from the right.
    final digitsAfterCaret = newValue.text
        .substring(newValue.selection.end.clamp(0, newValue.text.length))
        .replaceAll(RegExp(r'[^\d]'), '')
        .length;
    var offset = formatted.length;
    var seen = 0;
    while (offset > 0 && seen < digitsAfterCaret) {
      offset--;
      if (RegExp(r'\d').hasMatch(formatted[offset])) seen++;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}
