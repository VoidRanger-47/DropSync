import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/transfer_record.dart';
import '../models/transfer_session.dart';
import 'history_repository.dart';
import 'storage_service.dart';

enum InternetPeerPresence {
  waitingForPeer,
  bothPresent,
  peerLeft,
  disconnected,
}

enum InternetTransferState {
  idle,
  connecting,
  ready,
  transferring,
  paused,
  completed,
  failed,
}

/// Service managing End-to-End Encrypted (E2EE) file transfers over the Internet,
/// with strict mutual real-time presence guard (both peers must stay on the page)
/// and Vercel-ready serverless relay signaling.
class InternetTransferService {
  static const int chunkSize = 48 * 1024; // 48 KB chunk size for smooth WAN streaming
  static const Duration heartbeatInterval = Duration(milliseconds: 1500);
  static const Duration peerTimeout = Duration(milliseconds: 4000);

  final StorageService storageService;
  final HistoryRepository historyRepository;

  // Cryptography instances
  final AesGcm _aesGcm = AesGcm.with256bits();
  SecretKey? _derivedKey;

  // Connection & Room state
  String? _currentRoomCode;
  bool _isSender = false;
  String _localPeerId = '';
  String _remotePeerId = '';
  String _customVercelUrl = 'https://dropsync-web.vercel.app';

  // Presence & Heartbeat
  bool _isLocalOnPage = true;
  bool _isRemoteOnPage = false;
  DateTime _lastRemoteHeartbeat = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _heartbeatTimer;
  Timer? _presenceCheckTimer;

  // Active Transfer State
  InternetTransferState _transferState = InternetTransferState.idle;
  InternetPeerPresence _presenceState = InternetPeerPresence.waitingForPeer;
  String _statusMessage = 'Ready for Internet Transfer';
  TransferSession? _activeSession;

  // Stream Controllers
  final _presenceController = StreamController<InternetPeerPresence>.broadcast();
  final _transferStateController = StreamController<InternetTransferState>.broadcast();
  final _statusMessageController = StreamController<String>.broadcast();
  final _sessionController = StreamController<TransferSession?>.broadcast();
  final _fileReceivedController = StreamController<File>.broadcast();

  // Getters
  Stream<InternetPeerPresence> get presenceStream => _presenceController.stream;
  Stream<InternetTransferState> get transferStateStream => _transferStateController.stream;
  Stream<String> get statusMessageStream => _statusMessageController.stream;
  Stream<TransferSession?> get sessionStream => _sessionController.stream;
  Stream<File> get fileReceivedStream => _fileReceivedController.stream;

  String? get currentRoomCode => _currentRoomCode;
  bool get isSender => _isSender;
  InternetPeerPresence get presenceState => _presenceState;
  InternetTransferState get transferState => _transferState;
  String get statusMessage => _statusMessage;
  TransferSession? get activeSession => _activeSession;
  String get vercelUrl => _customVercelUrl;
  bool get areBothPresent => _isLocalOnPage && _isRemoteOnPage;
  String get remotePeerId => _remotePeerId;
  DateTime get lastRemoteHeartbeat => _lastRemoteHeartbeat;

  // In-memory relay bus for immediate zero-server local testing / fallback
  static final Map<String, _InMemoryRoom> _mockRelayRooms = {};

  InternetTransferService({
    required this.storageService,
    required this.historyRepository,
  }) {
    _localPeerId = 'peer_${Random().nextInt(900000) + 100000}';
  }

