import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import '../../models/transfer_record.dart';
import '../../models/transfer_session.dart';
import '../storage/history_repository.dart';
import '../storage/storage_service.dart';
import 'protobuf/nearby_sharing_protobuf.dart';
import 'ukey2_handshake.dart';

/// Quick Share TCP receiver handling UKEY2 cryptographic handshake,
/// Protobuf frame exchange, and file chunk reception from Android Quick Share.
class QuickShareReceiver {
  static const int defaultPort = 8088;

  final StorageService storageService;
  final HistoryRepository historyRepository;
  final void Function(String pin, String peerName)? onPinVerification;
  final void Function(TransferSession session)? onProgress;

  ServerSocket? _serverSocket;
  int _port = defaultPort;

  int get port => _port;
  bool get isListening => _serverSocket != null;

  QuickShareReceiver({
    required this.storageService,
    required this.historyRepository,
    this.onPinVerification,
    this.onProgress,
  });

  Future<void> start() async {
    int portToTry = defaultPort;
    bool bound = false;

    while (!bound && portToTry < defaultPort + 10) {
      try {
        _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, portToTry);
        _port = portToTry;
        bound = true;
      } catch (_) {
        portToTry++;
      }
    }

    if (_serverSocket != null) {
      _serverSocket!.listen(_handleConnection);
    }
  }

  void _handleConnection(Socket socket) async {
    final remoteIp = socket.remoteAddress.address;
    final ukey2 = Ukey2Handshake();
    await ukey2.initKeyPair();

    final buffer = BytesBuilder(copy: false);
    bool ukey2Done = false;
    String currentFileName = 'quickshare_file.bin';
    int currentFileSize = 0;
    int bytesReceived = 0;
    IOSink? fileSink;
    File? partFile;
    final stopwatch = Stopwatch()..start();

    void cleanup() {
      try {
        fileSink?.close();
      } catch (_) {}
      try {
        socket.close();
      } catch (_) {}
    }

    socket.listen((Uint8List data) async {
      buffer.add(data);

      if (!ukey2Done) {
        // Step 1: Read UKEY2 ClientInit (4-byte length prefix + protobuf)
        final raw = buffer.toBytes();
        if (raw.length < 4) return;
        final length = ByteData.sublistView(raw).getUint32(0, Endian.big);
        if (raw.length < 4 + length) return;

        final ukey2Payload = raw.sublist(4, 4 + length);
        buffer.clear();

        final clientInit = Ukey2Message.parse(ukey2Payload);
        if (clientInit != null) {
          // Process peer public key (contained in ClientInit subpayload)
          final peerPk = clientInit.payload.sublist(clientInit.payload.length - 32);
          await ukey2.processPeerPublicKey(peerPk, isClient: false);

          // Trigger PIN verification callback
          onPinVerification?.call(ukey2.pinCode, 'Android Device ($remoteIp)');

          // Send UKEY2 ServerInit
          final serverInit = await ukey2.createServerInit();
          final serverInitBytes = serverInit.toBytes();
          final framed = ByteData(4 + serverInitBytes.length);
          framed.setUint32(0, serverInitBytes.length, Endian.big);
          for (int i = 0; i < serverInitBytes.length; i++) {
            framed.setUint8(4 + i, serverInitBytes[i]);
          }
          socket.add(framed.buffer.asUint8List());
          await socket.flush();

          ukey2Done = true;
        }
      } else {
        // Step 2: Handle Encrypted OfflineFrames and NearbySharingFrames
        final raw = buffer.toBytes();
        if (raw.length < 4) return;
        final length = ByteData.sublistView(raw).getUint32(0, Endian.big);
        if (raw.length < 4 + length) return;

        final encryptedFrame = raw.sublist(4, 4 + length);
        buffer.clear();

        try {
          final decrypted = await ukey2.decryptFrame(encryptedFrame);
          final offlineFrame = OfflineFrame.parse(decrypted);

          if (offlineFrame != null) {
            if (offlineFrame.type == 1) {
              // ConnectionRequest -> reply with ConnectionResponse (ACCEPT)
              final responseFrame = OfflineFrame(type: 2);
              final respBytes = responseFrame.toBytes();
              final encResp = await ukey2.encryptFrame(respBytes);
              final framed = ByteData(4 + encResp.length);
              framed.setUint32(0, encResp.length, Endian.big);
              for (int i = 0; i < encResp.length; i++) {
                framed.setUint8(4 + i, encResp[i]);
              }
              socket.add(framed.buffer.asUint8List());
              await socket.flush();
            } else if (offlineFrame.type == 3) {
              // PayloadTransfer: parse IntroductionFrame or raw chunk
              if (fileSink == null) {
                // Initialize incoming file
                final intro = IntroductionFrame.parse(decrypted);
                if (intro.files.isNotEmpty) {
                  currentFileName = intro.files.first.name;
                  currentFileSize = intro.files.first.size;
                }

                final saveDir = storageService.downloadDirectory;
                final cleanName = p.basename(currentFileName);
                partFile = File(p.join(saveDir, '$cleanName.part'));
                fileSink = partFile!.openWrite();
              } else {
                // Streaming chunk
                fileSink!.add(decrypted);
                bytesReceived += decrypted.length;

                final progress = currentFileSize > 0 ? (bytesReceived / currentFileSize).clamp(0.0, 1.0) : 1.0;
                final session = TransferSession(
                  id: 'qs_${DateTime.now().millisecondsSinceEpoch}',
                  fileName: currentFileName,
                  fileSize: currentFileSize,
                  bytesTransferred: bytesReceived,
                  speedMBps: 20.0,
                  progress: progress,
                  etaSeconds: 1,
                  isUpload: false,
                  status: bytesReceived >= currentFileSize ? TransferStatus.completed : TransferStatus.transferring,
                  filePath: partFile?.path,
                );
                onProgress?.call(session);

                if (bytesReceived >= currentFileSize) {
                  await fileSink!.flush();
                  await fileSink!.close();
                  stopwatch.stop();

                  final finalPath = StorageService.resolveCollision(storageService.downloadDirectory, currentFileName);
                  final finalFile = await partFile!.rename(finalPath);

                  // Record in persistent history
                  await historyRepository.addRecord(
                    TransferRecord.create(
                      fileName: currentFileName,
                      fileSize: currentFileSize,
                      filePath: finalFile.path,
                      direction: TransferDirection.received,
                      peerName: 'Quick Share ($remoteIp)',
                      transferDurationMs: stopwatch.elapsedMilliseconds,
                      status: TransferRecordStatus.completed,
                    ),
                  );
                  cleanup();
                }
              }
            }
          }
        } catch (_) {}
      }
    }, onError: (_) => cleanup(), onDone: () => cleanup());
  }

  void stop() {
    _serverSocket?.close();
  }
}
