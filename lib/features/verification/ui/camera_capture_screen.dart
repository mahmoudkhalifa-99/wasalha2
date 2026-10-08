import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_text.dart';
import '../domain/image_quality.dart';

/// شكل الإطار الإرشادي فوق المعاينة.
enum CaptureFrame { card, document, face, none }

class CaptureSpec {
  final String title;
  final String instruction;
  final CaptureFrame frame;
  final bool useFrontCamera;
  final QualityThresholds thresholds;

  const CaptureSpec({
    required this.title,
    required this.instruction,
    this.frame = CaptureFrame.card,
    this.useFrontCamera = false,
    this.thresholds = const QualityThresholds(),
  });
}

class CaptureResult {
  final Uint8List jpegBytes;
  final QualityReport quality;
  const CaptureResult(this.jpegBytes, this.quality);
}

/// يفتح الكاميرا ويرجّع الصورة بعد فحص الجودة، أو null لو اتلغى.
/// مفيش اختيار من المعرض: الصورة بتتصوّر من الكاميرا مباشرة. (ده تقليل لمخاطر الصور القديمة
/// وليس حماية كافية: ممكن تصوير صورة من شاشة تانية، فالمراجعة البشرية هي القرار.)
Future<CaptureResult?> captureDocument(BuildContext context, CaptureSpec spec) {
  return Navigator.of(context).push<CaptureResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CameraCaptureScreen(spec: spec),
    ),
  );
}

// ───────── معالجة الصورة (Isolate) ─────────

class _ProcessArgs {
  final Uint8List bytes;
  final double? cropLeft, cropTop, cropW, cropH; // نسب 0..1 من المعاينة
  const _ProcessArgs(this.bytes, this.cropLeft, this.cropTop, this.cropW, this.cropH);
}

Uint8List _process(_ProcessArgs a) {
  var image = img.decodeImage(a.bytes);
  if (image == null) return a.bytes;
  image = img.bakeOrientation(image);
  if (a.cropW != null) {
    final x = (a.cropLeft! * image.width).round().clamp(0, image.width - 1);
    final y = (a.cropTop! * image.height).round().clamp(0, image.height - 1);
    final w = (a.cropW! * image.width).round().clamp(1, image.width - x);
    final h = (a.cropH! * image.height).round().clamp(1, image.height - y);
    image = img.copyCrop(image, x: x, y: y, width: w, height: h);
  }
  const maxSide = 2400;
  final longSide = math.max(image.width, image.height);
  if (longSide > maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxSide)
        : img.copyResize(image, height: maxSide);
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 88));
}

class CameraCaptureScreen extends StatefulWidget {
  final CaptureSpec spec;
  const CameraCaptureScreen({super.key, required this.spec});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _initializing = true;
  bool _busy = false;
  String? _error;
  bool _permanentlyDenied = false;

  // نتيجة اللقطة الأخيرة (للمراجعة قبل القبول)
  Uint8List? _shot;
  QualityReport? _report;

