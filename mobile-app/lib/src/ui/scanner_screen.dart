import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/models.dart';
import '../services/app_controller.dart';
import '../services/connection_service.dart';
import 'theme.dart';
import 'widgets.dart';

enum ScannerMode { scan, pair }

const List<BarcodeFormat> kScanFormats = [
  BarcodeFormat.ean13,
  BarcodeFormat.ean8,
  BarcodeFormat.upcA,
  BarcodeFormat.upcE,
  BarcodeFormat.code128,
  BarcodeFormat.code39,
  BarcodeFormat.code93,
  BarcodeFormat.itf14,
  BarcodeFormat.codabar,
  BarcodeFormat.qrCode,
  BarcodeFormat.dataMatrix,
  BarcodeFormat.pdf417,
  BarcodeFormat.aztec,
];

String wireFormat(BarcodeFormat f) => switch (f) {
  BarcodeFormat.ean13 => 'ean13',
  BarcodeFormat.ean8 => 'ean8',
  BarcodeFormat.upcA => 'upc_a',
  BarcodeFormat.upcE => 'upc_e',
  BarcodeFormat.code128 => 'code128',
  BarcodeFormat.code39 => 'code39',
  BarcodeFormat.code93 => 'code93',
  BarcodeFormat.itf14 => 'itf',
  BarcodeFormat.codabar => 'codabar',
  BarcodeFormat.qrCode => 'qr_code',
  BarcodeFormat.dataMatrix => 'data_matrix',
  BarcodeFormat.pdf417 => 'pdf417',
  BarcodeFormat.aztec => 'aztec',
  _ => f.name,
};

String formatLabel(String wire) => switch (wire) {
  'ean13' => 'EAN-13',
  'ean8' => 'EAN-8',
  'upc_a' => 'UPC-A',
  'upc_e' => 'UPC-E',
  'code128' => 'Code 128',
  'code39' => 'Code 39',
  'code93' => 'Code 93',
  'itf' => 'ITF',
  'codabar' => 'Codabar',
  'qr_code' => 'QR',
  'data_matrix' => 'DataMatrix',
  'pdf417' => 'PDF417',
  'aztec' => 'Aztec',
  _ => wire.toUpperCase(),
};

