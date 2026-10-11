import 'dart:io';
import 'package:flutter/material.dart';
import '../services/network_service.dart';
import '../services/storage_service.dart';
import '../theme/gemini_theme.dart';
import '../theme/responsive.dart';

/// Modal or dialog allowing configuration of custom save folders, port, and auto-accept options.
class SettingsDialog extends StatelessWidget {
  final StorageService storageService;
  final NetworkService networkService;

  const SettingsDialog({
    super.key,
    required this.storageService,
    required this.networkService,
  });

  static Future<void> show(
    BuildContext context, {
    required StorageService storageService,
    required NetworkService networkService,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: GeminiTheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SettingsDialog(
        storageService: storageService,
        networkService: networkService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxSheetHeight = context.screenHeight * 0.88;
    final horizontalPad = context.responsiveHorizontalPadding;
    final cardPad = context.responsiveCardPadding;

    return AnimatedBuilder(
      animation: storageService,
      builder: (context, _) {
        return SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 620,
                maxHeight: maxSheetHeight,
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(horizontalPad, 20, horizontalPad, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.settings_rounded, color: GeminiTheme.cyan),
                            SizedBox(width: 10),
                            Text(
                              'DropSync Settings',
                              style: TextStyle(
                                color: GeminiTheme.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: GeminiTheme.textMuted),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Save Location Card
                    const Text(
                      'SAVE LOCATION',
                      style: TextStyle(
                        color: GeminiTheme.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.all(cardPad),
                      decoration: BoxDecoration(
                        color: GeminiTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withOpacity(0.06)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.folder_rounded, color: GeminiTheme.lavender, size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  storageService.downloadDirectory,
                                  style: const TextStyle(
                                    color: GeminiTheme.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              ElevatedButton.icon(
                                onPressed: () async {
                                  final picked = await storageService.pickAndSetCustomDirectory();
                                  if (picked != null && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Save location set to: $picked')),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.folder_open_rounded, size: 16),
                                label: const Text('Change Folder'),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  textStyle: const TextStyle(fontSize: 12),
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  await storageService.resetToDefault();
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Reset to default Downloads folder')),
                                    );
                                  }
                                },
                                child: const Text('Reset Default', style: TextStyle(color: GeminiTheme.textMuted, fontSize: 12)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Device & Network Info Card
                    const Text(
                      'DEVICE & NETWORK',
                      style: TextStyle(
                        color: GeminiTheme.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.all(cardPad),
                      decoration: BoxDecoration(
                        color: GeminiTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withOpacity(0.06)),
                      ),
                      child: Column(
                        children: [
                          _buildInfoRow('Device Name', networkService.deviceName),
                          const Divider(height: 18),
                          _buildInfoRow('Platform', Platform.operatingSystem.toUpperCase()),
                          const Divider(height: 18),
                          _buildInfoRow('Local IP', '${networkService.localIp}:${networkService.currentPort}'),
                          const Divider(height: 18),
                          _buildInfoRow('Session Token', networkService.sessionToken),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: GeminiTheme.textSecondary, fontSize: 13)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(color: GeminiTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
