import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:custom_webview_plugin/custom_webview_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CustomWebViewController', () {
    late CustomWebViewController controller;
    final List<MethodCall> log = <MethodCall>[];

    setUp(() {
      controller = CustomWebViewController();
      controller.setViewId(0); // Initialize channel
      
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('custom_webview_flutter_0'),
        (MethodCall methodCall) async {
          log.add(methodCall);
          switch (methodCall.method) {
            case 'getCurrentUrl':
              return 'https://flutter.dev';
            case 'runJavaScript':
              return 'result';
            default:
              return null;
          }
        },
      );
    });

    tearDown(() {
      log.clear();
    });

    test('loadUrl invokes correctly', () async {
      await controller.loadUrl(
        'https://example.com',
        headers: {'Authorization': 'Bearer token'},
        javaScriptChannelNames: ['TestChannel'],
        isChart: false,
        zoomEnabled: true,
        enableMultipleWindows: true,
      );

      expect(log, hasLength(1));
      expect(log.first.method, 'loadUrl');
      expect(log.first.arguments['initialUrl'], 'https://example.com');
      expect(log.first.arguments['headers'], {'Authorization': 'Bearer token'});
      expect(log.first.arguments['javaScriptChannelNames'], ['TestChannel']);
      expect(log.first.arguments['isChart'], false);
      expect(log.first.arguments['zoomEnabled'], true);
      expect(log.first.arguments['enableMultipleWindows'], true);
    });

    test('loadHtmlData invokes correctly', () async {
      await controller.loadHtmlData(
        '<html><body>Hello</body></html>',
        baseURL: 'https://example.com',
        javaScriptChannelNames: ['TestChannel'],
        allowMixedContent: true,
      );

      expect(log, hasLength(1));
      expect(log.first.method, 'loadHtmlData');
      expect(log.first.arguments['htmlString'], '<html><body>Hello</body></html>');
      expect(log.first.arguments['baseURL'], 'https://example.com');
      expect(log.first.arguments['javaScriptChannelNames'], ['TestChannel']);
      expect(log.first.arguments['allowMixedContent'], true);
    });

    test('reloadUrl invokes correctly', () async {
      await controller.reloadUrl();
      expect(log, hasLength(1));
      expect(log.first.method, 'reloadUrl');
    });

    test('runJavaScript invokes correctly and returns result', () async {
      final result = await controller.runJavaScript('console.log("test");');
      expect(log, hasLength(1));
      expect(log.first.method, 'runJavaScript');
      expect(log.first.arguments['script'], 'console.log("test");');
      expect(result, 'result');
    });

    test('addJavascriptChannel invokes correctly', () async {
      await controller.addJavascriptChannel('NewChannel');
      expect(log, hasLength(1));
      expect(log.first.method, 'addJavascriptChannel');
      expect(log.first.arguments['channelName'], 'NewChannel');
    });

    test('getCurrentUrl invokes correctly and returns URL', () async {
      final result = await controller.getCurrentUrl();
      expect(log, hasLength(1));
      expect(log.first.method, 'getCurrentUrl');
      expect(result, 'https://flutter.dev');
    });

    test('setUserInteractionEnabled invokes correctly', () async {
      await controller.setUserInteractionEnabled(false);
      expect(log, hasLength(1));
      expect(log.first.method, 'setUserInteractionEnabled');
      expect(log.first.arguments['enabled'], false);
    });

    test('setCustomUserAgent invokes correctly', () async {
      await controller.setCustomUserAgent('CustomUA');
      expect(log, hasLength(1));
      expect(log.first.method, 'setCustomUserAgent');
      expect(log.first.arguments['userAgent'], 'CustomUA');
    });

    test('enableMultipleWindows invokes correctly', () async {
      await controller.enableMultipleWindows(true);
      expect(log, hasLength(1));
      expect(log.first.method, 'enableMultipleWindows');
      expect(log.first.arguments['enabled'], true);
    });

    test('setBackgroundColor invokes correctly', () async {
      await controller.setBackgroundColor(0x00000000);
      expect(log, hasLength(1));
      expect(log.first.method, 'setBackgroundColor');
      expect(log.first.arguments['color'], 0x00000000);
    });
    
    test('Native callbacks are routed correctly', () async {
      bool onPageStartedCalled = false;
      bool onPageFinishedCalled = false;
      int? progressValue;
      String? errorValue;
      String? alertUrl;
      String? alertMessage;
      String? jsChannelName;
      String? jsMessage;

      controller.onPageStarted = (url) => onPageStartedCalled = true;
      controller.onPageFinished = (url) => onPageFinishedCalled = true;
      controller.onProgress = (progress) => progressValue = progress;
      controller.onWebResourceError = (error) => errorValue = error;
      controller.onJsAlert = (url, message) {
        alertUrl = url;
        alertMessage = message;
      };
      controller.onJavascriptChannelMessageReceived = (channel, message) {
        jsChannelName = channel;
        jsMessage = message;
      };

      final binding = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const codec = StandardMethodCodec();

      await binding.handlePlatformMessage(
        'custom_webview_flutter_0',
        codec.encodeMethodCall(const MethodCall('onPageStarted', {'url': 'https://example.com'})),
        (ByteData? data) {},
      );
      expect(onPageStartedCalled, true);

      await binding.handlePlatformMessage(
        'custom_webview_flutter_0',
        codec.encodeMethodCall(const MethodCall('onPageFinished', {'url': 'https://example.com'})),
        (ByteData? data) {},
      );
      expect(onPageFinishedCalled, true);

      await binding.handlePlatformMessage(
        'custom_webview_flutter_0',
        codec.encodeMethodCall(const MethodCall('onProgress', {'progress': 50})),
        (ByteData? data) {},
      );
      expect(progressValue, 50);

      await binding.handlePlatformMessage(
        'custom_webview_flutter_0',
        codec.encodeMethodCall(const MethodCall('onReceivedError', {'message': 'error'})),
        (ByteData? data) {},
      );
      expect(errorValue, 'error');

      await binding.handlePlatformMessage(
        'custom_webview_flutter_0',
        codec.encodeMethodCall(const MethodCall('onJsAlert', {'url': 'url', 'message': 'alert'})),
        (ByteData? data) {},
      );
      expect(alertUrl, 'url');
      expect(alertMessage, 'alert');

      await binding.handlePlatformMessage(
        'custom_webview_flutter_0',
        codec.encodeMethodCall(const MethodCall('onJavascriptChannelMessageReceived', {'channelName': 'channel', 'message': 'msg'})),
        (ByteData? data) {},
      );
      expect(jsChannelName, 'channel');
      expect(jsMessage, 'msg');
    });

    test('onNavigationRequest returns correct value', () async {
      controller.onNavigationRequest = (url) {
        return url == 'https://allow.com';
      };

      final binding = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const codec = StandardMethodCodec();

      bool? resultAllow;
      await binding.handlePlatformMessage(
        'custom_webview_flutter_0',
        codec.encodeMethodCall(const MethodCall('onNavigationRequest', {'url': 'https://allow.com'})),
        (ByteData? data) {
          resultAllow = codec.decodeEnvelope(data!) as bool;
        },
      );
      expect(resultAllow, true);

      bool? resultBlock;
      await binding.handlePlatformMessage(
        'custom_webview_flutter_0',
        codec.encodeMethodCall(const MethodCall('onNavigationRequest', {'url': 'https://block.com'})),
        (ByteData? data) {
          resultBlock = codec.decodeEnvelope(data!) as bool;
        },
      );
      expect(resultBlock, false);
    });
  });
}
