// Contract gaps in CustomWebViewController, pinned so a fix is visible as these tests flipping.
//
// Each test documents a mismatch between what the Dart layer offers and what the native layers
// actually do. They are written to PASS while the gap exists, so a green run here means "still
// as described", not "healthy" — the expectation text says which way round each one is.
import 'dart:async';

import 'package:custom_webview_plugin/custom_webview_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const StandardMethodCodec codec = StandardMethodCodec();

  /// Installs a permissive mock for the per-view channel, so calls do not throw
  /// MissingPluginException. Note the controller does not catch that exception itself, which is
  /// its own gap: on a platform where the plugin is not registered, every call throws rather
  /// than degrading.
  void mockView(int viewId) {
    messenger.setMockMethodCallHandler(
      MethodChannel('custom_webview_flutter_$viewId'),
      (MethodCall call) async => null,
    );
  }

  /// Delivers [method] to the controller bound to [viewId], the way native does.
  Future<void> sendFromNative(int viewId, String method, [Object? args]) {
    return messenger.handlePlatformMessage(
      'custom_webview_flutter_$viewId',
      codec.encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }

  /// Delivers [method] and returns the value the controller replied with.
  ///
  /// Unlike [sendFromNative] this keeps the reply, because for navigation the reply *is* the
  /// behaviour: native reads it to decide whether to veto.
  Future<Object?> askFromNative(int viewId, String method, [Object? args]) {
    final Completer<Object?> reply = Completer<Object?>();
    messenger.handlePlatformMessage(
      'custom_webview_flutter_$viewId',
      codec.encodeMethodCall(MethodCall(method, args)),
      (ByteData? data) =>
          reply.complete(data == null ? null : codec.decodeEnvelope(data)),
    );
    return reply.future;
  }

  group('dropped and dead callbacks', () {
    test('onMessageReceived is emitted by native but has no handler', () async {
      mockView(10);
      final CustomWebViewController controller = CustomWebViewController()..setViewId(10);

      String? viaChannelCallback;
      String? viaGenericCallback;
      controller.onJavascriptChannelMessageReceived = (String c, String m) {
        viaGenericCallback = '$c/$m';
      };
      await controller.addJavascriptChannel('Bridge',
          onMessageReceived: (String m) => viaChannelCallback = m);

      // Exactly what CustomWebViewFactory.onMessageReceived sends: a bare String, not a map.
      await sendFromNative(10, 'onMessageReceived', 'hello from the page');

      expect(viaChannelCallback, isNull,
          reason: 'no per-channel callback can fire — the controller has no case for this method');
      expect(viaGenericCallback, isNull,
          reason: 'nor the generic one; the message is dropped in the default branch');
    });

    test('the documented JS-channel path does deliver, so only the alias is broken', () async {
      mockView(11);
      final CustomWebViewController controller = CustomWebViewController()..setViewId(11);
      String? seen;
      await controller.addJavascriptChannel('Bridge',
          onMessageReceived: (String m) => seen = m);

      await sendFromNative(11, 'onJavascriptChannelMessageReceived',
          <String, Object?>{'channelName': 'Bridge', 'message': 'ok'});

      expect(seen, 'ok');
    });

    test('onTitleChanged is reachable in Dart but no platform emits it', () async {
      final CustomWebViewController controller = CustomWebViewController()..setViewId(12);
      String? title;
      controller.onTitleChanged = (String t) => title = t;

      // The handler works when something calls it...
      await sendFromNative(12, 'onTitleChanged', <String, Object?>{'title': 'T'});
      expect(title, 'T', reason: 'the Dart side is wired correctly');

      // ...but neither CustomWebViewFactory.kt nor CustomWebViewFactory.swift ever invokes
      // "onTitleChanged", so in a real app this callback is dead. Asserted by grep in review,
      // not reproducible here — this test exists to fail loudly if the Dart side regresses.
    });

    test('pageLoaded arrives with null arguments, so the url is lost', () async {
      final CustomWebViewController controller = CustomWebViewController()..setViewId(13);
      final List<String> urls = <String>[];
      controller.onPageFinished = urls.add;

      // Android: methodChannel.invokeMethod("pageLoaded", null)
      await sendFromNative(13, 'pageLoaded');
      // Android: methodChannel.invokeMethod("onPageFinished", mapOf("url" to url))
      await sendFromNative(13, 'onPageFinished', <String, Object?>{'url': 'https://a.test'});

      expect(urls, <String>['', 'https://a.test'],
          reason: 'both funnel into onPageFinished, but pageLoaded contributes an empty url, so '
              'a listener cannot tell which document finished');
    });
  });

  group('view binding', () {
    test('a controller binds once and cannot follow a new platform view', () async {
      final CustomWebViewController controller = CustomWebViewController()..setViewId(20);

      final List<MethodCall> onFirst = <MethodCall>[];
      final List<MethodCall> onSecond = <MethodCall>[];
      messenger.setMockMethodCallHandler(
        const MethodChannel('custom_webview_flutter_20'),
        (MethodCall c) async {
          onFirst.add(c);
          return null;
        },
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('custom_webview_flutter_21'),
        (MethodCall c) async {
          onSecond.add(c);
          return null;
        },
      );

      // A remount hands the same controller a new view id.
      controller.setViewId(21);
      await controller.reloadUrl();

      expect(onSecond, isEmpty,
          reason: 'setViewId early-returns once its Completer is done, so the new view is ignored');
      expect(onFirst, hasLength(1),
          reason: 'calls keep going to the destroyed first view for the rest of the '
              'controller lifetime');

      messenger.setMockMethodCallHandler(
          const MethodChannel('custom_webview_flutter_20'), null);
      messenger.setMockMethodCallHandler(
          const MethodChannel('custom_webview_flutter_21'), null);
    });

    test('every method hangs forever on a controller that never got a view', () async {
      final CustomWebViewController orphan = CustomWebViewController();

      bool reloadReturned = false;
      bool urlReturned = false;
      unawaited(orphan.reloadUrl().then((_) => reloadReturned = true));
      unawaited(orphan.getCurrentUrl().then((_) => urlReturned = true));

      // Give them far longer than any real platform round-trip.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(reloadReturned, isFalse);
      expect(urlReturned, isFalse,
          reason: 'each method starts with `await _idCompleter.future` and only setViewId '
              'completes it. If the platform view is never created — a widget disposed before '
              'onPlatformViewCreated, or an unsupported platform where the widget renders a '
              'Text — the future never settles and the caller cannot distinguish a hang from '
              'slow work. There is no timeout and no error.');
    });

    test('setViewId is idempotent for the same id, which is the one safe case', () async {
      final CustomWebViewController controller = CustomWebViewController()
        ..setViewId(30)
        ..setViewId(30);
      final List<MethodCall> calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(
        const MethodChannel('custom_webview_flutter_30'),
        (MethodCall c) async {
          calls.add(c);
          return null;
        },
      );

      await controller.reloadUrl();
      expect(calls, hasLength(1));

      messenger.setMockMethodCallHandler(
          const MethodChannel('custom_webview_flutter_30'), null);
    });
  });

  // Unlike every group above, these pin behaviour that is CORRECT and must stay that way.
  // Android allows a navigation immediately and applies a `false` verdict afterwards via
  // stopLoading(), so what Dart replies decides whether a page survives.
  group('navigation verdicts', () {
    test('no handler replies true, so an unset callback cannot block the page', () async {
      CustomWebViewController().setViewId(40);
      expect(
        await askFromNative(
            40, 'onNavigationRequest', <String, Object?>{'url': 'https://example.com/'}),
        isTrue,
        reason: 'Native treats only a definite false as a veto, but it must never be handed a '
            'reply that reads as one by accident. A consumer that sets no callback gets its '
            'pages loaded.',
      );
    });

    test('a false verdict is passed through unchanged, and true is not', () async {
      final CustomWebViewController controller = CustomWebViewController()..setViewId(41);
      final List<String> seen = <String>[];
      controller.onNavigationRequest = (String url) {
        seen.add(url);
        return !url.startsWith('https://blocked.example/');
      };

      expect(
          await askFromNative(41, 'onNavigationRequest',
              <String, Object?>{'url': 'https://blocked.example/x'}),
          isFalse);
      expect(
          await askFromNative(41, 'onNavigationRequest',
              <String, Object?>{'url': 'https://allowed.example/x'}),
          isTrue);
      expect(seen, hasLength(2));
    });

    test('an async handler delays the verdict, which is why it must not await', () async {
      final CustomWebViewController controller = CustomWebViewController()..setViewId(42);
      controller.onNavigationRequest = (String url) async {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        return false;
      };

      final Stopwatch sw = Stopwatch()..start();
      final Object? verdict = await askFromNative(
          42, 'onNavigationRequest', <String, Object?>{'url': 'https://slow.example/'});
      sw.stop();

      expect(verdict, isFalse);
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(100),
          reason: 'The verdict cannot reach native until the handler completes, and native has '
              'already allowed the navigation by then. This delay is time the WebView spends '
              'loading a page about to be stopped, which is why handlers must return '
              'synchronously rather than awaiting an external launch.');
    });
  });
}
