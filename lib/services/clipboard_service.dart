import 'dart:async';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/peer.dart';
import 'network_service.dart';

/// Provides clipboard synchronization with loopback suppression.
class ClipboardService {
  final NetworkService networkService;

  Timer? _pollingTimer;
  StreamSubscription? _remoteClipSub;
  String? _lastKnownLocalHash;
  String? _lastText;

  final _clipboardChangeController = StreamController<String>.broadcast();
  Stream<String> get clipboardChangeStream => _clipboardChangeController.stream;
  String? get currentText => _lastText;

  ClipboardService({required this.networkService});

  void start() {
    // 1. Listen for remote clipboard events arriving via NetworkService
    _remoteClipSub = networkService.clipboardReceivedStream.listen((text) async {
      final hash = _computeHash(text);
      _lastKnownLocalHash = hash;
      _lastText = text;
      await Clipboard.setData(ClipboardData(text: text));
      _clipboardChangeController.add(text);
    });

    // 2. Poll local clipboard every 800ms
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      _pollLocalClipboard();
    });
  }

  Future<void> _pollLocalClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text != null && text.isNotEmpty) {
        final hash = _computeHash(text);
        if (hash != _lastKnownLocalHash) {
          _lastKnownLocalHash = hash;
          _lastText = text;
          _clipboardChangeController.add(text);
        }
      }
    } catch (_) {
      // Background clipboard access may be restricted on some platforms
    }
  }

  /// Sends the current system clipboard content directly to a specific peer.
  Future<bool> sendCurrentClipboard(Peer peer) async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text != null && text.isNotEmpty) {
        await networkService.sendClipboard(peer: peer, text: text);
        return true;
      }
    } catch (_) {}
    return false;
  }

  static String _computeHash(String text) {
    return sha256.convert(utf8.encode(text)).toString();
  }

  void stop() {
    _pollingTimer?.cancel();
    _remoteClipSub?.cancel();
    _clipboardChangeController.close();
  }
}
