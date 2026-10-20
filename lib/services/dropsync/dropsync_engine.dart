import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import '../../models/payload_header.dart';
import '../../models/transfer_session.dart';

export '../socket_engine.dart';

class _TransferProgressMsg {
  final int bytesTransferred;
  final double speedMBps;
  final double progress;
  final int etaSeconds;
  final bool isCompleted;
  final String? errorMessage;
  final String? sha256Digest;

  _TransferProgressMsg({
    required this.bytesTransferred,
    required this.speedMBps,
    required this.progress,
    required this.etaSeconds,
    this.isCompleted = false,
    this.errorMessage,
    this.sha256Digest,
  });
}

/// DropSync Native High-Performance Transfer Engine with Background Isolate Offloading.
/// Spawns dedicated background isolates for file I/O, SHA-256 hashing, and chunk streaming,
/// sending throttled progress updates (every 100 ms) via SendPort to avoid UI jank.
class DropSyncEngine {
  static const int chunkSize = 64 * 1024; // 64 KB binary packet chunks

  /// Sends a file through a dedicated background worker isolate for chunk reading and hashing,
  /// streaming chunks across the socket while guaranteeing 60fps UI smoothness.
  static Future<TransferSession> sendFileWithIsolate({
    required Socket socket,
    required File file,
    String? customFileName,
    void Function(TransferSession)? onProgress,
  }) async {
    final fileName = customFileName ?? p.basename(file.path);
    final fileSize = await file.length();

    var session = TransferSession.initial(
      fileName: fileName,
      fileSize: fileSize,
      isUpload: true,
      filePath: file.path,
    );
    onProgress?.call(session);

    // 1. Send binary header
    final header = PayloadHeader.file(
      fileName: fileName,
      fileSize: fileSize,
    );
    socket.add(header.toBytes());
    await socket.flush();

    session = session.copyWith(status: TransferStatus.transferring);
    onProgress?.call(session);

    // 2. Set up communication ports with the transfer isolate
    final receivePort = ReceivePort();
    final completer = Completer<TransferSession>();

    var lastProgressUpdate = DateTime.now();
    int bytesTransferred = 0;
    final stopwatch = Stopwatch()..start();

    // Spawn background reader isolate
    final isolate = await Isolate.spawn<_IsolateSendParams>(
      _fileReadIsolateEntry,
      _IsolateSendParams(
        filePath: file.path,
        chunkSize: chunkSize,
        sendPort: receivePort.sendPort,
      ),
    );

    receivePort.listen((message) async {
      if (message is List<int>) {
        // Chunk from background isolate: write to socket
        socket.add(message);
        bytesTransferred += message.length;

        final now = DateTime.now();
        final millisSinceTick = now.difference(lastProgressUpdate).inMilliseconds;

        // Throttled 100ms updates to main isolate UI
        if (millisSinceTick >= 100 || bytesTransferred >= fileSize) {
          final seconds = stopwatch.elapsedMilliseconds / 1000.0;
          final speedMBps = seconds > 0 ? (bytesTransferred / (1024 * 1024)) / seconds : 0.0;
          final progress = fileSize > 0 ? (bytesTransferred / fileSize).clamp(0.0, 1.0) : 1.0;
          final remainingBytes = fileSize - bytesTransferred;
          final etaSeconds = speedMBps > 0.01
              ? (remainingBytes / (speedMBps * 1024 * 1024)).ceil()
              : 0;

          session = session.copyWith(
            bytesTransferred: bytesTransferred,
            speedMBps: speedMBps,
            progress: progress,
            etaSeconds: etaSeconds,
          );
          onProgress?.call(session);
          lastProgressUpdate = now;
        }
      } else if (message is _TransferProgressMsg) {
        if (message.isCompleted) {
          try {
            await socket.flush();
          } catch (_) {}
          stopwatch.stop();
          isolate.kill(priority: Isolate.immediate);
          receivePort.close();

          final totalSec = stopwatch.elapsedMilliseconds / 1000.0;
          final finalSpeed = totalSec > 0 ? (fileSize / (1024 * 1024)) / totalSec : session.speedMBps;

          session = session.copyWith(
            bytesTransferred: fileSize,
            speedMBps: finalSpeed,
            progress: 1.0,
            etaSeconds: 0,
            status: TransferStatus.completed,
            sha256Digest: message.sha256Digest,
          );
          onProgress?.call(session);
          if (!completer.isCompleted) completer.complete(session);
        } else if (message.errorMessage != null) {
          isolate.kill(priority: Isolate.immediate);
          receivePort.close();
          session = session.copyWith(
            status: TransferStatus.failed,
            errorMessage: message.errorMessage,
          );
          onProgress?.call(session);
          if (!completer.isCompleted) completer.completeError(Exception(message.errorMessage));
        }
      }
    });

    return completer.future;
  }

  /// Entry point for background file reading and hashing isolate
  static void _fileReadIsolateEntry(_IsolateSendParams params) async {
    final sendPort = params.sendPort;
    final file = File(params.filePath);

    if (!file.existsSync()) {
      sendPort.send(_TransferProgressMsg(
        bytesTransferred: 0,
        speedMBps: 0,
        progress: 0,
        etaSeconds: 0,
        errorMessage: 'File not found on disk: ${params.filePath}',
      ));
      return;
    }

    try {
      final raf = file.openSync(mode: FileMode.read);
      final fileSize = raf.lengthSync();

      String calculatedSha256 = '';
      final completeDigestSink = sha256.startChunkedConversion(
        ChunkedConversionSink<Digest>.withCallback((digests) {
          if (digests.isNotEmpty) calculatedSha256 = digests.first.toString();
        }),
      );

      int readBytes = 0;
      while (readBytes < fileSize) {
        final toRead = (fileSize - readBytes) > params.chunkSize
            ? params.chunkSize
            : (fileSize - readBytes);
        final chunk = raf.readSync(toRead);
        readBytes += chunk.length;

        completeDigestSink.add(chunk);
        sendPort.send(chunk);
      }

      raf.closeSync();
      completeDigestSink.close();

      sendPort.send(_TransferProgressMsg(
        bytesTransferred: fileSize,
        speedMBps: 0,
        progress: 1.0,
        etaSeconds: 0,
        isCompleted: true,
        sha256Digest: calculatedSha256,
      ));
    } catch (e) {
      sendPort.send(_TransferProgressMsg(
        bytesTransferred: 0,
        speedMBps: 0,
        progress: 0,
        etaSeconds: 0,
        errorMessage: e.toString(),
      ));
    }
  }

  /// Offload chunk hashing to background isolate
  static Future<String> computeSha256Isolate(File file) async {
    return Isolate.run(() async {
      final stream = file.openRead();
      final digest = await sha256.bind(stream).first;
      return digest.toString();
    });
  }
}

class _IsolateSendParams {
  final String filePath;
  final int chunkSize;
  final SendPort sendPort;

  _IsolateSendParams({
    required this.filePath,
    required this.chunkSize,
    required this.sendPort,
  });
}