  CaptureSpec get spec => widget.spec;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed && _shot == null) {
      _init();
    }
  }

  Future<void> _init() async {
    setState(() {
      _initializing = true;
      _error = null;
    });
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        setState(() {
          _permanentlyDenied = status.isPermanentlyDenied;
          _error = 'محتاجين إذن الكاميرا عشان نصوّر المستند.';
          _initializing = false;
        });
        return;
      }
      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() {
          _error = 'لا توجد كاميرا متاحة على الجهاز.';
          _initializing = false;
        });
        return;
      }
      final want = spec.useFrontCamera ? CameraLensDirection.front : CameraLensDirection.back;
      final cam = cams.firstWhere((c) => c.lensDirection == want, orElse: () => cams.first);
      final controller = CameraController(
        cam,
        spec.frame == CaptureFrame.face ? ResolutionPreset.high : ResolutionPreset.ultraHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await _controller?.dispose();
      setState(() {
        _controller = controller;
        _initializing = false;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذر تشغيل الكاميرا (${e.code}).';
        _initializing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذر تشغيل الكاميرا.';
        _initializing = false;
      });
    }
  }

  /// مستطيل الإطار كنسب من مساحة المعاينة (يمين/أعلى/عرض/ارتفاع).
  Rect? _frameFractions(double previewW, double previewH) {
    switch (spec.frame) {
      case CaptureFrame.card:
      case CaptureFrame.document:
        final ratio = spec.frame == CaptureFrame.card ? kCardAspect : 1.4;
        final w = 0.9;
        final hPx = previewW * w / ratio;
        final h = math.min(0.9, hPx / previewH);
        return Rect.fromLTWH((1 - w) / 2, (1 - h) / 2, w, h);
      case CaptureFrame.face:
      case CaptureFrame.none:
        return null; // بنحتفظ بالصورة كاملة
    }
  }

  Future<void> _shoot() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await c.takePicture();
      final raw = await file.readAsBytes();
      // نسب الإطار بتتحسب على أبعاد المعاينة (portrait): العرض = 1 / aspectRatio.
      final ar = c.value.aspectRatio; // landscape (عرض/ارتفاع) للسنسور
      final pw = 1.0;
      final ph = ar; // نسبة الارتفاع للعرض في وضع portrait
      final fr = _frameFractions(pw, ph);
      final processed = await compute(
        _process,
        _ProcessArgs(raw, fr?.left, fr?.top, fr?.width, fr?.height),
      );
      final report = await analyzeImageQuality(
        processed,
        expectCardAspect: spec.frame == CaptureFrame.card,
        thresholds: spec.thresholds,
      );
      if (!mounted) return;
      setState(() {
        _shot = processed;
        _report = report;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'تعذر التقاط الصورة. حاول مرة تانية.';
      });
    }
  }

  void _retake() => setState(() {
        _shot = null;
        _report = null;
        _error = null;
      });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: _shot != null ? _reviewBody() : _cameraBody(),
        ),
      ),
    );
  }

  Widget _topBar() => Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Colors.white),
            ),
            Expanded(
              child: Text(spec.title,
                  textAlign: TextAlign.center,
                  style: T.s(16, T.w900, Colors.white)),
            ),
            const SizedBox(width: 48),
          ],
        ),
      );

  Widget _cameraBody() {
    if (_initializing) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    final c = _controller;
    if (_error != null && (c == null || !c.value.isInitialized)) {
      return Column(
        children: [
          _topBar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: T.s(15, T.w900, Colors.white)),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _permanentlyDenied ? openAppSettings : _init,
                      child: Text(_permanentlyDenied ? 'فتح الإعدادات' : 'إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }
    if (c == null || !c.value.isInitialized) return const SizedBox.shrink();

    return Column(
      children: [
        _topBar(),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1 / c.value.aspectRatio,
              child: LayoutBuilder(builder: (context, box) {
                final fr = _frameFractions(box.maxWidth, box.maxHeight);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreview(c),
                    CustomPaint(
                      painter: _FramePainter(
                        spec.frame,
                        fr == null
                            ? null
                            : Rect.fromLTWH(fr.left * box.maxWidth, fr.top * box.maxHeight,
                                fr.width * box.maxWidth, fr.height * box.maxHeight),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
        Container(
          color: Colors.black,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            children: [
              Text(spec.instruction,
                  textAlign: TextAlign.center,
                  style: T.s(13, T.w700, Colors.white70, height: 1.6)),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: _busy ? null : _shoot,
                child: Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  padding: const EdgeInsets.all(6),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _busy ? Colors.white38 : Colors.white,
                    ),
                    child: _busy
                        ? const Padding(
                            padding: EdgeInsets.all(18),
                            child: CircularProgressIndicator(strokeWidth: 3),
                          )
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _reviewBody() {
    final r = _report!;
    final failed = !r.passed;
    return Column(
      children: [
        _topBar(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(_shot!, fit: BoxFit.contain),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          color: Colors.black,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (failed) ...[
                Text(kRetakeMessage,
                    textAlign: TextAlign.center,
                    style: T.s(15, T.w900, C.rose500)),
                const SizedBox(height: 6),
                Text(
                    [for (final f in r.failures) kQualityFailureLabels[f] ?? f].join(' • '),
                    textAlign: TextAlign.center,
                    style: T.s(12, T.w700, Colors.white70)),
              ] else
                Text(
                    r.warnings.isEmpty
                        ? 'الصورة مقبولة. اتأكد إن كل البيانات مقروءة.'
                        : 'الصورة مقبولة، لكن لو تقدر تحسّن الإضاءة أو الوضوح أعد التصوير.',
                    textAlign: TextAlign.center,
                    style: T.s(13, T.w700, Colors.white70)),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _retake,
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                          padding: const EdgeInsets.symmetric(vertical: 16)),
                      child: const Text('إعادة التصوير'),
                    ),
                  ),
                  if (!failed) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () =>
                            Navigator.of(context).pop(CaptureResult(_shot!, r)),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: C.emerald600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16)),
                        child: const Text('استخدام الصورة'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FramePainter extends CustomPainter {
  final CaptureFrame frame;
  final Rect? rect;
  _FramePainter(this.frame, this.rect);

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = Colors.black54;
    final line = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final full = Path()..addRect(Offset.zero & size);
    if (rect != null) {
      final hole = Path()..addRRect(RRect.fromRectAndRadius(rect!, const Radius.circular(14)));
      canvas.drawPath(Path.combine(PathOperation.difference, full, hole), dim);
      canvas.drawRRect(RRect.fromRectAndRadius(rect!, const Radius.circular(14)), line);
    } else if (frame == CaptureFrame.face) {
      final oval = Rect.fromCenter(
          center: Offset(size.width / 2, size.height * 0.45),
          width: size.width * 0.7,
          height: size.height * 0.5);
      final hole = Path()..addOval(oval);
      canvas.drawPath(Path.combine(PathOperation.difference, full, hole), dim);
      canvas.drawOval(oval, line);
    }
  }

  @override
  bool shouldRepaint(covariant _FramePainter old) => old.rect != rect || old.frame != frame;
}
