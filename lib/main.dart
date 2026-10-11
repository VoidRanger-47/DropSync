import 'package:flutter/material.dart';
import 'services/clipboard_service.dart';
import 'services/history_repository.dart';
import 'services/hotspot_service.dart';
import 'services/internet_transfer_service.dart';
import 'services/network_service.dart';
import 'services/storage_service.dart';
import 'theme/gemini_theme.dart';
import 'views/landing_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize persistent storage & preferences
  final storageService = StorageService();
  await storageService.init();

  // 2. Initialize persistent transfer history repository
  final historyRepository = HistoryRepository();
  await historyRepository.init();

  // 3. Initialize Wi-Fi Hotspot configuration & credentials
  final hotspotService = HotspotService();
  await hotspotService.loadSettings();

  // 4. Initialize background networking & listening socket
  final networkService = NetworkService(
    storageService: storageService,
    historyRepository: historyRepository,
  );
  await networkService.start();

  // 5. Initialize bidirectional clipboard sync
  final clipboardService = ClipboardService(networkService: networkService);
  clipboardService.start();

  // 6. Initialize Internet End-to-End Encrypted Transfer Service
  final internetTransferService = InternetTransferService(
    storageService: storageService,
    historyRepository: historyRepository,
  );

  runApp(DropSyncApp(
    networkService: networkService,
    clipboardService: clipboardService,
    storageService: storageService,
    historyRepository: historyRepository,
    hotspotService: hotspotService,
    internetTransferService: internetTransferService,
  ));
}

class DropSyncApp extends StatelessWidget {
  final NetworkService networkService;
  final ClipboardService clipboardService;
  final StorageService storageService;
  final HistoryRepository historyRepository;
  final HotspotService hotspotService;
  final InternetTransferService internetTransferService;

  const DropSyncApp({
    super.key,
    required this.networkService,
    required this.clipboardService,
    required this.storageService,
    required this.historyRepository,
    required this.hotspotService,
    required this.internetTransferService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DropSync',
      debugShowCheckedModeBanner: false,
      theme: GeminiTheme.darkTheme,
      home: LandingView(
        networkService: networkService,
        clipboardService: clipboardService,
        storageService: storageService,
        historyRepository: historyRepository,
        hotspotService: hotspotService,
        internetTransferService: internetTransferService,
      ),
    );
  }
}
