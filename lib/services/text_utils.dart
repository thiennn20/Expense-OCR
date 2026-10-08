/// Text helpers shared by the receipt parser.
library;

const Map<String, String> _vietnameseGroups = {
  'a': 'àáạảãâầấậẩẫăằắặẳẵ',
  'e': 'èéẹẻẽêềếệểễ',
  'i': 'ìíịỉĩ',
  'o': 'òóọỏõôồốộổỗơờớợởỡ',
  'u': 'ùúụủũưừứựửữ',
  'y': 'ỳýỵỷỹ',
  'd': 'đ',
};

final Map<int, String> _foldTable = {
  for (final entry in _vietnameseGroups.entries)
    for (final rune in entry.value.runes) rune: entry.key,
};

final RegExp _combiningMarks = RegExp('[̀-ͯ]');

/// Lower-cases [input] and strips Vietnamese diacritics so keyword matching
/// works whether ML Kit returns "Tổng cộng", "TONG CONG" or "Tông công".
String fold(String input) {
  final lower = input.toLowerCase().replaceAll(_combiningMarks, '');
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    buffer.write(_foldTable[rune] ?? String.fromCharCode(rune));
  }
  return buffer.toString();
}

/// Fixes the most common OCR confusions *inside numbers*: the letter O read
/// in place of a zero right after a digit (e.g. `15O.0OO` → `150.000`).
/// A trailing `D`/`d` is left alone because OCR often reads `đ` that way.
String repairDigits(String line) {
  final pattern = RegExp(r'(?<=\d[.,]?)[Oo](?![A-NP-Za-np-z])');
  var previous = line;
  // Each pass converts one more character of a run such as "0OO".
  for (var i = 0; i < 6; i++) {
    final next = previous.replaceAll(pattern, '0');
    if (next == previous) break;
    previous = next;
  }
  return previous;
}

/// Ratio of characters in [s] that are decimal digits.
double digitRatio(String s) {
  final compact = s.replaceAll(RegExp(r'\s'), '');
  if (compact.isEmpty) return 0;
  final digits = RegExp(r'\d').allMatches(compact).length;
  return digits / compact.length;
}

/// Number of letters (including Vietnamese letters) in [s].
int letterCount(String s) => RegExp(r'[A-Za-zÀ-ỹĐđ]').allMatches(s).length;
