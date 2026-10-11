import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/peer.dart';

/// UDP-based zero-configuration local network peer discovery.
class DiscoveryService {
  static const int defaultDiscoveryPort = 53535;
  static const String beaconMagic = 'DROPSYNC_BEACON';
  static const String probeMagic = 'DROPSYNC_PROBE';
  static const String _legacyBeaconMagic = 'NEARLINK_BEACON';
  static const String _legacyProbeMagic = 'NEARLINK_PROBE';

  final String deviceName;
  final String deviceId;
  final String platform;
  final int tcpPort;
  final String token;

  RawDatagramSocket? _broadcastSocket;
  Timer? _beaconTimer;
  Timer? _pruneTimer;

  final Map<String, Peer> _peers = {};
  final _peersController = StreamController<List<Peer>>.broadcast();

  Stream<List<Peer>> get peersStream => _peersController.stream;
  List<Peer> get currentPeers => _peers.values.toList();

  DiscoveryService({
    required this.deviceName,
    required this.deviceId,
    required this.platform,
    required this.tcpPort,
    required this.token,
  });

  /// Starts listening for UDP beacons and broadcasting self-presence.
  Future<void> start() async {
    try {
      _broadcastSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        defaultDiscoveryPort,
        reuseAddress: true,
        reusePort: !Platform.isWindows, // reusePort supported on POSIX/Android
      );
      _broadcastSocket!.broadcastEnabled = true;

      _broadcastSocket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _broadcastSocket?.receive();
          if (datagram != null) {
            _handleIncomingDatagram(datagram);
          }
        }
      }, onError: (err) {
        // Log silently
      });

      // Send immediate probe
      _sendProbe();

      // Periodically broadcast beacon every 2.5 seconds
      _beaconTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
        _broadcastBeacon();
      });

      // Periodically prune stale peers (every 3 seconds)
      _pruneTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        _pruneStalePeers();
      });

      // Initial broadcast
      _broadcastBeacon();
    } catch (e) {
      // If port is occupied or permission denied, continue gracefully
      print('[Discovery] UDP bind warning: $e');
    }
  }

  void _broadcastBeacon() {
    if (_broadcastSocket == null) return;
    try {
      final payload = jsonEncode({
        'magic': beaconMagic,
        'device': deviceName,
        'device_name': deviceName,
        'id': deviceId,
        'platform': platform,
        'port': tcpPort,
        'token': token,
      });

      final bytes = utf8.encode(payload);
      _broadcastSocket!.send(
        bytes,
        InternetAddress('255.255.255.255'),
        defaultDiscoveryPort,
      );
    } catch (_) {}
  }

  void _sendProbe() {
    if (_broadcastSocket == null) return;
    try {
      final payload = jsonEncode({
        'magic': probeMagic,
        'device': deviceName,
        'id': deviceId,
        'port': tcpPort,
      });
      final bytes = utf8.encode(payload);
      _broadcastSocket!.send(
        bytes,
        InternetAddress('255.255.255.255'),
        defaultDiscoveryPort,
      );
    } catch (_) {}
  }

  void _handleIncomingDatagram(Datagram datagram) {
    try {
      final raw = utf8.decode(datagram.data);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final magic = json['magic'] as String?;

      if (magic != beaconMagic &&
          magic != probeMagic &&
          magic != _legacyBeaconMagic &&
          magic != _legacyProbeMagic) {
        return;
      }

      final senderId = json['id'] as String? ?? json['device_id'] as String?;
      if (senderId == deviceId) {
        // Ignore self broadcasts
        return;
      }

      final sourceIp = datagram.address.address;
      final peer = Peer.fromJson(json, sourceIp);

      _peers[peer.id] = peer;
      _emitPeers();

      // If probe was received, respond with direct beacon
      if (magic == probeMagic || magic == _legacyProbeMagic) {
        _broadcastBeacon();
      }
    } catch (_) {}
  }

  void _pruneStalePeers() {
    final now = DateTime.now();
    bool changed = false;

    _peers.removeWhere((id, peer) {
      if (peer.isManual) return false;
      if (now.difference(peer.lastSeen).inSeconds > 8) {
        changed = true;
        return true;
      }
      return false;
    });

    if (changed) {
      _emitPeers();
    }
  }

  /// Adds a manually paired or scanned peer to the active list.
  void addManualPeer(Peer peer) {
    final manualPeer = peer.copyWith(isManual: true, lastSeen: DateTime.now());
    _peers[manualPeer.id] = manualPeer;
    _emitPeers();
  }

  void _emitPeers() {
    if (!_peersController.isClosed) {
      _peersController.add(_peers.values.toList());
    }
  }

  /// Force a fresh scan now
  void refreshScan() {
    _sendProbe();
    _broadcastBeacon();
  }

  void stop() {
    _beaconTimer?.cancel();
    _pruneTimer?.cancel();
    _broadcastSocket?.close();
    _peersController.close();
  }
}
