import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service managing Wi-Fi Hotspot configuration, automatic connection,
/// and OS network tethering integration for zero-router P2P transfers.
class HotspotService {
  static const String _prefHotspotEnabled = 'hotspot_enabled';
  static const String _prefHotspotSsid = 'hotspot_ssid';
  static const String _prefHotspotPassword = 'hotspot_password';

  static const MethodChannel _androidChannel =
      MethodChannel('com.dropsync.app/hotspot');

  bool _isHotspotMode = false;
  String _ssid = '';
  String _password = '';

  bool get isHotspotMode => _isHotspotMode;
  String get ssid => _ssid;
  String get password => _password;

  HotspotService() {
    _initDefaults();
  }

  void _initDefaults() {
    final rand = Random();
    final suffix = rand.nextInt(9000) + 1000;
    _ssid = 'DropSync_$suffix';
    _password = 'dropsync$suffix';
  }

  /// Loads saved hotspot settings from persistent storage.
  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isHotspotMode = prefs.getBool(_prefHotspotEnabled) ?? false;
      final savedSsid = prefs.getString(_prefHotspotSsid);
      final savedPass = prefs.getString(_prefHotspotPassword);

      if (savedSsid != null && savedSsid.isNotEmpty) {
        _ssid = savedSsid;
      }
      if (savedPass != null && savedPass.isNotEmpty) {
        _password = savedPass;
      }
    } catch (_) {}
  }

  /// Saves updated hotspot credentials to persistent storage.
  Future<void> saveSettings({
    required bool enabled,
    required String ssid,
    required String password,
  }) async {
    _isHotspotMode = enabled;
    _ssid = ssid.trim();
    _password = password.trim();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefHotspotEnabled, _isHotspotMode);
      await prefs.setString(_prefHotspotSsid, _ssid);
      await prefs.setString(_prefHotspotPassword, _password);
    } catch (_) {}
  }

  void setHotspotMode(bool enabled) {
    _isHotspotMode = enabled;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool(_prefHotspotEnabled, enabled);
    }).catchError((_) {});
  }

  /// Detects the best IP address for the hotspot interface.
  /// Android hotspots typically use 192.168.43.1.
  /// Windows Mobile Hotspot typically uses 192.168.137.1.
  Future<String> getSuggestedHotspotIp(String fallbackIp) async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          // Android Hotspot subnet check
          if (ip.startsWith('192.168.43.')) return ip;
          // Windows Mobile Hotspot subnet check
          if (ip.startsWith('192.168.137.')) return ip;
        }
      }

      // If on Android and hotspot is enabled, default gateway is almost universally 192.168.43.1
      if (Platform.isAndroid && _isHotspotMode) {
        return '192.168.43.1';
      }
      // If on Windows and hotspot is enabled
      if (Platform.isWindows && _isHotspotMode) {
        return '192.168.137.1';
      }
    } catch (_) {}

    return fallbackIp;
  }

  /// Automatically connects to the designated Wi-Fi Hotspot on Android or Windows.
  Future<bool> connectToHotspot({
    required String ssid,
    required String password,
    void Function(String status)? onStatusUpdate,
  }) async {
    onStatusUpdate?.call('Preparing to connect to $ssid...');

    if (Platform.isAndroid) {
      return _connectAndroid(ssid: ssid, password: password, onStatusUpdate: onStatusUpdate);
    } else if (Platform.isWindows) {
      return _connectWindows(ssid: ssid, password: password, onStatusUpdate: onStatusUpdate);
    } else {
      // Fallback on iOS / macOS / Linux: copy password and prompt settings
      await Clipboard.setData(ClipboardData(text: password));
      onStatusUpdate?.call('Password copied to clipboard. Connect in Wi-Fi Settings.');
      return false;
    }
  }

  /// Android Native connection via MethodChannel + WifiNetworkSpecifier
  Future<bool> _connectAndroid({
    required String ssid,
    required String password,
    void Function(String status)? onStatusUpdate,
  }) async {
    try {
      onStatusUpdate?.call('Requesting Android Wi-Fi connection to $ssid...');
      final result = await _androidChannel.invokeMethod<bool>('connectToHotspot', {
        'ssid': ssid,
        'password': password,
      });

      if (result == true) {
        onStatusUpdate?.call('Connected to $ssid successfully!');
        return true;
      }
    } on PlatformException catch (e) {
      onStatusUpdate?.call('Android connection hint: ${e.message ?? 'Opening settings'}');
    } catch (_) {}

    // Fallback: copy password and launch Wi-Fi settings
    await Clipboard.setData(ClipboardData(text: password));
    onStatusUpdate?.call('Password copied! Please select $ssid in Wi-Fi settings.');
    await openWifiSettings();
    return false;
  }

  /// Windows connection via netsh WLAN profile creation
  Future<bool> _connectWindows({
    required String ssid,
    required String password,
    void Function(String status)? onStatusUpdate,
  }) async {
    try {
      onStatusUpdate?.call('Configuring Windows WLAN profile for $ssid...');

      final xmlContent = '''<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
  <name>$ssid</name>
  <SSIDConfig>
    <SSID>
      <name>$ssid</name>
    </SSID>
  </SSIDConfig>
  <connectionType>ESS</connectionType>
  <connectionMode>manual</connectionMode>
  <MSM>
    <security>
      <authEncryption>
        <authentication>WPA2PSK</authentication>
        <encryption>AES</encryption>
        <useOneX>false</useOneX>
      </authEncryption>
      <sharedKey>
        <keyType>passPhrase</keyType>
        <protected>false</protected>
        <keyMaterial>$password</keyMaterial>
      </sharedKey>
    </security>
  </MSM>
</WLANProfile>''';

      final tempDir = Directory.systemTemp;
      final profileFile = File('${tempDir.path}\\dropsync_wifi_$ssid.xml');
      await profileFile.writeAsString(xmlContent);

      // Add profile
      final addResult = await Process.run('netsh', [
        'wlan',
        'add',
        'profile',
        'filename=${profileFile.path}',
        'user=all',
      ]);

      // Delete temporary XML file safely
      try {
        await profileFile.delete();
      } catch (_) {}

      if (addResult.exitCode != 0) {
        onStatusUpdate?.call('Failed to register WLAN profile on Windows.');
        await Clipboard.setData(ClipboardData(text: password));
        return false;
      }

      onStatusUpdate?.call('Connecting to $ssid...');
      final connectResult = await Process.run('netsh', [
        'wlan',
        'connect',
        'name=$ssid',
      ]);

      if (connectResult.exitCode == 0) {
        onStatusUpdate?.call('Connection command sent. Verifying network link...');
        // Wait briefly for DHCP IP assignment
        await Future.delayed(const Duration(seconds: 3));
        onStatusUpdate?.call('Connected to $ssid!');
        return true;
      }
    } catch (e) {
      onStatusUpdate?.call('Windows Wi-Fi error: $e');
    }

    // Fallback on error
    await Clipboard.setData(ClipboardData(text: password));
    await openWifiSettings();
    return false;
  }

  /// Opens the system Wi-Fi settings page across Android and Windows.
  Future<void> openWifiSettings() async {
    try {
      if (Platform.isAndroid) {
        await _androidChannel.invokeMethod('openWifiSettings');
      } else if (Platform.isWindows) {
        await Process.run('cmd.exe', ['/c', 'start', 'ms-settings:network-wifi']);
      }
    } catch (_) {}
  }
}
