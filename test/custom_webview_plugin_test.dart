import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:custom_webview_plugin/custom_webview_plugin.dart';
import 'package:custom_webview_plugin/custom_webview_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CustomWebViewPlugin global actions', () {
    final List<MethodCall> log = <MethodCall>[];

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('custom_webview_flutter'),
        (MethodCall methodCall) async {
          log.add(methodCall);
          return null;
        },
      );
    });

    tearDown(() {
      log.clear();
    });

    test('resetCache invokes method correctly', () async {
      await CustomWebViewPlugin.resetCache();
      expect(log, hasLength(1));
      expect(log.first.method, 'resetCache');
    });

    test('resetCache rethrows PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('custom_webview_flutter'),
        (MethodCall methodCall) async {
          throw PlatformException(code: 'error', message: 'failed');
        },
      );
      
      expect(() => CustomWebViewPlugin.resetCache(), throwsA(isA<PlatformException>()));
    });
  });

  group('CustomWebViewWidget', () {
    testWidgets('renders without error on Android', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final controller = CustomWebViewController();
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomWebViewWidget(
              controller: controller,
              initialUrl: 'https://example.com',
            ),
          ),
        ),
      );

      expect(find.byType(CustomWebViewWidget), findsOneWidget);
      expect(find.byType(PlatformViewLink), findsOneWidget);
      
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('renders without error on iOS', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final controller = CustomWebViewController();
      
      await tester.pumpWidget(
        MaterialApp( home: Scaffold(
            body: CustomWebViewWidget(
              controller: controller,
              initialUrl: 'https://example.com',
            ),
          ),
        ),
      );

      expect(find.byType(CustomWebViewWidget), findsOneWidget);
      expect(find.byType(UiKitView), findsOneWidget);
      
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('renders fallback on unsupported platform', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
      final controller = CustomWebViewController();
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomWebViewWidget(
              controller: controller,
            ),
          ),
        ),
      );

      expect(find.textContaining('is not yet supported'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
