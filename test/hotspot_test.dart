import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dropsync/models/peer.dart';
import 'package:dropsync/services/hotspot_service.dart';
import 'package:dropsync/views/receiver_view.dart';

void main() {
  group('Hotspot QR Code Serialization & Parsing Tests', () {
    test('PeerQrHelper encodes Hotspot SSID, password and isHotspot flag', () {
      final jsonStr = PeerQrHelper.createQrJson(
        ip: '192.168.43.1',
        port: 8080,
        token: 'TEST',
        device: 'Test Phone',
        ssid: 'DropSync_Hotspot_123',
        password: 'pass_secret_456',
        isHotspot: true,
      );

      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(map['ip'], equals('192.168.43.1'));
      expect(map['port'], equals(8080));
      expect(map['token'], equals('TEST'));
      expect(map['device'], equals('Test Phone'));
      expect(map['ssid'], equals('DropSync_Hotspot_123'));
      expect(map['password'], equals('pass_secret_456'));
      expect(map['isHotspot'], isTrue);
      expect(map['auth'], equals('WPA2'));
    });

    test('Peer.fromQrString correctly parses DropSync Hotspot JSON payload', () {
      final payload = jsonEncode({
        'ip': '192.168.43.1',
        'port': 8080,
        'token': '9988',
        'device': 'Receiver Device',
        'ssid': 'Receiver_Hotspot',
        'password': 'mypassword789',
        'isHotspot': true,
      });

      final peer = Peer.fromQrString(payload);
      expect(peer, isNotNull);
      expect(peer!.ip, equals('192.168.43.1'));
      expect(peer.port, equals(8080));
      expect(peer.token, equals('9988'));
      expect(peer.name, equals('Receiver Device'));
      expect(peer.isHotspot, isTrue);
      expect(peer.hotspotSsid, equals('Receiver_Hotspot'));
      expect(peer.hotspotPassword, equals('mypassword789'));
    });

    test('Peer.fromQrString correctly parses standard Wi-Fi QR format (WIFI:S:...;P:...;;)', () {
      const wifiQr = 'WIFI:S:DropSync_Direct;T:WPA;P:directpass123;;';
      final peer = Peer.fromQrString(wifiQr);
      expect(peer, isNotNull);
      expect(peer!.isHotspot, isTrue);
      expect(peer.hotspotSsid, equals('DropSync_Direct'));
      expect(peer.hotspotPassword, equals('directpass123'));
      expect(peer.ip, equals('192.168.43.1'));
    });

    test('Peer.fromQrString handles reversed field order, quoted SSIDs, and escaped chars', () {
      // 1. Android Settings QR where T: is first and SSID is quoted
      const androidQr = 'WIFI:T:WPA;S:"Galaxy Hotspot";P:"securePass123";;';
      final peer1 = Peer.fromQrString(androidQr);
      expect(peer1, isNotNull);
      expect(peer1!.hotspotSsid, equals('Galaxy Hotspot'));
      expect(peer1.hotspotPassword, equals('securePass123'));
      expect(peer1.isHotspot, isTrue);

      // 2. Escaped semicolon and colon
      const escapedQr = r'WIFI:S:My\;Phone;P:pass\:123;;';
      final peer2 = Peer.fromQrString(escapedQr);
      expect(peer2, isNotNull);
      expect(peer2!.hotspotSsid, equals('My;Phone'));
      expect(peer2.hotspotPassword, equals('pass:123'));

      // 3. Open Wi-Fi (T:nopass) without password field
      const openQr = 'WIFI:T:nopass;S:OpenHotspot;;';
      final peer3 = Peer.fromQrString(openQr);
      expect(peer3, isNotNull);
      expect(peer3!.hotspotSsid, equals('OpenHotspot'));
      expect(peer3.hotspotPassword, equals(''));
    });

    test('Peer.fromQrString parses legacy non-hotspot JSON without crashing', () {
      final legacyPayload = jsonEncode({
        'ip': '192.168.1.100',
        'port': 8080,
        'token': '1234',
        'device': 'Router Peer',
      });

      final peer = Peer.fromQrString(legacyPayload);
      expect(peer, isNotNull);
      expect(peer!.ip, equals('192.168.1.100'));
      expect(peer.isHotspot, isFalse);
      expect(peer.hotspotSsid, isNull);
    });

    test('PeerQrHelper.createWifiQrString creates standard ZXing Wi-Fi format for camera scanning', () {
      final wifiStr = PeerQrHelper.createWifiQrString(
        ssid: 'Direct_WiFi_Net',
        password: 'securePassword99',
        ip: '192.168.43.1',
        port: 8080,
        token: '7788',
      );

      expect(wifiStr, startsWith('WIFI:S:Direct_WiFi_Net;T:WPA;P:securePassword99;'));
      expect(wifiStr, contains('IP:192.168.43.1;'));
      expect(wifiStr, contains('PORT:8080;'));
      expect(wifiStr, contains('TOKEN:7788;'));

      final peer = Peer.fromQrString(wifiStr);
      expect(peer, isNotNull);
      expect(peer!.isHotspot, isTrue);
      expect(peer.hotspotSsid, equals('Direct_WiFi_Net'));
      expect(peer.hotspotPassword, equals('securePassword99'));
      expect(peer.ip, equals('192.168.43.1'));
      expect(peer.port, equals(8080));
      expect(peer.token, equals('7788'));
    });

    test('Peer.fromQrString parses DROPSYNC_E2EE and web room URLs', () {
      final peer1 = Peer.fromQrString('DROPSYNC_E2EE:852-963');
      expect(peer1, isNotNull);
      expect(peer1!.token, equals('852-963'));
      expect(peer1.name, contains('852-963'));

      final peer2 = Peer.fromQrString('https://dropsync.voidranger.workers.dev/?room=123-456');
      expect(peer2, isNotNull);
      expect(peer2!.token, equals('123-456'));

      final peerLegacy = Peer.fromQrString('https://dropsync-web.vercel.app/?room=123-456');
      expect(peerLegacy, isNotNull);
      expect(peerLegacy!.token, equals('123-456'));

      final peer3 = Peer.fromQrString('789-012');
      expect(peer3, isNotNull);
      expect(peer3!.token, equals('789-012'));
    });
  });

  group('HotspotService Device Credentials Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('HotspotService default SSID matches device/computer name and has no random number suffix', () {
      final service = HotspotService();
      expect(service.ssid, isNotEmpty);
      expect(RegExp(r'^DropSync_\d{4}$').hasMatch(service.ssid), isFalse);
    });

    test('HotspotService saves and loads user-configured credentials', () async {
      final service = HotspotService();
      await service.saveSettings(
        enabled: true,
        ssid: 'MyPersonalNetwork',
        password: 'securePassword123',
      );

      final service2 = HotspotService();
      await service2.loadSettings();

      expect(service2.isHotspotMode, isTrue);
      expect(service2.ssid, equals('MyPersonalNetwork'));
      expect(service2.password, equals('securePassword123'));
    });

    test('HotspotService replaces legacy random DropSync_XXXX default on loadSettings', () async {
      SharedPreferences.setMockInitialValues({
        'hotspot_enabled': false,
        'hotspot_ssid': 'DropSync_8492',
        'hotspot_password': 'dropsync8492',
      });

      final service = HotspotService();
      await service.loadSettings();

      // Legacy random DropSync_XXXX should have been discarded
      expect(service.ssid, isNot(equals('DropSync_8492')));
    });
  });
}
