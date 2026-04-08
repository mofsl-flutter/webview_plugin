import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:custom_webview_plugin/custom_webview_plugin.dart';

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
  });
}
