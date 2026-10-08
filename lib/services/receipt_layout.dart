/// A recognised line of text with its bounding box in image pixels.
///
/// Kept independent of `dart:ui` / ML Kit so the layout logic is unit-testable.
class OcrLine {
  const OcrLine(
    this.text, {
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get height => bottom - top;
  double get centerY => (top + bottom) / 2;
}

/// Re-assembles visual rows of a receipt.
///
/// ML Kit groups text into *blocks* by column, so a row such as
/// `TỔNG CỘNG ........ 150.000` usually comes back as two separate lines that
/// are far apart in the output ("TỔNG CỘNG" in the left block, "150.000" in
/// the right block). The parser needs the label and the value on the same
/// line, so lines whose vertical centres overlap are merged left-to-right.
List<String> mergeIntoRows(List<OcrLine> lines) {
  if (lines.isEmpty) return const [];
  final sorted = [...lines]..sort((a, b) => a.centerY.compareTo(b.centerY));

  final rows = <List<OcrLine>>[];
  for (final line in sorted) {
    final row = rows.isEmpty ? null : rows.last;
    if (row != null) {
      final rowCenter =
          row.map((l) => l.centerY).reduce((a, b) => a + b) / row.length;
      final rowHeight =
          row.map((l) => l.height).reduce((a, b) => a + b) / row.length;
      // Half a line height of tolerance absorbs slight camera skew without
      // collapsing two genuinely different rows into one.
      final tolerance =
          0.5 * (rowHeight < line.height ? rowHeight : line.height);
      if ((line.centerY - rowCenter).abs() <= tolerance) {
        row.add(line);
        continue;
      }
    }
    rows.add([line]);
  }

  return [
    for (final row in rows)
      (row..sort((a, b) => a.left.compareTo(b.left)))
          .map((l) => l.text.trim())
          .where((t) => t.isNotEmpty)
          .join('  '),
  ].where((r) => r.isNotEmpty).toList();
}
