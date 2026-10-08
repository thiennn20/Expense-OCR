import 'dart:math' as math;

/// Geometry of one donut slice in radians, measured clockwise from 12 o'clock
/// (canvas angle `-pi/2`).
class DonutSlice<T> {
  const DonutSlice(this.key, this.value, this.start, this.sweep);

  final T key;
  final double value;
  final double start;
  final double sweep;

  double get end => start + sweep;
}

const double donutOrigin = -math.pi / 2;

/// Lays out non-zero [entries] around the circle with a small [gap] between
/// slices.
List<DonutSlice<T>> computeSlices<T>(
  Iterable<MapEntry<T, double>> entries, {
  double gap = 0.035,
}) {
  final positive = entries.where((e) => e.value > 0).toList();
  final total = positive.fold<double>(0, (s, e) => s + e.value);
  if (total <= 0) return const [];

  final n = positive.length;
  final gapEach = n > 1 ? gap : 0.0;
  final available = 2 * math.pi - gapEach * n;
  var angle = donutOrigin + gapEach / 2;
  return [
    for (final e in positive)
      () {
        final sweep = e.value / total * available;
        final slice = DonutSlice(e.key, e.value, angle, sweep);
        angle += sweep + gapEach;
        return slice;
      }(),
  ];
}

/// Returns the slice under [angle] (as given by `atan2(dy, dx)`), counting
/// the half-gaps either side as part of the nearest slice.
DonutSlice<T>? sliceAtAngle<T>(List<DonutSlice<T>> slices, double angle) {
  if (slices.isEmpty) return null;
  // Normalise into [origin, origin + 2π).
  var a = angle;
  while (a < donutOrigin) {
    a += 2 * math.pi;
  }
  while (a >= donutOrigin + 2 * math.pi) {
    a -= 2 * math.pi;
  }
  for (final s in slices) {
    if (a >= s.start && a < s.end) return s;
  }
  // Inside a gap: choose the closest slice edge.
  DonutSlice<T>? best;
  var bestDistance = double.infinity;
  for (final s in slices) {
    final d = math.min((a - s.start).abs(), (a - s.end).abs());
    if (d < bestDistance) {
      bestDistance = d;
      best = s;
    }
  }
  return best;
}

/// A "nice" axis step (1, 2, 2.5 or 5 × 10ⁿ) so that [divisions] steps cover
/// [maxValue].
double niceStep(double maxValue, int divisions) {
  if (maxValue <= 0) return 1;
  final raw = maxValue / divisions;
  final magnitude = math
      .pow(10, (math.log(raw) / math.ln10).floor())
      .toDouble();
  final normalised = raw / magnitude;
  final nice = normalised <= 1
      ? 1.0
      : normalised <= 2
      ? 2.0
      : normalised <= 2.5
      ? 2.5
      : normalised <= 5
      ? 5.0
      : 10.0;
  return nice * magnitude;
}
