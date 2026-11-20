import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

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

/// Accent colours for each visual state of the reticle.
class _Tone {
  const _Tone(this.start, this.end, this.icon);
  final Color start;
  final Color end;
  final IconData icon;

  static const idle = _Tone(Color(0xFFA5B4FC), Color(0xFFC084FC), Icons.qr_code_scanner_rounded);
  static const success = _Tone(Color(0xFF34D399), Color(0xFF10B981), Icons.check_rounded);
  static const waiting = _Tone(Color(0xFFFCD34D), Color(0xFFF59E0B), Icons.schedule_rounded);
  static const paused = _Tone(Color(0xFFFCD34D), Color(0xFFF59E0B), Icons.pause_rounded);
  static const failure = _Tone(Color(0xFFFDA4AF), Color(0xFFF43F5E), Icons.close_rounded);

  static _Tone forDelivery(ScanDelivery d) => switch (d) {
    ScanDelivery.delivered => success,
    ScanDelivery.paused => paused,
    ScanDelivery.queued || ScanDelivery.sending => waiting,
    ScanDelivery.failed => failure,
  };
}

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
  late final AnimationController _laser = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))
    ..repeat(reverse: true);
  late final AnimationController _result = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));
  _Tone _resultTone = _Tone.success;
  ScanDelivery? _resultDelivery;

  final Map<String, int> _lastSeen = {};
  ScanRecord? _last;
  int _count = 0;
  int _lastHintMs = 0;
  bool _popped = false;
  StreamSubscription<ScanEvent>? _events;

  ConnectionService get _conn => widget.app.connection;
  bool get _pairing => widget.mode == ScannerMode.pair;

  @override
  void initState() {
    super.initState();
    _events = _conn.events.listen((e) {
      if (!mounted) return;
      setState(() {
        _resultDelivery = e.record.delivery;
        _resultTone = _Tone.forDelivery(e.record.delivery);
      });
      unawaited(_result.forward(from: 0));
    });
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    _laser.dispose();
    _result.dispose();
    unawaited(_camera.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;

      if (_pairing) {
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

  /// Places the scan window below the top bar, in the upper part of the screen.
  Rect _window(Size size, EdgeInsets padding) {
    final w = math.min(size.width - 72, 340.0);
    final h = _pairing ? w : w * 0.72;
    final minTop = padding.top + 12 + 48 + 44;
    final top = math.max(minTop, size.height * 0.38 - h / 2);
    return Rect.fromLTWH((size.width - w) / 2, top, w, h);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            final window = _window(size, MediaQuery.paddingOf(context));
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
                    animation: Listenable.merge([_laser, _result]),
                    builder: (context, _) => CustomPaint(
                      painter: _ReticlePainter(
                        window: window,
                        laser: Curves.easeInOutSine.transform(_laser.value),
                        tone: _result.isAnimating ? _resultTone : _Tone.idle,
                        result: _result.isAnimating ? _result.value : null,
                      ),
                    ),
                  ),
                ),
                // Readability gradients behind the top bar and the controls.
                const IgnorePointer(child: _EdgeShades()),
                Positioned(
                  left: 0,
                  right: 0,
                  top: window.bottom + 20,
                  child: _UnderFrame(
                    pairing: _pairing,
                    result: _result,
                    resultDelivery: _resultDelivery,
                    desktopName: _conn.desktopName,
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: SafeArea(bottom: false, child: _topBar(context)),
                ),
                Positioned(left: 0, right: 0, bottom: 0, child: _bottom(context)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Row(
        children: [
          _GlassCircleButton(icon: Icons.close_rounded, tooltip: 'Close', onTap: () => Navigator.of(context).maybePop()),
          const SizedBox(width: 10),
          Expanded(
            child: _pairing
                ? const _ConnectionPill(color: AppColors.accent, title: 'Pairing mode', subtitle: 'Scan the code on your computer')
                : ListenableBuilder(
                    listenable: _conn,
                    builder: (context, _) {
                      final latency = _conn.latencyMs;
                      final (color, subtitle, pulse) = switch (_conn.phase) {
                        ConnectionPhase.connected when _conn.desktopPaused => (AppColors.warning, 'Paused on desktop', false),
                        ConnectionPhase.connected => (AppColors.success, latency == null ? 'Connected' : 'Connected · $latency ms', true),
                        ConnectionPhase.awaitingApproval => (AppColors.warning, 'Waiting for approval', true),
                        ConnectionPhase.connecting || ConnectionPhase.reconnecting => (AppColors.warning, 'Reconnecting…', true),
                        _ => (AppColors.danger, 'Offline · scans are queued', false),
                      };
                      return _ConnectionPill(color: color, title: _conn.desktopName, subtitle: subtitle, pulse: pulse);
                    },
                  ),
          ),
          if (!_pairing) ...[
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
        final available = state.isInitialized && state.torchState != TorchState.unavailable;
        final on = state.torchState == TorchState.on;
        return _DockButton(
          icon: on ? Icons.flash_on_rounded : Icons.flash_off_rounded,
          label: on ? 'Torch on' : 'Torch',
          active: on,
          onTap: available ? () => unawaited(_camera.toggleTorch()) : null,
        );
      },
    );
  }

  Widget _flipButton() {
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: _camera,
      builder: (context, state, _) {
        final cameras = state.availableCameras;
        final canSwitch = state.isInitialized && (cameras == null || cameras > 1);
        return _DockButton(
          icon: Icons.flip_camera_ios_rounded,
          label: 'Flip',
          onTap: canSwitch ? () => unawaited(_camera.switchCamera()) : null,
        );
      },
    );
  }

  Widget _bottom(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_pairing)
            ListenableBuilder(
              listenable: _conn,
              builder: (context, _) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 340),
                switchInCurve: Curves.easeOutBack,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(anim),
                    child: child,
                  ),
                ),
                child: _last == null
                    ? const SizedBox(height: 62, key: ValueKey('empty'))
                    : _LastScanCard(
                        key: ValueKey(_last!.messageId),
                        record: _last!,
                        queued: _conn.queuedCount,
                        desktopName: _conn.desktopName,
                      ),
              ),
            ),
          const SizedBox(height: 18),
          _GlassDock(
            children: _pairing ? [_torchButton()] : [_torchButton(), _flipButton()],
          ),
        ],
      ),
    );
  }
}

