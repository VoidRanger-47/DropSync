import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:dropsync/models/peer.dart';
import 'package:dropsync/models/payload_header.dart';
import 'package:dropsync/models/transfer_session.dart';
import 'package:dropsync/models/transfer_record.dart';

void main() {
  group('DropSync Models, History & Protocol Unit Tests', () {
    test('Peer JSON serialization and QR parsing', () {
      const qrJson =
          '{"ip": "192.168.1.100", "port": 8080, "token": "A7B9", "device": "Galaxy-S24", "platform": "android"}';

      final peer = Peer.fromQrString(qrJson);
      expect(peer, isNotNull);
      expect(peer!.ip, '192.168.1.100');
      expect(peer.port, 8080);
      expect(peer.token, 'A7B9');
      expect(peer.name, 'Galaxy-S24');
      expect(peer.platform, 'android');
      expect(peer.isManual, isTrue);

      // Verify QR roundtrip string
      final serialized = peer.toQrString();
      final roundtrip = Peer.fromQrString(serialized);
      expect(roundtrip!.ip, peer.ip);
      expect(roundtrip.port, peer.port);
      expect(roundtrip.token, peer.token);
    });

    test('PayloadHeader binary wire format encoding & parsing', () {
      const fileName = 'archive_backup.tar.gz';
      const fileSize = 104857600; // 100 MB

      final header = PayloadHeader.file(
        fileName: fileName,
        fileSize: fileSize,
      );

      final bytes = header.toBytes();

      // Check header wire length: 4 magic + 2 len + N filename + 8 size
      final nameBytes = utf8.encode(fileName);
      expect(bytes.length, 4 + 2 + nameBytes.length + 8);

      // Check Magic: 'DSYN' (0x44, 0x53, 0x59, 0x4E)
      expect(bytes.sublist(0, 4), DropSyncMagic.fileStream);

      // Parse back from buffer
      final parsed = PayloadHeader.tryParse(bytes);
      expect(parsed, isNotNull);
      expect(parsed!.fileName, fileName);
      expect(parsed.fileSize, fileSize);
      expect(parsed.isFileTransfer, isTrue);
      expect(parsed.isClipboardTransfer, isFalse);
    });

    test('Clipboard PayloadHeader frame verification', () {
      const clipText = 'https://gemini.google.com';
      final header = PayloadHeader.clipboard(text: clipText);

      final bytes = header.toBytes();
      expect(bytes.sublist(0, 4), DropSyncMagic.clipboard);

      final parsed = PayloadHeader.tryParse(bytes);
      expect(parsed, isNotNull);
      expect(parsed!.isClipboardTransfer, isTrue);
      expect(parsed.fileSize, utf8.encode(clipText).length);
    });

    test('TransferSession progress and formatted metrics', () {
      final session = TransferSession(
        id: 'tx_test_1',
        fileName: 'dataset.csv',
        fileSize: 100 * 1024 * 1024, // 100 MB
        bytesTransferred: 50 * 1024 * 1024, // 50 MB
        speedMBps: 32.5,
        progress: 0.5,
        etaSeconds: 2,
        isUpload: true,
        status: TransferStatus.transferring,
      );

      expect(session.formattedProgress, '50%');
      expect(session.formattedSpeed, '32.5 MB/s');
      expect(session.formattedEta, '2s');
      expect(session.formattedTransferred, '50.0 MB');
      expect(session.formattedTotalSize, '100.0 MB');
      expect(session.isActive, isTrue);
    });

    test('TransferRecord JSON roundtrip and date grouping', () {
      final record = TransferRecord.create(
        fileName: 'presentation.pdf',
        fileSize: 15 * 1024 * 1024,
        filePath: 'C:/Users/kbven/Downloads/DropSync/presentation.pdf',
        direction: TransferDirection.received,
        peerName: 'Pixel 8',
        transferDurationMs: 1200,
        status: TransferRecordStatus.completed,
      );

      expect(record.fileName, 'presentation.pdf');
      expect(record.formattedSize, '15.0 MB');
      expect(record.direction, TransferDirection.received);
      expect(record.dateCategory, 'Today');
      expect(record.status, TransferRecordStatus.completed);

      // JSON roundtrip
      final json = record.toJson();
      final restored = TransferRecord.fromJson(json);
      expect(restored.id, record.id);
      expect(restored.fileName, record.fileName);
      expect(restored.fileSize, record.fileSize);
      expect(restored.filePath, record.filePath);
      expect(restored.direction, record.direction);
      expect(restored.peerName, record.peerName);
      expect(restored.status, record.status);
    });
  });
}
