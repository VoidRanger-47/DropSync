import 'dart:convert';

enum PeerProtocolType {
  dropsync,
  quickShare,
}

/// Represents a peer node discovered on the local network (via Native DropSync or Quick Share mDNS).
class Peer {
  final String id;
  final String name;
  final String platform;
  final String ip;
  final int port;
  final String token;
  final DateTime lastSeen;
  final bool isManual;
  final PeerProtocolType protocolType;
  final String? hotspotSsid;
  final String? hotspotPassword;
  final bool isHotspot;

  Peer({
    required this.id,
    required this.name,
    required this.platform,
    required this.ip,
    required this.port,
    required this.token,
    required this.lastSeen,
    this.isManual = false,
    this.protocolType = PeerProtocolType.dropsync,
    this.hotspotSsid,
    this.hotspotPassword,
    this.isHotspot = false,
  });

  bool get isQuickShare => protocolType == PeerProtocolType.quickShare;

  /// Parse from standard JSON discovery beacon or direct message.
  factory Peer.fromJson(Map<String, dynamic> json, [String? sourceIp]) {
    final ipAddr = sourceIp ?? json['ip'] as String? ?? '127.0.0.1';
    final portNum = (json['port'] as num?)?.toInt() ?? 8080;
    final tokenStr = json['token'] as String? ?? '';
    final devName = json['device'] as String? ??
        json['device_name'] as String? ??
        'DropSync Node';
    final devId = json['id'] as String? ??
        json['device_id'] as String? ??
        'peer_${ipAddr.replaceAll('.', '_')}';
    final devPlatform = json['platform'] as String? ?? 'unknown';
    final ssid = json['ssid'] as String? ?? json['hotspot_ssid'] as String?;
    final pass = json['password'] as String? ?? json['hotspot_password'] as String?;
    final isHotspot = (json['isHotspot'] as bool?) ?? (ssid != null && ssid.isNotEmpty);

    return Peer(
      id: devId,
      name: devName,
      platform: devPlatform,
      ip: ipAddr,
      port: portNum,
      token: tokenStr,
      lastSeen: DateTime.now(),
      isManual: false,
      protocolType: PeerProtocolType.dropsync,
      hotspotSsid: ssid,
      hotspotPassword: pass,
      isHotspot: isHotspot,
    );
  }

