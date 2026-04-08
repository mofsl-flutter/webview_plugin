import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:custom_webview_plugin/custom_webview_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CustomWebViewController JS Handler Extended Tests', () {
    late CustomWebViewController controller;

    setUp(() {
      controller = CustomWebViewController();
      controller.setViewId(0);
      
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('custom_webview_flutter_0'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'addJavascriptChannel') {
            return null;
          }
          return null;
        },
      );
    });

    test('onJavascriptChannelMessageReceived distinguishes between multiple channels', () async {
      String? lastChannel;
      String? lastMessage;

      controller.onJavascriptChannelMessageReceived = (channel, message) {
        lastChannel = channel;
        lastMessage = message;
      };

      final binding = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const codec = StandardMethodCodec();

      // Simulate message from Channel A
      await binding.handlePlatformMessage(
        'custom_webview_flutter_0',
        codec.encodeMethodCall(const MethodCall('onJavascriptChannelMessageReceived', {
          'channelName': 'ChannelA',
          'message': 'Hello from A'
        })),
        (ByteData? data) {},
      );
      expect(lastChannel, 'ChannelA');
      expect(lastMessage, 'Hello from A');

      // Simulate message from Channel B
      await binding.handlePlatformMessage(
        'custom_webview_flutter_0',
        codec.encodeMethodCall(const MethodCall('onJavascriptChannelMessageReceived', {
          'channelName': 'ChannelB',
          'message': 'Hello from B'
        })),
        (ByteData? data) {},
      );
      expect(lastChannel, 'ChannelB');
      expect(lastMessage, 'Hello from B');
    });

    test('Specific channel callbacks work correctly', () async {
      String? authMessage;
      String? chartMessage;

      await controller.addJavascriptChannel('Auth', onMessageReceived: (msg) => authMessage = msg);
      await controller.addJavascriptChannel('Chart', onMessageReceived: (msg) => chartMessage = msg);

      final binding = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const codec = StandardMethodCodec();

      // Send to Auth
      await binding.handlePlatformMessage(
        'custom_webview_flutter_0',
        codec.encodeMethodCall(const MethodCall('onJavascriptChannelMessageReceived', {
          'channelName': 'Auth',
          'message': 'token123'
        })),
        (ByteData? data) {},
      );
      expect(authMessage, 'token123');
      expect(chartMessage, isNull);

      // Send to Chart
      await binding.handlePlatformMessage(
        'custom_webview_flutter_0',
        codec.encodeMethodCall(const MethodCall('onJavascriptChannelMessageReceived', {
          'channelName': 'Chart',
          'message': 'renderDone'
        })),
        (ByteData? data) {},
      );
      expect(chartMessage, 'renderDone');
    });

    test('runJavaScript handles null results correctly (Android style)', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('custom_webview_flutter_0'),
        (MethodCall methodCall) async => null,
      );

      final result = await controller.runJavaScript('test();');
      expect(result, isNull);
    });
  });
}
