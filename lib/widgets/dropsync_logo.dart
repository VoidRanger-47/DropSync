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
    this.backgroundColor = const Color(0xFF16120E),
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
    final effectiveAsset = widget.assetPath ?? 'assets/icon/icon.png';

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
              color: const Color(0xFFFF5500).withOpacity(0.35),
              width: 1.5,
            ),
            boxShadow: [
              // Deep ambient elevation shadow
              BoxShadow(
                color: Colors.black.withOpacity(0.55),
                blurRadius: markSize * 0.25,
                offset: Offset(0, markSize * 0.12),
              ),
              // Outer orange/amber ambient bloom
              if (widget.showGlow)
                BoxShadow(
                  color: const Color(0xFFFF5500).withOpacity(0.35),
                  blurRadius: markSize * 0.35,
                  spreadRadius: markSize * 0.02,
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(markSize * 0.28),
            child: widget.assetPath != null
                ? Image.asset(
                    effectiveAsset,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        _buildCustomPaint(markSize),
                  )
                : _buildCustomPaint(markSize),
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
                  color: const Color(0xFFFF5500).withOpacity(0.4),
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
              color: const Color(0xFFFF7A00).withOpacity(0.85),
              fontSize: fontSize * 0.42,
              fontWeight: FontWeight.w600,
              letterSpacing: letterSpacing * 0.6,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCustomPaint(double markSize) {
    return widget.animated
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
          );
  }
}

/// CustomPainter rendering the fluid infinity-droplet loop with two interconnected flow arrows
/// and a vibrant Cyberpunk Neon Orange (#FF5500) to Warm Amber (#FF7A00) gradient.
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
    final center = Offset(w * 0.5, h * 0.50);

    final strokeWidth = w * 0.11;

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
        Color(0xFFFF5500), // Electric Neon Orange
        Color(0xFFFF7A00), // Warm Amber
        Color(0xFFFF3D00), // Cyber Ember
      ],
      stops: [0.0, 0.5, 1.0],
    ).createShader(Rect.fromLTWH(w * 0.12, h * 0.12, w * 0.76, h * 0.76));

    // Outer glow pass
    if (showGlow) {
      final glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFFFF5500).withOpacity(0.35)
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

    // Specular highlight line
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

  /// Draws the dual-lobed infinity-droplet continuous curve matching official DropSync mark.
  void _drawInterconnectedLoop(Canvas canvas, Size size, Paint paint) {
    final w = size.width;
    final h = size.height;

    // Loop 1: Left teardrop loop flowing from center crossover down-left, around, and up to upper arrow
    final path1 = Path();
    path1.moveTo(w * 0.48, h * 0.44); // Center crossover
    path1.cubicTo(
      w * 0.52, h * 0.58, // down from center
      w * 0.44, h * 0.78, // bottom curve
      w * 0.32, h * 0.78,
    );
    path1.cubicTo(
      w * 0.18, h * 0.78, // bottom-left outer curve
      w * 0.16, h * 0.52, // sweeping up left flank
      w * 0.26, h * 0.38,
    );
    path1.cubicTo(
      w * 0.32, h * 0.30,
      w * 0.38, h * 0.26,
      w * 0.42, h * 0.26, // terminates at top arrow base
    );
    canvas.drawPath(path1, paint);

    // Loop 2: Right arc flowing from behind top arrow, around top-right, down to right arrow
    final path2 = Path();
    path2.moveTo(w * 0.48, h * 0.22); // Top apex behind Arrow 1
    path2.cubicTo(
      w * 0.65, h * 0.18, // Top-right ascending curve
      w * 0.82, h * 0.32, // Upper right lobe
      w * 0.80, h * 0.48,
    );
    path2.cubicTo(
      w * 0.78, h * 0.58,
      w * 0.72, h * 0.64,
      w * 0.64, h * 0.64, // terminates at right arrow base
    );
    canvas.drawPath(path2, paint);
  }

  /// Draws the two sleek directional arrowheads along the stream loops.
  void _drawArrowheads(Canvas canvas, Size size, Shader shader, double strokeWidth) {
    final w = size.width;
    final h = size.height;
    final arrowPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = shader;

    final arrowSize = strokeWidth * 1.55;

    // Arrow 1: Upper arrow pointing up-right into right lobe (Tangent ~ -0.65 rad)
    _drawArrowhead(
      canvas,
      tip: Offset(w * 0.45, h * 0.24),
      angle: -0.65,
      size: arrowSize,
      paint: arrowPaint,
    );

    // Arrow 2: Lower-right arrow pointing down-left into lower droplet (Tangent ~ 2.50 rad)
    _drawArrowhead(
      canvas,
      tip: Offset(w * 0.62, h * 0.64),
      angle: 2.50,
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
    highlightPath.moveTo(w * 0.24, h * 0.48);
    highlightPath.quadraticBezierTo(
      w * 0.20, h * 0.62,
      w * 0.30, h * 0.74,
    );
    canvas.drawPath(highlightPath, paint);
  }

  @override
  bool shouldRepaint(covariant _DropSyncMarkPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.showGlow != showGlow;
  }
}
