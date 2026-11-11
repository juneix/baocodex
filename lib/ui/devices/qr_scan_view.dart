import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../theme/app_theme.dart';

/// The camera config for reading pairing codes. A pairing code is dense
/// (version 13 and up) and small on the desktop's screen, about 4 cm across:
/// close enough to fill the frame at 1x, most phones cannot focus. So the
/// camera starts at 2x — the sensor crop keeps the detail, and the phone
/// stays at a distance it focuses at — frames are analysed every 100 ms
/// rather than 250, and auto zoom closes in further on a code seen too small.
MobileScannerController createPairingScannerController() =>
    MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
      cameraResolution: const Size(1920, 1080),
      detectionTimeoutMs: 100,
      autoZoom: true,
      initialZoom: pairingInitialZoom,
    );

/// A zoom ratio (over 1) on Android, where it is read as such.
const pairingInitialZoom = 2.0;

/// A live camera preview with rounded corner brackets, for scanning inline.
/// Pinching zooms the camera.
class QrScanView extends StatefulWidget {
  const QrScanView({
    super.key,
    required this.controller,
    required this.onDetect,
    required this.tr,
    required this.bracketColor,
    this.foreign = false,
  });
  final MobileScannerController controller;
  final void Function(BarcodeCapture capture) onDetect;
  final String Function(String zh, String en) tr;
  final Color bracketColor;

  /// A code that is not a BaoCode pairing link was seen.
  final bool foreign;

  @override
  State<QrScanView> createState() => _QrScanViewState();
}

class _QrScanViewState extends State<QrScanView> {
  /// The linear zoom (0–1) when the pinch began.
  double _pinchFrom = 0;

  @override
  Widget build(BuildContext context) {
    final tr = widget.tr;
    return GestureDetector(
      // One finger still scrolls the page: a pan has to go further than a
      // scroll before this claims it, a pinch does not.
      onScaleStart: (_) => _pinchFrom = widget.controller.value.zoomScale,
      onScaleUpdate: (details) {
        if (details.pointerCount < 2) return;
        final zoom = (_pinchFrom + (details.scale - 1) * .5).clamp(0.0, 1.0);
        unawaited(
          widget.controller.setZoomScale(zoom).catchError((Object _) {}),
        );
      },
      child: _view(tr),
    );
  }

  Widget _view(String Function(String zh, String en) tr) => Stack(
    fit: StackFit.expand,
    children: [
      MobileScanner(
        controller: widget.controller,
        onDetect: widget.onDetect,
        tapToFocus: true,
        errorBuilder: (context, error) => ScanPlaceholder(
          message: error.errorCode == MobileScannerErrorCode.permissionDenied
              ? tr(
                  '没有相机权限。可在系统设置中允许，或改为粘贴配对链接。',
                  'No camera access. Allow it in system settings, or paste the pairing link instead.',
                )
              : tr(
                  '相机无法启动。可改为粘贴配对链接。',
                  'The camera could not start. Paste the pairing link instead.',
                ),
        ),
      ),
      IgnorePointer(
        child: CustomPaint(
          painter: ScanBracketsPainter(color: widget.bracketColor),
        ),
      ),
      if (widget.foreign)
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(MobileSpace.md),
            child: Text(
              tr('这不是 BaoCode 配对码', 'This is not a BaoCode pairing code'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: MobileType.secondary,
                color: Colors.white,
              ),
            ),
          ),
        ),
    ],
  );
}

/// A dark box with an optional message: the camera's error, or the demo stand-in.
class ScanPlaceholder extends StatelessWidget {
  const ScanPlaceholder({super.key, this.message});
  final String? message;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: message == null
        ? null
        : Center(
            child: Padding(
              padding: const EdgeInsets.all(MobileSpace.lg),
              child: Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: MobileType.secondary,
                  color: Colors.white,
                ),
              ),
            ),
          ),
  );
}

/// Rounded brackets at the four corners of the box.
class ScanBracketsPainter extends CustomPainter {
  const ScanBracketsPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 14.0;
    const arm = 28.0;
    const radius = 12.0;
    final frame = Rect.fromLTRB(
      inset,
      inset,
      size.width - inset,
      size.height - inset,
    );
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path();
    for (final (x, y, dx, dy) in [
      (frame.left, frame.top, 1.0, 1.0),
      (frame.right, frame.top, -1.0, 1.0),
      (frame.left, frame.bottom, 1.0, -1.0),
      (frame.right, frame.bottom, -1.0, -1.0),
    ]) {
      path
        ..moveTo(x, y + dy * arm)
        ..lineTo(x, y + dy * radius)
        ..arcToPoint(
          Offset(x + dx * radius, y),
          radius: const Radius.circular(radius),
          clockwise: dx * dy > 0,
        )
        ..lineTo(x + dx * arm, y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(ScanBracketsPainter oldDelegate) =>
      oldDelegate.color != color;
}
