import 'dart:ui' show Rect;

import '../data/receipt_image_store.dart';
import '../models/expense.dart';
import 'ocr_service.dart';
import 'receipt_parser.dart';

class ScanOutcome {
  const ScanOutcome({
    required this.draft,
    required this.parsed,
    required this.ocrTime,
  });

  final Expense draft;
  final ParsedReceipt parsed;
  final Duration ocrTime;
}

/// Capture → crop/persist → on-device OCR → heuristic parse → draft expense.
Future<ScanOutcome> scanReceipt({
  required ReceiptImageStore images,
  required OcrService ocr,
  required ReceiptParser parser,
  required String sourcePath,
  Rect? crop,
  double? previewAspect,
}) async {
  final stored = await images.saveReceipt(
    sourcePath,
    crop: crop,
    previewAspect: previewAspect,
  );
  try {
    final result = await ocr.recognizeFile(
      images.resolve(stored.imageFile).path,
    );
    final parsed = parser.parse(result.rows);
    final now = DateTime.now();
    return ScanOutcome(
      parsed: parsed,
      ocrTime: result.elapsed,
      draft: Expense(
        merchant: parsed.merchant ?? '',
        amount: parsed.total ?? 0,
        category: parsed.category,
        date: parsed.date ?? now,
        imageFile: stored.imageFile,
        thumbFile: stored.thumbFile,
        rawText: result.rows.join('\n'),
        createdAt: now,
      ),
    );
  } catch (_) {
    await images.delete(stored.imageFile, stored.thumbFile);
    rethrow;
  }
}
