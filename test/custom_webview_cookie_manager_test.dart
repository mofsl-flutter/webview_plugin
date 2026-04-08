import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:custom_webview_plugin/custom_webview_cookie_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CustomWebViewCookieManager', () {
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

    test('clearCookies invokes method correctly', () async {
      await CustomWebViewCookieManager.clearCookies();
      expect(log, hasLength(1));
      expect(log.first.method, 'clearCookies');
    });
  });
}
