import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dropsync/models/transfer_session.dart';
import 'package:dropsync/services/storage/history_repository.dart';
import 'package:dropsync/services/internet_transfer_service.dart';
import 'package:dropsync/services/storage/storage_service.dart';
import 'package:dropsync/views/internet_transfer_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storageService;
  late HistoryRepository historyRepository;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dropsync_test_');
    SharedPreferences.setMockInitialValues({
      'dropsync_custom_download_path': tempDir.path,
    });

    storageService = StorageService();
    await storageService.init();

    historyRepository = HistoryRepository();
    await historyRepository.init();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Internet Transfer E2EE & Room Code Tests', () {
    test('generateRoomCode produces valid XXX-XXX format', () {
      final code = InternetTransferService.generateRoomCode();
      expect(code, matches(r'^\d{3}-\d{3}$'));
    });

    test('E2EE AES-256-GCM encrypts and decrypts payload correctly', () async {
      final service = InternetTransferService(
        storageService: storageService,
        historyRepository: historyRepository,
      );

      const roomCode = '555-888';
      await service.createSenderRoom(roomCode);

      const secretMessage = 'DropSync Zero-Knowledge End-to-End Encryption Over The Internet!';
      final plainBytes = utf8.encode(secretMessage);

      // Encrypt
      final encryptedBytes = await service.testEncryptBytes(plainBytes);
      expect(encryptedBytes, isNot(equals(plainBytes)));
      // Wire format should include 12-byte nonce + 16-byte MAC tag + ciphertext
      expect(encryptedBytes.length, greaterThan(28 + plainBytes.length - 1));

      // Decrypt
      final decryptedBytes = await service.testDecryptBytes(encryptedBytes);
      final decryptedMessage = utf8.decode(decryptedBytes);
      expect(decryptedMessage, equals(secretMessage));
    });

    test('E2EE throws on tampered ciphertext (authenticated AES-256-GCM)', () async {
      final service = InternetTransferService(
        storageService: storageService,
        historyRepository: historyRepository,
      );

      await service.createSenderRoom('123-456');
      final plainBytes = utf8.encode('Top Secret Financial Transfer');

      final encryptedBytes = await service.testEncryptBytes(plainBytes);

      // Tamper with the ciphertext byte
      final tamperedBytes = List<int>.from(encryptedBytes);
      tamperedBytes[tamperedBytes.length - 1] ^= 0xFF;

      expect(
        () async => await service.testDecryptBytes(Uint8List.fromList(tamperedBytes)),
        throwsA(anything),
      );
    });
  });

  group('Mutual Real-Time Presence Guard Tests', () {
    test('Sender creating room enters waitingForPeer state', () async {
      final senderService = InternetTransferService(
        storageService: storageService,
        historyRepository: historyRepository,
      );

      final code = await senderService.createSenderRoom('999-111');
      expect(code, equals('999-111'));
      expect(senderService.isSender, isTrue);
      expect(senderService.presenceState, equals(InternetPeerPresence.waitingForPeer));
      expect(senderService.areBothPresent, isFalse);

      senderService.dispose();
    });

    test('Receiver joining room triggers mutual presence (bothPresent)', () async {
      final senderService = InternetTransferService(
        storageService: storageService,
        historyRepository: historyRepository,
      );
      final receiverService = InternetTransferService(
        storageService: storageService,
        historyRepository: historyRepository,
      );

      const code = '777-222';
      await senderService.createSenderRoom(code);

      final joined = await receiverService.joinReceiverRoom(code);
      expect(joined, isTrue);
      expect(receiverService.isSender, isFalse);

      // Receiver immediately detects sender in room
      expect(receiverService.presenceState, equals(InternetPeerPresence.bothPresent));
      expect(receiverService.areBothPresent, isTrue);

      senderService.dispose();
      receiverService.dispose();
    });

    test('Local user navigating away pauses presence immediately', () async {
      final service = InternetTransferService(
        storageService: storageService,
        historyRepository: historyRepository,
      );

      await service.createSenderRoom('444-333');

      // User navigates away from page
      service.setLocalPagePresence(false);
      expect(service.presenceState, equals(InternetPeerPresence.disconnected));
      expect(service.areBothPresent, isFalse);

      // User returns to page
      service.setLocalPagePresence(true);
      expect(service.areBothPresent, isFalse); // still waiting for receiver

      service.dispose();
    });

    test('Full End-to-End file send and receive over in-memory relay', () async {
      final senderService = InternetTransferService(
        storageService: storageService,
        historyRepository: historyRepository,
      );
      final receiverService = InternetTransferService(
        storageService: storageService,
        historyRepository: historyRepository,
      );

      const code = '888-333';
      await senderService.createSenderRoom(code);
      await receiverService.joinReceiverRoom(code);

      // Create a test file of 200 KB (triggers multi-chunk buffering)
      final testFile = File('${tempDir.path}/test_upload.bin');
      final fileData = List<int>.generate(200 * 1024, (i) => i % 256);
      await testFile.writeAsBytes(fileData);

      // Start receiver in background
      final receiveFuture = receiverService.startReceiverListening();

      // Send file
      final sentSession = await senderService.sendFile(file: testFile);
      expect(sentSession.status, equals(TransferStatus.completed));
      expect(sentSession.bytesTransferred, equals(200 * 1024));

      // Await received file
      final receivedFile = await receiveFuture;
      expect(receivedFile, isNotNull);
      expect(receivedFile!.existsSync(), isTrue);

      final receivedBytes = await receivedFile.readAsBytes();
      expect(receivedBytes.length, equals(200 * 1024));
      expect(receivedBytes, equals(fileData));

      senderService.dispose();
      receiverService.dispose();
    });
  });

  group('InternetTransferView Widget Tests', () {
    testWidgets('InternetTransferView renders Send/Receive modes and Room Code', (tester) async {
      final service = InternetTransferService(
        storageService: storageService,
        historyRepository: historyRepository,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InternetTransferView(
              internetService: service,
              storageService: storageService,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Check header and encryption badge
      expect(find.text('Internet Transfer (E2EE)'), findsOneWidget);
      expect(find.textContaining('256-BIT AES-GCM'), findsOneWidget);

      // Check mode toggle buttons
      expect(find.text('Send via Internet'), findsOneWidget);
      expect(find.text('Receive via Internet'), findsOneWidget);

      // Check mutual presence banner exists
      expect(find.textContaining('WAITING FOR PEER TO OPEN THIS PAGE'), findsOneWidget);

      service.dispose();
    });
  });
}
