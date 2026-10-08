// Renders the real app screens with sample data into docs/screenshots/.
//
//   flutter test screenshot_test --update-goldens
//
// Not part of the normal `flutter test` run: font rasterisation differs
// between operating systems, so these images are documentation, not
// regression goldens. The camera is replaced by a fake CameraPlatform whose
// "preview" is a synthetic receipt photo; ML Kit is not available on the
// host, so the review screen is fed by running ReceiptParser over the
// receipt's text.
import 'dart:async';
import 'dart:io';
import 'dart:math' show Point;
import 'dart:ui' as ui;

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:expense_ocr/data/expense_repository.dart';
import 'package:expense_ocr/data/receipt_image_store.dart';
import 'package:expense_ocr/main.dart';
import 'package:expense_ocr/models/expense.dart';
import 'package:expense_ocr/models/expense_category.dart';
import 'package:expense_ocr/services/ocr_service.dart';
import 'package:expense_ocr/services/receipt_parser.dart';
import 'package:expense_ocr/state/expense_store.dart';
import 'package:expense_ocr/ui/screens/camera_screen.dart';
import 'package:expense_ocr/ui/screens/home_shell.dart';
import 'package:expense_ocr/ui/screens/review_screen.dart';
import 'package:expense_ocr/ui/widgets/crop_overlay.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

final now = DateTime(2026, 10, 8, 19, 5);

const receiptLines = [
  'CO.OPMART HAI CHAU',
  '478 Dien Bien Phu, Da Nang',
  'DT: 0236 3888 999',
  'HOA DON BAN HANG',
  'Ngay: 08/10/2026 18:42',
  'Sua tuoi Vinamilk 1L  2 x 32.000  64.000',
  'Banh mi sandwich  1 x 25.000  25.000',
  'Tao Envy  1 x 61.000  61.000',
  'TONG CONG  150.000 d',
  'Tien khach dua  200.000',
  'Tien thua  50.000',
  'Cam on quy khach!',
];

Future<void> loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? r'E:\Flutter\flutter';
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<ByteData> read(String f) async =>
      ByteData.sublistView(await File('$dir/$f').readAsBytes());
  final roboto = FontLoader('Roboto');
  for (final f in [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-black.ttf',
  ]) {
    roboto.addFont(read(f));
  }
  await roboto.load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(read('materialicons-regular.otf'))).load();
}

/// A phone photo of a thermal receipt lying on a desk (1080×1920).
Uint8List buildReceiptPhoto() {
  final photo = img.Image(width: 1080, height: 1920);
  img.fill(photo, color: img.ColorRgb8(58, 48, 40));
  // Paper with a soft shadow.
  img.fillRect(
    photo,
    x1: 178,
    y1: 214,
    x2: 916,
    y2: 1660,
    color: img.ColorRgb8(35, 28, 22),
  );
  img.fillRect(
    photo,
    x1: 170,
    y1: 200,
    x2: 906,
    y2: 1648,
    color: img.ColorRgb8(246, 243, 235),
  );

  final big = img.arial48, font = img.arial24;
  final ink = img.ColorRgb8(40, 40, 40);
  int width(img.BitmapFont f, String s) =>
      s.codeUnits.fold(0, (w, c) => w + (f.characters[c]?.xAdvance ?? 0));
  void center(String s, int y, img.BitmapFont f) => img.drawString(
    photo,
    s,
    font: f,
    x: 538 - width(f, s) ~/ 2,
    y: y,
    color: ink,
  );
  void row(String left, String right, int y, {img.BitmapFont? f}) {
    f ??= font;
    img.drawString(photo, left, font: f, x: 210, y: y, color: ink);
    img.drawString(
      photo,
      right,
      font: f,
      x: 866 - width(f, right),
      y: y,
      color: ink,
    );
  }

  void rule(int y) => img.drawLine(
    photo,
    x1: 210,
    y1: y,
    x2: 866,
    y2: y,
    color: img.ColorRgb8(150, 150, 150),
  );

  center('CO.OPMART HAI CHAU', 270, big);
  center('478 Dien Bien Phu, Da Nang', 350, font);
  center('DT: 0236 3888 999', 390, font);
  center('HOA DON BAN HANG', 470, big);
  row('Ngay: 08/10/2026 18:42', 'Quay 03', 560);
  rule(615);
  row('Sua tuoi Vinamilk 1L', '', 650);
  row('   2 x 32.000', '64.000', 690);
  row('Banh mi sandwich', '', 740);
  row('   1 x 25.000', '25.000', 780);
  row('Tao Envy', '', 830);
  row('   1 x 61.000', '61.000', 870);
  rule(930);
  row('TONG CONG', '150.000 d', 970, f: big);
  row('Tien khach dua', '200.000', 1060);
  row('Tien thua', '50.000', 1100);
  rule(1160);
  center('Cam on quy khach!', 1210, font);
  center('Hen gap lai', 1250, font);
  for (var x = 300; x < 780; x += 12) {
    img.fillRect(
      photo,
      x1: x,
      y1: 1330,
      x2: x + (x % 36 == 0 ? 7 : 3),
      y2: 1440,
      color: ink,
    );
  }
  return img.encodeJpg(photo, quality: 90);
}