/// Edge-to-edge camera scanner. In [ScannerMode.pair] it pops with the
/// [DesktopTarget] encoded in a desktop pairing QR code.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key, required this.app, this.mode = ScannerMode.scan});

  final AppController app;
  final ScannerMode mode;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with TickerProviderStateMixin {
  late final MobileScannerController _camera = MobileScannerController(
    formats: widget.mode == ScannerMode.pair ? const [BarcodeFormat.qrCode] : kScanFormats,
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 200,
  );
  late final AnimationController _laser = AnimationController(vsync: this, duration: const Duration(milliseconds: 1900))
    ..repeat(reverse: true);
  late final AnimationController _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  Color _flashColor = AppColors.success;

  final Map<String, int> _lastSeen = {};
  ScanRecord? _last;
  int _count = 0;
  int _lastHintMs = 0;
  bool _popped = false;
  StreamSubscription<ScanEvent>? _events;

  ConnectionService get _conn => widget.app.connection;

  @override
  void initState() {
    super.initState();
    _events = _conn.events.listen((e) {
      if (!mounted) return;
      _flashColor = switch (e.record.delivery) {
        ScanDelivery.delivered => AppColors.success,
        ScanDelivery.paused || ScanDelivery.queued => AppColors.warning,
        _ => AppColors.danger,
      };
      unawaited(_flash.forward(from: 0));
      setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    _laser.dispose();
    _flash.dispose();
    unawaited(_camera.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;

      if (widget.mode == ScannerMode.pair) {
        final target = DesktopTarget.fromPairingUri(raw);
        if (target != null && !_popped) {
          _popped = true;
          unawaited(HapticFeedback.mediumImpact());
          Navigator.of(context).pop(target);
          return;
        }
        if (now - _lastHintMs > 2500) {
          _lastHintMs = now;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(content: Text('That isn\'t a BarcodeSync pairing code')));
        }
        continue;
      }

      // Duplicate guard: ignore the same code inside the cooldown window.
      final cooldown = widget.app.settings.cooldownMs;
      final seen = _lastSeen[raw];
      if (seen != null && now - seen < cooldown) continue;
      _lastSeen[raw] = now;
      _lastSeen.removeWhere((_, t) => now - t > math.max(cooldown, 1000) * 4);

      widget.app.feedback.onDetect(widget.app.settings);
      final record = _conn.sendScan(raw, wireFormat(barcode.format));
      setState(() {
        _last = record;
        _count++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pairing = widget.mode == ScannerMode.pair;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            final w = math.min(size.width * 0.8, 340.0);
            final h = pairing ? w : w * 0.72;
            final window = Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.44), width: w, height: h);
            return Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _camera,
                  onDetect: _onDetect,
                  scanWindow: window,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error) => _CameraError(error: error),
                ),
                IgnorePointer(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_laser, _flash]),
                    builder: (context, _) => CustomPaint(
                      painter: _ReticlePainter(
                        window: window,
                        laser: Curves.easeInOut.transform(_laser.value),
                        flash: 1 - _flash.value,
                        flashColor: _flashColor,
                        showFlash: _flash.isAnimating,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: window.bottom + 20,
                  child: Text(
                    pairing ? 'Scan the QR code shown in BarcodeSync on your computer' : 'Align a barcode or QR code inside the frame',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13.5, fontWeight: FontWeight.w500),
                  ),
                ),
                SafeArea(child: _topBar(context, pairing)),
                if (!pairing) _bottom(context),
                if (pairing)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SafeArea(minimum: const EdgeInsets.only(bottom: 24), child: Center(child: _torchButton())),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context, bool pairing) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          _RoundButton(icon: Icons.close_rounded, tooltip: 'Close', onTap: () => Navigator.of(context).maybePop()),
          const SizedBox(width: 10),
          Expanded(
            child: pairing
                ? const Align(
                    alignment: Alignment.centerLeft,
                    child: StatusPill(color: AppColors.accent, label: 'Pairing mode', dark: true),
                  )
                : ListenableBuilder(
                    listenable: _conn,
                    builder: (context, _) {
                      final (color, label) = switch (_conn.phase) {
                        ConnectionPhase.connected when _conn.desktopPaused => (AppColors.warning, '${_conn.desktopName} · paused'),
                        ConnectionPhase.connected => (
                          AppColors.success,
                          _conn.latencyMs == null ? _conn.desktopName : '${_conn.desktopName} · ${_conn.latencyMs} ms',
                        ),
                        ConnectionPhase.awaitingApproval => (AppColors.warning, 'Approve on ${_conn.desktopName}'),
                        ConnectionPhase.connecting || ConnectionPhase.reconnecting => (AppColors.warning, 'Reconnecting…'),
                        _ => (AppColors.danger, 'Offline — scans are queued'),
                      };
                      return Align(alignment: Alignment.centerLeft, child: StatusPill(color: color, label: label, dark: true));
                    },
                  ),
          ),
          if (!pairing) ...[
            const SizedBox(width: 10),
            _CounterBadge(count: _count),
          ],
        ],
      ),
    );
  }

  Widget _torchButton() {
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: _camera,
      builder: (context, state, _) {
        if (!state.isInitialized || state.torchState == TorchState.unavailable) return const SizedBox(width: 56, height: 56);
        final on = state.torchState == TorchState.on;
        return _RoundButton(
          icon: on ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
          tooltip: on ? 'Turn torch off' : 'Turn torch on',
          active: on,
          size: 56,
          onTap: () => unawaited(_camera.toggleTorch()),
        );
      },
    );
  }

  Widget _bottom(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        minimum: const EdgeInsets.only(bottom: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListenableBuilder(
              listenable: _conn,
              builder: (context, _) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutBack,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, 0.35), end: Offset.zero).animate(anim),
                    child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(anim), child: child),
                  ),
                ),
                child: _last == null
                    ? const SizedBox(height: 56, key: ValueKey('empty'))
                    : _LastScanPill(key: ValueKey(_last!.messageId), record: _last!, queued: _conn.queuedCount),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _torchButton(),
                const SizedBox(width: 28),
                ValueListenableBuilder<MobileScannerState>(
                  valueListenable: _camera,
                  builder: (context, state, _) {
                    final cameras = state.availableCameras;
                    if (cameras != null && cameras < 2) return const SizedBox(width: 56, height: 56);
                    return _RoundButton(
                      icon: Icons.cameraswitch_rounded,
                      tooltip: 'Switch camera',
                      size: 56,
                      onTap: state.isInitialized ? () => unawaited(_camera.switchCamera()) : null,
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReticlePainter extends CustomPainter {
  _ReticlePainter({required this.window, required this.laser, required this.flash, required this.flashColor, required this.showFlash});

  final Rect window;
  final double laser;
  final double flash;
  final Color flashColor;
  final bool showFlash;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(window, const Radius.circular(26));
    final scrim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(rrect);
    canvas.drawPath(scrim, Paint()..color = Colors.black.withValues(alpha: 0.55));

    final color = showFlash ? Color.lerp(Colors.white, flashColor, flash)! : Colors.white;
    if (showFlash) {
      canvas.drawRRect(rrect, Paint()..color = flashColor.withValues(alpha: 0.18 * flash));
    }

    // Corner brackets that "breathe" slightly with the laser.
    final inset = 2.0 + 2.0 * math.sin(laser * math.pi);
    final r = window.deflate(-inset);
    const len = 34.0;
    const rad = 26.0;
    final bracket = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    final corners = <Path>[
      Path()
        ..moveTo(r.left, r.top + len)
        ..lineTo(r.left, r.top + rad)
        ..arcToPoint(Offset(r.left + rad, r.top), radius: const Radius.circular(rad))
        ..lineTo(r.left + len, r.top),
      Path()
        ..moveTo(r.right - len, r.top)
        ..lineTo(r.right - rad, r.top)
        ..arcToPoint(Offset(r.right, r.top + rad), radius: const Radius.circular(rad))
        ..lineTo(r.right, r.top + len),
      Path()
        ..moveTo(r.right, r.bottom - len)
        ..lineTo(r.right, r.bottom - rad)
        ..arcToPoint(Offset(r.right - rad, r.bottom), radius: const Radius.circular(rad))
        ..lineTo(r.right - len, r.bottom),
      Path()
        ..moveTo(r.left + len, r.bottom)
        ..lineTo(r.left + rad, r.bottom)
        ..arcToPoint(Offset(r.left, r.bottom - rad), radius: const Radius.circular(rad))
        ..lineTo(r.left, r.bottom - len),
    ];
    for (final p in corners) {
      canvas.drawPath(p, bracket);
    }

    // Scan laser with a soft glow trail.
    final y = window.top + 14 + (window.height - 28) * laser;
    final laserRect = Rect.fromLTRB(window.left + 18, y - 1.5, window.right - 18, y + 1.5);
    final laserColor = showFlash ? flashColor : AppColors.accent;
    canvas.drawRect(
      Rect.fromLTRB(laserRect.left, y - 18, laserRect.right, y + 18),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [laserColor.withValues(alpha: 0), laserColor.withValues(alpha: 0.22), laserColor.withValues(alpha: 0)],
        ).createShader(Rect.fromLTRB(laserRect.left, y - 18, laserRect.right, y + 18)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(laserRect, const Radius.circular(2)),
      Paint()
        ..shader = LinearGradient(
          colors: [laserColor.withValues(alpha: 0), laserColor, laserColor.withValues(alpha: 0)],
        ).createShader(laserRect),
    );
  }

  @override
  bool shouldRepaint(_ReticlePainter old) =>
      old.laser != laser || old.flash != flash || old.window != window || old.showFlash != showFlash || old.flashColor != flashColor;
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.onTap, this.active = false, this.size = 44});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? Colors.white : Colors.black.withValues(alpha: 0.45),
        shape: CircleBorder(side: BorderSide(color: Colors.white.withValues(alpha: active ? 0 : 0.14))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox.square(
            dimension: size,
            child: Icon(icon, color: active ? Colors.black : Colors.white, size: size * 0.46),
          ),
        ),
      ),
    );
  }
}

