import 'package:flutter/material.dart';
import '../models/transfer_session.dart';
import '../theme/gemini_theme.dart';
import '../theme/responsive.dart';

/// Gemini-aesthetic card showing real-time file transfer progress, speed, and ETA.
class TransferProgressWidget extends StatelessWidget {
  final TransferSession session;
  final VoidCallback? onCancel;
  final VoidCallback? onDismiss;

  const TransferProgressWidget({
    super.key,
    required this.session,
    this.onCancel,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isUpload = session.isUpload;
    final isCompleted = session.isCompleted;
    final hasFailed = session.hasFailed;
    final cardPadding = context.responsiveCardPadding;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: EdgeInsets.all(cardPadding),
      decoration: BoxDecoration(
        color: GeminiTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasFailed
              ? GeminiTheme.coralError.withOpacity(0.4)
              : isCompleted
                  ? GeminiTheme.emeraldGreen.withOpacity(0.4)
                  : GeminiTheme.cyan.withOpacity(0.3),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: hasFailed
                ? GeminiTheme.coralError.withOpacity(0.12)
                : isCompleted
                    ? GeminiTheme.emeraldGreen.withOpacity(0.12)
                    : GeminiTheme.electricBlue.withOpacity(0.18),
            blurRadius: 20,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header: Icon + File Name + Badges
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: isCompleted
                      ? const LinearGradient(
                          colors: [GeminiTheme.emeraldGreen, Color(0xFF059669)],
                        )
                      : hasFailed
                          ? const LinearGradient(
                              colors: [GeminiTheme.coralError, Color(0xFFDC2626)],
                            )
                          : GeminiTheme.geminiGlowGradient,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: GeminiTheme.glowShadow(
                    color: isCompleted
                        ? GeminiTheme.emeraldGreen
                        : hasFailed
                            ? GeminiTheme.coralError
                            : GeminiTheme.cyan,
                    opacity: 0.3,
                    blur: 12,
                  ),
                ),
                child: Icon(
                  isCompleted
                      ? Icons.check_circle_rounded
                      : hasFailed
                          ? Icons.error_outline_rounded
                          : isUpload
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.fileName,
                      style: const TextStyle(
                        color: GeminiTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 2,
                      children: [
                        Text(
                          isUpload ? 'Uploading' : 'Receiving',
                          style: TextStyle(
                            color: isUpload ? GeminiTheme.cyan : GeminiTheme.lavender,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '•  ${session.formattedTransferred} of ${session.formattedTotalSize}',
                          style: const TextStyle(
                            color: GeminiTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onCancel != null && session.isActive)
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: GeminiTheme.textMuted, size: 20),
                  onPressed: onCancel,
                  tooltip: 'Cancel',
                )
              else if (onDismiss != null && (isCompleted || hasFailed))
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: GeminiTheme.textMuted, size: 20),
                  onPressed: onDismiss,
                  tooltip: 'Dismiss',
                ),
            ],
          ),

          const SizedBox(height: 16),

          // Custom Gemini Gradient Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: Container(
              height: 7,
              width: double.infinity,
              color: Colors.white.withOpacity(0.06),
              child: Stack(
                children: [
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: session.progress.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: isCompleted
                            ? const LinearGradient(
                                colors: [GeminiTheme.emeraldGreen, Color(0xFF10B981)],
                              )
                            : hasFailed
                                ? const LinearGradient(
                                    colors: [GeminiTheme.coralError, Color(0xFFEF4444)],
                                  )
                                : GeminiTheme.geminiHorizontalGradient,
                        borderRadius: BorderRadius.circular(100),
                        boxShadow: [
                          BoxShadow(
                            color: GeminiTheme.cyan.withOpacity(0.5),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Metrics Footer: Percentage, Speed, and ETA
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              // Progress Percentage
              Text(
                session.formattedProgress,
                style: TextStyle(
                  color: isCompleted
                      ? GeminiTheme.emeraldGreen
                      : hasFailed
                          ? GeminiTheme.coralError
                          : GeminiTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),

              // Speed & ETA
              if (session.isActive)
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: GeminiTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withOpacity(0.06)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.speed_rounded, size: 13, color: GeminiTheme.cyan),
                          const SizedBox(width: 4),
                          Text(
                            session.formattedSpeed,
                            style: const TextStyle(
                              color: GeminiTheme.cyan,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: GeminiTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withOpacity(0.06)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.timer_outlined, size: 13, color: GeminiTheme.lavender),
                          const SizedBox(width: 4),
                          Text(
                            'ETA: ${session.formattedEta}',
                            style: const TextStyle(
                              color: GeminiTheme.lavender,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              else if (isCompleted)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: GeminiTheme.emeraldGreen.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: GeminiTheme.emeraldGreen.withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_rounded, size: 13, color: GeminiTheme.emeraldGreen),
                      SizedBox(width: 4),
                      Text(
                        'Transfer Complete',
                        style: TextStyle(
                          color: GeminiTheme.emeraldGreen,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                )
              else if (hasFailed)
                Text(
                  session.errorMessage ?? 'Transfer failed',
                  style: const TextStyle(
                    color: GeminiTheme.coralError,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
