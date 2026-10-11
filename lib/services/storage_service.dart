import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Manages save directory locations, preferences persistence, and collision resolution.
class StorageService with ChangeNotifier {
  static const String _keyCustomPath = 'dropsync_custom_download_path';
  static const String _keyAutoAccept = 'dropsync_auto_accept';

  String _currentDownloadDirectory = '';
  bool _autoAccept = true;

  String get downloadDirectory => _currentDownloadDirectory;
  bool get autoAccept => _autoAccept;

  /// Initializes storage paths, checking persistent preferences first.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _autoAccept = prefs.getBool(_keyAutoAccept) ?? true;

    final savedPath = prefs.getString(_keyCustomPath);
    if (savedPath != null && savedPath.isNotEmpty && Directory(savedPath).existsSync()) {
      _currentDownloadDirectory = savedPath;
    } else {
      _currentDownloadDirectory = await _resolveDefaultPath();
    }
    _ensureDirectoryExists(_currentDownloadDirectory);
    notifyListeners();
  }

  Future<String> _resolveDefaultPath() async {
    try {
      Directory? dir;
      if (Platform.isAndroid) {
        // Try public Android Downloads directory first
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final parent = extDir.parent.parent.parent.parent;
          final publicDownload = Directory(p.join(parent.path, 'Download', 'DropSync'));
          if (publicDownload.existsSync() || _tryCreate(publicDownload)) {
            return publicDownload.path;
          }
          dir = extDir;
        }
      } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        dir = await getDownloadsDirectory();
      }
      dir ??= await getApplicationDocumentsDirectory();

      final target = p.join(dir.path, 'DropSync');
      _ensureDirectoryExists(target);
      return target;
    } catch (_) {
      final docDir = await getApplicationDocumentsDirectory();
      final target = p.join(docDir.path, 'DropSync');
      _ensureDirectoryExists(target);
      return target;
    }
  }

  bool _tryCreate(Directory d) {
    try {
      d.createSync(recursive: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _ensureDirectoryExists(String path) {
    try {
      final d = Directory(path);
      if (!d.existsSync()) {
        d.createSync(recursive: true);
      }
    } catch (_) {}
  }

  /// Opens directory picker for user to select custom destination.
  Future<String?> pickAndSetCustomDirectory() async {
    final selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select DropSync Destination Folder',
      initialDirectory: _currentDownloadDirectory,
    );

    if (selected != null && selected.isNotEmpty) {
      await setCustomDirectory(selected);
      return selected;
    }
    return null;
  }

  Future<void> setCustomDirectory(String path) async {
    _ensureDirectoryExists(path);
    _currentDownloadDirectory = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCustomPath, path);
    notifyListeners();
  }

  Future<void> resetToDefault() async {
    final defaultPath = await _resolveDefaultPath();
    _currentDownloadDirectory = defaultPath;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCustomPath);
    notifyListeners();
  }

  Future<void> setAutoAccept(bool enabled) async {
    _autoAccept = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoAccept, enabled);
    notifyListeners();
  }

  /// Resolves filename collision: 'file.ext' -> 'file (1).ext'
  static String resolveCollision(String dir, String baseName) {
    var candidate = p.join(dir, baseName);
    if (!File(candidate).existsSync()) return candidate;

    final nameWithoutExt = p.basenameWithoutExtension(baseName);
    final ext = p.extension(baseName);
    int counter = 1;

    while (true) {
      candidate = p.join(dir, '$nameWithoutExt ($counter)$ext');
      if (!File(candidate).existsSync()) return candidate;
      counter++;
    }
  }
}