class _CounterBadge extends StatelessWidget {
  const _CounterBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
            child: Text(
              '$count',
              key: ValueKey(count),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
        ],
      ),
    );
  }
}

class _LastScanPill extends StatelessWidget {
  const _LastScanPill({super.key, required this.record, required this.queued});

  final ScanRecord record;
  final int queued;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (record.delivery) {
      ScanDelivery.delivered => (Icons.check_circle_rounded, AppColors.success, 'Sent'),
      ScanDelivery.sending => (Icons.arrow_upward_rounded, AppColors.accent, 'Sending'),
      ScanDelivery.queued => (Icons.schedule_rounded, AppColors.warning, queued > 1 ? '$queued queued' : 'Queued'),
      ScanDelivery.paused => (Icons.pause_circle_rounded, AppColors.warning, 'Desktop paused'),
      ScanDelivery.failed => (Icons.error_rounded, AppColors.danger, 'Failed'),
    };
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
      constraints: const BoxConstraints(maxWidth: 420),
      decoration: BoxDecoration(
        color: const Color(0xFF16171C).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  record.code,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatLabel(record.format)} · ${record.detail ?? label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.error});
  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(denied ? Icons.no_photography_rounded : Icons.videocam_off_rounded, color: Colors.white70, size: 48),
              const SizedBox(height: 16),
              Text(
                denied ? 'Camera access is off' : 'Camera unavailable',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                denied
                    ? 'Allow camera access for BarcodeSync in your phone\'s Settings, then come back.'
                    : (error.errorDetails?.message ?? 'Another app may be using the camera.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
