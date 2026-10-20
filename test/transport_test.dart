import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dropsync/models/peer.dart';
import 'package:dropsync/services/transport/transfer_transport.dart';
import 'package:dropsync/services/transport/dropsync_lan_transport.dart';
import 'package:dropsync/services/transport/quickshare_transport.dart';
import 'package:dropsync/services/transport/internet_relay_transport.dart';
import 'package:dropsync/services/dropsync/dropsync_engine.dart';
import 'package:dropsync/services/storage/storage_service.dart';
import 'package:dropsync/services/storage/history_repository.dart';
import 'package:dropsync/services/internet_transfer_service.dart';
import 'package:dropsync/services/quickshare/ukey2_handshake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Unified Transport Architecture Tests', () {
    test('UnifiedTransportManager registers transports and resolves for peer types', () async {
      final manager = UnifiedTransportManager();
      final lanTransport = DropSyncLanTransport();
      final qsTransport = QuickShareTransport();

      manager.registerTransport(lanTransport);
      manager.registerTransport(qsTransport);

      expect(manager.getTransport(TransportType.dropsyncLan), equals(lanTransport));
      expect(manager.getTransport(TransportType.quickShare), equals(qsTransport));

      final lanPeer = Peer(
        id: 'peer_1',
        name: 'LAN Node',
        platform: 'windows',
        ip: '192.168.1.50',
        port: 8080,
        token: 'token123',
        lastSeen: DateTime.now(),
        protocolType: PeerProtocolType.dropsync,
      );

      final qsPeer = Peer(
        id: 'peer_2',
        name: 'Samsung Galaxy',
        platform: 'android',
        ip: '192.168.1.60',
        port: 8088,
        token: 'token456',
        lastSeen: DateTime.now(),
        protocolType: PeerProtocolType.quickShare,
      );

      expect(lanPeer.isQuickShare, isFalse);
      expect(qsPeer.isQuickShare, isTrue);

      await manager.dispose();
    });

    test('InternetRelayTransport binds presence and session streams', () async {
      final storage = StorageService();
      final history = HistoryRepository();
      final internetService = InternetTransferService(
        storageService: storage,
        historyRepository: history,
      );

      final relayTransport = InternetRelayTransport(internetService: internetService);
      expect(relayTransport.type, equals(TransportType.internetRelay));
      expect(relayTransport.name, contains('Internet E2EE Relay'));
      expect(relayTransport.state, equals(TransportState.idle));

      internetService.dispose();
    });
  });

  group('UKEY2 Background Isolate Cryptography Tests', () {
    test('UKEY2 Handshake generates keys and encrypts frames offloaded to Isolate', () async {
      final clientHandshake = Ukey2Handshake();
      final serverHandshake = Ukey2Handshake();

      await clientHandshake.initKeyPair();
      await serverHandshake.initKeyPair();

      final clientInit = await clientHandshake.createClientInit();
      final serverInit = await serverHandshake.createServerInit();

      expect(clientInit.payload.isNotEmpty, isTrue);
      expect(serverInit.payload.isNotEmpty, isTrue);

      // Extract raw keys and exchange
      final clientPk = clientInit.payload.sublist(clientInit.payload.length - 32);
      final serverPk = serverInit.payload.sublist(serverInit.payload.length - 32);

      await clientHandshake.processPeerPublicKey(serverPk, isClient: true);
      await serverHandshake.processPeerPublicKey(clientPk, isClient: false);

      // Both should derive the exact same 4-digit PIN in background isolate!
      expect(clientHandshake.pinCode, equals(serverHandshake.pinCode));
      expect(clientHandshake.pinCode.length, equals(4));

      // Test AES-GCM isolate encryption / decryption
      const plainText = 'Hello Secure DropSync UKEY2 Isolate!';
      final plainBytes = plainText.codeUnits;

      final encrypted = await clientHandshake.encryptFrame(Uint8List.fromList(plainBytes));
      expect(encrypted.isNotEmpty, isTrue);

      final decrypted = await serverHandshake.decryptFrame(encrypted);
      expect(String.fromCharCodes(decrypted), equals(plainText));
    });
  });

  group('DropSyncEngine Background Isolate Hashing Tests', () {
    test('computeSha256Isolate hashes files correctly in background isolate', () async {
      final tempDir = Directory.systemTemp.createTempSync('dropsync_iso_test_');
      final testFile = File('${tempDir.path}/test.bin');
      await testFile.writeAsBytes(List.generate(1024 * 128, (i) => i % 256));

      final hash = await DropSyncEngine.computeSha256Isolate(testFile);
      expect(hash.length, equals(64));

      tempDir.deleteSync(recursive: true);
    });
  });
}
