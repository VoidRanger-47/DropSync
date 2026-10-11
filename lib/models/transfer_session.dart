enum TransferStatus {
  idle,
  connecting,
  transferring,
  completed,
  failed,
  cancelled,
}

/// Represents the real-time state of an ongoing or completed transfer.
class TransferSession {
  final String id;
  final String fileName;
  final int fileSize;
  final int bytesTransferred;
  final double speedMBps;
  final double progress; // 0.0 to 1.0
  final int etaSeconds;
  final bool isUpload;
  final TransferStatus status;
  final String? errorMessage;
  final String? filePath;
  final String? sha256Digest;
  final DateTime startTime;

  TransferSession({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.bytesTransferred,
    required this.speedMBps,
    required this.progress,
    required this.etaSeconds,
    required this.isUpload,
    required this.status,
    this.errorMessage,
    this.filePath,
    this.sha256Digest,
    DateTime? startTime,
  }) : startTime = startTime ?? DateTime.now();

  factory TransferSession.initial({
    required String fileName,
    required int fileSize,
    required bool isUpload,
    String? filePath,
  }) {
    return TransferSession(
      id: 'tx_${DateTime.now().millisecondsSinceEpoch}',
      fileName: fileName,
      fileSize: fileSize,
      bytesTransferred: 0,
      speedMBps: 0.0,
      progress: 0.0,
      etaSeconds: 0,
      isUpload: isUpload,
      status: TransferStatus.connecting,
      filePath: filePath,
    );
  }

  TransferSession copyWith({
    String? id,
    String? fileName,
    int? fileSize,
    int? bytesTransferred,
    double? speedMBps,
    double? progress,
    int? etaSeconds,
    bool? isUpload,
    TransferStatus? status,
    String? errorMessage,
    String? filePath,
    String? sha256Digest,
    DateTime? startTime,
  }) {
    return TransferSession(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      speedMBps: speedMBps ?? this.speedMBps,
      progress: progress ?? this.progress,
      etaSeconds: etaSeconds ?? this.etaSeconds,
      isUpload: isUpload ?? this.isUpload,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      filePath: filePath ?? this.filePath,
      sha256Digest: sha256Digest ?? this.sha256Digest,
      startTime: startTime ?? this.startTime,
    );
  }

  String get formattedSpeed => '${speedMBps.toStringAsFixed(1)} MB/s';

  String get formattedProgress => '${(progress * 100).toStringAsFixed(0)}%';

  String get formattedEta {
    if (etaSeconds <= 0) return '0s';
    if (etaSeconds < 60) return '${etaSeconds}s';
    final minutes = etaSeconds ~/ 60;
    final seconds = etaSeconds % 60;
    return '${minutes}m ${seconds}s';
  }

  String get formattedTransferred => _formatBytes(bytesTransferred);
  String get formattedTotalSize => _formatBytes(fileSize);

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  bool get isActive =>
      status == TransferStatus.transferring ||
      status == TransferStatus.connecting;

  bool get isCompleted => status == TransferStatus.completed;
  bool get hasFailed => status == TransferStatus.failed;
}
