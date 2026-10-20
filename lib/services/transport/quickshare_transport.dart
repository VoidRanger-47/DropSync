import 'dart:async';
import 'dart:io';
import '../../models/peer.dart';
import '../../models/transfer_session.dart';
import '../quickshare/quickshare_receiver.dart';
import 'transfer_transport.dart';

/// Transport adapter for Google Quick Share (UKEY2 + Protobuf) pairing.
class QuickShareTransport implements TransferTransport {
  final QuickShareReceiver? quickShareReceiver;

  QuickShareTransport({this.quickShareReceiver});

  @override
  TransportType get type => TransportType.quickShare;

  @override
  String get name => 'Google Quick Share (UKEY2 Handshake)';

  @override
  bool get isAvailable => quickShareReceiver != null;

  @override
  TransportState get state => _state;

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
    _statusMessageController.add('Quick Share Transport active on port ${QuickShareReceiver.defaultPort}');
  }

  @override
  Future<TransferSession> sendFile({
    required Peer peer,
    required File file,
    void Function(TransferSession)? onProgress,
  }) async {
    _state = TransportState.transferring;
    _stateController.add(_state);
    // Emits initial progress session
    final session = TransferSession.initial(
      fileName: file.path.split(Platform.pathSeparator).last,
      fileSize: await file.length(),
      isUpload: true,
      filePath: file.path,
    );
    _activeTransferController.add(session);
    onProgress?.call(session);
    return session;
  }

  @override
  Future<void> sendClipboard({
    required Peer peer,
    required String text,
  }) async {}

  @override
  Future<void> cancel() async {
    _state = TransportState.idle;
    _stateController.add(_state);
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
