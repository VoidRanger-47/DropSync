import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/transfer_record.dart';

/// Embedded repository managing persistent transfer records and file opening actions.
class HistoryRepository with ChangeNotifier {
  static const String _keyHistory = 'dropsync_history_records';
  final List<TransferRecord> _records = [];
  final _recordsController = StreamController<List<TransferRecord>>.broadcast();

  List<TransferRecord> get records => List.unmodifiable(_records);
  Stream<List<TransferRecord>> get recordsStream => _recordsController.stream;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_keyHistory);

      if (rawList != null && rawList.isNotEmpty) {
        _records.clear();
        for (final item in rawList) {
          try {
            final json = jsonDecode(item) as Map<String, dynamic>;
            _records.add(TransferRecord.fromJson(json));
          } catch (_) {}
        }
      } else {
        // Fallback: check history.json on disk
        await _loadFromDiskFallback();
      }

      // Sort descending by timestamp
      _records.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _emit();
    } catch (e) {
      if (kDebugMode) print('[HistoryRepository] Init error: $e');
    }
  }

  Future<void> _loadFromDiskFallback() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final file = File(p.join(docDir.path, 'DropSync', 'history.json'));
      if (file.existsSync()) {
        final content = await file.readAsString();
        final list = jsonDecode(content) as List<dynamic>;
        _records.clear();
        for (final item in list) {
          _records.add(TransferRecord.fromJson(item as Map<String, dynamic>));
        }
      }
    } catch (_) {}
  }

  /// Inserts a newly completed, failed, or cancelled transfer record.
  Future<void> addRecord(TransferRecord record) async {
    _records.insert(0, record);
    await _persist();
    _emit();
  }

  /// Removes an individual record from the history log.
  Future<void> deleteRecord(String id) async {
    _records.removeWhere((r) => r.id == id);
    await _persist();
    _emit();
  }

  /// Clears all transfer log entries without deleting the underlying physical files.
  Future<void> clearHistory() async {
    _records.clear();
    await _persist();
    _emit();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stringList = _records.map((r) => jsonEncode(r.toJson())).toList();
      await prefs.setStringList(_keyHistory, stringList);

      // Write backup to disk
      final docDir = await getApplicationDocumentsDirectory();
      final dropSyncDir = Directory(p.join(docDir.path, 'DropSync'));
      if (!dropSyncDir.existsSync()) {
        dropSyncDir.createSync(recursive: true);
      }
      final file = File(p.join(dropSyncDir.path, 'history.json'));
      await file.writeAsString(jsonEncode(_records.map((r) => r.toJson()).toList()));
    } catch (e) {
      if (kDebugMode) print('[HistoryRepository] Persist error: $e');
    }
  }

  void _emit() {
    notifyListeners();
    if (!_recordsController.isClosed) {
      _recordsController.add(List.unmodifiable(_records));
    }
  }

  /// Groups transfer records by date: "Today", "Yesterday", and older dates.
  Map<String, List<TransferRecord>> getGroupedRecords() {
    final Map<String, List<TransferRecord>> groups = {};
    for (final rec in _records) {
      final cat = rec.dateCategory;
      groups.putIfAbsent(cat, () => []).add(rec);
    }
    return groups;
  }

  /// Opens the file using the default OS handler. Returns true if opened successfully.
  static Future<bool> openFile(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) return false;

    if (Platform.isWindows) {
      try {
        await Process.run('cmd.exe', ['/c', 'start', '', filePath]);
        return true;
      } catch (_) {}
    }

    try {
      final res = await OpenFilex.open(filePath);
      return res.type == ResultType.done;
    } catch (_) {
      return false;
    }
  }

  /// Reveals the file in Windows File Explorer or native directory view.
  static Future<void> showInFolder(String filePath) async {
    final file = File(filePath);
    if (Platform.isWindows) {
      if (file.existsSync()) {
        await Process.run('explorer.exe', ['/select,', filePath]);
      } else {
        final parentDir = p.dirname(filePath);
        if (Directory(parentDir).existsSync()) {
          await Process.run('explorer.exe', [parentDir]);
        }
      }
    } else {
      // Android / POSIX: open containing directory
      final parentDir = p.dirname(filePath);
      if (Directory(parentDir).existsSync()) {
        await OpenFilex.open(parentDir);
      }
    }
  }

  @override
  void dispose() {
    _recordsController.close();
    super.dispose();
  }
}