  /// Parse from pairing QR code format:
  /// `{"ip": "<local_ip>", "port": 8080, "token": "<session_token>", "device": "<device_name>", "ssid": "...", "password": "...", "isHotspot": true}`
  /// OR Standard Wi-Fi QR Code string: `WIFI:S:MyHotspot;T:WPA;P:secret123;;`
  /// OR Internet E2EE Transfer Room: `DROPSYNC_E2EE:XXX-XXX` or `https://...?room=XXX-XXX`
  static Peer? fromQrString(String raw) {
    try {
      final trimmed = raw.trim();

      // Case 1: Standard Wi-Fi QR Code format (WIFI:S:SSID;T:WPA;P:PASSWORD;;)
      if (trimmed.toUpperCase().startsWith('WIFI:')) {
        String? ssid;
        String? password;
        String? customIp;
        int? customPort;
        String? token;

        final parts = trimmed.substring(5).split(';');
        for (final part in parts) {
          final p = part.trim();
          final upper = p.toUpperCase();
          if (upper.startsWith('S:')) {
            ssid = p.substring(2);
          } else if (upper.startsWith('P:')) {
            password = p.substring(2);
          } else if (upper.startsWith('IP:')) {
            customIp = p.substring(3);
          } else if (upper.startsWith('PORT:')) {
            customPort = int.tryParse(p.substring(5));
          } else if (upper.startsWith('TOKEN:')) {
            token = p.substring(6);
          }
        }
        if (ssid != null && ssid.isNotEmpty) {
          return Peer(
            id: 'hotspot_${ssid.replaceAll(' ', '_')}',
            name: ssid,
            platform: 'hotspot',
            ip: customIp ?? '192.168.43.1', // Standard mobile hotspot gateway fallback
            port: customPort ?? 8080,
            token: token ?? '',
            lastSeen: DateTime.now(),
            isManual: true,
            protocolType: PeerProtocolType.dropsync,
            hotspotSsid: ssid,
            hotspotPassword: password ?? '',
            isHotspot: true,
          );
        }
      }

      // Case 2: DropSync Internet Transfer Room (DROPSYNC_E2EE:XXX-XXX or https://...?room=XXX-XXX)
      if (trimmed.toUpperCase().startsWith('DROPSYNC_E2EE:') ||
          trimmed.contains('room=') ||
          RegExp(r'^\d{3}-\d{3}$').hasMatch(trimmed)) {
        String roomCode = '';
        if (trimmed.toUpperCase().startsWith('DROPSYNC_E2EE:')) {
          roomCode = trimmed.substring(14).trim();
        } else if (trimmed.contains('room=')) {
          final uri = Uri.tryParse(trimmed);
          roomCode = uri?.queryParameters['room'] ?? '';
          if (roomCode.isEmpty) {
            final match = RegExp(r'room=([A-Za-z0-9-]+)').firstMatch(trimmed);
            roomCode = match?.group(1) ?? '';
          }
        } else {
          roomCode = trimmed;
        }

        if (roomCode.isNotEmpty) {
          return Peer(
            id: 'e2ee_${roomCode.replaceAll('-', '_')}',
            name: 'Internet E2EE ($roomCode)',
            platform: 'internet',
            ip: 'internet',
            port: 443,
            token: roomCode,
            lastSeen: DateTime.now(),
            isManual: true,
            protocolType: PeerProtocolType.dropsync,
          );
        }
      }

      // Case 3: DropSync JSON format
      if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        final map = jsonDecode(trimmed) as Map<String, dynamic>;
        final ip = map['ip'] as String?;
        final port = (map['port'] as num?)?.toInt() ?? 8080;
        final token = map['token'] as String? ?? '';
        final device = map['device'] as String? ?? map['device_name'] as String? ?? 'Receiver Node';
        final platform = map['platform'] as String? ?? 'remote';
        final ssid = map['ssid'] as String? ?? map['hotspot_ssid'] as String?;
        final password = map['password'] as String? ?? map['hotspot_password'] as String?;
        final isHotspot = (map['isHotspot'] as bool?) ?? (ssid != null && ssid.isNotEmpty);

        if (ip != null && ip.isNotEmpty) {
          return Peer(
            id: 'qr_${ip.replaceAll('.', '_')}_$port',
            name: device,
            platform: platform,
            ip: ip,
            port: port,
            token: token,
            lastSeen: DateTime.now(),
            isManual: true,
            protocolType: PeerProtocolType.dropsync,
            hotspotSsid: ssid,
            hotspotPassword: password,
            isHotspot: isHotspot,
          );
        }
      } else {
        // Fallback: raw "IP:PORT" or "IP"
        final parts = trimmed.split(':');
        if (parts.isNotEmpty && parts[0].split('.').length == 4) {
          final ip = parts[0];
          final port = parts.length > 1 ? (int.tryParse(parts[1]) ?? 8080) : 8080;
          return Peer(
            id: 'raw_${ip.replaceAll('.', '_')}_$port',
            name: 'Direct Node ($ip)',
            platform: 'remote',
            ip: ip,
            port: port,
            token: '',
            lastSeen: DateTime.now(),
            isManual: true,
            protocolType: PeerProtocolType.dropsync,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  /// Serialize to pairing QR JSON string
  String toQrString() {
    return jsonEncode({
      'ip': ip,
      'port': port,
      'token': token,
      'device': name,
      'platform': platform,
      if (isHotspot && hotspotSsid != null) ...{
        'ssid': hotspotSsid,
        'password': hotspotPassword ?? '',
        'isHotspot': true,
      },
    });
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'device': name,
        'platform': platform,
        'ip': ip,
        'port': port,
        'token': token,
        'protocol': protocolType.name,
        if (isHotspot) ...{
          'ssid': hotspotSsid,
          'password': hotspotPassword,
          'isHotspot': true,
        },
      };

  Peer copyWith({
    String? id,
    String? name,
    String? platform,
    String? ip,
    int? port,
    String? token,
    DateTime? lastSeen,
    bool? isManual,
    PeerProtocolType? protocolType,
    String? hotspotSsid,
    String? hotspotPassword,
    bool? isHotspot,
  }) {
    return Peer(
      id: id ?? this.id,
      name: name ?? this.name,
      platform: platform ?? this.platform,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      token: token ?? this.token,
      lastSeen: lastSeen ?? this.lastSeen,
      isManual: isManual ?? this.isManual,
      protocolType: protocolType ?? this.protocolType,
      hotspotSsid: hotspotSsid ?? this.hotspotSsid,
      hotspotPassword: hotspotPassword ?? this.hotspotPassword,
      isHotspot: isHotspot ?? this.isHotspot,
    );
  }

  @override
  String toString() => '$name (${protocolType.name}) @ $ip:$port${isHotspot ? " [Hotspot: $hotspotSsid]" : ""}';
}