// screenshot_test/ is a test directory, but the analyzer only treats test/ as one.
// ignore: invalid_use_of_visible_for_testing_member
class FakeCamera extends CameraPlatform with MockPlatformInterfaceMixin {
  FakeCamera(this.preview);

  final Widget preview;
  final _initialized = StreamController<CameraInitializedEvent>.broadcast();
  final _errors = StreamController<CameraErrorEvent>.broadcast();

  @override
  Future<List<CameraDescription>> availableCameras() async => const [
    CameraDescription(
      name: 'back',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
  ];

  @override
  Future<int> createCameraWithSettings(
    CameraDescription description,
    MediaSettings? settings,
  ) async => 1;

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    scheduleMicrotask(
      () => _initialized.add(
        CameraInitializedEvent(
          cameraId,
          1920,
          1080,
          ExposureMode.auto,
          true,
          FocusMode.auto,
          true,
        ),
      ),
    );
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      _initialized.stream;

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => _errors.stream;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  Widget buildPreview(int cameraId) => preview;

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {}

  @override
  Future<void> setFocusMode(int cameraId, FocusMode mode) async {}

  @override
  Future<void> setFocusPoint(int cameraId, Point<double>? point) async {}

  @override
  Future<void> setExposurePoint(int cameraId, Point<double>? point) async {}

  @override
  Future<void> dispose(int cameraId) async {}
}

List<Expense> sampleExpenses() {
  Expense e(
    String m,
    double a,
    ExpenseCategory c,
    DateTime d, {
    String? image,
    String? thumb,
  }) => Expense(
    merchant: m,
    amount: a,
    category: c,
    date: d,
    imageFile: image,
    thumbFile: thumb,
    createdAt: d,
  );
  return [
    e('Bách Hóa Xanh', 240000, ExpenseCategory.food, DateTime(2026, 9, 28, 18)),
    e(
      'Lotte Cinema',
      160000,
      ExpenseCategory.entertainment,
      DateTime(2026, 9, 29, 20),
    ),
    e(
      'Nhà sách Phương Nam',
      95000,
      ExpenseCategory.study,
      DateTime(2026, 10, 1, 10),
    ),
    e('Petrolimex', 80000, ExpenseCategory.travel, DateTime(2026, 10, 2, 7)),
    e('WinMart', 210000, ExpenseCategory.food, DateTime(2026, 10, 3, 17)),
    e('Circle K', 32000, ExpenseCategory.food, DateTime(2026, 10, 5, 9)),
    e('GearVN', 390000, ExpenseCategory.gear, DateTime(2026, 10, 5, 15)),
    e('Bún bò Cô Ba', 55000, ExpenseCategory.food, DateTime(2026, 10, 6, 12)),
    e('CGV', 180000, ExpenseCategory.entertainment, DateTime(2026, 10, 6, 21)),
    e('Grab', 62000, ExpenseCategory.travel, DateTime(2026, 10, 7, 8)),
    e('Fahasa', 128000, ExpenseCategory.study, DateTime(2026, 10, 7, 16)),
    e(
      'Highlands Coffee',
      45000,
      ExpenseCategory.food,
      DateTime(2026, 10, 8, 8),
    ),
  ];
}

void main() {
  late Directory tmp;
  late ReceiptImageStore images;
  late Uint8List photo;

  setUpAll(() async {
    await loadFonts();
    tmp = await Directory.systemTemp.createTemp('shots');
    images = ReceiptImageStore(tmp.path);
    photo = buildReceiptPhoto();
  });

  tearDownAll(() => tmp.delete(recursive: true));

  Future<ExpenseStore> makeStore(
    WidgetTester tester, {
    List<Expense> extra = const [],
  }) async {
    final store = ExpenseStore(
      InMemoryExpenseRepository([...sampleExpenses(), ...extra]),
      images: images,
    );
    await store.load();
    return store;
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
  }

  // flutter_test paints shadows as solid black unless this is turned off;
  // it must be restored before the test body ends.
  Future<void> shoot(WidgetTester tester, String name) => expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('../docs/screenshots/$name.png'),
  );

  void testShot(String name, Future<void> Function(WidgetTester) body) =>
      testWidgets(name, (tester) async {
        debugDisableShadows = false;
        try {
          await body(tester);
        } finally {
          debugDisableShadows = true;
        }
      });

