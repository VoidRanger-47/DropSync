import 'dart:async';
import 'dart:io';
import '../../models/peer.dart';
import '../../models/transfer_session.dart';
import '../internet_transfer_service.dart';
import 'transfer_transport.dart';

/// Transport adapter for Long-Distance E2EE Internet Relay via WebRTC signaling.
class InternetRelayTransport implements TransferTransport {
  final InternetTransferService internetService;

  InternetRelayTransport({required this.internetService});

  @override
  TransportType get type => TransportType.internetRelay;

  @override
  String get name => 'Internet E2EE Relay (WebRTC Signaling)';

  @override
  bool get isAvailable => internetService.areBothPresent;

  @override
  TransportState get state {
    switch (internetService.transferState) {
      case InternetTransferState.idle:
        return TransportState.idle;
      case InternetTransferState.connecting:
        return TransportState.connecting;
      case InternetTransferState.ready:
        return TransportState.listening;
      case InternetTransferState.transferring:
        return TransportState.transferring;
      case InternetTransferState.paused:
        return TransportState.connecting;
      case InternetTransferState.completed:
        return TransportState.completed;
      case InternetTransferState.failed:
        return TransportState.failed;
    }
  }

  @override
  Stream<TransportState> get stateStream =>
      internetService.transferStateStream.map((s) {
        switch (s) {
          case InternetTransferState.idle:
            return TransportState.idle;
          case InternetTransferState.connecting:
            return TransportState.connecting;
          case InternetTransferState.ready:
            return TransportState.listening;
          case InternetTransferState.transferring:
            return TransportState.transferring;
          case InternetTransferState.paused:
            return TransportState.connecting;
          case InternetTransferState.completed:
            return TransportState.completed;
          case InternetTransferState.failed:
            return TransportState.failed;
        }
      });

  @override
  Stream<TransferSession?> get activeTransferStream => internetService.sessionStream;

  @override
  Stream<File> get fileReceivedStream => internetService.fileReceivedStream;

  @override
  Stream<String> get clipboardReceivedStream => const Stream.empty();

  @override
  Stream<String> get statusMessageStream => internetService.statusMessageStream;

  @override
  Future<void> start() async {}

  @override
  Future<TransferSession> sendFile({
    required Peer peer,
    required File file,
    void Function(TransferSession)? onProgress,
  }) async {
    return internetService.sendFile(file: file, onProgress: onProgress);
  }

  @override
  Future<void> sendClipboard({
    required Peer peer,
    required String text,
  }) async {}

  @override
  Future<void> cancel() async {
    internetService.closeRoom();
  }

  @override
  Future<void> dispose() async {}
}
