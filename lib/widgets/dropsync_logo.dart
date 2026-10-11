import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Reusable branding widget for DropSync featuring the custom infinity-droplet mark,
/// dual interconnected flow arrows, signature cyan-to-emerald gradient, and modern typography.
class DropSyncLogo extends StatefulWidget {
  /// Base size of the logo icon mark in logical pixels.
  final double size;

  /// Whether to display the bold "DROPSYNC" wordmark underneath the icon.
  final bool showText;

  /// Whether to render the ambient outer cyan/teal glow effect.
  final bool showGlow;

  /// Whether to gently animate the continuous fluid flow of the mark.
  final bool animated;

  /// Optional background color override. Defaults to deep midnight navy (#0D1742).
  final Color backgroundColor;

  /// Optional asset image path (if rendering a static SVG/PNG instead of procedural vector).
  final String? assetPath;

  const DropSyncLogo({
    super.key,
    this.size = 120.0,
    this.showText = true,
    this.showGlow = true,
    this.animated = false,
    this.backgroundColor = const Color(0xFF172062),
    this.assetPath,
  });

  /// Factory constructor configured for splash screens with glowing ambient rings and animation.
  factory DropSyncLogo.splash({
    Key? key,
    double size = 150.0,
    bool animated = true,
  }) {
    return DropSyncLogo(
      key: key,
      size: size,
      showText: true,
      showGlow: true,
      animated: animated,
    );
  }

  @override
  State<DropSyncLogo> createState() => _DropSyncLogoState();
}

