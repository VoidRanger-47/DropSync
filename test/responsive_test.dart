import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dropsync/models/transfer_session.dart';
import 'package:dropsync/theme/responsive.dart';
import 'package:dropsync/theme/gemini_theme.dart';
import 'package:dropsync/widgets/pin_confirmation_dialog.dart';
import 'package:dropsync/widgets/transfer_progress_widget.dart';

void main() {
  group('Responsive Layout & Breakpoint Tests', () {
    testWidgets('ResponsiveContext detects compact screen correctly', (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      late bool isCompact;
      late bool isMobile;
      late double hPad;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              isCompact = context.isCompact;
              isMobile = context.isMobile;
              hPad = context.responsiveHorizontalPadding;
              return Container();
            },
          ),
        ),
      );

      expect(isCompact, isTrue);
      expect(isMobile, isTrue);
      expect(hPad, equals(12.0));
    });

    testWidgets('ResponsiveContext detects standard mobile correctly', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      late bool isCompact;
      late bool isMobile;
      late double hPad;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              isCompact = context.isCompact;
              isMobile = context.isMobile;
              hPad = context.responsiveHorizontalPadding;
              return Container();
            },
          ),
        ),
      );

      expect(isCompact, isFalse);
      expect(isMobile, isTrue);
      expect(hPad, equals(16.0));
    });

    testWidgets('ResponsiveContext detects landscape and tablet correctly', (tester) async {
      tester.view.physicalSize = const Size(768, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      late bool isTablet;
      late bool isDesktop;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              isTablet = context.isTablet;
              isDesktop = context.isDesktop;
              return Container();
            },
          ),
        ),
      );

      expect(isTablet, isTrue);
      expect(isDesktop, isFalse);
    });

    testWidgets('PinConfirmationDialog renders without overflow on 320px compact screen', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: GeminiTheme.darkTheme,
          home: const Scaffold(
            body: PinConfirmationDialog(
              pin: '4829',
              peerName: 'Google Pixel 8 Pro with Very Long Name',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('4829'), findsOneWidget);
      expect(find.text('Quick Share Pairing'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('PinConfirmationDialog renders in landscape without vertical overflow', (tester) async {
      tester.view.physicalSize = const Size(700, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: GeminiTheme.darkTheme,
          home: const Scaffold(
            body: PinConfirmationDialog(
              pin: '9012',
              peerName: 'Windows PC',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('9012'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('TransferProgressWidget renders on compact width without overflow', (tester) async {
      tester.view.physicalSize = const Size(300, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final session = TransferSession(
        id: 'test_session',
        fileName: 'a_very_long_file_name_that_should_truncate_properly.zip',
        fileSize: 2048 * 1024 * 1024,
        bytesTransferred: 1024 * 1024 * 1024,
        speedMBps: 45.0,
        progress: 0.5,
        etaSeconds: 22,
        isUpload: true,
        status: TransferStatus.transferring,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: GeminiTheme.darkTheme,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(8.0),
              child: TransferProgressWidget(session: session),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('50%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
