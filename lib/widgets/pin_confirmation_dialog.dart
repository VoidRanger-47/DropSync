import 'package:flutter/material.dart';
import '../theme/gemini_theme.dart';

/// Modal dialog matching Android Quick Share's PIN verification prompt.
class PinConfirmationDialog extends StatelessWidget {
  final String pin;
  final String peerName;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  const PinConfirmationDialog({
    super.key,
    required this.pin,
    required this.peerName,
    this.onAccept,
    this.onReject,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String pin,
    required String peerName,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PinConfirmationDialog(
        pin: pin,
        peerName: peerName,
        onAccept: () => Navigator.of(ctx).pop(true),
        onReject: () => Navigator.of(ctx).pop(false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: GeminiTheme.surfaceContainer,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: GeminiTheme.cyan.withOpacity(0.3), width: 1.5),
      ),
      contentPadding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: GeminiTheme.geminiGlowGradient,
                  boxShadow: GeminiTheme.glowShadow(color: GeminiTheme.cyan, blur: 16),
                ),
                child: const Icon(Icons.security_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 18),
              const Text(
                'Quick Share Pairing',
                style: TextStyle(
                  color: GeminiTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$peerName wants to connect. Verify that this 4-digit security PIN matches the one on their screen:',
                style: const TextStyle(
                  color: GeminiTheme.textSecondary,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              // 4-Digit Security Code Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  color: GeminiTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: GeminiTheme.cyan.withOpacity(0.4)),
                  boxShadow: [
                    BoxShadow(
                      color: GeminiTheme.cyan.withOpacity(0.15),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    pin,
                    style: const TextStyle(
                      color: GeminiTheme.cyan,
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Builder(
                builder: (context) {
                  final isCompact = MediaQuery.sizeOf(context).width < 340;
                  final declineBtn = OutlinedButton(
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: GeminiTheme.coralError,
                      side: BorderSide(color: GeminiTheme.coralError.withOpacity(0.4)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Decline'),
                  );

                  final acceptBtn = Container(
                    decoration: BoxDecoration(
                      gradient: GeminiTheme.geminiHorizontalGradient,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: ElevatedButton(
                      onPressed: onAccept,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Accept'),
                    ),
                  );

                  if (isCompact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        acceptBtn,
                        const SizedBox(height: 8),
                        declineBtn,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: declineBtn),
                      const SizedBox(width: 14),
                      Expanded(child: acceptBtn),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