  testShot('dashboard', (tester) async {
    phone(tester);
    final store = await makeStore(tester);
    await tester.pumpWidget(
      ExpenseApp(
        store: store,
        images: images,
        ocr: OcrService(),
        home: HomeShell(now: now),
      ),
    );
    await tester.pumpAndSettle();
    // Select a slice to show the interaction state.
    await tester.tap(find.text('Gear'));
    await tester.pumpAndSettle();
    await shoot(tester, '01_dashboard');

    await tester.drag(find.byType(ListView).first, const Offset(0, -560));
    await tester.pumpAndSettle();
    final bars = tester.getRect(
      find
          .byType(CustomPaint)
          .at(
            find
                .byType(CustomPaint)
                .evaluate()
                .toList()
                .indexWhere(
                  (e) =>
                      e.widget is CustomPaint &&
                      (e.widget as CustomPaint).painter.runtimeType
                              .toString() ==
                          '_BarPainter',
                ),
          ),
    );
    final slot = (bars.width - 44) / 7;
    await tester.tapAt(Offset(bars.left + 40 + slot * 0.5, bars.center.dy));
    await tester.pumpAndSettle();
    await shoot(tester, '02_dashboard_weekly');
  });

  testShot('dashboard dark', (tester) async {
    phone(tester);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final store = await makeStore(tester);
    await tester.pumpWidget(
      ExpenseApp(
        store: store,
        images: images,
        ocr: OcrService(),
        home: HomeShell(now: now),
      ),
    );
    await tester.pumpAndSettle();
    await shoot(tester, '06_dashboard_dark');
  });

  testShot('history', (tester) async {
    phone(tester);
    final store = await makeStore(tester);
    await tester.pumpWidget(
      ExpenseApp(
        store: store,
        images: images,
        ocr: OcrService(),
        home: HomeShell(now: now, initialTab: 1),
      ),
    );
    await tester.pumpAndSettle();
    await shoot(tester, '05_history');
  });

  testShot('camera', (tester) async {
    phone(tester);
    CameraPlatform.instance = FakeCamera(
      SizedBox.expand(
        child: Image.memory(photo, fit: BoxFit.cover, gaplessPlayback: true),
      ),
    );
    final store = await makeStore(tester);
    await tester.pumpWidget(
      ExpenseApp(
        store: store,
        images: images,
        ocr: OcrService(),
        home: const CameraScreen(),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.runAsync(() async {
      final ctx = tester.element(find.byType(CameraScreen));
      await precacheImage(MemoryImage(photo), ctx);
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Tap to focus near the total line.
    final preview = tester.getRect(find.byType(AspectRatio).first);
    await tester.tapAt(
      Offset(preview.center.dx + 60, preview.top + preview.height * 0.5),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await shoot(tester, '03_camera');
    await tester.pump(const Duration(seconds: 2));
  });

  testShot('review', (tester) async {
    phone(tester);
    final store = await makeStore(tester);
    // Same crop the camera screen applies: frame fractions of a 9:16 preview.
    final previewSize = const Size(411, 731);
    late StoredReceipt stored;
    await tester.runAsync(() async {
      final src = File('${tmp.path}/capture.jpg')..writeAsBytesSync(photo);
      stored = await images.saveReceipt(
        src.path,
        crop: frameFractions(previewSize),
        previewAspect: previewSize.width / previewSize.height,
      );
    });
    final parsed = const ReceiptParser().parse(receiptLines, now: now);
    final draft = Expense(
      merchant: parsed.merchant!,
      amount: parsed.total!,
      category: parsed.category,
      date: parsed.date!,
      imageFile: stored.imageFile,
      thumbFile: stored.thumbFile,
      rawText: receiptLines.join('\n'),
      createdAt: now,
    );
    // File I/O started inside the fake-async test zone never completes, so
    // decode the cropped receipt for real and seed the image cache with the
    // exact key Image.file(cacheWidth: 900) will look up.
    final provider = ResizeImage(
      FileImage(images.resolve(stored.imageFile)),
      width: 900,
    );
    final key = await provider.obtainKey(ImageConfiguration.empty);
    late ui.Image decoded;
    await tester.runAsync(() async {
      final bytes = await images.resolve(stored.imageFile).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 900);
      decoded = (await codec.getNextFrame()).image;
    });
    imageCache.putIfAbsent(
      key,
      () => OneFrameImageStreamCompleter(
        SynchronousFuture(ImageInfo(image: decoded)),
      ),
    );
    await tester.pumpWidget(
      ExpenseApp(
        store: store,
        images: images,
        ocr: OcrService(),
        home: ReviewScreen(initial: draft, parsed: parsed),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await shoot(tester, '04_review');
  });
}
