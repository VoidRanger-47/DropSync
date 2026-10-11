import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/peer.dart';
import '../theme/gemini_theme.dart';
import '../theme/responsive.dart';

/// Full-screen camera scanner for Android with an animated Gemini-styled scanning reticle.
class CameraScannerView extends StatefulWidget {
  const CameraScannerView({super.key});

  @override
  State<CameraScannerView> createState() => _CameraScannerViewState();
}

class _CameraScannerViewState extends State<CameraScannerView>
    with SingleTickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  late AnimationController _laserController;
  late Animation<double> _laserAnimation;

  bool _isDetected = false;
  bool _isTorchOn = false;

  @override
  void initState() {
    super.initState();
    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _laserAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _laserController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _laserController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isDetected) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.isNotEmpty) {
        final peer = Peer.fromQrString(raw);
        if (peer != null) {
          _isDetected = true;
          Navigator.of(context).pop(peer);
          return;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final isLandscape = context.isLandscape;
    final scanBoxSize = (math.min(screenSize.width, screenSize.height) * 0.65).clamp(180.0, 270.0);

    return Scaffold(
      backgroundColor: GeminiTheme.deepVoid,
      appBar: AppBar(
        backgroundColor: GeminiTheme.surfaceContainer.withOpacity(0.9),
        title: const Text(
          'Scan DropSync QR Code',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: GeminiTheme.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: GeminiTheme.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
              color: _isTorchOn ? GeminiTheme.cyan : GeminiTheme.textSecondary,
            ),
            onPressed: () async {
              await _controller.toggleTorch();
              setState(() => _isTorchOn = !_isTorchOn);
            },
            tooltip: 'Flashlight',
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios_rounded, color: GeminiTheme.textSecondary),
            onPressed: () => _controller.switchCamera(),
            tooltip: 'Switch Camera',
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // Dark frosted vignette around scan area
          ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withOpacity(0.65),
              BlendMode.srcOut,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    backgroundBlendMode: BlendMode.dstOut,
                  ),
                ),
                Center(
                  child: Container(
                    width: scanBoxSize,
                    height: scanBoxSize,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Gemini-styled scanning frame & laser beam
          Center(
            child: SizedBox(
              width: scanBoxSize,
              height: scanBoxSize,
              child: Stack(
                children: [
                  // Outer glowing frame border
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: GeminiTheme.cyan.withOpacity(0.8),
                        width: 2.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: GeminiTheme.electricBlue.withOpacity(0.35),
                          blurRadius: 30,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),

                  // Animated horizontal laser sweep
                  AnimatedBuilder(
                    animation: _laserAnimation,
                    builder: (context, child) {
                      return Positioned(
                        top: 16 + _laserAnimation.value * (scanBoxSize - 32),
                        left: 16,
                        right: 16,
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Colors.transparent,
                                GeminiTheme.cyan,
                                GeminiTheme.lavender,
                                Colors.transparent,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: GeminiTheme.cyan.withOpacity(0.8),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Bottom floating guidance prompt
          Positioned(
            bottom: isLandscape ? 14 : 36,
            left: 20,
            right: 20,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    color: GeminiTheme.surfaceContainer.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                    boxShadow: GeminiTheme.subtleCardShadow,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.qr_code_scanner_rounded, color: GeminiTheme.cyan, size: 20),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Point camera at DropSync QR code on PC or Phone',
                          style: TextStyle(
                            color: GeminiTheme.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