/// Chip and hint shown directly under the scan window.
class _UnderFrame extends StatelessWidget {
  const _UnderFrame({required this.pairing, required this.result, required this.resultDelivery, required this.desktopName});

  final bool pairing;
  final AnimationController result;
  final ScanDelivery? resultDelivery;
  final String desktopName;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: result,
      builder: (context, _) {
        final showResult = result.isAnimating && resultDelivery != null;
        final (chip, hint) = !showResult
            ? (
                pairing ? 'BarcodeSync pairing code' : 'Barcode  ·  QR  ·  DataMatrix',
                pairing ? 'Scan the QR code shown on your computer' : 'Align a barcode or QR code inside the frame',
              )
            : switch (resultDelivery!) {
                ScanDelivery.delivered => ('Sent to $desktopName', 'Ready for the next code'),
                ScanDelivery.paused => ('Scanning is paused on $desktopName', 'Resume on the computer to type codes'),
                ScanDelivery.failed => ('Couldn\'t deliver this code', 'Check the computer and try again'),
                ScanDelivery.queued || ScanDelivery.sending => ('Queued', 'It will be sent when the connection is back'),
              };
        return Column(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Container(
                key: ValueKey(chip),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: Text(
                  chip,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 12.5, fontWeight: FontWeight.w500),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                hint,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.62), fontSize: 13.5),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EdgeShades extends StatelessWidget {
  const _EdgeShades();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 150,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withValues(alpha: 0.55), Colors.transparent],
            ),
          ),
        ),
        const Spacer(),
        Container(
          height: 260,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.6)],
            ),
          ),
        ),
      ],
    );
  }
}

class _ReticlePainter extends CustomPainter {
  _ReticlePainter({required this.window, required this.laser, required this.tone, required this.result});

  final Rect window;
  final double laser;
  final _Tone tone;

  /// Progress (0..1) of the scan-result animation, or null while idle.
  final double? result;

  static const _radius = 26.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(window, const Radius.circular(_radius));

