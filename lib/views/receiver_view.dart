import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:qr_flutter/qr_flutter.dart';
import '../models/transfer_session.dart';
import '../services/hotspot_service.dart';
import '../services/network_service.dart';
import '../services/storage/storage_service.dart';
import '../theme/gemini_theme.dart';
import '../widgets/transfer_progress_widget.dart';
import '../theme/responsive.dart';

/// Receiver Mode View: Displays QR code, LAN IP, background socket status,
/// custom storage location picker, Hotspot Mode, and live download progress.
class ReceiverView extends StatefulWidget {
  final NetworkService networkService;
  final StorageService storageService;
  final HotspotService hotspotService;

  const ReceiverView({
    super.key,
    required this.networkService,
    required this.storageService,
    required this.hotspotService,
  });

  @override
  State<ReceiverView> createState() => _ReceiverViewState();
}

class _ReceiverViewState extends State<ReceiverView>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  TransferSession? _activeTransfer;
  final List<File> _receivedFiles = [];
  bool _hotspotMode = false;
  String _hotspotIp = '192.168.43.1';
  bool _showWifiConnectQr = true; // When in Hotspot mode, default to standard Wi-Fi QR for phone camera pairing

  @override
  void initState() {
    super.initState();
    _hotspotMode = widget.hotspotService.isHotspotMode;
    _refreshHotspotIp();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Listen to transfer progress
    widget.networkService.activeTransferStream.listen((session) {
      if (mounted) {
        setState(() {
          _activeTransfer = session;
        });
      }
    });

    // Listen to newly received files
    widget.networkService.fileReceivedStream.listen((file) {
      if (mounted) {
        setState(() {
          _receivedFiles.insert(0, file);
        });
      }
    });
  }

  Future<void> _refreshHotspotIp() async {
    final ip = await widget.hotspotService.getSuggestedHotspotIp(widget.networkService.localIp);
    if (mounted) {
      setState(() {
        _hotspotIp = ip;
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String get _qrPayload {
    if (_hotspotMode && _showWifiConnectQr && widget.hotspotService.ssid.isNotEmpty) {
      return PeerQrHelper.createWifiQrString(
        ssid: widget.hotspotService.ssid,
        password: widget.hotspotService.password,
        ip: _hotspotIp,
        port: widget.networkService.currentPort,
        token: widget.networkService.sessionToken,
      );
    }
    final effectiveIp = _hotspotMode ? _hotspotIp : widget.networkService.localIp;
    return PeerQrHelper.createQrJson(
      ip: effectiveIp,
      port: widget.networkService.currentPort,
      token: widget.networkService.sessionToken,
      device: widget.networkService.deviceName,
      ssid: _hotspotMode ? widget.hotspotService.ssid : null,
      password: _hotspotMode ? widget.hotspotService.password : null,
      isHotspot: _hotspotMode,
    );
  }

  void _copyQrPayload() {
    Clipboard.setData(ClipboardData(text: _qrPayload));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_hotspotMode && _showWifiConnectQr
            ? 'Wi-Fi connection credentials copied to clipboard'
            : 'Pairing JSON copied to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openDownloadDirectory() async {
    final path = widget.storageService.downloadDirectory;
    if (Platform.isWindows) {
      await Process.run('explorer.exe', [path]);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Files saved to: $path'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _showConfigureHotspotDialog() {
    final ssidCtrl = TextEditingController(text: widget.hotspotService.ssid);
    final passCtrl = TextEditingController(text: widget.hotspotService.password);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: GeminiTheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.wifi_tethering_rounded, color: GeminiTheme.emeraldGreen),
            SizedBox(width: 10),
            Text('Configure Hotspot', style: TextStyle(color: GeminiTheme.textPrimary, fontSize: 18)),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter the Wi-Fi Hotspot name (SSID) and Password of this device so senders can connect directly:',
                style: TextStyle(color: GeminiTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ssidCtrl,
                style: const TextStyle(color: GeminiTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Hotspot SSID / Network Name',
                  labelStyle: const TextStyle(color: GeminiTheme.cyan),
                  filled: true,
                  fillColor: GeminiTheme.surfaceVariant,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.wifi_rounded, color: GeminiTheme.cyan),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: passCtrl,
                style: const TextStyle(color: GeminiTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Hotspot Password',
                  labelStyle: const TextStyle(color: GeminiTheme.lavender),
                  filled: true,
                  fillColor: GeminiTheme.surfaceVariant,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.lock_rounded, color: GeminiTheme.lavender),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: GeminiTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newSsid = ssidCtrl.text.trim();
              final newPass = passCtrl.text.trim();
              if (newSsid.isNotEmpty) {
                final nav = Navigator.of(ctx);
                final messenger = ScaffoldMessenger.of(context);
                await widget.hotspotService.saveSettings(
                  enabled: _hotspotMode,
                  ssid: newSsid,
                  password: newPass,
                );
                await _refreshHotspotIp();
                if (mounted) {
                  setState(() {});
                  nav.pop();
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Hotspot credentials updated')),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final net = widget.networkService;
    final storage = widget.storageService;
    final isListening = net.connectionState != ServerConnectionState.stopped;

    final horizontalPadding = context.responsiveHorizontalPadding;
    final verticalPadding = context.isMobile ? 12.0 : 24.0;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Status & Device Info Card
              _buildDeviceBanner(net, isListening),

              const SizedBox(height: 14),

              // Hotspot Mode Card
              _buildHotspotCard(),

              const SizedBox(height: 14),

              // Stylized QR Code Pairing Card
              _buildQrCodeCard(net),

              const SizedBox(height: 16),

              // Active Transfer Progress Widget
              if (_activeTransfer != null) ...[
                const Text(
                  'CURRENT TRANSFER',
                  style: TextStyle(
                    color: GeminiTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                TransferProgressWidget(
                  session: _activeTransfer!,
                  onDismiss: () {
                    setState(() => _activeTransfer = null);
                  },
                ),
                const SizedBox(height: 16),
              ],

              // Received Files & Destination Directory Card
              _buildStorageAndReceivedCard(net, storage),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceBanner(NetworkService net, bool isListening) {
    final cardPadding = context.responsiveCardPadding;
    final isCompact = context.isCompact;

    return Container(
      padding: EdgeInsets.all(cardPadding),
      decoration: BoxDecoration(
        color: GeminiTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(isCompact ? 18 : 24),
        border: GeminiTheme.thinBorder,
        boxShadow: GeminiTheme.subtleCardShadow,
      ),
      child: Row(
        children: [
          // Glowing status ring
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              final ringSize = isCompact ? 42.0 : 52.0;
              return Container(
                width: ringSize,
                height: ringSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isListening
                      ? GeminiTheme.emeraldGreen.withOpacity(0.15)
                      : GeminiTheme.coralError.withOpacity(0.15),
                  boxShadow: isListening
                      ? [
                          BoxShadow(
                            color: GeminiTheme.emeraldGreen.withOpacity(0.3),
                            blurRadius: 16 * _pulseAnimation.value,
                            spreadRadius: 2 * _pulseAnimation.value,
                          ),
                        ]
                      : [],
                ),
                child: Center(
                  child: Icon(
                    isListening
                        ? Icons.wifi_tethering_rounded
                        : Icons.portable_wifi_off_rounded,
                    color: isListening
                        ? GeminiTheme.emeraldGreen
                        : GeminiTheme.coralError,
                    size: isCompact ? 22 : 26,
                  ),
                ),
              );
            },
          ),
          SizedBox(width: isCompact ? 10 : 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        net.deviceName,
                        style: TextStyle(
                          color: GeminiTheme.textPrimary,
                          fontSize: isCompact ? 15 : 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: GeminiTheme.electricBlue.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        Platform.operatingSystem.toUpperCase(),
                        style: const TextStyle(
                          color: GeminiTheme.cyan,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  net.statusMessage,
                  style: const TextStyle(
                    color: GeminiTheme.textSecondary,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Token Badge
          Container(
            padding: EdgeInsets.symmetric(horizontal: isCompact ? 8 : 12, vertical: isCompact ? 4 : 6),
            decoration: BoxDecoration(
              color: GeminiTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              children: [
                const Text(
                  'PIN',
                  style: TextStyle(
                    color: GeminiTheme.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  net.sessionToken,
                  style: TextStyle(
                    color: GeminiTheme.lavender,
                    fontSize: isCompact ? 13 : 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: isCompact ? 1.0 : 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHotspotCard() {
    final cardPadding = context.responsiveCardPadding;
    final isCompact = context.isCompact;

    return Container(
      padding: EdgeInsets.all(cardPadding),
      decoration: BoxDecoration(
        color: _hotspotMode
            ? GeminiTheme.emeraldGreen.withOpacity(0.08)
            : GeminiTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(isCompact ? 18 : 24),
        border: Border.all(
          color: _hotspotMode
              ? GeminiTheme.emeraldGreen.withOpacity(0.35)
              : Colors.white.withOpacity(0.06),
        ),
        boxShadow: _hotspotMode
            ? [
                BoxShadow(
                  color: GeminiTheme.emeraldGreen.withOpacity(0.15),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ]
            : GeminiTheme.subtleCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _hotspotMode
                      ? GeminiTheme.emeraldGreen.withOpacity(0.2)
                      : GeminiTheme.surfaceVariant,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.wifi_tethering_rounded,
                  color: _hotspotMode
                      ? GeminiTheme.emeraldGreen
                      : GeminiTheme.textSecondary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Wi-Fi Hotspot Mode',
                            style: TextStyle(
                              color: GeminiTheme.textPrimary,
                              fontSize: isCompact ? 14 : 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (_hotspotMode) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: GeminiTheme.emeraldGreen.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'DIRECT P2P',
                              style: TextStyle(
                                color: GeminiTheme.emeraldGreen,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _hotspotMode
                          ? 'Senders will auto-connect to this hotspot via QR code'
                          : 'Transfer without shared Wi-Fi router or internet',
                      style: const TextStyle(
                        color: GeminiTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _hotspotMode,
                activeColor: GeminiTheme.emeraldGreen,
                onChanged: (val) async {
                  widget.hotspotService.setHotspotMode(val);
                  setState(() => _hotspotMode = val);
                  await _refreshHotspotIp();
                  if (val && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Hotspot Mode active! Senders scanning QR will connect to this Hotspot.'),
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
          if (_hotspotMode) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: GeminiTheme.surfaceVariant.withOpacity(0.7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.04)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.wifi_rounded, size: 14, color: GeminiTheme.cyan),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'SSID: ${widget.hotspotService.ssid}',
                                style: const TextStyle(
                                  color: GeminiTheme.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.lock_outline_rounded, size: 14, color: GeminiTheme.lavender),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                widget.hotspotService.password.isNotEmpty
                                    ? 'Password: ${widget.hotspotService.password}'
                                    : 'Password: (None / Open)',
                                style: const TextStyle(
                                  color: GeminiTheme.textSecondary,
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _showConfigureHotspotDialog,
                    icon: const Icon(Icons.edit_rounded, size: 14, color: GeminiTheme.cyan),
                    label: const Text('Edit', style: TextStyle(color: GeminiTheme.cyan, fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      side: BorderSide(color: GeminiTheme.cyan.withOpacity(0.4)),
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

  Widget _buildQrCodeCard(NetworkService net) {
    final cardPadding = context.responsiveCardPadding;

    return Container(
      padding: EdgeInsets.all(cardPadding),
      decoration: BoxDecoration(
        color: GeminiTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(context.isCompact ? 20 : 28),
        border: GeminiTheme.thinBorder,
        boxShadow: GeminiTheme.subtleCardShadow,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Pairing QR Code',
                          style: TextStyle(
                            color: GeminiTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_hotspotMode) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: GeminiTheme.emeraldGreen.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: GeminiTheme.emeraldGreen.withOpacity(0.4)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.wifi_tethering_rounded, size: 11, color: GeminiTheme.emeraldGreen),
                                SizedBox(width: 4),
                                Text(
                                  'HOTSPOT READY',
                                  style: TextStyle(
                                    color: GeminiTheme.emeraldGreen,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _hotspotMode
                          ? 'Encodes Hotspot Wi-Fi connection & DropSync credentials'
                          : 'Scan with DropSync sender on Android or PC',
                      style: const TextStyle(
                        color: GeminiTheme.textSecondary,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded,
                    color: GeminiTheme.cyan, size: 20),
                onPressed: _copyQrPayload,
                tooltip: 'Copy pairing JSON',
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Hotspot QR Mode Selector (Wi-Fi standard vs DropSync pairing)
          if (_hotspotMode) ...[
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: GeminiTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(100),
                    onTap: () => setState(() => _showWifiConnectQr = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _showWifiConnectQr ? GeminiTheme.emeraldGreen : Colors.transparent,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi_rounded, size: 14, color: _showWifiConnectQr ? Colors.black : GeminiTheme.textSecondary),
                          const SizedBox(width: 6),
                          Text(
                            'Wi-Fi Connect (Camera)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _showWifiConnectQr ? Colors.black : GeminiTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(100),
                    onTap: () => setState(() => _showWifiConnectQr = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: !_showWifiConnectQr ? GeminiTheme.cyan : Colors.transparent,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.qr_code_2_rounded, size: 14, color: !_showWifiConnectQr ? Colors.black : GeminiTheme.textSecondary),
                          const SizedBox(width: 6),
                          Text(
                            'App Direct (JSON)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: !_showWifiConnectQr ? Colors.black : GeminiTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _showWifiConnectQr
                  ? 'Scan with any phone camera to connect directly to this Wi-Fi hotspot'
                  : 'Scan with DropSync in-app camera scanner',
              style: const TextStyle(color: GeminiTheme.textMuted, fontSize: 11),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
          ],

          // Stylized QR Code with glowing frame that scales responsively
          LayoutBuilder(
            builder: (context, constraints) {
              final qrSize = (constraints.maxWidth * 0.58).clamp(130.0, 210.0);
              return Container(
                padding: EdgeInsets.all(context.isCompact ? 10 : 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(context.isCompact ? 18 : 24),
                  border: Border.all(
                    color: _hotspotMode
                        ? GeminiTheme.emeraldGreen.withOpacity(0.7)
                        : GeminiTheme.cyan.withOpacity(0.5),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _hotspotMode
                          ? GeminiTheme.emeraldGreen.withOpacity(0.28)
                          : GeminiTheme.electricBlue.withOpacity(0.25),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: QrImageView(
                  data: _qrPayload,
                  version: QrVersions.auto,
                  size: qrSize,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF0E0E10),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF1E1F22),
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 18),

          // LAN Address & Port Pills
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (_hotspotMode)
                _buildInfoPill(
                  icon: Icons.wifi_tethering_rounded,
                  label: 'Hotspot',
                  value: widget.hotspotService.ssid,
                  color: GeminiTheme.emeraldGreen,
                ),
              _buildInfoPill(
                icon: Icons.lan_rounded,
                label: 'IP',
                value: _hotspotMode ? _hotspotIp : net.localIp,
                color: GeminiTheme.cyan,
              ),
              _buildInfoPill(
                icon: Icons.tag_rounded,
                label: 'Port',
                value: '${net.currentPort}',
                color: GeminiTheme.lavender,
              ),
              _buildInfoPill(
                icon: Icons.lock_outline_rounded,
                label: 'Token',
                value: net.sessionToken,
                color: GeminiTheme.emeraldGreen,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPill({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: GeminiTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: const TextStyle(
              color: GeminiTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: GeminiTheme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageAndReceivedCard(NetworkService net, StorageService storage) {
    final cardPadding = context.responsiveCardPadding;
    final isCompact = context.isCompact;

    return Container(
      padding: EdgeInsets.all(cardPadding),
      decoration: BoxDecoration(
        color: GeminiTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(isCompact ? 18 : 24),
        border: GeminiTheme.thinBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_open_rounded,
                      color: GeminiTheme.cyan, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Save Destination',
                    style: TextStyle(
                      color: GeminiTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      final picked = await storage.pickAndSetCustomDirectory();
                      if (picked != null && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Save location: $picked')),
                        );
                      }
                    },
                    icon: const Icon(Icons.edit_location_alt_rounded, size: 16),
                    label: const Text('Change'),
                    style: TextButton.styleFrom(
                      foregroundColor: GeminiTheme.lavender,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _openDownloadDirectory,
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Open'),
                    style: TextButton.styleFrom(
                      foregroundColor: GeminiTheme.cyan,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            storage.downloadDirectory,
            style: const TextStyle(
              color: GeminiTheme.textMuted,
              fontSize: 12,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (_receivedFiles.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            const Text(
              'RECENTLY RECEIVED IN THIS SESSION',
              style: TextStyle(
                color: GeminiTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _receivedFiles.length.clamp(0, 5),
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final file = _receivedFiles[index];
                final name = p.basename(file.path);
                final size = file.existsSync() ? file.lengthSync() : 0;
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: GeminiTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.insert_drive_file_rounded,
                          color: GeminiTheme.cyan, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            color: GeminiTheme.textPrimary,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _formatFileSize(size),
                        style: const TextStyle(
                          color: GeminiTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Helper to serialize pairing JSON format:
/// `{"ip": "<local_ip>", "port": 8080, "token": "<session_token>", "device": "<device_name>", "ssid": "...", "password": "...", "isHotspot": true}`
class PeerQrHelper {
  /// Standard ZXing / Mobile Wi-Fi format: WIFI:S:<SSID>;T:WPA;P:<PASSWORD>;;
  /// Phones scanning this barcode with their native camera immediately prompt "Join Wi-Fi network"
  static String createWifiQrString({
    required String ssid,
    required String password,
    String? ip,
    int? port,
    String? token,
  }) {
    final buffer = StringBuffer('WIFI:S:$ssid;T:WPA;P:$password;');
    if (ip != null && ip.isNotEmpty) buffer.write('IP:$ip;');
    if (port != null) buffer.write('PORT:$port;');
    if (token != null && token.isNotEmpty) buffer.write('TOKEN:$token;');
    buffer.write(';');
    return buffer.toString();
  }

  static String createQrJson({
    required String ip,
    required int port,
    required String token,
    required String device,
    String? ssid,
    String? password,
    bool isHotspot = false,
  }) {
    final map = <String, dynamic>{
      'ip': ip,
      'port': port,
      'token': token,
      'device': device,
      'platform': Platform.operatingSystem,
    };
    if (isHotspot && ssid != null && ssid.isNotEmpty) {
      map['ssid'] = ssid;
      map['password'] = password ?? '';
      map['auth'] = 'WPA2';
      map['isHotspot'] = true;
    }
    return jsonEncode(map);
  }
}
