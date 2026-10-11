import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dropsync/services/quickshare/protobuf/nearby_sharing_protobuf.dart';
import 'package:dropsync/services/quickshare/ukey2_handshake.dart';
import 'package:dropsync/services/quickshare/quickshare_discovery.dart';

void main() {
  group('Quick Share Protobuf & Wire Format Tests', () {
    test('Varint encoding and decoding', () {
      final v1 = PbWire.encodeVarint(1);
      expect(v1, equals([1]));

      final v300 = PbWire.encodeVarint(300);
      expect(v300.length, equals(2));
    });

    test('Ukey2Message parse and serialization', () {
      final msg = Ukey2Message(
        messageType: 1,
        payload: Uint8List.fromList([10, 20, 30, 40]),
      );
      final raw = msg.toBytes();
      final parsed = Ukey2Message.parse(raw);
      expect(parsed, isNotNull);
      expect(parsed!.messageType, equals(1));
      expect(parsed.payload, equals([10, 20, 30, 40]));
    });

    test('OfflineFrame framing with 4-byte big-endian length', () {
      final frame = OfflineFrame(
        type: 1,
        endpointId: 'DSYK',
        endpointName: 'Pixel 9 Pro',
      );
      final framedBytes = frame.toFramedBytes();
      expect(framedBytes.length, greaterThan(4));

      final bd = ByteData.sublistView(framedBytes);
      final length = bd.getUint32(0, Endian.big);
      expect(framedBytes.length, equals(length + 4));

      final parsed = OfflineFrame.parseFramed(framedBytes);
      expect(parsed, isNotNull);
      expect(parsed!.type, equals(1));
      expect(parsed.endpointId, equals('DSYK'));
      expect(parsed.endpointName, equals('Pixel 9 Pro'));
    });

    test('IntroductionFrame serialization and deserialization', () {
      final intro = IntroductionFrame(files: [
        QuickShareFileMeta(
          name: 'project_backup.zip',
          type: 1,
          payloadId: 4001,
          size: 10485760,
          mimeType: 'application/zip',
        ),
      ]);
      final bytes = intro.toBytes();
      final parsed = IntroductionFrame.parse(bytes);
      expect(parsed, isNotNull);
      expect(parsed.files.length, equals(1));
      expect(parsed.files.first.name, equals('project_backup.zip'));
      expect(parsed.files.first.size, equals(10485760));
      expect(parsed.files.first.payloadId, equals(4001));
    });
  });

  group('UKEY2 Cryptographic Handshake & Session Tests', () {
    test('Client & Server generate matching 4-digit PIN and decrypt AES-256-GCM payload', () async {
      final client = Ukey2Handshake();
      final server = Ukey2Handshake();

      await client.initKeyPair();
      await server.initKeyPair();

      // Client creates ClientInit
      final clientInit = await client.createClientInit();
      expect(clientInit.messageType, equals(1));

      // Server creates ServerInit
      final serverInit = await server.createServerInit();
      expect(serverInit.messageType, equals(2));

      // Extract public keys and exchange
      // In UKEY2, public key is field 2 of the Ukey2Message payload
      Uint8List extractPk(Uint8List payload) {
        int offset = 0;
        while (offset < payload.length) {
          final tagByte = payload[offset++];
          final fieldNum = tagByte >> 3;
          final wireType = tagByte & 0x07;
          if (wireType == 0) {
            while (payload[offset++] >= 0x80) {}
          } else if (wireType == 2) {
            int len = 0;
            int shift = 0;
            while (true) {
              final b = payload[offset++];
              len |= (b & 0x7F) << shift;
              if ((b & 0x80) == 0) break;
              shift += 7;
            }
            final bytes = payload.sublist(offset, offset + len);
            offset += len;
            if (fieldNum == 2) return bytes;
          }
        }
        throw Exception('Public key not found in payload');
      }

      final clientPk = extractPk(clientInit.payload);
      final serverPk = extractPk(serverInit.payload);

      // Both process each other's public key
      await client.processPeerPublicKey(serverPk, isClient: true);
      await server.processPeerPublicKey(clientPk, isClient: false);

      // Verify that both derived the EXACT SAME 4-digit PIN!
      expect(client.pinCode, equals(server.pinCode));
      expect(client.pinCode.length, equals(4));
      expect(int.tryParse(client.pinCode), isNotNull);

      // Test AES-256-GCM authenticated encryption/decryption between client and server
      final testData = utf8.encode('DropSync QuickShare interoperability payload stream test');
      final encryptedFromClient = await client.encryptFrame(Uint8List.fromList(testData));
      final decryptedOnServer = await server.decryptFrame(encryptedFromClient);

      expect(utf8.decode(decryptedOnServer), equals('DropSync QuickShare interoperability payload stream test'));
    });
  });

  group('Quick Share Discovery & Intent Trigger Tests', () {
    test('generateQuickSharePairingUri creates valid Google Quick Share URI', () {
      final uri = QuickShareDiscovery.generateQuickSharePairingUri('abcd1234efgh');
      expect(uri, equals('https://quickshare.google/qrcode#key=abcd1234efgh'));
    });
  });
}
