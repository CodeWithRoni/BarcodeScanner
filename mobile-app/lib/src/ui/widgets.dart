import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Concentric pulses with a rotating sweep, used while looking for desktops.
class RadarPulse extends StatefulWidget {
  const RadarPulse({super.key, this.size = 220, this.color = AppColors.accent, this.child, this.active = true});

  final double size;
  final Color color;
  final Widget? child;
  final bool active;

  @override
  State<RadarPulse> createState() => _RadarPulseState();
}

class _RadarPulseState extends State<RadarPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(RadarPulse old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) _c.repeat();
    if (!widget.active && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) => CustomPaint(
            painter: _RadarPainter(progress: _c.value, color: widget.color, active: widget.active),
            child: child,
          ),
          child: Center(child: widget.child),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.progress, required this.color, required this.active});

  final double progress;
  final Color color;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 1; i <= 3; i++) {
      ring.color = color.withValues(alpha: 0.10);
      canvas.drawCircle(center, radius * i / 3, ring);
    }
    if (!active) return;

    for (var i = 0; i < 3; i++) {
      final t = (progress + i / 3) % 1.0;
      final r = radius * (0.25 + 0.75 * t);
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: (1 - t) * 0.45);
      canvas.drawCircle(center, r, p);
    }

    final angle = progress * 2 * math.pi;
    final sweep = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi / 2,
        colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.28)],
        transform: GradientRotation(angle - math.pi / 2),
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, sweep);
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.progress != progress || old.active != active || old.color != color;
}

/// Small dot with a breathing halo.
class PulseDot extends StatefulWidget {
  const PulseDot({super.key, required this.color, this.size = 8, this.pulse = true});

  final Color color;
  final double size;
  final bool pulse;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _c.repeat();
  }

  @override
  void didUpdateWidget(PulseDot old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_c.isAnimating) _c.repeat();
    if (!widget.pulse) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox.square(
      dimension: s * 2.6,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = Curves.easeOut.transform(_c.value);
          return Stack(
            alignment: Alignment.center,
            children: [
              if (widget.pulse)
                Container(
                  width: s + s * 1.6 * t,
                  height: s + s * 1.6 * t,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: 0.45 * (1 - t))),
                ),
              Container(
                width: s,
                height: s,
                decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Gradient call-to-action button with a press animation.
class GradientButton extends StatefulWidget {
  const GradientButton({super.key, required this.label, required this.icon, required this.onPressed, this.height = 60});

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final double height;

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: const Duration(milliseconds: 120),
          child: AnimatedOpacity(
            opacity: enabled ? 1 : 0.5,
            duration: const Duration(milliseconds: 200),
            child: Container(
              height: widget.height,
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(color: AppColors.accent.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10)),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.icon, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    widget.label,
                    style: const TextStyle(color: Colors.white, fontSize: 16.5, fontWeight: FontWeight.w700, letterSpacing: -0.2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rounded pill used for compact status information.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.color, required this.label, this.pulse = true, this.dark = false});

  final Color color;
  final String label;
  final bool pulse;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final onDark = dark || Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.only(left: 4, right: 12, top: 2, bottom: 2),
      decoration: BoxDecoration(
        color: dark ? Colors.black.withValues(alpha: 0.45) : color.withValues(alpha: onDark ? 0.14 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.12) : color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PulseDot(color: color, size: 7, pulse: pulse),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: dark ? Colors.white : (onDark ? Colors.white : const Color(0xFF27272A)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

IconData platformIcon(String platform) => switch (platform.toLowerCase()) {
  'windows' => Icons.desktop_windows_rounded,
  'macos' => Icons.laptop_mac_rounded,
  'linux' => Icons.computer_rounded,
  _ => Icons.computer_rounded,
};
