import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dropsync/widgets/dropsync_logo.dart';

void main() {
  group('DropSyncLogo Branding & Widget Tests', () {
    testWidgets('DropSyncLogo renders mark, gradient, and wordmark correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: DropSyncLogo(
                size: 140,
                showText: true,
                showGlow: true,
              ),
            ),
          ),
        ),
      );

      // Verify wordmark is present
      expect(find.text('DROPSYNC'), findsOneWidget);
      expect(find.text('HIGH-SPEED P2P SYNC'), findsOneWidget);

      // Verify custom painter is present
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('DropSyncLogo without text renders compact mark', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: DropSyncLogo(
                size: 48,
                showText: false,
                showGlow: false,
              ),
            ),
          ),
        ),
      );

      expect(find.text('DROPSYNC'), findsNothing);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('DropSyncLogo.splash factory initializes animated state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: DropSyncLogo.splash(size: 160),
            ),
          ),
        ),
      );

      expect(find.text('DROPSYNC'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('DropSyncLogo renders Image.asset when assetPath is provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: DropSyncLogo(
                size: 64,
                assetPath: 'assets/icon/icon.png',
                showText: false,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Image), findsOneWidget);
      expect(
        find.byWidgetPredicate((widget) =>
            widget is CustomPaint &&
            widget.painter.runtimeType.toString() == '_DropSyncMarkPainter'),
        findsNothing,
      );
    });
  });
}
