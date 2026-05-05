import "package:flutter/foundation.dart";
import "package:flutter/services.dart";

/// Plugin for controlling a native WebView.
class CustomWebViewPlugin {
  static const MethodChannel _channel = MethodChannel("custom_webview_flutter");
  static const EventChannel _eventChannel =
      EventChannel("custom_webview_plugin_events");

  // Method to open the WebView in iOS

  // Stream<String>? _onPageLoadedStream;

  // ignore: use_late_for_private_fields_and_variables, field is nullable until a channel is registered
  static Stream<String>? _onMessageReceivedStream;

  /// The stream of messages received from the JavaScript channel.
  Stream<String> get onMessageReceived => _onMessageReceivedStream!;

  /// Opens the WebView and loads the given [url].
  static Future<void> openWebView(
    String url, {
    String? javascriptChannelName,
    bool? isChart,
    bool? isZoomEnabled,
    bool? enableMultipleWindows,
  }) async {
    try {
      await _channel.invokeMethod<void>("loadUrl", <String, dynamic>{
        "initialUrl": url,
        "javaScriptChannelName": javascriptChannelName,
        "isChart": isChart,
        "zoomEnabled": isZoomEnabled,
        "enableMultipleWindows": enableMultipleWindows,
      });
    } on PlatformException catch (e) {
      debugPrint("Failed to open WebView: '${e.message}'.");
    }
  }

  /// Loads raw HTML data into the WebView.
  static Future<void> loadHtmlData(
    String htmlString, {
    String? baseURL,
    String? javaScriptChannelName,
  }) async {
    try {
      await _channel.invokeMethod<void>("loadHtmlData", <String, dynamic>{
        "htmlString": htmlString,
        "baseURL": baseURL,
        "javaScriptChannelName": javaScriptChannelName,
      });
    } on Exception catch (e) {
      debugPrint("Failed to load HTML data: $e");
    }
  }

  /// Adds a JavaScript channel to the WebView.
  static Future<void> addJavascriptChannel(String channelName) async {
    try {
      debugPrint("addJavascriptChannel  $channelName");
      await _channel.invokeMethod<void>(
        "addJavascriptChannel",
        <String, dynamic>{"channelName": channelName},
      );
    } on PlatformException catch (e) {
      debugPrint("Failed to add JavaScript channel: ${e.message}");
      rethrow;
    }
  }

  /// Reloads the current URL.
  static Future<void> reloadUrl() async {
    try {
      await _channel.invokeMethod<void>("reloadUrl");
    } on PlatformException catch (e) {
      debugPrint("Failed to reload URL: ${e.message}");
      rethrow;
    }
  }

  /// Resets the web view's cache.
  static Future<void> resetCache() async {
    try {
      await _channel.invokeMethod<void>("resetCache");
    } on PlatformException catch (e) {
      debugPrint("Failed to reset cache: ${e.message}");
      rethrow;
    }
  }

  // Method to authenticate the webviewSession in iOS

  /// Runs JavaScript code in the WebView.
  static Future<void> runJavaScript(String script) async {
    try {
      await _channel.invokeMethod<void>(
        "runJavaScript",
        <String, dynamic>{"script": script},
      );
    } on PlatformException catch (e) {
      debugPrint("Failed to run JavaScript: '${e.message}'.");
    }
  }

  /// Enables multiple windows support in the WebView.
  static Future<void> enableMultipleWindows() async {
    try {
      await _channel.invokeMethod<void>("enableMultipleWindows");
    } on PlatformException catch (e) {
      debugPrint("Failed to renableMultipleWindows: '${e.message}'.");
    }
  }

  // Stream<String> get onPageLoaded {
  //   _onPageLoadedStream ??= _eventChannel
  //       .receiveBroadcastStream()
  //       .map<String>((event) => event as String);
  //   return _onPageLoadedStream!;
  // }

  /// Returns the currently loaded URL.
  static Future<String> getCurrentLoadedUrl() async {
    try {
      return await _channel.invokeMethod("getCurrentUrl");
    } on PlatformException catch (e) {
      debugPrint("Failed to get current URL: '${e.message}'.");
      rethrow;
    }
  }

  /// Registers a callback to receive events from the JavaScript channel stream.
  static void getJavaScriptChannelStream(
    void Function(dynamic) callback,
  ) {
    _eventChannel.receiveBroadcastStream().listen(callback);
  }

  /// Registers a callback to be called when the WebView finishes loading.
  static void setWebViewLoadedCallback(
    void Function(dynamic) callback,
  ) {
    _eventChannel.receiveBroadcastStream().listen((dynamic event) {
      debugPrint("$event");
      callback(event);
    });
  }

  /// Sets whether user interaction is enabled on the WebView.
  static Future<void> setUserInteractionEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>(
        "setUserInteractionEnabled",
        <String, dynamic>{"enabled": enabled},
      );
      debugPrint("Called setUserInteractionEnabled: $enabled");
    } on PlatformException catch (e) {
      debugPrint("Failed to set user interaction: '${e.message}'.");
    }
  }
}