    // Dim everything outside the scan window.
    final scrim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(rrect);
    canvas.drawPath(scrim, Paint()..color = const Color(0xFF05060A).withValues(alpha: 0.6));

    final r = result;
    if (r != null) {
      final fade = 1 - Curves.easeIn.transform((r / 0.6).clamp(0.0, 1.0));
      canvas.drawRRect(rrect, Paint()..color = tone.end.withValues(alpha: 0.2 * fade));
    }
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.16),
    );

    // Gradient corner brackets that breathe slightly, with a soft glow.
    final breathe = 3.0 + 2.5 * math.sin(laser * math.pi);
    final b = window.inflate(breathe);
    final brackets = _brackets(b, 40, _radius + breathe);
    final shader = LinearGradient(colors: [tone.start, tone.end], begin: Alignment.topLeft, end: Alignment.bottomRight)
        .createShader(b);
    canvas.drawPath(
      brackets,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7)
        ..color = Colors.white.withValues(alpha: 0.5),
    );
    canvas.drawPath(
      brackets,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );

    final showingResult = r != null && r < 0.55;
    if (!showingResult) {
      _paintLaser(canvas);
    } else {
      _paintResultBadge(canvas, r);
    }
  }

  void _paintLaser(Canvas canvas) {
    final left = window.left + 16;
    final right = window.right - 16;
    final y = window.top + 16 + (window.height - 32) * laser;
    final trail = Rect.fromLTRB(left, y - 34, right, y);
    canvas.drawRect(
      trail,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tone.end.withValues(alpha: 0), tone.end.withValues(alpha: 0.3)],
        ).createShader(trail),
    );
    final line = Rect.fromLTRB(left, y - 1.5, right, y + 1.5);
    final lineShader = LinearGradient(
      colors: [tone.start.withValues(alpha: 0), Colors.white, tone.end.withValues(alpha: 0)],
    ).createShader(line);
    canvas.drawRRect(
      RRect.fromRectAndRadius(line.inflate(3), const Radius.circular(4)),
      Paint()
        ..shader = lineShader
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawRRect(RRect.fromRectAndRadius(line, const Radius.circular(2)), Paint()..shader = lineShader);
  }

  void _paintResultBadge(Canvas canvas, double r) {
    final t = (r / 0.55).clamp(0.0, 1.0);
    final scale = Curves.elasticOut.transform((t * 1.7).clamp(0.0, 1.0));
    final opacity = t < 0.75 ? 1.0 : (1 - (t - 0.75) / 0.25);
    final center = window.center;
    final radius = 34 * scale;
    if (radius <= 0) return;
    canvas.drawCircle(
      center,
      radius + 6,
      Paint()
        ..color = tone.end.withValues(alpha: 0.55 * opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.drawCircle(center, radius, Paint()..color = tone.end.withValues(alpha: opacity));
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(tone.icon.codePoint),
        style: TextStyle(
          fontFamily: tone.icon.fontFamily,
          package: tone.icon.fontPackage,
          fontSize: 42 * scale,
          color: Colors.white.withValues(alpha: opacity),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
  }

  static Path _brackets(Rect r, double len, double rad) {
    return Path()
      ..moveTo(r.left, r.top + len)
      ..lineTo(r.left, r.top + rad)
      ..arcToPoint(Offset(r.left + rad, r.top), radius: Radius.circular(rad))
      ..lineTo(r.left + len, r.top)
      ..moveTo(r.right - len, r.top)
      ..lineTo(r.right - rad, r.top)
      ..arcToPoint(Offset(r.right, r.top + rad), radius: Radius.circular(rad))
      ..lineTo(r.right, r.top + len)
      ..moveTo(r.right, r.bottom - len)
      ..lineTo(r.right, r.bottom - rad)
      ..arcToPoint(Offset(r.right - rad, r.bottom), radius: Radius.circular(rad))
      ..lineTo(r.right - len, r.bottom)
      ..moveTo(r.left + len, r.bottom)
      ..lineTo(r.left + rad, r.bottom)
      ..arcToPoint(Offset(r.left, r.bottom - rad), radius: Radius.circular(rad))
      ..lineTo(r.left, r.bottom - len);
  }

  @override
  bool shouldRepaint(_ReticlePainter old) =>
      old.laser != laser || old.result != result || old.window != window || old.tone != tone;
}

/// Frosted-glass surface used for the floating controls.
class _Glass extends StatelessWidget {
  const _Glass({required this.child, required this.radius, this.padding = EdgeInsets.zero, this.opacity = 0.45});

  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: const Color(0xFF0D0E12).withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: _Glass(
        radius: 24,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: SizedBox.square(dimension: 46, child: Icon(icon, color: Colors.white, size: 24)),
          ),
        ),
      ),
    );
  }
}

