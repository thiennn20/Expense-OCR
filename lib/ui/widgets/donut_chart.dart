import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/expense_category.dart';
import 'chart_math.dart';

/// Animated, tappable category donut drawn with [CustomPainter].
///
/// * On first build (and whenever the data changes) the ring sweeps in
///   clockwise from 12 o'clock.
/// * Tapping a slice selects it: the slice thickens and the others fade.
///   Tapping it again, or the empty centre, clears the selection.
class DonutChart extends StatefulWidget {
  const DonutChart({
    super.key,
    required this.values,
    required this.selected,
    required this.onSelected,
    required this.center,
    this.size = 220,
  });

  final Map<ExpenseCategory, double> values;
  final ExpenseCategory? selected;
  final ValueChanged<ExpenseCategory?> onSelected;
  final Widget center;
  final double size;

  @override
  State<DonutChart> createState() => _DonutChartState();
}

class _DonutChartState extends State<DonutChart> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();
  late final AnimationController _selection = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );

  late final Animation<double> _introCurve = CurvedAnimation(
    parent: _intro,
    curve: Curves.easeOutCubic,
  );
  late final Animation<double> _selectionCurve = CurvedAnimation(
    parent: _selection,
    curve: Curves.easeOutBack,
  );

  late List<DonutSlice<ExpenseCategory>> _slices = computeSlices(
    widget.values.entries,
  );

  @override
  void didUpdateWidget(DonutChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!mapEquals(oldWidget.values, widget.values)) {
      _slices = computeSlices(widget.values.entries);
      _intro.forward(from: 0);
    }
    if (oldWidget.selected != widget.selected) {
      _selection.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _selection.dispose();
    super.dispose();
  }

  void _handleTap(TapUpDetails details) {
    final c = Offset(widget.size / 2, widget.size / 2);
    final v = details.localPosition - c;
    final geometry = _DonutGeometry(widget.size);
    final inRing =
        v.distance >= geometry.radius - geometry.thickness / 2 - 10 &&
        v.distance <= geometry.radius + geometry.thickness / 2 + 16;
    if (!inRing) {
      widget.onSelected(null);
      return;
    }
    final slice = sliceAtAngle(_slices, math.atan2(v.dy, v.dx));
    widget.onSelected(
      slice == null || slice.key == widget.selected ? null : slice.key,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Spending by category donut chart',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: _handleTap,
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _DonutPainter(
            slices: _slices,
            intro: _introCurve,
            selection: _selectionCurve,
            selected: widget.selected,
            trackColor: scheme.surfaceContainerHighest,
          ),
          child: SizedBox.square(
            dimension: widget.size,
            child: Center(child: widget.center),
          ),
        ),
      ),
    );
  }
}

class _DonutGeometry {
  _DonutGeometry(double size) : radius = size / 2 - 14, thickness = size * 0.13;

  final double radius;
  final double thickness;
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.slices,
    required this.intro,
    required this.selection,
    required this.selected,
    required this.trackColor,
  }) : super(repaint: Listenable.merge([intro, selection]));

  final List<DonutSlice<ExpenseCategory>> slices;
  final Animation<double> intro;
  final Animation<double> selection;
  final ExpenseCategory? selected;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final g = _DonutGeometry(size.shortestSide);
    final center = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: center, radius: g.radius);

    canvas.drawCircle(
      center,
      g.radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = g.thickness
        ..color = trackColor,
    );
    if (slices.isEmpty) return;

    // The sweep-in reveals slices up to this angle.
    final limit = donutOrigin + 2 * math.pi * intro.value;
    final t = selection.value;

    for (final s in slices) {
      final visible = (limit - s.start).clamp(0.0, s.sweep);
      if (visible <= 0) continue;

      final isSelected = s.key == selected;
      final dimmed = selected != null && !isSelected;
      final extra = isSelected ? 10 * t : 0.0;
      final color = dimmed
          ? s.key.color.withValues(alpha: 1 - 0.6 * t.clamp(0.0, 1.0))
          : s.key.color;

      canvas.drawArc(
        isSelected ? rect.inflate(extra / 2) : rect,
        s.start,
        visible,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = g.thickness + extra
          ..strokeCap = StrokeCap.butt
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.slices != slices ||
      old.selected != selected ||
      old.trackColor != trackColor;
}
