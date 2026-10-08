import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_scope.dart';
import '../../services/receipt_scanner.dart';
import '../widgets/crop_overlay.dart';
import 'review_screen.dart';

/// Live viewfinder with flash toggle, tap-to-focus and a receipt framing
/// overlay. The captured photo is cropped to the frame before OCR.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  String? _error;
  bool _processing = false;
  FlashMode _flash = FlashMode.off;
  Offset? _focusPoint;
  int _focusTick = 0;
  Timer? _focusTimer;
  Size? _previewSize;

  static const _flashCycle = [
    FlashMode.off,
    FlashMode.auto,
    FlashMode.always,
    FlashMode.torch,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    // The camera is an exclusive resource: release it when backgrounded and
    // re-acquire it on resume, as required by the camera plugin.
    if (state == AppLifecycleState.inactive) {
      if (controller == null || !controller.value.isInitialized) return;
      _controller = null;
      controller.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    setState(() => _error = null);
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera found on this device.');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      await _try(() => controller.setFlashMode(_flash));
      await _try(() => controller.setFocusMode(FocusMode.auto));
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } on CameraException catch (e) {
      setState(
        () => _error = switch (e.code) {
          'CameraAccessDenied' ||
          'CameraAccessDeniedWithoutPrompt' ||
          'CameraAccessRestricted' =>
            'Camera permission was denied. Enable it in system settings, '
                'or import a receipt photo from the gallery.',
          _ => 'Could not start the camera (${e.description ?? e.code}).',
        },
      );
    }
  }

  /// Some devices do not support focus/flash controls; ignore those errors.
  Future<void> _try(Future<void> Function() action) async {
    try {
      await action();
    } on CameraException catch (e) {
      debugPrint('Camera control not supported: ${e.code}');
    }
  }

  Future<void> _cycleFlash() async {
    final controller = _controller;
    if (controller == null) return;
    final next =
        _flashCycle[(_flashCycle.indexOf(_flash) + 1) % _flashCycle.length];
    await _try(() => controller.setFlashMode(next));
    setState(() => _flash = next);
  }

  Future<void> _focusAt(Offset local, Size size) async {
    final controller = _controller;
    if (controller == null) return;
    final point = Offset(
      (local.dx / size.width).clamp(0.0, 1.0),
      (local.dy / size.height).clamp(0.0, 1.0),
    );
    setState(() {
      _focusPoint = local;
      _focusTick++;
    });
    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _focusPoint = null);
    });
    await _try(() => controller.setFocusPoint(point));
    await _try(() => controller.setExposurePoint(point));
  }

  Future<void> _capture(Size previewSize) async {
    final controller = _controller;
    if (controller == null || _processing || controller.value.isTakingPicture) {
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _processing = true);
    try {
      final shot = await controller.takePicture();
      if (_flash == FlashMode.torch) {
        await _try(() => controller.setFlashMode(FlashMode.off));
        _flash = FlashMode.off;
      }
      await _process(
        shot.path,
        crop: frameFractions(previewSize),
        previewAspect: previewSize.width / previewSize.height,
      );
      unawaited(File(shot.path).delete().catchError((_) => File(shot.path)));
    } on CameraException catch (e) {
      _fail('Capture failed: ${e.description ?? e.code}');
    }
  }

  Future<void> _pickFromGallery() async {
    if (_processing) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _processing = true);
    await _process(picked.path);
  }

  Future<void> _process(
    String path, {
    Rect? crop,
    double? previewAspect,
  }) async {
    final scope = AppScope.read(context);
    try {
      final outcome = await scanReceipt(
        images: scope.images,
        ocr: scope.ocr,
        parser: scope.parser,
        sourcePath: path,
        crop: crop,
        previewAspect: previewAspect,
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ReviewScreen(
            initial: outcome.draft,
            parsed: outcome.parsed,
            ocrTime: outcome.ocrTime,
          ),
        ),
      );
    } catch (e) {
      _fail('Could not read the receipt: $e');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _processing = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _manualEntry() {
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => ReviewScreen.manual()));
  }

  IconData get _flashIcon => switch (_flash) {
    FlashMode.off => Icons.flash_off_rounded,
    FlashMode.auto => Icons.flash_auto_rounded,
    FlashMode.always => Icons.flash_on_rounded,
    FlashMode.torch => Icons.flashlight_on_rounded,
  };

  String get _flashLabel => switch (_flash) {
    FlashMode.off => 'Flash off',
    FlashMode.auto => 'Flash auto',
    FlashMode.always => 'Flash on',
    FlashMode.torch => 'Torch',
  };

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _topBar(),
                  Expanded(child: _viewfinder(accent)),
                  _bottomBar(accent),
                ],
              ),
              if (_processing) const _ProcessingOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Close',
          color: Colors.white,
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const Expanded(
          child: Text(
            'Align the receipt inside the frame',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
        IconButton(
          tooltip: _flashLabel,
          color: _flash == FlashMode.off ? Colors.white : Colors.amber,
          icon: Icon(_flashIcon),
          onPressed: _controller == null ? null : _cycleFlash,
        ),
      ],
    ),
  );

  Widget _viewfinder(Color accent) {
    final controller = _controller;
    if (_error != null) {
      return _CameraError(
        message: _error!,
        onRetry: _initCamera,
        onGallery: _pickFromGallery,
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    // Portrait: the sensor's landscape aspect ratio is inverted.
    final aspect = 1 / controller.value.aspectRatio;
    return Center(
      child: AspectRatio(
        aspectRatio: aspect,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            _previewSize = size;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _focusAt(d.localPosition, size),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRect(child: CameraPreview(controller)),
                  CustomPaint(painter: CropOverlayPainter(accent: accent)),
                  if (_focusPoint != null)
                    Positioned(
                      left: _focusPoint!.dx - 32,
                      top: _focusPoint!.dy - 32,
                      child: _FocusRing(key: ValueKey(_focusTick)),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _bottomBar(Color accent) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          onPressed: _processing ? null : _pickFromGallery,
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Gallery'),
        ),
        _ShutterButton(
          enabled: !_processing && _controller != null,
          onPressed: () {
            final size = _previewSize;
            if (size != null) _capture(size);
          },
        ),
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          onPressed: _processing ? null : _manualEntry,
          icon: const Icon(Icons.edit_note_rounded),
          label: const Text('Manual'),
        ),
      ],
    ),
  );
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Capture receipt',
      child: GestureDetector(
        onTap: enabled ? onPressed : null,
        child: Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          padding: const EdgeInsets.all(5),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: enabled ? Colors.white : Colors.white38,
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusRing extends StatelessWidget {
  const _FocusRing({super.key});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.5, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.amber, width: 2),
        ),
      ),
    );
  }
}

class _ProcessingOverlay extends StatelessWidget {
  const _ProcessingOverlay();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Reading receipt on-device…',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({
    required this.message,
    required this.onRetry,
    required this.onGallery,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              color: Colors.white70,
              size: 56,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              children: [
                OutlinedButton(
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
                FilledButton.icon(
                  onPressed: onGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Pick from gallery'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