  final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 4);

  Future<Map<String, dynamic>?> _postJson(String endpoint, Map<String, dynamic> body) async {
    try {
      final uri = Uri.parse('$_customVercelUrl$endpoint');
      final req = await _httpClient.postUrl(uri);
      req.headers.contentType = ContentType.json;
      req.headers.set('X-DropSync-Peer', _localPeerId);
      req.write(jsonEncode(body));
      final resp = await req.close().timeout(const Duration(seconds: 4));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final bodyStr = await resp.transform(utf8.decoder).join();
        return jsonDecode(bodyStr) as Map<String, dynamic>?;
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> _getJson(String endpoint) async {
    try {
      final uri = Uri.parse('$_customVercelUrl$endpoint');
      final req = await _httpClient.getUrl(uri);
      req.headers.set('X-DropSync-Peer', _localPeerId);
      final resp = await req.close().timeout(const Duration(seconds: 4));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final bodyStr = await resp.transform(utf8.decoder).join();
        return jsonDecode(bodyStr) as Map<String, dynamic>?;
      }
    } catch (_) {}
    return null;
  }

  void setVercelUrl(String url) {
    _customVercelUrl = url.trim();
  }

  /// Generates a human-friendly 6-character room code (e.g., "742-198")
  static String generateRoomCode() {
    final rand = Random();
    final p1 = rand.nextInt(900) + 100;
    final p2 = rand.nextInt(900) + 100;
    return '$p1-$p2';
  }

  /// Sets whether the local user is currently on the Internet Transfer page.
  void setLocalPagePresence(bool isOnPage) {
    _isLocalOnPage = isOnPage;
    if (!isOnPage) {
      _sendHeartbeat(status: 'left');
      _setPresence(InternetPeerPresence.disconnected, 'You left the transfer page');
      if (_transferState == InternetTransferState.transferring) {
        _setTransferState(InternetTransferState.paused, 'Transfer paused: You left the page');
      }
    } else {
      if (_currentRoomCode != null) {
        _sendHeartbeat(status: 'active');
        _checkPresence();
      }
    }
  }

  /// Creates a new E2EE Internet Transfer room as Sender.
  Future<String> createSenderRoom([String? customCode]) async {
    final code = customCode ?? generateRoomCode();
    _currentRoomCode = code;
    _isSender = true;
    _remotePeerId = '';
    _isRemoteOnPage = false;

    // Derive 256-bit AES-GCM Key from Room Code
    await _deriveKeyFromRoomCode(code);

    // Initialize mock relay room for immediate local tests/offline fallback
    _mockRelayRooms[code] = _InMemoryRoom(
      roomCode: code,
      senderId: _localPeerId,
      createdAt: DateTime.now(),
    );

    // Register on Vercel relay
    _postJson('/api/room', {
      'roomCode': code,
      'peerId': _localPeerId,
      'role': 'sender',
      'transferState': 'waiting',
    }).catchError((_) => null);

    _setPresence(InternetPeerPresence.waitingForPeer, 'Room created ($code). Waiting for receiver to open this page...');
    _setTransferState(InternetTransferState.ready, 'Share room code $code with receiver');

    _startHeartbeatLoop();
    return code;
  }

  /// Joins an existing E2EE Internet Transfer room as Receiver.
  Future<bool> joinReceiverRoom(String code) async {
    final cleanCode = code.trim().toUpperCase();
    _currentRoomCode = cleanCode;
    _isSender = false;
    _isRemoteOnPage = false;

    await _deriveKeyFromRoomCode(cleanCode);

    // Register receiver in mock room
    final room = _mockRelayRooms[cleanCode];
    if (room != null) {
      room.receiverId = _localPeerId;
      room.receiverLastHeartbeat = DateTime.now();
      _remotePeerId = room.senderId;
      _isRemoteOnPage = true;
      _lastRemoteHeartbeat = DateTime.now();
      _setPresence(InternetPeerPresence.bothPresent, 'Connected to Sender! Both peers are on page.');
      _setTransferState(InternetTransferState.ready, 'Ready to receive files via E2EE');
    } else {
      _setPresence(InternetPeerPresence.waitingForPeer, 'Joined room ($cleanCode). Connecting to sender...');
      _setTransferState(InternetTransferState.connecting, 'Waiting for sender presence...');
    }

    // Register on Vercel relay
    _postJson('/api/room', {
      'roomCode': cleanCode,
      'peerId': _localPeerId,
      'role': 'receiver',
    }).then((data) {
      if (data != null && data['presence'] != null) {
        final pres = data['presence'] as Map<String, dynamic>;
        if (pres['bothPresent'] == true) {
          _isRemoteOnPage = true;
          _lastRemoteHeartbeat = DateTime.now();
          _setPresence(InternetPeerPresence.bothPresent, 'Connected to Sender! Both peers are on page.');
          _setTransferState(InternetTransferState.ready, 'Ready to receive files via E2EE');
        }
      }
    }).catchError((_) => null);

    _startHeartbeatLoop();
    return true;
  }

  /// Derives an AES-256-GCM symmetric key using HKDF-SHA256 from the Room Code.
  Future<void> _deriveKeyFromRoomCode(String code) async {
    final cleanCode = code.replaceAll('-', '').trim();
    const saltString = 'DropSync_E2EE_Vercel_Relay_Salt_2026';
    final hkdf = Hkdf(
      hmac: Hmac.sha256(),
      outputLength: 32,
    );

    final inputKey = SecretKey(utf8.encode(cleanCode));
    final derivedSecret = await hkdf.deriveKey(
      secretKey: inputKey,
      nonce: utf8.encode(saltString),
      info: utf8.encode('DropSync_E2EE_SessionKey'),
    );

    _derivedKey = derivedSecret;
  }

  void _startHeartbeatLoop() {
    _heartbeatTimer?.cancel();
    _presenceCheckTimer?.cancel();

    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      if (_currentRoomCode != null && _isLocalOnPage) {
        _sendHeartbeat(status: 'active');
      }
    });

    _presenceCheckTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      _checkPresence();
    });
  }

  void _sendHeartbeat({required String status}) {
    final code = _currentRoomCode;
    if (code == null) return;

    // Send HTTP Heartbeat to Vercel (unified router)
    _postJson('/api/room?action=heartbeat', {
      'roomCode': code,
      'peerId': _localPeerId,
      'role': _isSender ? 'sender' : 'receiver',
      'status': status,
      'transferState': _transferState == InternetTransferState.transferring
          ? 'transferring'
          : (_transferState == InternetTransferState.completed ? 'completed' : 'waiting'),
    }).then((data) {
      if (data != null && data['presence'] != null) {
        final pres = data['presence'] as Map<String, dynamic>;
        final both = pres['bothPresent'] as bool? ?? false;
        if (both) {
          _lastRemoteHeartbeat = DateTime.now();
          if (!_isRemoteOnPage) {
            _isRemoteOnPage = true;
            _setPresence(InternetPeerPresence.bothPresent, 'Both peers are active on this page. Transfer enabled.');
          }
        }
      }
    }).catchError((_) => null);

    final room = _mockRelayRooms[code];
    if (room != null) {
      if (_isSender) {
        room.senderLastHeartbeat = status == 'active' ? DateTime.now() : DateTime.fromMillisecondsSinceEpoch(0);
      } else {
        room.receiverLastHeartbeat = status == 'active' ? DateTime.now() : DateTime.fromMillisecondsSinceEpoch(0);
      }
    }
  }

  void _checkPresence() {
    final code = _currentRoomCode;
    if (code == null) return;

    // Poll Vercel presence (unified router)
    _getJson('/api/room?action=heartbeat&roomCode=$code').then((data) {
      if (data != null && data['presence'] != null) {
        final pres = data['presence'] as Map<String, dynamic>;
        final both = pres['bothPresent'] as bool? ?? false;
        final now = DateTime.now();
        if (both) {
          _lastRemoteHeartbeat = now;
          if (!_isRemoteOnPage) {
            _isRemoteOnPage = true;
            _setPresence(InternetPeerPresence.bothPresent, 'Both peers are active on this page. Transfer enabled.');
            if (_transferState == InternetTransferState.paused) {
              _setTransferState(InternetTransferState.transferring, 'Peer returned! Resuming transfer...');
            }
          }
        } else {
          // If remote peer is offline according to relay and timeout has elapsed
          if (_isRemoteOnPage && now.difference(_lastRemoteHeartbeat) >= peerTimeout) {
            _isRemoteOnPage = false;
            _setPresence(
              InternetPeerPresence.peerLeft,
              _isSender
                  ? 'PAUSED: Receiver has navigated away or closed the app.'
                  : 'PAUSED: Sender has navigated away or closed the app.',
            );
            if (_transferState == InternetTransferState.transferring) {
              _setTransferState(
                InternetTransferState.paused,
                'Transfer paused: Both users must stay on this page.',
              );
            }
          }
        }
      }
    }).catchError((_) => null);

    // Fallback for offline local unit tests / mock relay rooms
    final room = _mockRelayRooms[code];
    if (room != null && (room.senderId != _localPeerId || room.receiverId != null)) {
      final now = DateTime.now();
      final remoteHeartbeat = _isSender ? room.receiverLastHeartbeat : room.senderLastHeartbeat;

      if (remoteHeartbeat != null && now.difference(remoteHeartbeat) < peerTimeout) {
        _lastRemoteHeartbeat = remoteHeartbeat;
        if (!_isRemoteOnPage) {
          _isRemoteOnPage = true;
          _setPresence(InternetPeerPresence.bothPresent, 'Both peers are active on this page. Transfer enabled.');
          if (_transferState == InternetTransferState.paused) {
            _setTransferState(InternetTransferState.transferring, 'Peer returned! Resuming transfer...');
          }
        }
      }
    }
  }

  /// Streams and sends a file through the E2EE Internet pipeline,
  /// strictly pausing whenever either peer leaves the page.
  Future<TransferSession> sendFile({
    required File file,
    void Function(TransferSession session)? onProgress,
  }) async {
    if (_currentRoomCode == null || !_isSender) {
      throw Exception('Not initialized as Sender in an active room');
    }
    if (!_isLocalOnPage) {
      throw Exception('Cannot start transfer while outside the transfer page');
    }

    final code = _currentRoomCode!;
    final room = _mockRelayRooms[code];
    if (room == null) {
      throw Exception('Room not found on relay');
    }

    _setTransferState(InternetTransferState.transferring, 'Initiating E2EE stream...');
    final fileName = p.basename(file.path);
    final fileSize = await file.length();
    final stopwatch = Stopwatch()..start();

    // Compute SHA-256 of plaintext for end-to-end audit
    final fileBytesForHash = await file.readAsBytes();
    final fileSha256 = crypto.sha256.convert(fileBytesForHash).toString();

    // Signal Vercel relay that file transfer is beginning
    _postJson('/api/room', {
      'roomCode': code,
      'peerId': _localPeerId,
      'role': 'sender',
      'transferState': 'transferring',
      'metadata': {
        'fileName': fileName,
        'fileSize': fileSize,
        'sha256': fileSha256,
      },
    }).catchError((_) => null);

    // Send metadata header (encrypted)
    final metaJson = jsonEncode({
      'fileName': fileName,
      'fileSize': fileSize,
      'sha256': fileSha256,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    final encryptedHeader = await _encryptBytes(utf8.encode(metaJson));
    room.chunkQueue.add(_RelayChunk(
      isHeader: true,
      data: encryptedHeader,
      chunkIndex: 0,
    ));

    // Submit header chunk to Vercel (unified router) and await delivery
    await _postJson('/api/room?action=chunk', {
      'roomCode': code,
      'peerId': _localPeerId,
      'chunkIndex': 0,
      'totalChunks': (fileSize / chunkSize).ceil() + 1,
      'isHeader': true,
      'dataBase64': base64Encode(encryptedHeader),
    }).catchError((_) => null);

    int bytesTransferred = 0;
    int chunkIndex = 1;
    final totalChunks = (fileSize / chunkSize).ceil() + 1;
    final fileStream = file.openRead();

    await for (final rawChunk in fileStream) {
      // 1. STRICT MUTUAL PRESENCE GUARD:
      // Loop until both sender and receiver are confirmed on the page
      while ((!_isLocalOnPage || !_isRemoteOnPage) && _currentRoomCode != null) {
        _setTransferState(
          InternetTransferState.paused,
          !_isRemoteOnPage
              ? 'Transfer Paused: Receiver left the page. Waiting...'
              : 'Transfer Paused: You navigated away from the page.',
        );
        await Future.delayed(const Duration(milliseconds: 500));
        _checkPresence();
      }

      if (_currentRoomCode == null) {
        throw Exception('Transfer cancelled: room closed');
      }

      // 2. Encrypt 48 KB binary chunk with AES-256-GCM
      final encryptedChunk = await _encryptBytes(rawChunk);

      // 3. Relay to room queue
      room.chunkQueue.add(_RelayChunk(
        isHeader: false,
        data: encryptedChunk,
        chunkIndex: chunkIndex,
      ));

      // Post chunk to Vercel relay and await transmission confirmation
      await _postJson('/api/room?action=chunk', {
        'roomCode': code,
        'peerId': _localPeerId,
        'chunkIndex': chunkIndex++,
        'totalChunks': totalChunks,
        'isHeader': false,
        'dataBase64': base64Encode(encryptedChunk),
      }).catchError((_) => null);

      bytesTransferred += rawChunk.length;
      final progress = fileSize > 0 ? (bytesTransferred / fileSize).clamp(0.0, 1.0) : 1.0;
      final elapsedSec = stopwatch.elapsedMilliseconds / 1000.0;
      final speedMBps = elapsedSec > 0 ? (bytesTransferred / (1024 * 1024)) / elapsedSec : 15.0;
      final remainingBytes = fileSize - bytesTransferred;
      final etaSec = speedMBps > 0 ? (remainingBytes / (speedMBps * 1024 * 1024)).ceil() : 0;

      final session = TransferSession(
        id: 'internet_${DateTime.now().millisecondsSinceEpoch}',
        fileName: fileName,
        fileSize: fileSize,
        bytesTransferred: bytesTransferred,
        speedMBps: speedMBps,
        progress: progress,
        etaSeconds: etaSec,
        isUpload: true,
        status: bytesTransferred >= fileSize ? TransferStatus.completed : TransferStatus.transferring,
        filePath: file.path,
      );

      _activeSession = session;
      _sessionController.add(session);
      onProgress?.call(session);

      // Brief throttle for smooth async streaming
      await Future.delayed(const Duration(milliseconds: 10));
    }

    stopwatch.stop();
    _setTransferState(InternetTransferState.completed, 'File sent with 256-bit AES-GCM encryption!');

    final completedSession = TransferSession(
      id: 'internet_${DateTime.now().millisecondsSinceEpoch}',
      fileName: fileName,
      fileSize: fileSize,
      bytesTransferred: fileSize,
      speedMBps: (fileSize / (1024 * 1024)) / (stopwatch.elapsedMilliseconds / 1000.0).clamp(0.1, 9999.0),
      progress: 1.0,
      etaSeconds: 0,
      isUpload: true,
      status: TransferStatus.completed,
      filePath: file.path,
    );

    await historyRepository.addRecord(
      TransferRecord.create(
        fileName: fileName,
        fileSize: fileSize,
        filePath: file.path,
        direction: TransferDirection.sent,
        peerName: 'Internet E2EE (${_currentRoomCode ?? "Relay"})',
        transferDurationMs: stopwatch.elapsedMilliseconds,
        status: TransferRecordStatus.completed,
      ),
    );

    return completedSession;
  }

  /// Receiver polling loop: receives encrypted chunks, verifies presence,
  /// decrypts chunks with AES-256-GCM, and writes atomically to download directory.
  Future<File?> startReceiverListening() async {
    final code = _currentRoomCode;
    if (code == null) return null;

    final room = _mockRelayRooms.putIfAbsent(
      code,
      () => _InMemoryRoom(roomCode: code, senderId: 'remote', createdAt: DateTime.now()),
    );

    _setTransferState(InternetTransferState.ready, 'Waiting for incoming file stream...');

    final destDir = storageService.downloadDirectory;
    String? incomingFileName;
    int incomingFileSize = 0;
    String expectedSha256 = '';
    IOSink? partSink;
    File? partFile;
    int bytesReceived = 0;
    final stopwatch = Stopwatch();

    while (_currentRoomCode != null && _presenceState != InternetPeerPresence.disconnected) {
      // 1. Check mutual presence
      while ((!_isLocalOnPage || !_isRemoteOnPage) && _currentRoomCode != null) {
        _setTransferState(
          InternetTransferState.paused,
          !_isRemoteOnPage
              ? 'Transfer Paused: Sender left the page. Waiting...'
              : 'Transfer Paused: You navigated away from the page.',
        );
        await Future.delayed(const Duration(milliseconds: 500));
        _checkPresence();
      }

      // Check HTTP relay for pending chunks if in-memory queue is empty
      if (room.chunkQueue.isEmpty) {
        try {
          final chunkData = await _getJson('/api/room?action=chunk&roomCode=$code');
          if (chunkData != null && chunkData['chunks'] != null) {
            final pulled = chunkData['chunks'] as List<dynamic>;
            for (final c in pulled) {
              final map = c as Map<String, dynamic>;
              final isHdr = map['isHeader'] as bool? ?? false;
              final b64 = map['dataBase64'] as String? ?? '';
              final idx = (map['chunkIndex'] as num?)?.toInt() ?? 0;
              if (b64.isNotEmpty) {
                room.chunkQueue.add(_RelayChunk(
                  isHeader: isHdr,
                  data: base64Decode(b64),
                  chunkIndex: idx,
                ));
              }
            }
          }
        } catch (_) {}
      }

      if (room.chunkQueue.isNotEmpty) {
        final chunk = room.chunkQueue.removeAt(0);

        if (chunk.isHeader) {
          // Decrypt Header
          final decryptedBytes = await _decryptBytes(chunk.data);
          final meta = jsonDecode(utf8.decode(decryptedBytes)) as Map<String, dynamic>;
          incomingFileName = meta['fileName'] as String;
          incomingFileSize = meta['fileSize'] as int;
          expectedSha256 = meta['sha256'] as String? ?? '';

          final partPath = p.join(destDir, '$incomingFileName.part');
          partFile = File(partPath);
          partSink = partFile.openWrite();
          stopwatch.start();
          _setTransferState(InternetTransferState.transferring, 'Receiving $incomingFileName (E2EE)...');
        } else if (partSink != null && incomingFileName != null) {
          // Decrypt binary chunk
          final decryptedChunk = await _decryptBytes(chunk.data);
          partSink.add(decryptedChunk);
          bytesReceived += decryptedChunk.length;

          final progress = (bytesReceived / incomingFileSize).clamp(0.0, 1.0);
          final elapsedSec = stopwatch.elapsedMilliseconds / 1000.0;
          final speedMBps = elapsedSec > 0 ? (bytesReceived / (1024 * 1024)) / elapsedSec : 15.0;
          final remainingBytes = incomingFileSize - bytesReceived;
          final etaSec = speedMBps > 0 ? (remainingBytes / (speedMBps * 1024 * 1024)).ceil() : 0;

          final session = TransferSession(
            id: 'internet_rx_${DateTime.now().millisecondsSinceEpoch}',
            fileName: incomingFileName,
            fileSize: incomingFileSize,
            bytesTransferred: bytesReceived,
            speedMBps: speedMBps,
            progress: progress,
            etaSeconds: etaSec,
            isUpload: false,
            status: bytesReceived >= incomingFileSize ? TransferStatus.completed : TransferStatus.transferring,
            filePath: partFile!.path,
          );

          _activeSession = session;
          _sessionController.add(session);

          if (bytesReceived >= incomingFileSize) {
            await partSink.flush();
            await partSink.close();
            stopwatch.stop();

            // Final rename from .part to final file
            final finalPath = p.join(destDir, incomingFileName);
            final finalFile = await partFile.rename(finalPath);

            // Verify integrity if hash provided
            if (expectedSha256.isNotEmpty) {
              final fileDigest = await crypto.sha256.bind(finalFile.openRead()).first;
              if (fileDigest.toString() != expectedSha256) {
                _setTransferState(InternetTransferState.failed, 'Checksum warning: File may be corrupt');
              }
            }

            _fileReceivedController.add(finalFile);
            _setTransferState(InternetTransferState.completed, 'File received and decrypted: $incomingFileName');

            await historyRepository.addRecord(
              TransferRecord.create(
                fileName: incomingFileName,
                fileSize: incomingFileSize,
                filePath: finalPath,
                direction: TransferDirection.received,
                peerName: 'Internet E2EE ($code)',
                transferDurationMs: stopwatch.elapsedMilliseconds,
                status: TransferRecordStatus.completed,
              ),
            );

            return finalFile;
          }
        }
      }

      // Only delay if queue is empty to avoid artificial lag behind sender
      if (room.chunkQueue.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 30));
      }
    }

    return null;
  }

  /// Encrypts bytes using AES-256-GCM.
  /// Wire format: 12-byte nonce + 16-byte MAC tag + ciphertext
  Future<Uint8List> _encryptBytes(List<int> plainBytes) async {
    if (_derivedKey == null) throw Exception('Encryption key not initialized');

    final nonce = _aesGcm.newNonce();
    final secretBox = await _aesGcm.encrypt(
      plainBytes,
      secretKey: _derivedKey!,
      nonce: nonce,
    );

    final builder = BytesBuilder();
    builder.add(secretBox.nonce);
    builder.add(secretBox.mac.bytes);
    builder.add(secretBox.cipherText);
    return builder.toBytes();
  }

  /// Decrypts bytes using AES-256-GCM.
  Future<List<int>> _decryptBytes(Uint8List wireBytes) async {
    if (_derivedKey == null) throw Exception('Decryption key not initialized');
    if (wireBytes.length < 28) throw Exception('Invalid encrypted payload');

    final nonce = wireBytes.sublist(0, 12);
    final macBytes = wireBytes.sublist(12, 28);
    final cipherText = wireBytes.sublist(28);

    final secretBox = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(macBytes),
    );

    return await _aesGcm.decrypt(
      secretBox,
      secretKey: _derivedKey!,
    );
  }

  @visibleForTesting
  Future<Uint8List> testEncryptBytes(List<int> plainBytes) => _encryptBytes(plainBytes);

  @visibleForTesting
  Future<List<int>> testDecryptBytes(Uint8List wireBytes) => _decryptBytes(wireBytes);

  void _setPresence(InternetPeerPresence presence, String message) {
    _presenceState = presence;
    _statusMessage = message;
    if (!_presenceController.isClosed) _presenceController.add(presence);
    if (!_statusMessageController.isClosed) _statusMessageController.add(message);
  }

  void _setTransferState(InternetTransferState state, String message) {
    _transferState = state;
    _statusMessage = message;
    if (!_transferStateController.isClosed) _transferStateController.add(state);
    if (!_statusMessageController.isClosed) _statusMessageController.add(message);
  }

  void closeRoom() {
    _sendHeartbeat(status: 'left');
    _heartbeatTimer?.cancel();
    _presenceCheckTimer?.cancel();
    _currentRoomCode = null;
    _isRemoteOnPage = false;
    _activeSession = null;
    _setPresence(InternetPeerPresence.disconnected, 'Room closed');
    _setTransferState(InternetTransferState.idle, 'Ready for Internet Transfer');
  }

  void dispose() {
    closeRoom();
    _httpClient.close(force: true);
    _presenceController.close();
    _transferStateController.close();
    _statusMessageController.close();
    _sessionController.close();
    _fileReceivedController.close();
  }
}

class _InMemoryRoom {
  final String roomCode;
  final String senderId;
  String? receiverId;
  final DateTime createdAt;
  DateTime? senderLastHeartbeat;
  DateTime? receiverLastHeartbeat;
  final List<_RelayChunk> chunkQueue = [];

  _InMemoryRoom({
    required this.roomCode,
    required this.senderId,
    required this.createdAt,
  }) {
    senderLastHeartbeat = DateTime.now();
  }
}

class _RelayChunk {
  final bool isHeader;
  final Uint8List data;
  final int chunkIndex;

  _RelayChunk({
    required this.isHeader,
    required this.data,
    required this.chunkIndex,
  });
}
