import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import '../models/payload_header.dart';
import '../models/transfer_session.dart';

/// High-performance chunked binary socket engine for P2P file transfers.
class SocketEngine {
  /// 64 KB chunk size for optimal high-throughput local network TCP streaming
  static const int chunkSize = 64 * 1024; // 65,536 bytes

  /// Sends a local file across an established TCP socket using 64 KB chunks.
  static Future<TransferSession> sendFile({
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

    // 1. Send binary protocol header
    final header = PayloadHeader.file(
      fileName: fileName,
      fileSize: fileSize,
    );
    socket.add(header.toBytes());
    await socket.flush();

    session = session.copyWith(status: TransferStatus.transferring);
    onProgress?.call(session);

    // 2. Stream file content in 64 KB chunks
    final stream = file.openRead();
    int bytesTransferred = 0;
    final stopwatch = Stopwatch()..start();
    var lastProgressUpdate = DateTime.now();
    int bytesSinceLastTick = 0;
    double currentSpeedMBps = 0.0;
    final sha256Sink = sha256.startChunkedConversion(
      ChunkedConversionSink<Digest>.withCallback((digests) {}),
    );

    try {
      await for (final chunk in stream) {
        socket.add(chunk);
        sha256Sink.add(chunk);
        bytesTransferred += chunk.length;
        bytesSinceLastTick += chunk.length;

        final now = DateTime.now();
        final millisSinceTick = now.difference(lastProgressUpdate).inMilliseconds;

        if (millisSinceTick >= 100 || bytesTransferred == fileSize) {
          final seconds = millisSinceTick / 1000.0;
          if (seconds > 0) {
            currentSpeedMBps = (bytesSinceLastTick / (1024 * 1024)) / seconds;
          }
          final progress = fileSize > 0 ? (bytesTransferred / fileSize).clamp(0.0, 1.0) : 1.0;
          final remainingBytes = fileSize - bytesTransferred;
          final etaSeconds = currentSpeedMBps > 0.01
              ? (remainingBytes / (currentSpeedMBps * 1024 * 1024)).ceil()
              : 0;

          session = session.copyWith(
            bytesTransferred: bytesTransferred,
            speedMBps: currentSpeedMBps,
            progress: progress,
            etaSeconds: etaSeconds,
          );
          onProgress?.call(session);

          lastProgressUpdate = now;
          bytesSinceLastTick = 0;
        }
      }

      await socket.flush();
      sha256Sink.close();
      stopwatch.stop();

      final totalDurationSeconds = stopwatch.elapsedMilliseconds / 1000.0;
      final avgSpeed = totalDurationSeconds > 0
          ? (fileSize / (1024 * 1024)) / totalDurationSeconds
          : currentSpeedMBps;

      session = session.copyWith(
        bytesTransferred: fileSize,
        speedMBps: avgSpeed,
        progress: 1.0,
        etaSeconds: 0,
        status: TransferStatus.completed,
      );
      onProgress?.call(session);
      return session;
    } catch (e) {
      session = session.copyWith(
        status: TransferStatus.failed,
        errorMessage: e.toString(),
      );
      onProgress?.call(session);
      rethrow;
    }
  }

  /// Sends a raw text clipboard payload over socket using DropSync frame.
  static Future<void> sendClipboard({
    required Socket socket,
    required String text,
  }) async {
    final header = PayloadHeader.clipboard(text: text);
    socket.add(header.toBytes());
    final textBytes = utf8.encode(text);
    socket.add(textBytes);
    await socket.flush();
  }

  /// Receives incoming stream on socket, parses header, and streams to .part file.
  static Future<void> handleIncomingConnection({
    required Socket socket,
    required String destinationDir,
    void Function(TransferSession)? onProgress,
    void Function(String clipboardText)? onClipboard,
    void Function(File receivedFile)? onFileReceived,
  }) async {
    final completer = Completer<void>();
    final buffer = BytesBuilder(copy: false);
    PayloadHeader? header;
    IOSink? partSink;
    File? partFile;
    int bytesReceivedForFile = 0;
    TransferSession? session;
    Stopwatch? stopwatch;
    DateTime lastProgressUpdate = DateTime.now();
    int bytesSinceLastTick = 0;
    double currentSpeedMBps = 0.0;
    String? calculatedSha256;
    ByteConversionSink? sha256Sink;

    StreamSubscription? sub;

    void cleanup() {
      try {
        partSink?.close();
      } catch (_) {}
      sub?.cancel();
    }

    sub = socket.listen(
      (Uint8List data) async {
        buffer.add(data);

        // If header not yet parsed, try parsing from accumulated buffer
        if (header == null) {
          final accumulated = buffer.toBytes();
          final parsed = PayloadHeader.tryParse(accumulated);
          if (parsed != null) {
            header = parsed;
            final headerLen = parsed.wireHeaderLength;
            // The remaining bytes belong to the body
            final bodyBytes = accumulated.sublist(headerLen);
            buffer.clear();

            if (header!.isClipboardTransfer) {
              // Wait for all text bytes
              if (bodyBytes.length >= header!.fileSize) {
                final clipText = utf8.decode(
                  bodyBytes.sublist(0, header!.fileSize),
                  allowMalformed: true,
                );
                onClipboard?.call(clipText);
                cleanup();
                completer.complete();
                return;
              } else {
                buffer.add(bodyBytes);
                return;
              }
            } else if (header!.isFileTransfer) {
              // Prepare file destination
              final cleanName = p.basename(header!.fileName).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
              final outDir = Directory(destinationDir);
              if (!outDir.existsSync()) {
                outDir.createSync(recursive: true);
              }

              partFile = File(p.join(destinationDir, '$cleanName.part'));
              partSink = partFile!.openWrite();

              sha256Sink = sha256.startChunkedConversion(
                ChunkedConversionSink<Digest>.withCallback((digests) {
                  if (digests.isNotEmpty) {
                    calculatedSha256 = digests.first.toString();
                  }
                }),
              );

              stopwatch = Stopwatch()..start();
              lastProgressUpdate = DateTime.now();

              session = TransferSession.initial(
                fileName: cleanName,
                fileSize: header!.fileSize,
                isUpload: false,
                filePath: partFile!.path,
              ).copyWith(status: TransferStatus.transferring);
              onProgress?.call(session!);

              if (bodyBytes.isNotEmpty) {
                partSink!.add(bodyBytes);
                sha256Sink!.add(bodyBytes);
                bytesReceivedForFile += bodyBytes.length;
                bytesSinceLastTick += bodyBytes.length;
              }

              if (bytesReceivedForFile >= header!.fileSize) {
                await _finalizeFileTransfer(
                  partSink: partSink!,
                  partFile: partFile!,
                  destinationDir: destinationDir,
                  cleanName: cleanName,
                  fileSize: header!.fileSize,
                  sha256Sink: sha256Sink!,
                  sha256Digest: calculatedSha256,
                  stopwatch: stopwatch!,
                  session: session!,
                  onProgress: onProgress,
                  onFileReceived: onFileReceived,
                );
                cleanup();
                completer.complete();
              }
              return;
            }
          } else {
            // Header not complete yet, wait for more bytes
            return;
          }
        } else {
          // Header already active
          if (header!.isClipboardTransfer) {
            final accumulated = buffer.toBytes();
            if (accumulated.length >= header!.fileSize) {
              final clipText = utf8.decode(
                accumulated.sublist(0, header!.fileSize),
                allowMalformed: true,
              );
              onClipboard?.call(clipText);
              cleanup();
              completer.complete();
            }
            return;
          }

          if (header!.isFileTransfer && partSink != null) {
            final toWrite = buffer.toBytes();
            buffer.clear();

            partSink!.add(toWrite);
            sha256Sink?.add(toWrite);
            bytesReceivedForFile += toWrite.length;
            bytesSinceLastTick += toWrite.length;

            final now = DateTime.now();
            final millisSinceTick = now.difference(lastProgressUpdate).inMilliseconds;

            if (millisSinceTick >= 100 || bytesReceivedForFile >= header!.fileSize) {
              final seconds = millisSinceTick / 1000.0;
              if (seconds > 0) {
                currentSpeedMBps = (bytesSinceLastTick / (1024 * 1024)) / seconds;
              }
              final progress = header!.fileSize > 0
                  ? (bytesReceivedForFile / header!.fileSize).clamp(0.0, 1.0)
                  : 1.0;
              final remainingBytes = header!.fileSize - bytesReceivedForFile;
              final etaSeconds = currentSpeedMBps > 0.01
                  ? (remainingBytes / (currentSpeedMBps * 1024 * 1024)).ceil()
                  : 0;

              session = session!.copyWith(
                bytesTransferred: bytesReceivedForFile,
                speedMBps: currentSpeedMBps,
                progress: progress,
                etaSeconds: etaSeconds,
              );
              onProgress?.call(session!);

              lastProgressUpdate = now;
              bytesSinceLastTick = 0;
            }

            if (bytesReceivedForFile >= header!.fileSize) {
              await _finalizeFileTransfer(
                partSink: partSink!,
                partFile: partFile!,
                destinationDir: destinationDir,
                cleanName: p.basename(header!.fileName),
                fileSize: header!.fileSize,
                sha256Sink: sha256Sink!,
                sha256Digest: calculatedSha256,
                stopwatch: stopwatch!,
                session: session!,
                onProgress: onProgress,
                onFileReceived: onFileReceived,
              );
              cleanup();
              completer.complete();
            }
          }
        }
      },
      onError: (err) {
        if (session != null) {
          session = session!.copyWith(
            status: TransferStatus.failed,
            errorMessage: err.toString(),
          );
          onProgress?.call(session!);
        }
        cleanup();
        if (partFile != null && partFile!.existsSync()) {
          try {
            partFile!.deleteSync();
          } catch (_) {}
        }
        if (!completer.isCompleted) completer.completeError(err);
      },
      onDone: () {
        cleanup();
        if (header != null &&
            header!.isFileTransfer &&
            bytesReceivedForFile < header!.fileSize) {
          // Socket closed before file finished
          if (partFile != null && partFile!.existsSync()) {
            try {
              partFile!.deleteSync();
            } catch (_) {}
          }
          if (session != null) {
            session = session!.copyWith(
              status: TransferStatus.failed,
              errorMessage: 'Connection closed prematurely before file was complete.',
            );
            onProgress?.call(session!);
          }
        }
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );

    return completer.future;
  }

  static Future<void> _finalizeFileTransfer({
    required IOSink partSink,
    required File partFile,
    required String destinationDir,
    required String cleanName,
    required int fileSize,
    required ByteConversionSink sha256Sink,
    String? sha256Digest,
    required Stopwatch stopwatch,
    required TransferSession session,
    void Function(TransferSession)? onProgress,
    void Function(File receivedFile)? onFileReceived,
  }) async {
    await partSink.flush();
    await partSink.close();
    sha256Sink.close();
    stopwatch.stop();

    // Resolve filename collisions: file.ext -> file (1).ext
    final finalPath = _resolveCollision(destinationDir, cleanName);
    final finalFile = await partFile.rename(finalPath);

    final durationSec = stopwatch.elapsedMilliseconds / 1000.0;
    final avgSpeed = durationSec > 0
        ? (fileSize / (1024 * 1024)) / durationSec
        : session.speedMBps;

    final completedSession = session.copyWith(
      bytesTransferred: fileSize,
      speedMBps: avgSpeed,
      progress: 1.0,
      etaSeconds: 0,
      status: TransferStatus.completed,
      filePath: finalFile.path,
      sha256Digest: sha256Digest,
    );
    onProgress?.call(completedSession);
    onFileReceived?.call(finalFile);
  }

  static String _resolveCollision(String dir, String baseName) {
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
