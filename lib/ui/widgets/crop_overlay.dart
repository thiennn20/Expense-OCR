import 'package:flutter/material.dart';

/// Receipt-shaped framing rectangle inside a preview of [size].
Rect receiptFrame(Size size) {
  final width = size.width * 0.84;
  final height = (width * 1.5).clamp(0.0, size.height * 0.86);
  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height * 0.48),
    width: width,
    height: height,
  );
}

/// The frame as 0..1 fractions of the preview, used to crop the still photo.
Rect frameFractions(Size size) {
  final f = receiptFrame(size);
  return Rect.fromLTRB(
    f.left / size.width,
    f.top / size.height,
    f.right / size.width,
    f.bottom / size.height,
  );
}

/// Dims everything outside the framing rectangle and draws corner brackets.
class CropOverlayPainter extends CustomPainter {
  const CropOverlayPainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = receiptFrame(size);
    final rrect = RRect.fromRectAndRadius(frame, const Radius.circular(18));

    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(rrect);
    canvas.drawPath(
      shade,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.6),
    );

    final corner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = accent;
    const len = 28.0, r = 18.0;
    final l = frame.left, t = frame.top, rt = frame.right, b = frame.bottom;
    for (final path in [
      Path()
        ..moveTo(l, t + len)
        ..lineTo(l, t + r)
        ..arcToPoint(Offset(l + r, t), radius: const Radius.circular(r))
        ..lineTo(l + len, t),
      Path()
        ..moveTo(rt - len, t)
        ..lineTo(rt - r, t)
        ..arcToPoint(Offset(rt, t + r), radius: const Radius.circular(r))
        ..lineTo(rt, t + len),
      Path()
        ..moveTo(rt, b - len)
        ..lineTo(rt, b - r)
        ..arcToPoint(Offset(rt - r, b), radius: const Radius.circular(r))
        ..lineTo(rt - len, b),
      Path()
        ..moveTo(l + len, b)
        ..lineTo(l + r, b)
        ..arcToPoint(Offset(l, b - r), radius: const Radius.circular(r))
        ..lineTo(l, b - len),
    ]) {
      canvas.drawPath(path, corner);
    }
  }

  @override
  bool shouldRepaint(CropOverlayPainter old) => old.accent != accent;
}
