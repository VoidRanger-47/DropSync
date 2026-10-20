import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:qr_flutter/qr_flutter.dart';
import '../models/peer.dart';
import '../models/transfer_session.dart';
import '../services/internet_transfer_service.dart';
import '../services/storage/storage_service.dart';
import '../theme/gemini_theme.dart';
import '../theme/responsive.dart';
import 'camera_scanner_view.dart';
import '../widgets/transfer_progress_widget.dart';

enum InternetMode {
  send,
  receive,
}

/// Dedicated Internet E2EE Transfer Page:
/// Allows transferring files securely through the internet with 256-bit AES-GCM E2EE.
/// The transfer strictly executes ONLY when BOTH sender and receiver remain actively on this page.
class InternetTransferView extends StatefulWidget {
  final InternetTransferService internetService;
  final StorageService storageService;

  const InternetTransferView({
    super.key,
    required this.internetService,
    required this.storageService,
  });

  @override
  State<InternetTransferView> createState() => _InternetTransferViewState();
}

class _InternetTransferViewState extends State<InternetTransferView>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  InternetMode _mode = InternetMode.send;
  final List<File> _selectedFiles = [];
  final TextEditingController _roomCodeInputController = TextEditingController();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  TransferSession? _activeSession;
  String _currentCode = '';
  bool _isCreatingRoom = false;
  bool _isReceivingStream = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.88, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Announce local page presence
    widget.internetService.setLocalPagePresence(true);

    // Auto-create room for Sender if none exists
    _initSenderRoom();

    // Listen to session stream
    widget.internetService.sessionStream.listen((session) {
      if (mounted) {
        setState(() {
          _activeSession = session;
        });
      }
    });

    // Listen to presence updates
    widget.internetService.presenceStream.listen((presence) {
      if (mounted) setState(() {});
    });

    // Listen to transfer state updates
    widget.internetService.transferStateStream.listen((state) {
      if (mounted) setState(() {});
    });

    // Listen to completed files
    widget.internetService.fileReceivedStream.listen((file) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: GeminiTheme.surfaceVariant,
            content: Row(
              children: [
                const Icon(Icons.verified_rounded, color: GeminiTheme.emeraldGreen),
                const SizedBox(width: 10),
                Expanded(child: Text('Decrypted & Saved: ${p.basename(file.path)}')),
              ],
            ),
          ),
        );
      }
    });
  }

  Future<void> _initSenderRoom() async {
    if (_mode == InternetMode.send && widget.internetService.currentRoomCode == null) {
      setState(() => _isCreatingRoom = true);
      final code = await widget.internetService.createSenderRoom();
      if (mounted) {
        setState(() {
          _currentCode = code;
          _isCreatingRoom = false;
        });
      }
    } else {
      _currentCode = widget.internetService.currentRoomCode ?? '';
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Strict mutual presence rule:
    // If the app is minimized, inactive, or hidden, mark local presence as false!
    if (state == AppLifecycleState.resumed) {
      widget.internetService.setLocalPagePresence(true);
    } else {
      widget.internetService.setLocalPagePresence(false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // User left this page
    widget.internetService.setLocalPagePresence(false);
    _pulseController.dispose();
    _roomCodeInputController.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Picker error: $e')));
    }
  }

  Future<void> _startSending() async {
    if (_selectedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one file to send.')),
      );
      return;
    }

    if (!widget.internetService.areBothPresent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot send: Receiver is not on this page yet! Both peers must stay on this page.'),
          backgroundColor: GeminiTheme.coralError,
        ),
      );
      return;
    }

    try {
      for (final file in _selectedFiles) {
        await widget.internetService.sendFile(file: file);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: GeminiTheme.surfaceVariant,
            content: Text('All files encrypted and delivered successfully over the internet!'),
          ),
        );
        setState(() {
          _selectedFiles.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Internet transfer error: $e')),
        );
      }
    }
  }

  Future<void> _joinReceiverRoom(String code) async {
    final clean = code.trim().toUpperCase();
    if (clean.isEmpty) return;

    final ok = await widget.internetService.joinReceiverRoom(clean);
    if (ok && mounted) {
      setState(() {
        _currentCode = clean;
        _isReceivingStream = true;
      });
      // Start receiver polling loop in background
      widget.internetService.startReceiverListening();
    }
  }

  void _scanRoomQr() async {
    final scannedPeer = await Navigator.of(context).push<Peer>(
      MaterialPageRoute(builder: (context) => const CameraScannerView()),
    );
    if (scannedPeer != null && mounted) {
      final code = scannedPeer.token.isNotEmpty ? scannedPeer.token : scannedPeer.name;
      _roomCodeInputController.text = code;
      _joinReceiverRoom(code);
    }
  }

  void _showVercelConfigDialog() {
    final ctrl = TextEditingController(text: widget.internetService.vercelUrl);
    bool isTesting = false;
    Map<String, dynamic>? testResult;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: GeminiTheme.surfaceContainer,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            title: const Row(
              children: [
                Icon(Icons.public_rounded, color: GeminiTheme.cyan),
                SizedBox(width: 10),
                Text('Relay Hosting & Diagnostics', style: TextStyle(color: GeminiTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Host your relay anywhere (Vercel, Render, Railway, Fly.io, or Docker) for maximum speed and zero file-size limits:',
                      style: TextStyle(color: GeminiTheme.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 12),

                    // Quick Presets
                    const Text('QUICK PRESETS', style: TextStyle(color: GeminiTheme.textMuted, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        ActionChip(
                          backgroundColor: const Color(0xFFF38020).withOpacity(0.18),
                          avatar: const Icon(Icons.bolt_rounded, size: 14, color: Color(0xFFFFA033)),
                          label: const Text('Cloudflare Edge (Default)', style: TextStyle(fontSize: 11, color: Color(0xFFFFA033), fontWeight: FontWeight.bold)),
                          onPressed: () {
                            setDialogState(() {
                              ctrl.text = 'https://dropsync.voidranger.workers.dev';
                              testResult = null;
                            });
                          },
                        ),
                        ActionChip(
                          backgroundColor: GeminiTheme.surfaceVariant,
                          avatar: const Icon(Icons.cloud_done_rounded, size: 14, color: GeminiTheme.cyan),
                          label: const Text('DropSync Cloud (Vercel)', style: TextStyle(fontSize: 11, color: GeminiTheme.textPrimary)),
                          onPressed: () {
                            setDialogState(() {
                              ctrl.text = 'https://dropsync-web.vercel.app';
                              testResult = null;
                            });
                          },
                        ),
                        ActionChip(
                          backgroundColor: GeminiTheme.surfaceVariant,
                          avatar: const Icon(Icons.dns_rounded, size: 14, color: GeminiTheme.lavender),
                          label: const Text('Render / Cloud', style: TextStyle(fontSize: 11, color: GeminiTheme.textPrimary)),
                          onPressed: () {
                            setDialogState(() {
                              ctrl.text = 'https://dropsync-relay.onrender.com';
                              testResult = null;
                            });
                          },
                        ),
                        ActionChip(
                          backgroundColor: GeminiTheme.surfaceVariant,
                          avatar: const Icon(Icons.computer_rounded, size: 14, color: GeminiTheme.emeraldGreen),
                          label: const Text('Local (Port 3000)', style: TextStyle(fontSize: 11, color: GeminiTheme.textPrimary)),
                          onPressed: () {
                            setDialogState(() {
                              ctrl.text = Platform.isAndroid ? 'http://10.0.2.2:3000' : 'http://localhost:3000';
                              testResult = null;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    TextField(
                      controller: ctrl,
                      style: const TextStyle(color: GeminiTheme.textPrimary, fontFamily: 'Consolas', fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Relay Endpoint URL',
                        labelStyle: const TextStyle(color: GeminiTheme.cyan),
                        hintText: 'https://dropsync.voidranger.workers.dev',
                        hintStyle: const TextStyle(color: GeminiTheme.textMuted),
                        filled: true,
                        fillColor: GeminiTheme.surfaceVariant,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.clear, size: 18, color: GeminiTheme.textMuted),
                          onPressed: () => setDialogState(() => ctrl.clear()),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Test Connection Button & Latency Benchmark
                    Row(
                      children: [
                        OutlinedButton.icon(
                          icon: isTesting
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: GeminiTheme.cyan))
                              : const Icon(Icons.speed_rounded, size: 16, color: GeminiTheme.cyan),
                          label: Text(isTesting ? 'Testing...' : 'Test Connection & Ping', style: const TextStyle(fontSize: 12, color: GeminiTheme.cyan)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: GeminiTheme.cyan),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: isTesting
                              ? null
                              : () async {
                                  setDialogState(() {
                                    isTesting = true;
                                    testResult = null;
                                  });
                                  final res = await widget.internetService.checkRelayHealth(ctrl.text);
                                  setDialogState(() {
                                    isTesting = false;
                                    testResult = res;
                                  });
                                },
                        ),
                      ],
                    ),

                    if (testResult != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (testResult!['ok'] == true ? GeminiTheme.emeraldGreen : GeminiTheme.coralError).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: (testResult!['ok'] == true ? GeminiTheme.emeraldGreen : GeminiTheme.coralError).withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              testResult!['ok'] == true ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                              size: 18,
                              color: testResult!['ok'] == true ? GeminiTheme.emeraldGreen : GeminiTheme.coralError,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                testResult!['ok'] == true
                                    ? 'Online (${testResult!['latencyMs']} ms latency) • Storage: ${testResult!['storageEngine']}'
                                    : 'Unreachable: ${testResult!['error'] ?? "Connection refused"}',
                                style: TextStyle(
                                  color: testResult!['ok'] == true ? GeminiTheme.emeraldGreen : GeminiTheme.coralError,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.terminal_rounded, size: 14, color: GeminiTheme.lavender),
                              SizedBox(width: 6),
                              Text('Self-Host Commands (vercel/ directory):', style: TextStyle(color: GeminiTheme.textPrimary, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          SizedBox(height: 4),
                          Text(
                            '• Node.js: npm start (or node server.js)\n• Docker: docker build -t dropsync-relay vercel/ && docker run -p 3000:3000 dropsync-relay\n• Cloud: npx vercel --prod',
                            style: TextStyle(color: GeminiTheme.textMuted, fontSize: 10, fontFamily: 'Consolas'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setDialogState(() {
                    ctrl.text = InternetTransferService.defaultRelayUrl;
                    testResult = null;
                  });
                },
                child: const Text('Reset Default', style: TextStyle(color: GeminiTheme.cyan)),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel', style: TextStyle(color: GeminiTheme.textMuted)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: GeminiTheme.cyan,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  widget.internetService.setVercelUrl(ctrl.text);
                  if (mounted) setState(() {});
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Relay endpoint saved: ${ctrl.text}')),
                  );
                },
                child: const Text('Save & Connect', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = context.responsiveHorizontalPadding;
    final verticalPadding = context.isMobile ? 12.0 : 20.0;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Banner with E2EE and Vercel branding
              _buildTopHeader(),

              const SizedBox(height: 14),

              // Mutual Presence Guard Banner
              _buildPresenceBanner(),

              const SizedBox(height: 14),

              // Send / Receive Internet Mode Switcher
              _buildModeSwitcher(),

              const SizedBox(height: 16),

              // Active View (Send or Receive)
              _mode == InternetMode.send ? _buildSendSection() : _buildReceiveSection(),

              const SizedBox(height: 16),

              // Active Transfer Progress Widget
              if (_activeSession != null) ...[
                TransferProgressWidget(
                  session: _activeSession!,
                  onDismiss: () => setState(() => _activeSession = null),
                ),
                const SizedBox(height: 16),
              ],

              // Security & Vercel Info Card
              _buildSecurityInfoCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader() {
    final isCompact = context.isCompact;
    final isCf = widget.internetService.isCloudflareRelay;
    final isWs = widget.internetService.isWebSocketConnected;
    final host = widget.internetService.relayHost;

    return Container(
      padding: EdgeInsets.all(context.responsiveCardPadding),
      decoration: BoxDecoration(
        color: GeminiTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(isCompact ? 18 : 24),
        border: GeminiTheme.thinBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  gradient: GeminiTheme.geminiGlowGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.public_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Internet Transfer (E2EE)',
                            style: TextStyle(
                              color: GeminiTheme.textPrimary,
                              fontSize: isCompact ? 16 : 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: GeminiTheme.emeraldGreen.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: GeminiTheme.emeraldGreen.withOpacity(0.4)),
                          ),
                          child: const Text(
                            '256-BIT AES-GCM',
                            style: TextStyle(
                              color: GeminiTheme.emeraldGreen,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Global WAN sync • Zero-knowledge encryption',
                      style: TextStyle(color: GeminiTheme.textSecondary, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.tune_rounded, color: GeminiTheme.cyan, size: 20),
                onPressed: _showVercelConfigDialog,
                tooltip: 'Configure Relay Server',
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Live Relay Connection & Ping Chip
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _showVercelConfigDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isCf ? const Color(0xFFF38020).withOpacity(0.12) : Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isCf ? const Color(0xFFF38020).withOpacity(0.4) : Colors.white.withOpacity(0.08),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: isWs
                          ? GeminiTheme.emeraldGreen
                          : (isCf ? const Color(0xFFF38020) : GeminiTheme.cyan),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      isCf
                          ? (isWs ? '⚡ Cloudflare ($host) • Active' : '⚡ Cloudflare ($host) • Connecting...')
                          : '🌐 Relay ($host)',
                      style: TextStyle(
                        color: isCf ? const Color(0xFFFFA033) : GeminiTheme.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Tap to switch',
                    style: TextStyle(color: GeminiTheme.textMuted.withOpacity(0.7), fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresenceBanner() {
    final presence = widget.internetService.presenceState;
    final bothPresent = widget.internetService.areBothPresent;

    Color color;
    IconData icon;
    String title;
    String subtitle;

    if (bothPresent) {
      color = GeminiTheme.emeraldGreen;
      icon = Icons.verified_user_rounded;
      title = 'BOTH PEERS CONNECTED';
      subtitle = 'Mutual presence confirmed. Encrypted transmission is active.';
    } else if (presence == InternetPeerPresence.waitingForPeer) {
      color = GeminiTheme.amberWarning;
      icon = Icons.hourglass_top_rounded;
      title = 'WAITING FOR PEER TO OPEN THIS PAGE';
      subtitle = 'Both sender and receiver must be on this screen for transfer to occur.';
    } else {
      color = GeminiTheme.textMuted;
      icon = Icons.cloud_queue_rounded;
      title = 'CONNECTING TO E2EE ROOM';
      subtitle = 'Establishing secure handshake...';
    }

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(bothPresent ? 0.4 : 0.25)),
            boxShadow: bothPresent
                ? [
                    BoxShadow(
                      color: color.withOpacity(0.12 * _pulseAnimation.value),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ]
                : [],
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(color: GeminiTheme.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModeSwitcher() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: GeminiTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildSubTab(
              label: 'Send via Internet',
              icon: Icons.upload_rounded,
              isSelected: _mode == InternetMode.send,
              onTap: () {
                setState(() => _mode = InternetMode.send);
                _initSenderRoom();
              },
            ),
          ),
          Expanded(
            child: _buildSubTab(
              label: 'Receive via Internet',
              icon: Icons.download_rounded,
              isSelected: _mode == InternetMode.receive,
              onTap: () {
                setState(() => _mode = InternetMode.receive);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubTab({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(100),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          gradient: isSelected ? GeminiTheme.geminiHorizontalGradient : null,
          boxShadow: isSelected ? GeminiTheme.glowShadow(color: GeminiTheme.cyan, blur: 12) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : GeminiTheme.textMuted),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : GeminiTheme.textSecondary,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSendSection() {
    final code = _currentCode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Room Code Display Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: GeminiTheme.surfaceContainer,
            borderRadius: BorderRadius.circular(22),
            border: GeminiTheme.thinBorder,
          ),
          child: Column(
            children: [
              const Text(
                'YOUR E2EE ROOM CODE',
                style: TextStyle(
                  color: GeminiTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              if (_isCreatingRoom)
                const SizedBox(
                  height: 36,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: GeminiTheme.cyan)),
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      code,
                      style: const TextStyle(
                        fontFamily: 'Consolas',
                        color: GeminiTheme.cyan,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3.0,
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, color: GeminiTheme.lavender, size: 22),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: code));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Room Code $code copied to clipboard!')),
                        );
                      },
                      tooltip: 'Copy Code',
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, color: GeminiTheme.textSecondary, size: 22),
                      onPressed: () => _initSenderRoom(),
                      tooltip: 'Regenerate Code',
                    ),
                  ],
                ),
              const SizedBox(height: 10),
              // Direct Web Share Link pill & copy
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: GeminiTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.public_rounded, size: 16, color: GeminiTheme.cyan),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${widget.internetService.vercelUrl}/?room=$code',
                        style: const TextStyle(
                          color: GeminiTheme.textPrimary,
                          fontSize: 12,
                          fontFamily: 'Consolas',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 16, color: GeminiTheme.cyan),
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        final link = '${widget.internetService.vercelUrl}/?room=$code';
                        Clipboard.setData(ClipboardData(text: link));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Long-distance web link copied! The page unlocks when you start the transfer.'),
                            duration: Duration(seconds: 3),
                          ),
                        );
                      },
                      tooltip: 'Copy Web Link',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: GeminiTheme.lavender.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: GeminiTheme.lavender.withOpacity(0.2)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_clock_rounded, size: 14, color: GeminiTheme.lavender),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'This web page stays locked until you tap "Encrypt & Send Files".',
                        style: TextStyle(color: GeminiTheme.lavender, fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // QR Code representation (Standard Web URL opens browser directly or DropSync in-app)
              if (code.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: QrImageView(
                    data: '${widget.internetService.vercelUrl}/?room=$code',
                    version: QrVersions.auto,
                    size: 140,
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // File Selection & Send Actions
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: GeminiTheme.surfaceContainer,
            borderRadius: BorderRadius.circular(22),
            border: GeminiTheme.thinBorder,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Selected Files to Encrypt',
                    style: TextStyle(color: GeminiTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  if (_selectedFiles.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() => _selectedFiles.clear()),
                      child: const Text('Clear', style: TextStyle(color: GeminiTheme.coralError, fontSize: 12)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickFiles,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  decoration: BoxDecoration(
                    color: GeminiTheme.surfaceVariant.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: GeminiTheme.cyan.withOpacity(0.3)),
                  ),
                  child: const Center(
                    child: Column(
                      children: [
                        Icon(Icons.add_circle_outline_rounded, color: GeminiTheme.cyan, size: 28),
                        SizedBox(height: 8),
                        Text(
                          'Tap to pick files for Internet E2EE Transfer',
                          style: TextStyle(color: GeminiTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              if (_selectedFiles.isNotEmpty) ...[
                const SizedBox(height: 12),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _selectedFiles.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, idx) {
                    final f = _selectedFiles[idx];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: GeminiTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.insert_drive_file_rounded, size: 16, color: GeminiTheme.cyan),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              p.basename(f.path),
                              style: const TextStyle(color: GeminiTheme.textPrimary, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 16, color: GeminiTheme.textMuted),
                            onPressed: () => setState(() => _selectedFiles.removeAt(idx)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],

              const SizedBox(height: 16),

              // Prominent Send Button
              Container(
                decoration: BoxDecoration(
                  gradient: (_selectedFiles.isNotEmpty && widget.internetService.areBothPresent)
                      ? GeminiTheme.geminiHorizontalGradient
                      : null,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: ElevatedButton.icon(
                  onPressed: _startSending,
                  icon: const Icon(Icons.lock_rounded, size: 18),
                  label: Text(
                    _selectedFiles.isEmpty
                        ? 'Select Files to Send'
                        : (!widget.internetService.areBothPresent
                            ? 'Waiting for Receiver to Connect...'
                            : 'Encrypt & Send Files (E2EE)'),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: (_selectedFiles.isNotEmpty && widget.internetService.areBothPresent)
                        ? Colors.transparent
                        : GeminiTheme.surfaceVariant,
                    foregroundColor: (_selectedFiles.isNotEmpty && widget.internetService.areBothPresent)
                        ? Colors.white
                        : GeminiTheme.textSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReceiveSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: GeminiTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(22),
        border: GeminiTheme.thinBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'JOIN E2EE ROOM TO RECEIVE',
            style: TextStyle(
              color: GeminiTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Enter the 6-character room code from the sender device to establish encrypted stream:',
            style: TextStyle(color: GeminiTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _roomCodeInputController,
                  style: const TextStyle(
                    fontFamily: 'Consolas',
                    color: GeminiTheme.cyan,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                  ),
                  decoration: InputDecoration(
                    hintText: 'e.g. 742-198',
                    hintStyle: const TextStyle(color: GeminiTheme.textMuted),
                    filled: true,
                    fillColor: GeminiTheme.surfaceVariant,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    prefixIcon: const Icon(Icons.key_rounded, color: GeminiTheme.cyan),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                icon: const Icon(Icons.qr_code_scanner_rounded, color: GeminiTheme.lavender, size: 24),
                onPressed: _scanRoomQr,
                tooltip: 'Scan Room QR',
              ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _joinReceiverRoom(_roomCodeInputController.text),
            icon: const Icon(Icons.vpn_key_rounded, size: 18),
            label: const Text('Join Room & Listen for Stream'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          if (_isReceivingStream) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: GeminiTheme.emeraldGreen.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: GeminiTheme.emeraldGreen.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: GeminiTheme.emeraldGreen),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Connected! Listening for encrypted chunks from sender...',
                      style: TextStyle(color: GeminiTheme.emeraldGreen, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSecurityInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GeminiTheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.security_rounded, size: 16, color: GeminiTheme.cyan),
              SizedBox(width: 8),
              Text(
                'End-to-End Security & Mutual Presence Guard',
                style: TextStyle(color: GeminiTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            '• Pure 256-bit AES-GCM: Chunks are encrypted on your local device with ephemeral keys. Plaintext never leaves your machine.\n'
            '• Strict Presence Check: Transfer is only allowed while both users stay actively inside this page in the app. Leaving the screen pauses the stream immediately.\n'
            '• Next Update (Vercel Ready): Designed for zero-config global serverless deployment on Vercel.',
            style: TextStyle(color: GeminiTheme.textSecondary, fontSize: 11, height: 1.45),
          ),
        ],
      ),
    );
  }
}
