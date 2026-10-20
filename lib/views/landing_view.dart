import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/clipboard_service.dart';
import '../services/storage/history_repository.dart';
import '../services/network_service.dart';
import '../services/storage/storage_service.dart';
import '../theme/gemini_theme.dart';
import 'history_view.dart';
import 'internet_transfer_view.dart';
import 'receiver_view.dart';
import '../services/hotspot_service.dart';
import '../services/internet_transfer_service.dart';
import 'sender_view.dart';
import '../widgets/settings_dialog.dart';

import '../widgets/pin_confirmation_dialog.dart';
import '../widgets/dropsync_logo.dart';
import '../theme/responsive.dart';

enum DropSyncRole {
  send,
  receive,
  internet,
}

/// Main Landing View with prominent Send / Receive / Internet role switcher,
/// top navigation to History, Settings, and Internet E2EE mode.
class LandingView extends StatefulWidget {
  final NetworkService networkService;
  final ClipboardService clipboardService;
  final StorageService storageService;
  final HistoryRepository historyRepository;
  final HotspotService hotspotService;
  final InternetTransferService internetTransferService;

  const LandingView({
    super.key,
    required this.networkService,
    required this.clipboardService,
    required this.storageService,
    required this.historyRepository,
    required this.hotspotService,
    required this.internetTransferService,
  });

  @override
  State<LandingView> createState() => _LandingViewState();
}

class _LandingViewState extends State<LandingView> {
  DropSyncRole _selectedRole = DropSyncRole.send;
  String _lastClipboardSnippet = 'Syncing clipboard...';

