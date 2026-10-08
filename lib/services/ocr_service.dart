import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'receipt_layout.dart';

class OcrResult {
  const OcrResult({
    required this.rows,
    required this.rawText,
    required this.elapsed,
  });

  /// Visual rows (label + value merged), top to bottom.
  final List<String> rows;
  final String rawText;

  /// Time spent inside ML Kit only (excludes image decoding / cropping).
  final Duration elapsed;
}

/// Thin wrapper around ML Kit's on-device Latin text recogniser.
///
/// The Latin model covers Vietnamese diacritics, runs fully offline and is
/// bundled into the APK, so there is no network call and no cloud cost.
class OcrService {
  TextRecognizer? _recognizer;

  TextRecognizer get _instance =>
      _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);

  Future<OcrResult> recognizeFile(String path) async {
    final stopwatch = Stopwatch()..start();
    final recognized = await _instance.processImage(
      InputImage.fromFilePath(path),
    );
    stopwatch.stop();

    final lines = <OcrLine>[
      for (final block in recognized.blocks)
        for (final line in block.lines)
          OcrLine(
            line.text,
            left: line.boundingBox.left,
            top: line.boundingBox.top,
            right: line.boundingBox.right,
            bottom: line.boundingBox.bottom,
          ),
    ];

    return OcrResult(
      rows: mergeIntoRows(lines),
      rawText: recognized.text,
      elapsed: stopwatch.elapsed,
    );
  }

  Future<void> dispose() async {
    await _recognizer?.close();
    _recognizer = null;
  }
}