class _ConnectionPill extends StatelessWidget {
  const _ConnectionPill({required this.color, required this.title, required this.subtitle, this.pulse = true});

  final Color color;
  final String title;
  final String subtitle;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: _Glass(
        radius: 24,
        padding: const EdgeInsets.fromLTRB(4, 5, 16, 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PulseDot(color: color, size: 8, pulse: pulse),
            const SizedBox(width: 2),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: -0.1),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.62), fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
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
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(23),
        boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.45), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (child, a) => SlideTransition(
              position: Tween(begin: const Offset(0, 0.6), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
              child: FadeTransition(opacity: a, child: child),
            ),
            child: Text(
              '$count',
              key: ValueKey(count),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            count == 1 ? 'scan' : 'scans',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _GlassDock extends StatelessWidget {
  const _GlassDock({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        items.add(Container(width: 1, height: 36, margin: const EdgeInsets.symmetric(horizontal: 18), color: Colors.white.withValues(alpha: 0.12)));
      }
      items.add(children[i]);
    }
    return _Glass(
      radius: 30,
      opacity: 0.5,
      padding: const EdgeInsets.fromLTRB(26, 12, 26, 10),
      child: Row(mainAxisSize: MainAxisSize.min, children: items),
    );
  }
}

class _DockButton extends StatefulWidget {
  const _DockButton({required this.icon, required this.label, required this.onTap, this.active = false});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  State<_DockButton> createState() => _DockButtonState();
}

class _DockButtonState extends State<_DockButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFFFCD34D);
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      label: widget.label,
      toggled: widget.active,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTap: () {
          if (!enabled) return;
          unawaited(HapticFeedback.selectionClick());
          widget.onTap!();
        },
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: enabled ? 1 : 0.4,
          child: SizedBox(
            width: 64,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: _down ? 0.9 : 1,
                  duration: const Duration(milliseconds: 120),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.active ? activeColor : Colors.white.withValues(alpha: 0.1),
                      border: Border.all(color: widget.active ? Colors.transparent : Colors.white.withValues(alpha: 0.16)),
                      boxShadow: widget.active
                          ? [BoxShadow(color: activeColor.withValues(alpha: 0.6), blurRadius: 22, spreadRadius: 1)]
                          : const [],
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, a) => RotationTransition(
                        turns: Tween(begin: 0.85, end: 1.0).animate(a),
                        child: FadeTransition(opacity: a, child: child),
                      ),
                      child: Icon(
                        widget.icon,
                        key: ValueKey(widget.icon),
                        size: 25,
                        color: widget.active ? const Color(0xFF1C1917) : Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  widget.label,
                  maxLines: 1,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LastScanCard extends StatelessWidget {
  const _LastScanCard({super.key, required this.record, required this.queued, required this.desktopName});

  final ScanRecord record;
  final int queued;
  final String desktopName;

  @override
  Widget build(BuildContext context) {
    final tone = _Tone.forDelivery(record.delivery);
    final status = switch (record.delivery) {
      ScanDelivery.delivered => 'Sent to $desktopName',
      ScanDelivery.sending => 'Sending…',
      ScanDelivery.queued => queued > 1 ? '$queued queued' : 'Queued',
      ScanDelivery.paused => 'Desktop paused',
      ScanDelivery.failed => record.detail ?? 'Not delivered',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: _Glass(
          radius: 20,
          opacity: 0.7,
          padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: tone.end.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(13)),
                child: record.delivery == ScanDelivery.sending
                    ? Padding(
                        padding: const EdgeInsets.all(11),
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: tone.start),
                      )
                    : Icon(tone.icon, color: tone.start, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      record.code,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${formatLabel(record.format)} · $status',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.62), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
