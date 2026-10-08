import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import 'chart_math.dart';

/// Seven-day spending bar chart drawn with [CustomPainter].
///
/// Bars grow with a staggered animation; tapping a bar shows a tooltip with
/// the exact amount.
class WeeklyBarChart extends StatefulWidget {
  const WeeklyBarChart({
    super.key,
    required this.values,
    required this.labels,
    this.highlightIndex,
    this.height = 200,
  });

  final List<double> values;
  final List<String> labels;

  /// Usually "today"; drawn in the full accent colour.
  final int? highlightIndex;
  final double height;

  @override
  State<WeeklyBarChart> createState() => _WeeklyBarChartState();
}

class _WeeklyBarChartState extends State<WeeklyBarChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();
  int? _selected;

  @override
  void didUpdateWidget(WeeklyBarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.values, widget.values)) {
      _selected = null;
      _grow.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _grow.dispose();
    super.dispose();
  }

  void _handleTap(TapUpDetails d, Size size) {
    final layout = _BarLayout(size, widget.values.length);
    final index = layout.indexAt(d.localPosition.dx);
    setState(
      () => _selected = (index == null || index == _selected) ? null : index,
    );
  }

  @override
  Widget build(BuildContext context) {
    assert(widget.values.length == widget.labels.length);
    final theme = Theme.of(context);
    return Semantics(
      label:
          'Weekly spending bar chart. '
          '${[for (var i = 0; i < widget.values.length; i++) '${widget.labels[i]}: ${formatVnd(widget.values[i])}'].join(', ')}',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, widget.height);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _handleTap(d, size),
            child: CustomPaint(
              size: size,
              painter: _BarPainter(
                values: widget.values,
                labels: widget.labels,
                highlightIndex: widget.highlightIndex,
                selectedIndex: _selected,
                progress: _grow,
                barColor: theme.colorScheme.primary,
                gridColor: theme.colorScheme.outlineVariant,
                labelStyle: theme.textTheme.labelSmall!.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                tooltipColor: theme.colorScheme.inverseSurface,
                tooltipTextColor: theme.colorScheme.onInverseSurface,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BarLayout {
  _BarLayout(this.size, this.count)
    : plot = Rect.fromLTRB(40, 30, size.width - 4, size.height - 24);

  final Size size;
  final int count;
  final Rect plot;

  double get slot => plot.width / count;
  double get barWidth => (slot * 0.56).clamp(6.0, 34.0);
  double centerX(int i) => plot.left + slot * (i + 0.5);

  int? indexAt(double x) {
    if (x < plot.left || x > plot.right) return null;
    return ((x - plot.left) / slot).floor().clamp(0, count - 1);
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.values,
    required this.labels,
    required this.highlightIndex,
    required this.selectedIndex,
    required this.progress,
    required this.barColor,
    required this.gridColor,
    required this.labelStyle,
    required this.tooltipColor,
    required this.tooltipTextColor,
  }) : super(repaint: progress);

  final List<double> values;
  final List<String> labels;
  final int? highlightIndex;
  final int? selectedIndex;
  final Animation<double> progress;
  final Color barColor;
  final Color gridColor;
  final TextStyle labelStyle;
  final Color tooltipColor;
  final Color tooltipTextColor;

  static const _divisions = 4;

  TextPainter _text(String s, TextStyle style) => TextPainter(
    text: TextSpan(text: s, style: style),
    textDirection: TextDirection.ltr,
  )..layout();

  /// Staggered growth: bar i starts 60 ms after bar i-1.
  double _barProgress(int i) {
    final start = i * 0.06;
    final t = ((progress.value - start) / 0.55).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(t);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final layout = _BarLayout(size, values.length);
    final plot = layout.plot;
    final maxValue = values.fold<double>(0, (m, v) => v > m ? v : m);
    final step = niceStep(maxValue, _divisions);
    final top = step * _divisions;

    // Horizontal grid + Y labels.
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= _divisions; i++) {
      final y = plot.bottom - plot.height * i / _divisions;
      _dashedLine(
        canvas,
        Offset(plot.left, y),
        Offset(plot.right, y),
        gridPaint,
      );
      final label = _text(
        maxValue == 0 ? '0' : formatCompact(step * i),
        labelStyle,
      );
      label.paint(
        canvas,
        Offset(plot.left - label.width - 8, y - label.height / 2),
      );
    }

    // Bars + X labels.
    for (var i = 0; i < values.length; i++) {
      final cx = layout.centerX(i);
      final h = top == 0
          ? 0.0
          : plot.height * (values[i] / top) * _barProgress(i);
      final emphasised = i == highlightIndex || i == selectedIndex;
      final paint = Paint()
        ..color = emphasised ? barColor : barColor.withValues(alpha: 0.4);
      if (h > 0) {
        final r = Rect.fromLTRB(
          cx - layout.barWidth / 2,
          plot.bottom - h,
          cx + layout.barWidth / 2,
          plot.bottom,
        );
        final radius = Radius.circular(layout.barWidth / 3);
        canvas.drawRRect(
          RRect.fromRectAndCorners(r, topLeft: radius, topRight: radius),
          paint,
        );
      }

      final style = i == highlightIndex
          ? labelStyle.copyWith(color: barColor, fontWeight: FontWeight.w700)
          : labelStyle;
      final label = _text(labels[i], style);
      label.paint(canvas, Offset(cx - label.width / 2, plot.bottom + 6));
    }

    final sel = selectedIndex;
    if (sel != null) _tooltip(canvas, layout, sel, top);
  }

  void _tooltip(Canvas canvas, _BarLayout layout, int i, double top) {
    final plot = layout.plot;
    final h = top == 0
        ? 0.0
        : plot.height * (values[i] / top) * _barProgress(i);
    final text = _text(
      formatVnd(values[i]),
      labelStyle.copyWith(color: tooltipTextColor, fontWeight: FontWeight.w600),
    );
    final w = text.width + 16, th = text.height + 8;
    var left = layout.centerX(i) - w / 2;
    left = left.clamp(0.0, layout.size.width - w);
    final bottom = (plot.bottom - h - 6).clamp(th, layout.size.height);
    final bubble = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, bottom - th, w, th),
      const Radius.circular(8),
    );
    canvas.drawRRect(bubble, Paint()..color = tooltipColor);
    text.paint(canvas, Offset(left + 8, bottom - th + 4));
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 4.0, gap = 4.0;
    var x = a.dx;
    while (x < b.dx) {
      canvas.drawLine(
        Offset(x, a.dy),
        Offset((x + dash).clamp(a.dx, b.dx), a.dy),
        paint,
      );
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      !listEquals(old.values, values) ||
      old.selectedIndex != selectedIndex ||
      old.highlightIndex != highlightIndex ||
      old.barColor != barColor;
}
