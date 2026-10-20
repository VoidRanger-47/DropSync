import 'dart:async';
import 'dart:io';
import '../../models/peer.dart';
import '../../models/transfer_session.dart';
import '../dropsync/dropsync_engine.dart';
import 'transfer_transport.dart';

/// Transport adapter for Native DropSync LAN socket streaming with background isolate offloading.
class DropSyncLanTransport implements TransferTransport {
  @override
  TransportType get type => TransportType.dropsyncLan;

  @override
  String get name => 'DropSync LAN Socket (Isolate Streaming)';

  @override
  bool get isAvailable => _isAvailable;

  @override
  TransportState get state => _state;

  final bool _isAvailable = true;
  TransportState _state = TransportState.idle;

  final _activeTransferController = StreamController<TransferSession?>.broadcast();
  final _fileReceivedController = StreamController<File>.broadcast();
  final _clipboardReceivedController = StreamController<String>.broadcast();
  final _statusMessageController = StreamController<String>.broadcast();
  final _stateController = StreamController<TransportState>.broadcast();

  @override
  Stream<TransferSession?> get activeTransferStream => _activeTransferController.stream;

  @override
  Stream<File> get fileReceivedStream => _fileReceivedController.stream;

  @override
  Stream<String> get clipboardReceivedStream => _clipboardReceivedController.stream;

  @override
  Stream<String> get statusMessageStream => _statusMessageController.stream;

  @override
  Stream<TransportState> get stateStream => _stateController.stream;

  @override
  Future<void> start() async {
    _state = TransportState.listening;
    _stateController.add(_state);
    _statusMessageController.add('DropSync LAN Transport active');
  }

  @override
  Future<TransferSession> sendFile({
    required Peer peer,
    required File file,
    void Function(TransferSession)? onProgress,
  }) async {
    _state = TransportState.connecting;
    _stateController.add(_state);
    _statusMessageController.add('Connecting to ${peer.name} (${peer.ip}:${peer.port})...');

    Socket? socket;
    try {
      socket = await Socket.connect(peer.ip, peer.port, timeout: const Duration(seconds: 5));
      _state = TransportState.transferring;
      _stateController.add(_state);

      // Use dedicated DropSyncEngine background isolate streaming
      final session = await DropSyncEngine.sendFileWithIsolate(
        socket: socket,
        file: file,
        onProgress: (s) {
          _activeTransferController.add(s);
          onProgress?.call(s);
        },
      );

      _state = TransportState.completed;
      _stateController.add(_state);
      _statusMessageController.add('File transfer completed: ${session.fileName}');
      return session;
    } catch (e) {
      _state = TransportState.failed;
      _stateController.add(_state);
      _statusMessageController.add('Transfer error: $e');
      rethrow;
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
    }
  }

  @override
  Future<void> sendClipboard({
    required Peer peer,
    required String text,
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(peer.ip, peer.port, timeout: const Duration(seconds: 4));
      await SocketEngine.sendClipboard(socket: socket, text: text);
      _statusMessageController.add('Clipboard synced to ${peer.name}');
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
    }
  }

  @override
  Future<void> cancel() async {
    _state = TransportState.idle;
    _stateController.add(_state);
    _activeTransferController.add(null);
  }

  @override
  Future<void> dispose() async {
    await _activeTransferController.close();
    await _fileReceivedController.close();
    await _clipboardReceivedController.close();
    await _statusMessageController.close();
    await _stateController.close();
  }
}
