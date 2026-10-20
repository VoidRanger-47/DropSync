import 'dart:async';
import 'dart:io';
import '../../models/peer.dart';
import '../../models/transfer_session.dart';

enum TransportType {
  dropsyncLan,
  quickShare,
  hotspot,
  internetRelay,
}

enum TransportState {
  idle,
  listening,
  connecting,
  transferring,
  completed,
  failed,
}

/// Abstract interface unifying all DropSync network transport engines
/// (Native LAN Sockets, Google Quick Share, Wi-Fi Hotspot, and Internet Relay).
abstract class TransferTransport {
  TransportType get type;
  String get name;
  bool get isAvailable;
  TransportState get state;

  Stream<TransportState> get stateStream;
  Stream<TransferSession?> get activeTransferStream;
  Stream<File> get fileReceivedStream;
  Stream<String> get clipboardReceivedStream;
  Stream<String> get statusMessageStream;

  Future<void> start();
  Future<TransferSession> sendFile({
    required Peer peer,
    required File file,
    void Function(TransferSession)? onProgress,
  });
  Future<void> sendClipboard({
    required Peer peer,
    required String text,
  });
  Future<void> cancel();
  Future<void> dispose();
}

/// Unified Transport Manager orchestrating and selecting between
/// LAN Sockets, Quick Share, Hotspot, and Internet transports.
class UnifiedTransportManager {
  final Map<TransportType, TransferTransport> _transports = {};
  TransportType _activeTransportType = TransportType.dropsyncLan;

  final _activeTransferController = StreamController<TransferSession?>.broadcast();
  final _fileReceivedController = StreamController<File>.broadcast();
  final _clipboardReceivedController = StreamController<String>.broadcast();
  final _statusMessageController = StreamController<String>.broadcast();
  final _stateController = StreamController<TransportState>.broadcast();

  final List<StreamSubscription> _subscriptions = [];

  Stream<TransferSession?> get activeTransferStream => _activeTransferController.stream;
  Stream<File> get fileReceivedStream => _fileReceivedController.stream;
  Stream<String> get clipboardReceivedStream => _clipboardReceivedController.stream;
  Stream<String> get statusMessageStream => _statusMessageController.stream;
  Stream<TransportState> get stateStream => _stateController.stream;

  TransportType get activeTransportType => _activeTransportType;
  TransferTransport? get activeTransport => _transports[_activeTransportType];

  void registerTransport(TransferTransport transport) {
    _transports[transport.type] = transport;

    _subscriptions.add(transport.activeTransferStream.listen((session) {
      if (transport.type == _activeTransportType && !_activeTransferController.isClosed) {
        _activeTransferController.add(session);
      }
    }));

    _subscriptions.add(transport.fileReceivedStream.listen((file) {
      if (!_fileReceivedController.isClosed) {
        _fileReceivedController.add(file);
      }
    }));

    _subscriptions.add(transport.clipboardReceivedStream.listen((clip) {
      if (!_clipboardReceivedController.isClosed) {
        _clipboardReceivedController.add(clip);
      }
    }));

    _subscriptions.add(transport.statusMessageStream.listen((msg) {
      if (transport.type == _activeTransportType && !_statusMessageController.isClosed) {
        _statusMessageController.add(msg);
      }
    }));

    _subscriptions.add(transport.stateStream.listen((st) {
      if (transport.type == _activeTransportType && !_stateController.isClosed) {
        _stateController.add(st);
      }
    }));
  }

  void setActiveTransport(TransportType type) {
    _activeTransportType = type;
    final transport = _transports[type];
    if (transport != null && !_stateController.isClosed) {
      _stateController.add(transport.state);
    }
  }

  TransferTransport? getTransport(TransportType type) => _transports[type];

  Future<TransferSession> sendFile({
    required Peer peer,
    required File file,
    TransportType? overrideTransport,
    void Function(TransferSession)? onProgress,
  }) async {
    final type = overrideTransport ?? _resolveTransportForPeer(peer);
    setActiveTransport(type);
    final transport = _transports[type];
    if (transport == null) {
      throw StateError('Transport $type is not registered');
    }
    return transport.sendFile(peer: peer, file: file, onProgress: onProgress);
  }

  Future<void> sendClipboard({
    required Peer peer,
    required String text,
    TransportType? overrideTransport,
  }) async {
    final type = overrideTransport ?? _resolveTransportForPeer(peer);
    setActiveTransport(type);
    final transport = _transports[type];
    if (transport == null) {
      throw StateError('Transport $type is not registered');
    }
    return transport.sendClipboard(peer: peer, text: text);
  }

  TransportType _resolveTransportForPeer(Peer peer) {
    if (peer.isHotspot) return TransportType.hotspot;
    if (peer.isQuickShare) return TransportType.quickShare;
    return TransportType.dropsyncLan;
  }

  Future<void> dispose() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    for (final t in _transports.values) {
      await t.dispose();
    }
    await _activeTransferController.close();
    await _fileReceivedController.close();
    await _clipboardReceivedController.close();
    await _statusMessageController.close();
    await _stateController.close();
  }
}
