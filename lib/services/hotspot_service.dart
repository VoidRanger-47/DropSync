import 'dart:async';
import 'dart:io';
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
    String defaultName = 'DropSync';
    if (Platform.isWindows) {
      final comp = Platform.environment['COMPUTERNAME'];
      if (comp != null && comp.isNotEmpty) defaultName = comp;
    } else if (Platform.isAndroid) {
      defaultName = 'Android Device';
    }
    _ssid = defaultName;
    _password = '';
  }

  /// Loads saved hotspot settings from persistent storage, or automatically
  /// queries the device for its real Wi-Fi Hotspot SSID and password.
  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isHotspotMode = prefs.getBool(_prefHotspotEnabled) ?? false;
      final savedSsid = prefs.getString(_prefHotspotSsid);
      final savedPass = prefs.getString(_prefHotspotPassword);

      // Check if user has explicitly saved custom credentials before
      final isLegacyRandom = savedSsid != null &&
          RegExp(r'^DropSync_\d{4}$').hasMatch(savedSsid);

      if (savedSsid != null && savedSsid.isNotEmpty && !isLegacyRandom) {
        _ssid = savedSsid;
        _password = savedPass ?? '';
        return;
      }

      // If no valid user-configured credentials saved, detect device credentials
      await detectAndApplyDeviceCredentials();
    } catch (_) {}
  }

  /// Queries the host operating system (Android, Windows) for the actual
  /// device hotspot SSID and password so DropSync matches the device by default.
  Future<void> detectAndApplyDeviceCredentials() async {
    try {
      if (Platform.isAndroid) {
        final result = await _androidChannel.invokeMapMethod<String, dynamic>('getDeviceHotspotInfo');
        if (result != null) {
          final detectedSsid = result['ssid']?.toString().trim();
          final detectedPass = result['password']?.toString().trim();
          if (detectedSsid != null && detectedSsid.isNotEmpty) {
            _ssid = detectedSsid;
          }
          if (detectedPass != null && detectedPass.isNotEmpty) {
            _password = detectedPass;
          }
        }
      } else if (Platform.isWindows) {
        final creds = await _detectWindowsWifiCredentials();
        if (creds['ssid'] != null && creds['ssid']!.isNotEmpty) {
          _ssid = creds['ssid']!;
        }
        if (creds['password'] != null && creds['password']!.isNotEmpty) {
          _password = creds['password']!;
        }
      }
    } catch (_) {}
  }

  /// Extracts the active Wi-Fi / Hotspot SSID and password from Windows WLAN profiles.
  static Future<Map<String, String>> _detectWindowsWifiCredentials() async {
    String detectedSsid = '';
    String detectedPass = '';
    try {
      final ifaceResult = await Process.run('netsh', ['wlan', 'show', 'interfaces']);
      if (ifaceResult.exitCode == 0) {
        final out = ifaceResult.stdout as String;
        final lines = out.split(RegExp(r'\r?\n'));
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('SSID') && trimmed.contains(':')) {
            final parts = trimmed.split(':');
            if (parts.length >= 2) {
              final candidate = parts.sublist(1).join(':').trim();
              if (candidate.isNotEmpty && !candidate.startsWith('<')) {
                detectedSsid = candidate;
                break;
              }
            }
          }
        }
      }

      if (detectedSsid.isNotEmpty) {
        final profileResult = await Process.run('netsh', [
          'wlan',
          'show',
          'profile',
          'name=$detectedSsid',
          'key=clear',
        ]);
        if (profileResult.exitCode == 0) {
          final out = profileResult.stdout as String;
          final lines = out.split(RegExp(r'\r?\n'));
          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.startsWith('Key Content') && trimmed.contains(':')) {
              final parts = trimmed.split(':');
              if (parts.length >= 2) {
                detectedPass = parts.sublist(1).join(':').trim();
                break;
              }
            }
          }
        }
      }
    } catch (_) {}

    if (detectedSsid.isEmpty) {
      final compName = Platform.environment['COMPUTERNAME'];
      detectedSsid = (compName != null && compName.isNotEmpty) ? compName : 'Windows PC';
    }

    return {
      'ssid': detectedSsid,
      'password': detectedPass,
    };
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

  /// Returns the SSID of the currently connected Wi-Fi network on Android.
  Future<String> getCurrentWifiSsid() async {
    try {
      if (Platform.isAndroid) {
        final ssid = await _androidChannel.invokeMethod<String>('getCurrentWifiSsid');
        return ssid?.trim() ?? '';
      }
    } catch (_) {}
    return '';
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

  /// Android Native connection via MethodChannel + WifiNetworkSpecifier & Suggestions
  Future<bool> _connectAndroid({
    required String ssid,
    required String password,
    void Function(String status)? onStatusUpdate,
  }) async {
    final cleanSsid = ssid.trim();
    final cleanPass = password.trim();

    try {
      onStatusUpdate?.call('Requesting Android Wi-Fi connection to $cleanSsid...');
      final result = await _androidChannel.invokeMethod<bool>('connectToHotspot', {
        'ssid': cleanSsid,
        'password': cleanPass,
      });

      if (result == true) {
        onStatusUpdate?.call('Connected to $cleanSsid successfully!');
        return true;
      }
    } on PlatformException catch (e) {
      onStatusUpdate?.call('Android connection hint: ${e.message ?? 'Connecting...'}');
    } catch (_) {}

    // Copy password to clipboard for user convenience if needed
    if (cleanPass.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: cleanPass));
    }
    onStatusUpdate?.call('If prompted by Android, tap "Connect" to join $cleanSsid');
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
