import 'package:intl/intl.dart';

enum TransferDirection {
  sent,
  received,
}

enum TransferRecordStatus {
  completed,
  failed,
  cancelled,
}

/// Represents an immutable persistent historical transfer record.
class TransferRecord {
  final String id;
  final String fileName;
  final int fileSize;
  final String filePath;
  final TransferDirection direction;
  final String peerName;
  final DateTime timestamp;
  final TransferRecordStatus status;
  final int transferDurationMs;

  const TransferRecord({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.filePath,
    required this.direction,
    required this.peerName,
    required this.timestamp,
    required this.status,
    required this.transferDurationMs,
  });

  factory TransferRecord.create({
    required String fileName,
    required int fileSize,
    required String filePath,
    required TransferDirection direction,
    required String peerName,
    TransferRecordStatus status = TransferRecordStatus.completed,
    int transferDurationMs = 0,
  }) {
    return TransferRecord(
      id: 'rec_${DateTime.now().millisecondsSinceEpoch}_${fileName.hashCode.abs()}',
      fileName: fileName,
      fileSize: fileSize,
      filePath: filePath,
      direction: direction,
      peerName: peerName,
      timestamp: DateTime.now(),
      status: status,
      transferDurationMs: transferDurationMs,
    );
  }

  factory TransferRecord.fromJson(Map<String, dynamic> json) {
    return TransferRecord(
      id: json['id'] as String? ?? 'rec_${DateTime.now().millisecondsSinceEpoch}',
      fileName: json['file_name'] as String? ?? 'file',
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
      filePath: json['file_path'] as String? ?? '',
      direction: (json['direction'] as String? ?? 'received') == 'sent'
          ? TransferDirection.sent
          : TransferDirection.received,
      peerName: json['peer_name'] as String? ?? 'Remote Device',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      status: _parseStatus(json['status'] as String?),
      transferDurationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'file_name': fileName,
        'file_size': fileSize,
        'file_path': filePath,
        'direction': direction == TransferDirection.sent ? 'sent' : 'received',
        'peer_name': peerName,
        'timestamp': timestamp.toIso8601String(),
        'status': status.name,
        'duration_ms': transferDurationMs,
      };

  static TransferRecordStatus _parseStatus(String? name) {
    switch (name) {
      case 'completed':
        return TransferRecordStatus.completed;
      case 'failed':
        return TransferRecordStatus.failed;
      case 'cancelled':
        return TransferRecordStatus.cancelled;
      default:
        return TransferRecordStatus.completed;
    }
  }

  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get formattedDuration {
    if (transferDurationMs <= 0) return '< 1s';
    final seconds = transferDurationMs / 1000.0;
    if (seconds < 60) return '${seconds.toStringAsFixed(1)}s';
    final mins = (seconds / 60).floor();
    final remSecs = (seconds % 60).round();
    return '${mins}m ${remSecs}s';
  }

  String get formattedSpeed {
    if (transferDurationMs <= 0 || fileSize <= 0) return '0.0 MB/s';
    final seconds = transferDurationMs / 1000.0;
    final mb = fileSize / (1024 * 1024);
    final speed = mb / seconds;
    return '${speed.toStringAsFixed(1)} MB/s';
  }

  String get formattedTime => DateFormat('hh:mm a').format(timestamp);

  String get dateCategory {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final entryDate = DateTime(timestamp.year, timestamp.month, timestamp.day);

    final differenceInDays = today.difference(entryDate).inDays;
    if (differenceInDays == 0) {
      return 'Today';
    } else if (differenceInDays == 1) {
      return 'Yesterday';
    } else if (differenceInDays < 7) {
      return DateFormat('EEEE').format(timestamp); // e.g. "Monday"
    } else {
      return DateFormat('MMM d, yyyy').format(timestamp); // e.g. "Sep 24, 2026"
    }
  }
}