  @override
  void initState() {
    super.initState();
    widget.clipboardService.clipboardChangeStream.listen((text) {
      if (mounted) {
        setState(() {
          final clean = text.replaceAll('\n', ' ').trim();
          _lastClipboardSnippet = clean.length > 50 ? '${clean.substring(0, 48)}...' : clean;
        });
      }
    });

    widget.networkService.pinPromptStream.listen((prompt) {
      if (mounted) {
        PinConfirmationDialog.show(
          context,
          pin: prompt.pin,
          peerName: prompt.peerName,
        );
      }
    });
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => HistoryView(
          historyRepository: widget.historyRepository,
        ),
      ),
    );
  }

  void _openSettings() {
    SettingsDialog.show(
      context,
      storageService: widget.storageService,
      networkService: widget.networkService,
    );
  }

  @override
  Widget build(BuildContext context) {
    final net = widget.networkService;

    return Scaffold(
      backgroundColor: GeminiTheme.deepVoid,
      body: SafeArea(
        child: Column(
          children: [
            // Top App Bar with DropSync branding, History, and Settings navigation
            _buildTopBar(net),

            // Prominent Role Switcher (Send Mode vs. Receive Mode)
            _buildRoleSwitcher(),

            // Active View (Sender or Receiver)
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: _selectedRole == DropSyncRole.send
                    ? SenderView(
                        key: const ValueKey('sender_view'),
                        networkService: widget.networkService,
                        clipboardService: widget.clipboardService,
                        hotspotService: widget.hotspotService,
                      )
                    : _selectedRole == DropSyncRole.receive
                        ? ReceiverView(
                            key: const ValueKey('receiver_view'),
                            networkService: widget.networkService,
                            storageService: widget.storageService,
                            hotspotService: widget.hotspotService,
                          )
                        : InternetTransferView(
                            key: const ValueKey('internet_view'),
                            internetService: widget.internetTransferService,
                            storageService: widget.storageService,
                          ),
              ),
            ),

            // Bottom Clipboard Status Bar
            _buildBottomClipboardBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(NetworkService net) {
    final horizontalPadding = context.responsiveHorizontalPadding;
    final isCompact = context.isCompact;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: isCompact ? 10 : 14),
      decoration: BoxDecoration(
        color: GeminiTheme.deepVoid,
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // DropSync Brand Logo & Title with Gemini Gradient
          Expanded(
            child: Row(
              children: [
                DropSyncLogo(
                  size: isCompact ? 32 : 38,
                  showText: false,
                  showGlow: true,
                  assetPath: 'assets/icon/icon.png',
                ),
                SizedBox(width: isCompact ? 8 : 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ShaderMask(
                        shaderCallback: (bounds) =>
                            GeminiTheme.geminiHorizontalGradient.createShader(bounds),
                        child: Text(
                          'DropSync',
                          style: TextStyle(
                            fontSize: isCompact ? 17 : 20,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: GeminiTheme.emeraldGreen,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              '${net.localIp}:${net.currentPort}',
                              style: const TextStyle(
                                color: GeminiTheme.textMuted,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Action Navigation Buttons: History & Settings
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // History Navigation Button
              AnimatedBuilder(
                animation: widget.historyRepository,
                builder: (context, _) {
                  final count = widget.historyRepository.records.length;
                  return IconButton(
                    padding: isCompact ? const EdgeInsets.all(4) : const EdgeInsets.all(8),
                    constraints: isCompact ? const BoxConstraints() : null,
                    icon: Badge(
                      isLabelVisible: count > 0,
                      label: Text('$count', style: const TextStyle(fontSize: 10)),
                      backgroundColor: GeminiTheme.electricBlue,
                      child: Icon(Icons.history_rounded, color: GeminiTheme.textPrimary, size: isCompact ? 20 : 22),
                    ),
                    tooltip: 'Transfer History',
                    onPressed: _openHistory,
                  );
                },
              ),
              SizedBox(width: isCompact ? 2 : 4),

              // Settings Navigation Button
              IconButton(
                padding: isCompact ? const EdgeInsets.all(4) : const EdgeInsets.all(8),
                constraints: isCompact ? const BoxConstraints() : null,
                icon: Icon(Icons.settings_outlined, color: GeminiTheme.textPrimary, size: isCompact ? 20 : 22),
                tooltip: 'Settings',
                onPressed: _openSettings,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoleSwitcher() {
    final horizontalPadding = context.responsiveHorizontalPadding;
    final isCompact = context.isCompact || context.screenWidth < 420;

    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 6),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: GeminiTheme.surfaceContainer,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Row(
              children: [
                // Send Mode Button
                Expanded(
                  child: _buildRoleButton(
                    role: DropSyncRole.send,
                    label: isCompact ? 'Send' : 'Send Mode',
                    icon: Icons.upload_file_rounded,
                  ),
                ),
                // Receive Mode Button
                Expanded(
                  child: _buildRoleButton(
                    role: DropSyncRole.receive,
                    label: isCompact ? 'Receive' : 'Receive Mode',
                    icon: Icons.qr_code_2_rounded,
                  ),
                ),
                // Internet E2EE Transfer Button
                Expanded(
                  child: _buildRoleButton(
                    role: DropSyncRole.internet,
                    label: isCompact ? 'Internet' : 'Internet (E2EE)',
                    icon: Icons.public_rounded,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleButton({
    required DropSyncRole role,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _selectedRole == role;
    final isNarrow = context.screenWidth < 400;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedRole = role;
        });
      },
      borderRadius: BorderRadius.circular(100),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: EdgeInsets.symmetric(vertical: isNarrow ? 9 : 11, horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          gradient: isSelected ? GeminiTheme.geminiHorizontalGradient : null,
          boxShadow: isSelected
              ? GeminiTheme.glowShadow(color: GeminiTheme.cyan, blur: 16)
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: isNarrow ? 15 : 17,
              color: isSelected ? Colors.white : GeminiTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : GeminiTheme.textSecondary,
                  fontSize: isNarrow ? 11 : 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomClipboardBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: GeminiTheme.surfaceContainer,
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.content_paste_rounded, color: GeminiTheme.lavender, size: 16),
          const SizedBox(width: 8),
          const Text(
            'Clipboard: ',
            style: TextStyle(
              color: GeminiTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: Text(
              _lastClipboardSnippet,
              style: const TextStyle(
                color: GeminiTheme.textSecondary,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 15, color: GeminiTheme.textMuted),
            tooltip: 'Copy current text',
            onPressed: () {
              final text = widget.clipboardService.currentText;
              if (text != null && text.isNotEmpty) {
                Clipboard.setData(ClipboardData(text: text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
