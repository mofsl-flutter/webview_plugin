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
            case 'canGoBack':
              return true;
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

    test('loadUrl rethrows PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('custom_webview_flutter_0'),
        (MethodCall methodCall) async {
          throw PlatformException(code: 'error', message: 'failed');
        },
      );
      expect(() => controller.loadUrl('url'), throwsA(isA<PlatformException>()));
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

    test('loadHtmlData rethrows PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('custom_webview_flutter_0'),
        (MethodCall methodCall) async {
          throw PlatformException(code: 'error', message: 'failed');
        },
      );
      expect(() => controller.loadHtmlData('html'), throwsA(isA<PlatformException>()));
    });

    test('reloadUrl invokes correctly', () async {
      await controller.reloadUrl();
      expect(log, hasLength(1));
      expect(log.first.method, 'reloadUrl');
    });

    test('reloadUrl rethrows PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('custom_webview_flutter_0'),
        (MethodCall methodCall) async {
          throw PlatformException(code: 'error', message: 'failed');
        },
      );
      expect(() => controller.reloadUrl(), throwsA(isA<PlatformException>()));
    });

    test('runJavaScript invokes correctly and returns result', () async {
      final result = await controller.runJavaScript('console.log("test");');
      expect(log, hasLength(1));
      expect(log.first.method, 'runJavaScript');
      expect(log.first.arguments['script'], 'console.log("test");');
      expect(result, 'result');
    });

    test('runJavaScript rethrows PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('custom_webview_flutter_0'),
        (MethodCall methodCall) async {
          throw PlatformException(code: 'error', message: 'failed');
        },
      );
      expect(() => controller.runJavaScript('script'), throwsA(isA<PlatformException>()));
    });

    test('addJavascriptChannel invokes correctly', () async {
      await controller.addJavascriptChannel('NewChannel');
      expect(log, hasLength(1));
      expect(log.first.method, 'addJavascriptChannel');
      expect(log.first.arguments['channelName'], 'NewChannel');
    });

    test('addJavascriptChannel rethrows PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('custom_webview_flutter_0'),
        (MethodCall methodCall) async {
          throw PlatformException(code: 'error', message: 'failed');
        },
      );
      expect(() => controller.addJavascriptChannel('name'), throwsA(isA<PlatformException>()));
    });

    test('getCurrentUrl invokes correctly and returns URL', () async {
      final result = await controller.getCurrentUrl();
      expect(log, hasLength(1));
      expect(log.first.method, 'getCurrentUrl');
      expect(result, 'https://flutter.dev');
    });

    test('getCurrentUrl rethrows PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('custom_webview_flutter_0'),
        (MethodCall methodCall) async {
          throw PlatformException(code: 'error', message: 'failed');
        },
      );
      expect(() => controller.getCurrentUrl(), throwsA(isA<PlatformException>()));
    });

    test('setUserInteractionEnabled invokes correctly', () async {
      await controller.setUserInteractionEnabled(false);
      expect(log, hasLength(1));
      expect(log.first.method, 'setUserInteractionEnabled');
      expect(log.first.arguments['enabled'], false);
    });

    test('setUserInteractionEnabled rethrows PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('custom_webview_flutter_0'),
        (MethodCall methodCall) async {
          throw PlatformException(code: 'error', message: 'failed');
        },
      );
      expect(() => controller.setUserInteractionEnabled(true), throwsA(isA<PlatformException>()));
    });

    test('setCustomUserAgent invokes correctly', () async {
      await controller.setCustomUserAgent('CustomUA');
      expect(log, hasLength(1));
      expect(log.first.method, 'setCustomUserAgent');
      expect(log.first.arguments['userAgent'], 'CustomUA');
    });

    test('setCustomUserAgent rethrows PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('custom_webview_flutter_0'),
        (MethodCall methodCall) async {
          throw PlatformException(code: 'error', message: 'failed');
        },
      );
      expect(() => controller.setCustomUserAgent('ua'), throwsA(isA<PlatformException>()));
    });

    test('enableMultipleWindows invokes correctly', () async {
      await controller.enableMultipleWindows(true);
      expect(log, hasLength(1));
      expect(log.first.method, 'enableMultipleWindows');
      expect(log.first.arguments['enabled'], true);
    });

    test('enableMultipleWindows rethrows PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('custom_webview_flutter_0'),
        (MethodCall methodCall) async {
          throw PlatformException(code: 'error', message: 'failed');
        },
      );
      expect(() => controller.enableMultipleWindows(true), throwsA(isA<PlatformException>()));
    });

    test('setBackgroundColor invokes correctly', () async {
      await controller.setBackgroundColor(0x00000000);
      expect(log, hasLength(1));
      expect(log.first.method, 'setBackgroundColor');
      expect(log.first.arguments['color'], 0x00000000);
    });

    test('setBackgroundColor rethrows PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('custom_webview_flutter_0'),
        (MethodCall methodCall) async {
          throw PlatformException(code: 'error', message: 'failed');
        },
      );
      expect(() => controller.setBackgroundColor(0), throwsA(isA<PlatformException>()));
    });

    test('canGoBack returns correctly', () async {
      final result = await controller.canGoBack();
      expect(log, hasLength(1));
      expect(log.first.method, 'canGoBack');
      expect(result, true);
    });

    test('canGoBack returns false on PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('custom_webview_flutter_0'),
        (MethodCall methodCall) async {
          throw PlatformException(code: 'error', message: 'failed');
        },
      );
      final result = await controller.canGoBack();
      expect(result, false);
    });

    test('goBack invokes correctly', () async {
      await controller.goBack();
      expect(log, hasLength(1));
      expect(log.first.method, 'goBack');
    });

    test('goBack rethrows PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('custom_webview_flutter_0'),
        (MethodCall methodCall) async {
          throw PlatformException(code: 'error', message: 'failed');
        },
      );
      expect(() => controller.goBack(), throwsA(isA<PlatformException>()));
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
      String? titleValue;

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
      controller.onTitleChanged = (title) => titleValue = title;

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
        codec.encodeMethodCall(const MethodCall('onJavascriptChannelMessageReceived', {'channelName': 'channel', 'message': 'msg'})),
        (ByteData? data) {},
      );
      expect(jsChannelName, 'channel');
      expect(jsMessage, 'msg');

      await binding.handlePlatformMessage(
        'custom_webview_flutter_0',
        codec.encodeMethodCall(const MethodCall('onTitleChanged', {'title': 'New Title'})),
        (ByteData? data) {},
      );
      expect(titleValue, 'New Title');

      await binding.handlePlatformMessage(
        'custom_webview_flutter_0',
        codec.encodeMethodCall(const MethodCall('onMessageReceived', 'generic')),
        (ByteData? data) {},
      );
      // Currently onMessageReceived just logs or does nothing in controller, 
      // but testing it triggers the handler without error.
    });

    test('pageLoaded triggers onPageFinished', () async {
      bool called = false;
      controller.onPageFinished = (url) => called = true;

      final binding = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const codec = StandardMethodCodec();

      await binding.handlePlatformMessage(
        'custom_webview_flutter_0',
        codec.encodeMethodCall(const MethodCall('pageLoaded', {'url': 'https://example.com'})),
        (ByteData? data) {},
      );
      expect(called, true);
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

    test('onNavigationRequest returns true by default when no callback set', () async {
      controller.onNavigationRequest = null;

      final binding = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const codec = StandardMethodCodec();

      bool? result;
      await binding.handlePlatformMessage(
        'custom_webview_flutter_0',
        codec.encodeMethodCall(const MethodCall('onNavigationRequest', {'url': 'https://any.com'})),
        (ByteData? data) {
          result = codec.decodeEnvelope(data!) as bool;
        },
      );
      expect(result, true);
    });

    test('Unhandled method calls handle gracefully', () async {
      final binding = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const codec = StandardMethodCodec();

      await binding.handlePlatformMessage(
        'custom_webview_flutter_0',
        codec.encodeMethodCall(const MethodCall('unhandled', {})),
        (ByteData? data) {},
      );
      // Should not throw
    });
  });
}
