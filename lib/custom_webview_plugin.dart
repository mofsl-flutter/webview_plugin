import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CustomWebViewPlugin {
  static const MethodChannel _channel = MethodChannel('custom_webview_flutter');
  static const EventChannel _eventChannel = EventChannel('custom_webview_plugin_events');

  // Method to open the WebView in iOS

  // Stream<String>? _onPageLoadedStream;

  static Stream<String>? _onMessageReceivedStream;

  Stream<String> get onMessageReceived => _onMessageReceivedStream!;

  static Future<void> openWebView(final String url,
      {final String? javascriptChannelName,
      final bool? isChart,
      final bool? isZoomEnabled,
      final bool? enableMultipleWindows}) async {
    try {
      await _channel.invokeMethod<void>('loadUrl', <String, dynamic>{
        'initialUrl': url,
        'javaScriptChannelName': javascriptChannelName,
        'isChart': isChart,
        'zoomEnabled': isZoomEnabled,
        'enableMultipleWindows': enableMultipleWindows,
      });
    } on PlatformException catch (e) {
      debugPrint("Failed to open WebView: '${e.message}'.");
    }
  }

  static Future<void> loadHtmlData(
    final String htmlString, {
    final String? baseURL,
    final String? javaScriptChannelName,
  }) async {
    try {
      await _channel.invokeMethod<void>('loadHtmlData', <String, dynamic>{
        'htmlString': htmlString,
        'baseURL': baseURL,
        "javaScriptChannelName": javaScriptChannelName,
      });
    } on Exception catch (e) {
      debugPrint("Failed to load HTML data: $e");
    }
  }

  static Future<void> addJavascriptChannel(final String channelName) async {
    try {
      debugPrint("addJavascriptChannel  $channelName");
      await _channel.invokeMethod<void>('addJavascriptChannel', <String, dynamic>{'channelName': channelName});
    } on PlatformException catch (e) {
      debugPrint("Failed to add JavaScript channel: ${e.message}");
      rethrow;
    }
  }

  /// Reloads the current URL.
  static Future<void> reloadUrl() async {
    try {
      await _channel.invokeMethod<void>('reloadUrl');
    } on PlatformException catch (e) {
      debugPrint("Failed to reload URL: ${e.message}");
      rethrow;
    }
  }

  /// Resets the web view's cache.
  static Future<void> resetCache() async {
    try {
      await _channel.invokeMethod<void>('resetCache');
    } on PlatformException catch (e) {
      debugPrint("Failed to reset cache: ${e.message}");
      rethrow;
    }
  }

  // Method to authenticate the webviewSession in iOS

  static Future<void> runJavaScript(final String script) async {
    try {
      await _channel.invokeMethod<void>('runJavaScript', <String, dynamic>{'script': script});
    } on PlatformException catch (e) {
      debugPrint("Failed to run JavaScript: '${e.message}'.");
    }
  }

  static Future<void> enableMultipleWindows() async {
    try {
      await _channel.invokeMethod<void>('enableMultipleWindows');
    } on PlatformException catch (e) {
      debugPrint("Failed to renableMultipleWindows: '${e.message}'.");
    }
  }

  // Stream<String> get onPageLoaded {
  //   _onPageLoadedStream ??=
  //       _eventChannel.receiveBroadcastStream().map<String>((event) => event as String);
  //   return _onPageLoadedStream!;
  // }

  static Future<String> getCurrentLoadedUrl() async {
    try {
      return await _channel.invokeMethod('getCurrentUrl');
    } on PlatformException catch (e) {
      debugPrint("Failed to get current URL: '${e.message}'.");
      rethrow;
    }
  }

  static void getJavaScriptChannelStream(final Function(dynamic) callback) {
    _eventChannel.receiveBroadcastStream().listen((final dynamic event) {
      callback(event);
    });
  }

  static void setWebViewLoadedCallback(final Function(dynamic) callback) {
    _eventChannel.receiveBroadcastStream().listen((final dynamic event) {
      debugPrint('$event');
      callback(event);
    });
  }

  static Future<void> setUserInteractionEnabled(final bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setUserInteractionEnabled', <String, dynamic>{'enabled': enabled});
      debugPrint("Called setUserInteractionEnabled: $enabled");
    } on PlatformException catch (e) {
      debugPrint("Failed to set user interaction: '${e.message}'.");
    }
  }
}
