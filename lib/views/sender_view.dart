import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:qr_flutter/qr_flutter.dart';
import '../models/peer.dart';
import '../models/transfer_session.dart';
import '../services/clipboard_service.dart';
import '../services/hotspot_service.dart';
import '../services/network_service.dart';
import '../theme/gemini_theme.dart';
import 'camera_scanner_view.dart';
import 'receiver_view.dart';
import 'transfer_progress_widget.dart';
import '../theme/responsive.dart';

/// Sender Mode View: File picker, UDP Peer Radar, QR Scanner,
/// manual IP/JSON fallback, Hotspot auto-connector, and high-throughput chunked sending.
class SenderView extends StatefulWidget {
  final NetworkService networkService;
  final ClipboardService clipboardService;
  final HotspotService hotspotService;

  const SenderView({
    super.key,
    required this.networkService,
    required this.clipboardService,
    required this.hotspotService,
  });

  @override
  State<SenderView> createState() => _SenderViewState();
}

class _SenderViewState extends State<SenderView>
    with SingleTickerProviderStateMixin {
  final List<File> _selectedFiles = [];
  Peer? _selectedPeer;
  TransferSession? _activeTransfer;
  String _batchProgressText = '';
  bool _isSending = false;

  late AnimationController _radarController;

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    widget.networkService.activeTransferStream.listen((session) {
      if (mounted) {
        setState(() {
          _activeTransfer = session;
        });
      }
    });
  }

  @override
  void dispose() {
    _radarController.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          for (final f in result.files) {
            if (f.path != null) {
              final file = File(f.path!);
              if (!_selectedFiles.any((existing) => existing.path == file.path)) {
                _selectedFiles.add(file);
              }
            }
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File selection error: $e')),
      );
    }
  }

  void _removeFile(int index) {
    setState(() {
      _selectedFiles.removeAt(index);
    });
  }

  void _clearFiles() {
    setState(() {
      _selectedFiles.clear();
    });
  }

  Future<void> _openCameraScanner() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      _showManualConnectDialog();
      return;
    }

    final scannedPeer = await Navigator.of(context).push<Peer>(
      MaterialPageRoute(builder: (context) => const CameraScannerView()),
    );

    if (scannedPeer != null && mounted) {
      if (scannedPeer.isHotspot &&
          scannedPeer.hotspotSsid != null &&
          scannedPeer.hotspotSsid!.isNotEmpty) {
        _showHotspotConnectDialog(scannedPeer);
      } else {
        _connectAndSelectPeer(scannedPeer);
      }
    }
  }

  void _connectAndSelectPeer(Peer peer) {
    widget.networkService.addManualPeer(peer);
    setState(() {
      _selectedPeer = peer;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Connected to ${peer.name} (${peer.ip})'),
        backgroundColor: GeminiTheme.surfaceVariant,
      ),
    );

    if (_selectedFiles.isNotEmpty) {
      _startTransfer();
    }
  }

  void _showHotspotConnectDialog(Peer peer) {
    String status = 'Connecting to ${peer.hotspotSsid}...';
    bool isConnecting = true;
    bool connectionSuccess = false;
    bool connectionAttemptStarted = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          if (!connectionAttemptStarted) {
            connectionAttemptStarted = true;
            widget.hotspotService.connectToHotspot(
              ssid: peer.hotspotSsid!,
              password: peer.hotspotPassword ?? '',
              onStatusUpdate: (newStatus) {
                if (ctx.mounted) {
                  setDialogState(() {
                    status = newStatus;
                  });
                }
              },
            ).then((success) {
              if (ctx.mounted) {
                setDialogState(() {
                  isConnecting = false;
                  connectionSuccess = success;
                  status = success
                      ? 'Connected to ${peer.hotspotSsid}!'
                      : 'Connecting... If prompted by OS, tap "Connect" or check Wi-Fi settings.';
                });
              }
            });
          }

          return AlertDialog(
            backgroundColor: GeminiTheme.surfaceContainer,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: GeminiTheme.emeraldGreen.withOpacity(0.18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.wifi_tethering_rounded, color: GeminiTheme.emeraldGreen, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Receiver Hotspot',
                        style: TextStyle(color: GeminiTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Direct P2P Wi-Fi connection',
                        style: TextStyle(color: GeminiTheme.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: GeminiTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.06)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.wifi_rounded, size: 16, color: GeminiTheme.cyan),
                            const SizedBox(width: 8),
                            const Text('Network (SSID): ', style: TextStyle(color: GeminiTheme.textMuted, fontSize: 12)),
                            Expanded(
                              child: Text(
                                peer.hotspotSsid ?? 'Unknown',
                                style: const TextStyle(color: GeminiTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(Icons.lock_rounded, size: 16, color: GeminiTheme.lavender),
                            const SizedBox(width: 8),
                            const Text('Password: ', style: TextStyle(color: GeminiTheme.textMuted, fontSize: 12)),
                            Expanded(
                              child: Text(
                                (peer.hotspotPassword != null && peer.hotspotPassword!.isNotEmpty)
                                    ? peer.hotspotPassword!
                                    : '(None / Open)',
                                style: const TextStyle(color: GeminiTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (peer.hotspotPassword != null && peer.hotspotPassword!.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.copy_rounded, size: 16, color: GeminiTheme.cyan),
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: peer.hotspotPassword!));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Password copied to clipboard'), duration: Duration(seconds: 2)),
                                  );
                                },
                                tooltip: 'Copy password',
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (isConnecting)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: GeminiTheme.emeraldGreen),
                        )
                      else
                        Icon(
                          connectionSuccess ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                          size: 16,
                          color: connectionSuccess ? GeminiTheme.emeraldGreen : GeminiTheme.amberWarning,
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          status,
                          style: TextStyle(
                            color: connectionSuccess ? GeminiTheme.emeraldGreen : GeminiTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel', style: TextStyle(color: GeminiTheme.textMuted)),
              ),
              OutlinedButton.icon(
                onPressed: () => widget.hotspotService.openWifiSettings(),
                icon: const Icon(Icons.settings_rounded, size: 14, color: GeminiTheme.cyan),
                label: const Text('Wi-Fi Settings', style: TextStyle(color: GeminiTheme.cyan, fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: GeminiTheme.cyan.withOpacity(0.4)),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _connectAndSelectPeer(peer);
                },
                child: const Text('Proceed to Transfer'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSenderHotspotDialog() {
    final net = widget.networkService;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: GeminiTheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.wifi_tethering_rounded, color: GeminiTheme.emeraldGreen),
            SizedBox(width: 10),
            Text('Sender Hotspot Mode', style: TextStyle(color: GeminiTheme.textPrimary, fontSize: 18)),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'Host a direct Wi-Fi Hotspot on this device. Receivers can scan the QR code to connect and receive files without an external router:',
                style: TextStyle(color: GeminiTheme.textSecondary, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: PeerQrHelper.createWifiQrString(
                    ssid: widget.hotspotService.ssid,
                    password: widget.hotspotService.password,
                    ip: net.localIp,
                    port: net.currentPort,
                    token: net.sessionToken,
                  ),
                  version: QrVersions.auto,
                  size: 160,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'SSID: ${widget.hotspotService.ssid}',
                style: const TextStyle(color: GeminiTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              Text(
                'Password: ${widget.hotspotService.password}',
                style: const TextStyle(color: GeminiTheme.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showManualConnectDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: GeminiTheme.surfaceContainer,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        title: const Row(
          children: [
            Icon(Icons.link_rounded, color: GeminiTheme.cyan),
            SizedBox(width: 10),
            Text('Manual Connection', style: TextStyle(color: GeminiTheme.textPrimary, fontSize: 18)),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Paste pairing JSON, Wi-Fi QR string, or IP:Port (e.g. 192.168.1.5:8080):',
                  style: TextStyle(color: GeminiTheme.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  style: const TextStyle(color: GeminiTheme.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: '{"ip": "192.168.43.1", "ssid": "...", ...}',
                    hintStyle: const TextStyle(color: GeminiTheme.textMuted),
                    filled: true,
                    fillColor: GeminiTheme.surfaceVariant,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: GeminiTheme.cyan),
                    ),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: GeminiTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              final raw = controller.text.trim();
              if (raw.isNotEmpty) {
                final peer = Peer.fromQrString(raw);
                if (peer != null) {
                  Navigator.of(ctx).pop();
                  if (peer.isHotspot &&
                      peer.hotspotSsid != null &&
                      peer.hotspotSsid!.isNotEmpty) {
                    _showHotspotConnectDialog(peer);
                  } else {
                    _connectAndSelectPeer(peer);
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invalid format. Enter valid IP:port, JSON, or Wi-Fi QR.')),
                  );
                }
              }
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  Future<void> _startTransfer() async {
    if (_selectedPeer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or scan a receiver peer first.')),
      );
      return;
    }
    if (_selectedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one file to send.')),
      );
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      if (_selectedFiles.length == 1) {
        await widget.networkService.sendFile(
          peer: _selectedPeer!,
          file: _selectedFiles.first,
        );
      } else {
        await widget.networkService.sendMultipleFiles(
          peer: _selectedPeer!,
          files: _selectedFiles,
          onBatchProgress: (cur, tot, session) {
            if (mounted) {
              setState(() {
                _batchProgressText = 'Sending file $cur of $tot';
              });
            }
          },
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: GeminiTheme.surfaceVariant,
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: GeminiTheme.emeraldGreen, size: 20),
                const SizedBox(width: 10),
                Text('All ${_selectedFiles.length} file(s) sent successfully!'),
              ],
            ),
          ),
        );
        setState(() {
          _selectedFiles.clear();
          _batchProgressText = '';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Transfer error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Future<void> _sendClipboardText() async {
    if (_selectedPeer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select or connect to a receiver first.')),
      );
      return;
    }

    final ok = await widget.clipboardService.sendCurrentClipboard(_selectedPeer!);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? 'Clipboard text pushed to ${_selectedPeer!.name}'
              : 'Clipboard is empty or transfer failed.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = context.isDesktop || (context.isTablet && context.isLandscape);
    final horizontalPadding = context.responsiveHorizontalPadding;
    final verticalPadding = context.isMobile ? 12.0 : 24.0;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: isDesktop
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: _buildFileSelectionCard()),
                    const SizedBox(width: 20),
                    Expanded(flex: 6, child: _buildRadarAndPeersCard()),
                  ],
                )
              : Column(
                  children: [
                    _buildFileSelectionCard(),
                    const SizedBox(height: 16),
                    _buildRadarAndPeersCard(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildFileSelectionCard() {
    final totalBytes = _selectedFiles.fold<int>(
      0,
      (sum, f) => sum + (f.existsSync() ? f.lengthSync() : 0),
    );
    final cardPadding = context.responsiveCardPadding;

    return Container(
      padding: EdgeInsets.all(cardPadding),
      decoration: BoxDecoration(
        color: GeminiTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(context.isCompact ? 18 : 26),
        border: GeminiTheme.thinBorder,
        boxShadow: GeminiTheme.subtleCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.file_copy_rounded, color: GeminiTheme.electricBlue, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Selected Files',
                        style: TextStyle(
                          color: GeminiTheme.textPrimary,
                          fontSize: context.isCompact ? 14 : 16,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (_selectedFiles.isNotEmpty)
                TextButton(
                  onPressed: _clearFiles,
                  child: const Text('Clear All', style: TextStyle(color: GeminiTheme.coralError, fontSize: 13)),
                ),
            ],
          ),

          const SizedBox(height: 16),

          // Pick Files Dropzone / Button
          InkWell(
            onTap: _pickFiles,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
              decoration: BoxDecoration(
                color: GeminiTheme.surfaceVariant.withOpacity(0.5),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: GeminiTheme.cyan.withOpacity(0.3),
                  style: BorderStyle.solid,
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Column(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: GeminiTheme.geminiGlowGradient,
                        shape: BoxShape.circle,
                        boxShadow: GeminiTheme.glowShadow(color: GeminiTheme.cyan, blur: 14),
                      ),
                      child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Tap to browse & select files',
                      style: TextStyle(
                        color: GeminiTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Multi-file support, zero size limit',
                      style: TextStyle(
                        color: GeminiTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // File List
          if (_selectedFiles.isNotEmpty) ...[
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _selectedFiles.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, idx) {
                final file = _selectedFiles[idx];
                final name = p.basename(file.path);
                final size = file.existsSync() ? file.lengthSync() : 0;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: GeminiTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.04)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.insert_drive_file_rounded, color: GeminiTheme.cyan, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                color: GeminiTheme.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              _formatBytes(size),
                              style: const TextStyle(
                                color: GeminiTheme.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18, color: GeminiTheme.textMuted),
                        onPressed: () => _removeFile(idx),
                        tooltip: 'Remove',
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_selectedFiles.length} file(s) selected',
                  style: const TextStyle(color: GeminiTheme.textSecondary, fontSize: 13),
                ),
                Text(
                  _formatBytes(totalBytes),
                  style: const TextStyle(
                    color: GeminiTheme.cyan,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 20),

          // Active Transfer Widget
          if (_activeTransfer != null) ...[
            if (_batchProgressText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  _batchProgressText,
                  style: const TextStyle(
                    color: GeminiTheme.lavender,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            TransferProgressWidget(session: _activeTransfer!),
            const SizedBox(height: 16),
          ],

          // Action Buttons: Send Files & Push Clipboard
          LayoutBuilder(
            builder: (context, constraints) {
              final isVeryNarrow = constraints.maxWidth < 340;
              final sendBtn = Container(
                decoration: BoxDecoration(
                  gradient: (_selectedPeer != null && _selectedFiles.isNotEmpty && !_isSending)
                      ? GeminiTheme.geminiHorizontalGradient
                      : null,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: ElevatedButton.icon(
                  onPressed: (_selectedPeer != null && _selectedFiles.isNotEmpty && !_isSending)
                      ? _startTransfer
                      : null,
                  icon: _isSending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded, size: 18),
                  label: Text(_isSending ? 'Sending...' : 'Send Files'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: (_selectedPeer != null && _selectedFiles.isNotEmpty && !_isSending)
                        ? Colors.transparent
                        : GeminiTheme.surfaceVariant,
                    shadowColor: Colors.transparent,
                    padding: EdgeInsets.symmetric(
                      horizontal: context.isCompact ? 12 : 18,
                      vertical: 12,
                    ),
                  ),
                ),
              );

              final clipBtn = OutlinedButton.icon(
                onPressed: _selectedPeer != null ? _sendClipboardText : null,
                icon: const Icon(Icons.paste_rounded, size: 18, color: GeminiTheme.cyan),
                label: const Text('Clipboard', style: TextStyle(color: GeminiTheme.cyan)),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.isCompact ? 10 : 16,
                    vertical: 12,
                  ),
                  side: BorderSide(
                    color: _selectedPeer != null
                        ? GeminiTheme.cyan.withOpacity(0.5)
                        : Colors.white.withOpacity(0.08),
                  ),
                ),
              );

              if (isVeryNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    sendBtn,
                    const SizedBox(height: 8),
                    clipBtn,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: sendBtn),
                  const SizedBox(width: 10),
                  clipBtn,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRadarAndPeersCard() {
    final cardPadding = context.responsiveCardPadding;
    final isCompact = context.isCompact;

    return Container(
      padding: EdgeInsets.all(cardPadding),
      decoration: BoxDecoration(
        color: GeminiTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(isCompact ? 18 : 26),
        border: GeminiTheme.thinBorder,
        boxShadow: GeminiTheme.subtleCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.radar_rounded, color: GeminiTheme.cyan, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        isCompact ? 'Receivers' : 'Discovered Receivers',
                        style: TextStyle(
                          color: GeminiTheme.textPrimary,
                          fontSize: isCompact ? 14 : 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (Platform.isAndroid || Platform.isIOS)
                    IconButton(
                      padding: EdgeInsets.all(isCompact ? 4 : 8),
                      constraints: isCompact ? const BoxConstraints() : null,
                      icon: Icon(Icons.qr_code_scanner_rounded, color: GeminiTheme.cyan, size: isCompact ? 20 : 22),
                      onPressed: _openCameraScanner,
                      tooltip: 'Scan QR Code',
                    ),
                  IconButton(
                    padding: EdgeInsets.all(isCompact ? 4 : 8),
                    constraints: isCompact ? const BoxConstraints() : null,
                    icon: Icon(Icons.add_link_rounded, color: GeminiTheme.lavender, size: isCompact ? 20 : 22),
                    onPressed: _showManualConnectDialog,
                    tooltip: 'Manual IP / Paste JSON',
                  ),
                  IconButton(
                    padding: EdgeInsets.all(isCompact ? 4 : 8),
                    constraints: isCompact ? const BoxConstraints() : null,
                    icon: Icon(Icons.wifi_tethering_rounded, color: GeminiTheme.emeraldGreen, size: isCompact ? 20 : 22),
                    onPressed: _showSenderHotspotDialog,
                    tooltip: 'Host Hotspot (No Router)',
                  ),
                  IconButton(
                    padding: EdgeInsets.all(isCompact ? 4 : 8),
                    constraints: isCompact ? const BoxConstraints() : null,
                    icon: Icon(Icons.refresh_rounded, color: GeminiTheme.textSecondary, size: isCompact ? 20 : 22),
                    onPressed: () => widget.networkService.refreshScan(),
                    tooltip: 'Refresh radar',
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Animated Gemini Radar Screen
          _buildRadarScreen(),

          const SizedBox(height: 20),

          // Discovered Peer Devices Stream
          StreamBuilder<List<Peer>>(
            stream: widget.networkService.discoveredPeersStream,
            initialData: widget.networkService.currentPeers,
            builder: (context, snapshot) {
              final peers = snapshot.data ?? [];

              if (peers.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      children: [
                        const Text(
                          'Scanning local Wi-Fi for receivers...',
                          style: TextStyle(color: GeminiTheme.textSecondary, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: (Platform.isAndroid || Platform.isIOS)
                              ? _openCameraScanner
                              : _showManualConnectDialog,
                          icon: Icon(
                            (Platform.isAndroid || Platform.isIOS)
                                ? Icons.qr_code_scanner_rounded
                                : Icons.paste_rounded,
                            size: 16,
                            color: GeminiTheme.cyan,
                          ),
                          label: Text(
                            (Platform.isAndroid || Platform.isIOS)
                                ? 'Scan QR on PC'
                                : 'Paste QR Code / IP',
                            style: const TextStyle(color: GeminiTheme.cyan, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: peers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final peer = peers[index];
                  final isSelected = _selectedPeer?.id == peer.id;

                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedPeer = peer;
                      });
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? GeminiTheme.electricBlue.withOpacity(0.15)
                            : GeminiTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? GeminiTheme.cyan.withOpacity(0.8)
                              : Colors.white.withOpacity(0.06),
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: isSelected
                                  ? GeminiTheme.geminiGlowGradient
                                  : null,
                              color: isSelected ? null : Colors.white.withOpacity(0.06),
                            ),
                            child: Icon(
                              _getPlatformIcon(peer.platform),
                              color: isSelected ? Colors.white : GeminiTheme.cyan,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    Text(
                                      peer.name,
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : GeminiTheme.textPrimary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (peer.isQuickShare)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: GeminiTheme.lavender.withOpacity(0.18),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: GeminiTheme.lavender.withOpacity(0.4)),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.public_rounded, size: 10, color: GeminiTheme.lavender),
                                            SizedBox(width: 3),
                                            Text(
                                              'Quick Share',
                                              style: TextStyle(color: GeminiTheme.lavender, fontSize: 9, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      )
                                    else
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: GeminiTheme.electricBlue.withOpacity(0.18),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: GeminiTheme.cyan.withOpacity(0.4)),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.bolt_rounded, size: 10, color: GeminiTheme.cyan),
                                            SizedBox(width: 2),
                                            Text(
                                              'DropSync',
                                              style: TextStyle(color: GeminiTheme.cyan, fontSize: 9, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (peer.isManual)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text('PAIRED', style: TextStyle(color: Colors.white70, fontSize: 8, fontWeight: FontWeight.bold)),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${peer.ip}:${peer.port}',
                                  style: const TextStyle(
                                    color: GeminiTheme.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Radio<String>(
                            value: peer.id,
                            groupValue: _selectedPeer?.id,
                            activeColor: GeminiTheme.cyan,
                            onChanged: (_) {
                              setState(() => _selectedPeer = peer);
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRadarScreen() {
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: GeminiTheme.deepVoid,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Concentric radar rings
          for (final size in [40.0, 80.0, 120.0])
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: GeminiTheme.cyan.withOpacity(0.12),
                  width: 1.0,
                ),
              ),
            ),

          // Rotating radar sweep
          RotationTransition(
            turns: _radarController,
            child: Container(
              width: 120,
              height: 120,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: GeminiTheme.radarSweepGradient,
              ),
            ),
          ),

          // Central pulsing dot
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: GeminiTheme.cyan,
              boxShadow: GeminiTheme.glowShadow(color: GeminiTheme.cyan, blur: 10),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getPlatformIcon(String platform) {
    final p = platform.toLowerCase();
    if (p.contains('win')) return Icons.desktop_windows_rounded;
    if (p.contains('android')) return Icons.android_rounded;
    if (p.contains('mac') || p.contains('apple')) return Icons.laptop_mac_rounded;
    if (p.contains('ios') || p.contains('iphone')) return Icons.phone_iphone_rounded;
    if (p.contains('linux')) return Icons.terminal_rounded;
    return Icons.devices_rounded;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