class _DropSyncLogoState extends State<DropSyncLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    if (widget.animated) {
      _animController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant DropSyncLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animated != oldWidget.animated) {
      if (widget.animated) {
        _animController.repeat();
      } else {
        _animController.stop();
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final markSize = widget.size;
    final fontSize = markSize * 0.18;
    final letterSpacing = markSize * 0.04;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Brand Icon Mark Container
        Container(
          width: markSize,
          height: markSize,
          decoration: BoxDecoration(
            color: widget.backgroundColor,
            borderRadius: BorderRadius.circular(markSize * 0.28),
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
              width: 1.5,
            ),
            boxShadow: [
              // Deep ambient elevation shadow
              BoxShadow(
                color: Colors.black.withOpacity(0.55),
                blurRadius: markSize * 0.25,
                offset: Offset(0, markSize * 0.12),
              ),
              // Subtle outer cyan/teal ambient bloom
              if (widget.showGlow)
                BoxShadow(
                  color: const Color(0xFF00D2FF).withOpacity(0.25),
                  blurRadius: markSize * 0.35,
                  spreadRadius: markSize * 0.02,
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(markSize * 0.28),
            child: Stack(
              fit: StackFit.expand,
              children: [
                widget.animated
                    ? AnimatedBuilder(
                        animation: _animController,
                        builder: (context, child) {
                          return CustomPaint(
                            size: Size(markSize, markSize),
                            painter: _DropSyncMarkPainter(
                              progress: _animController.value,
                              showGlow: widget.showGlow,
                            ),
                          );
                        },
                      )
                    : CustomPaint(
                        size: Size(markSize, markSize),
                        painter: _DropSyncMarkPainter(
                          progress: 0.0,
                          showGlow: widget.showGlow,
                        ),
                      ),
                Image.asset(
                  widget.assetPath ?? 'assets/icon/dropsync_mark.png',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),

        // Brand Wordmark Typography
        if (widget.showText) ...[
          SizedBox(height: markSize * 0.16),
          Text(
            'DROPSYNC',
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: letterSpacing,
              fontFamily: 'Roboto',
              height: 1.1,
              shadows: [
                Shadow(
                  color: const Color(0xFF00D2FF).withOpacity(0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
          SizedBox(height: markSize * 0.04),
          Text(
            'HIGH-SPEED P2P SYNC',
            style: TextStyle(
              color: const Color(0xFF00F29D).withOpacity(0.75),
              fontSize: fontSize * 0.42,
              fontWeight: FontWeight.w600,
              letterSpacing: letterSpacing * 0.6,
            ),
          ),
        ],
      ],
    );
  }
}

/// CustomPainter rendering the fluid infinity-droplet loop with two interconnected flow arrows
/// and a vibrant Cyan (#00D2FF) to Emerald-Teal (#00F29D) gradient.
class _DropSyncMarkPainter extends CustomPainter {
  final double progress;
  final bool showGlow;

  _DropSyncMarkPainter({
    required this.progress,
    required this.showGlow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w * 0.5, h * 0.52);

    final strokeWidth = w * 0.095;

    // Optional animation rotation around center
    if (progress > 0) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(progress * 2 * math.pi * 0.05);
      canvas.translate(-center.dx, -center.dy);
    }

    final gradientShader = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF00D2FF), // Vibrant Cyan
        Color(0xFF00E5C9), // Aquamarine transition
        Color(0xFF00F29D), // Emerald Teal
      ],
      stops: [0.0, 0.5, 1.0],
    ).createShader(Rect.fromLTWH(w * 0.15, h * 0.15, w * 0.7, h * 0.7));

    // Outer glow pass
    if (showGlow) {
      final glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF00D2FF).withOpacity(0.28)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.08);

      _drawInterconnectedLoop(canvas, size, glowPaint);
    }

    // Main vibrant gradient stroke
    final mainPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = gradientShader;

    _drawInterconnectedLoop(canvas, size, mainPaint);

    // Directional Arrowheads showing continuous fluid synchronization
    _drawArrowheads(canvas, size, gradientShader, strokeWidth);

    // Specular highlight line on upper lobe
    final highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 0.22
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withOpacity(0.45);

    _drawSpecularHighlight(canvas, size, highlightPaint);

    if (progress > 0) {
      canvas.restore();
    }
  }

  /// Draws the dual-lobed infinity-droplet continuous curve.
  void _drawInterconnectedLoop(Canvas canvas, Size size, Paint paint) {
    final w = size.width;
    final h = size.height;

    // Droplet apex at top
    final apex = Offset(w * 0.5, h * 0.22);
    final bottomCenter = Offset(w * 0.5, h * 0.62);

    // Left teardrop curve
    final pathLeft = Path();
    pathLeft.moveTo(apex.dx, apex.dy);
    pathLeft.cubicTo(
      w * 0.22, h * 0.30, // Control 1: bulbous upper left
      w * 0.16, h * 0.68, // Control 2: sweeping bottom left
      bottomCenter.dx, bottomCenter.dy + h * 0.16, // Bottom curve
    );
    pathLeft.cubicTo(
      w * 0.68, bottomCenter.dy + h * 0.14,
      w * 0.74, h * 0.56,
      bottomCenter.dx, bottomCenter.dy,
    );
    canvas.drawPath(pathLeft, paint);

    // Right complementary teardrop loop
    final pathRight = Path();
    pathRight.moveTo(apex.dx, apex.dy);
    pathRight.cubicTo(
      w * 0.78, h * 0.30, // Control 1: bulbous upper right
      w * 0.84, h * 0.68, // Control 2: sweeping bottom right
      bottomCenter.dx, bottomCenter.dy + h * 0.16,
    );
    pathRight.cubicTo(
      w * 0.32, bottomCenter.dy + h * 0.14,
      w * 0.26, h * 0.56,
      bottomCenter.dx, bottomCenter.dy,
    );
    canvas.drawPath(pathRight, paint);
  }

  /// Draws the two sleek directional arrowheads along the stream loops.
  void _drawArrowheads(Canvas canvas, Size size, Shader shader, double strokeWidth) {
    final w = size.width;
    final h = size.height;
    final arrowPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = shader;

    final arrowSize = strokeWidth * 1.55;

    // Arrow 1: Upper Right sweeping down (Tangent pointing down-right ~ 55 degrees)
    _drawArrowhead(
      canvas,
      tip: Offset(w * 0.78, h * 0.44),
      angle: 1.15, // Radians
      size: arrowSize,
      paint: arrowPaint,
    );

    // Arrow 2: Lower Left sweeping up into the central crossing (Tangent pointing up-right ~ -40 degrees)
    _drawArrowhead(
      canvas,
      tip: Offset(w * 0.30, h * 0.64),
      angle: -0.75, // Radians
      size: arrowSize,
      paint: arrowPaint,
    );
  }

  void _drawArrowhead(
    Canvas canvas, {
    required Offset tip,
    required double angle,
    required double size,
    required Paint paint,
  }) {
    canvas.save();
    canvas.translate(tip.dx, tip.dy);
    canvas.rotate(angle);

    final path = Path();
    path.moveTo(0, 0); // Tip
    path.lineTo(-size, -size * 0.55);
    path.lineTo(-size * 0.7, 0); // Inner concave notch
    path.lineTo(-size, size * 0.55);
    path.close();

    canvas.drawPath(path, paint);
    canvas.restore();
  }

  /// Subtle specular sheen on the apex curve
  void _drawSpecularHighlight(Canvas canvas, Size size, Paint paint) {
    final w = size.width;
    final h = size.height;
    final highlightPath = Path();
    highlightPath.moveTo(w * 0.40, h * 0.27);
    highlightPath.quadraticBezierTo(
      w * 0.50, h * 0.23,
      w * 0.60, h * 0.27,
    );
    canvas.drawPath(highlightPath, paint);
  }

  @override
  bool shouldRepaint(covariant _DropSyncMarkPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.showGlow != showGlow;
  }
}
