import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:multicast_dns/multicast_dns.dart';
import '../../models/peer.dart';

/// Quick Share mDNS Discovery and Advertising service using the official service type `_FC9F5ED42C8A._tcp`.
class QuickShareDiscovery {
  /// The official Google Nearby Connections / Quick Share mDNS service type
  static const String serviceType = '_FC9F5ED42C8A._tcp.local';
  static const String shortServiceType = '_FC9F5ED42C8A._tcp';

  final String deviceName;
  final int port;
  final String endpointId;

  MDnsClient? _mDnsClient;
  RawDatagramSocket? _advertiserSocket;
  Timer? _beaconTimer;

  final _peersController = StreamController<List<Peer>>.broadcast();
  final Map<String, Peer> _discoveredQuickSharePeers = {};

  Stream<List<Peer>> get peersStream => _peersController.stream;
  List<Peer> get currentPeers => _discoveredQuickSharePeers.values.toList();

  QuickShareDiscovery({
    required this.deviceName,
    required this.port,
    String? endpointId,
  }) : endpointId = endpointId ?? _generateEndpointId();

  /// Starts mDNS client to browse for nearby Quick Share peers and starts advertising DropSync.
  Future<void> start() async {
    await _startBrowser();
    await _startAdvertiser();
  }

  Future<void> _startBrowser() async {
    try {
      _mDnsClient = MDnsClient();
      await _mDnsClient!.start();

      // Periodically scan for _FC9F5ED42C8A._tcp.local PTR & SRV records
      _beaconTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        _queryQuickSharePeers();
      });
      _queryQuickSharePeers();
    } catch (e) {
      print('[QuickShare mDNS] Browser start warning: $e');
    }
  }

  Future<void> _queryQuickSharePeers() async {
    if (_mDnsClient == null) return;
    try {
      await for (final PtrResourceRecord ptr in _mDnsClient!.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(serviceType),
      )) {
        await for (final SrvResourceRecord srv in _mDnsClient!.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
        )) {
          await for (final IPAddressResourceRecord ip in _mDnsClient!.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
          )) {
            final targetIp = ip.address.address;
            final targetPort = srv.port;

            // Extract display name from domain name or default
            var peerName = 'Android Quick Share';
            if (ptr.domainName.contains('.')) {
              final prefix = ptr.domainName.split('.').first;
              if (prefix.isNotEmpty && !prefix.startsWith('_')) {
                peerName = prefix;
              }
            }

            final peerId = 'qs_${targetIp.replaceAll('.', '_')}_$targetPort';
            final peer = Peer(
              id: peerId,
              name: peerName,
              platform: 'android',
              ip: targetIp,
              port: targetPort,
              token: 'QUICK_SHARE',
              lastSeen: DateTime.now(),
              protocolType: PeerProtocolType.quickShare,
            );

            _discoveredQuickSharePeers[peerId] = peer;
            _emit();
          }
        }
      }
    } catch (_) {}
  }

  /// Advertises DropSync as an mDNS Quick Share receiver on the local subnet.
  Future<void> _startAdvertiser() async {
    try {
      _advertiserSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
      _advertiserSocket!.broadcastEnabled = true;

      // Broadcast mDNS response announcement to 224.0.0.251:5353
      _broadcastMdnsAnnouncement();
    } catch (_) {}
  }

  void _broadcastMdnsAnnouncement() {
    if (_advertiserSocket == null) return;
    try {
      final packet = _buildMdnsAnnouncementPacket();
      _advertiserSocket!.send(
        packet,
        InternetAddress('224.0.0.251'),
        5353,
      );
    } catch (_) {}
  }

  /// Builds a DNS response packet announcing the _FC9F5ED42C8A._tcp service.
  Uint8List _buildMdnsAnnouncementPacket() {
    final b = BytesBuilder();
    // Transaction ID: 0x0000
    b.add([0x00, 0x00]);
    // Flags: 0x8400 (Standard response, authoritative)
    b.add([0x84, 0x00]);
    // Questions: 0, Answers: 1, Auth RRs: 0, Additional: 0
    b.add([0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00]);

    // Name: _FC9F5ED42C8A._tcp.local
    _writeDnsName(b, '_FC9F5ED42C8A._tcp.local');

    // Type: PTR (12), Class: IN (1)
    b.add([0x00, 0x0C, 0x00, 0x01]);
    // TTL: 120 seconds
    b.add([0x00, 0x00, 0x00, 0x78]);

    // RDLENGTH & RDATA
    final instanceName = '$deviceName._FC9F5ED42C8A._tcp.local';
    final nameBytes = BytesBuilder();
    _writeDnsName(nameBytes, instanceName);
    final rdata = nameBytes.toBytes();
    b.add([rdata.length >> 8, rdata.length & 0xFF]);
    b.add(rdata);

    return b.toBytes();
  }

  static void _writeDnsName(BytesBuilder b, String name) {
    final parts = name.split('.');
    for (final part in parts) {
      final bytes = utf8.encode(part);
      b.addByte(bytes.length);
      b.add(bytes);
    }
    b.addByte(0); // Root null byte
  }

  /// Generates the official Google Quick Share pairing URI for visual QR handshakes.
  static String generateQuickSharePairingUri(String endpointKey) {
    return 'https://quickshare.google/qrcode#key=$endpointKey';
  }

  static String _generateEndpointId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random();
    return List.generate(4, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  void _emit() {
    if (!_peersController.isClosed) {
      _peersController.add(_discoveredQuickSharePeers.values.toList());
    }
  }

  void stop() {
    _beaconTimer?.cancel();
    _mDnsClient?.stop();
    _advertiserSocket?.close();
    _peersController.close();
  }
}
