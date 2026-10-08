import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class StoredReceipt {
  const StoredReceipt({required this.imageFile, required this.thumbFile});

  /// File names relative to [ReceiptImageStore.directory].
  final String imageFile;
  final String thumbFile;
}

/// Persists cropped receipt photos and their thumbnails inside the app's
/// documents directory (`<documents>/receipts`).
///
/// Paths are resolved synchronously from a base directory looked up once at
/// start-up, so list tiles can build `Image.file` without awaiting.
class ReceiptImageStore {
  ReceiptImageStore(this.directory);

  final String directory;

  static const maxImageSide = 1600;
  static const thumbWidth = 240;

  static Future<ReceiptImageStore> open() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'receipts'));
    await dir.create(recursive: true);
    return ReceiptImageStore(dir.path);
  }

  File resolve(String fileName) => File(p.join(directory, fileName));

  /// Crops [sourcePath] to the on-screen framing rectangle, downsizes it and
  /// writes the full image plus a thumbnail.
  ///
  /// [crop] is expressed as fractions (0..1) of the *preview* area and
  /// [previewAspect] is that area's width / height. The still photo can have
  /// a different aspect ratio than the preview stream, so the photo is first
  /// centre-cropped to the preview aspect (which is what the user actually
  /// saw) before the framing fractions are applied.
  ///
  /// Decoding a 12 MP JPEG in Dart takes ~1 s, so the work runs in a
  /// background isolate to keep the UI at 60 fps.
  Future<StoredReceipt> saveReceipt(
    String sourcePath, {
    Rect? crop,
    double? previewAspect,
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final job = _ImageJob(
      sourcePath: sourcePath,
      imagePath: p.join(directory, 'receipt_$id.jpg'),
      thumbPath: p.join(directory, 'thumb_$id.jpg'),
      crop: crop == null
          ? null
          : [crop.left, crop.top, crop.right, crop.bottom],
      previewAspect: previewAspect,
    );
    await compute(_processImage, job);
    return StoredReceipt(
      imageFile: p.basename(job.imagePath),
      thumbFile: p.basename(job.thumbPath),
    );
  }

  Future<void> delete(String? imageFile, String? thumbFile) async {
    for (final name in [imageFile, thumbFile]) {
      if (name == null) continue;
      final file = resolve(name);
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException catch (e) {
        debugPrint('Could not delete $name: $e');
      }
    }
  }
}

class _ImageJob {
  const _ImageJob({
    required this.sourcePath,
    required this.imagePath,
    required this.thumbPath,
    this.crop,
    this.previewAspect,
  });

  final String sourcePath;
  final String imagePath;
  final String thumbPath;
  final List<double>? crop;
  final double? previewAspect;
}

void _processImage(_ImageJob job) {
  final decoded = img.decodeImage(File(job.sourcePath).readAsBytesSync());
  if (decoded == null) {
    throw const FormatException('Unsupported or corrupted image');
  }
  // Camera JPEGs are stored sideways with an EXIF rotation tag.
  var image = img.bakeOrientation(decoded);

  final aspect = job.previewAspect;
  if (aspect != null && aspect > 0) {
    image = _centerCropToAspect(image, aspect);
  }

  final crop = job.crop;
  if (crop != null) {
    final x = (crop[0].clamp(0.0, 1.0) * image.width).round();
    final y = (crop[1].clamp(0.0, 1.0) * image.height).round();
    final r = (crop[2].clamp(0.0, 1.0) * image.width).round();
    final b = (crop[3].clamp(0.0, 1.0) * image.height).round();
    if (r - x > 32 && b - y > 32) {
      image = img.copyCrop(image, x: x, y: y, width: r - x, height: b - y);
    }
  }

  final longest = image.width > image.height ? image.width : image.height;
  if (longest > ReceiptImageStore.maxImageSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: ReceiptImageStore.maxImageSide)
        : img.copyResize(image, height: ReceiptImageStore.maxImageSide);
  }

  File(job.imagePath).writeAsBytesSync(img.encodeJpg(image, quality: 88));
  final thumb = img.copyResize(
    image,
    width: ReceiptImageStore.thumbWidth,
    interpolation: img.Interpolation.average,
  );
  File(job.thumbPath).writeAsBytesSync(img.encodeJpg(thumb, quality: 80));
}

img.Image _centerCropToAspect(img.Image image, double aspect) {
  final current = image.width / image.height;
  if ((current - aspect).abs() < 0.01) return image;
  if (current > aspect) {
    final w = (image.height * aspect).round();
    return img.copyCrop(
      image,
      x: (image.width - w) ~/ 2,
      y: 0,
      width: w,
      height: image.height,
    );
  }
  final h = (image.width / aspect).round();
  return img.copyCrop(
    image,
    x: 0,
    y: (image.height - h) ~/ 2,
    width: image.width,
    height: h,
  );
}
