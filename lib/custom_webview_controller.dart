import "dart:async";
import "dart:convert";

import "package:flutter/foundation.dart";
import "package:flutter/services.dart";

/// Signature for callbacks that receive a message from JavaScript.
typedef JavaScriptMessageCallback = void Function(String message);

/// Controller for a single [CustomWebViewWidget] instance.
class CustomWebViewController {
  late MethodChannel _methodChannel;
  final Completer<int> _idCompleter = Completer<int>();
  final Map<String, JavaScriptMessageCallback> _javascriptChannels = {};

  // Callbacks for navigation events
  void Function(String url)? onPageStarted;
  void Function(String url)? onPageFinished;
  void Function(int progress)? onProgress;
  void Function(String error)? onWebResourceError;
  void Function(String? url, String? message)? onJsAlert;
  void Function(String title)? onTitleChanged;
  
  /// Generic callback for any JS channel message.
  void Function(String channelName, String message)? onJavascriptChannelMessageReceived;
  
  /// Callback for navigation requests. Returning true allows the navigation, false blocks it.
  FutureOr<bool> Function(String url)? onNavigationRequest;

  /// Internal constructor.
  CustomWebViewController();

  /// Called by the widget when the native view is created.
  void setViewId(int id) {
    if (_idCompleter.isCompleted) return;
    _methodChannel = MethodChannel("custom_webview_flutter_$id");
    _methodChannel.setMethodCallHandler(_handleMethodCall);
    _idCompleter.complete(id);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case "onPageStarted":
        final Map? args = call.arguments as Map?;
        onPageStarted?.call(args?["url"] as String? ?? "");
        break;
      case "pageLoaded":
      case "onPageFinished":
        final Map? args = call.arguments as Map?;
        onPageFinished?.call(args?["url"] as String? ?? "");
        break;
      case "onProgress":
        final Map? args = call.arguments as Map?;
        onProgress?.call(args?["progress"] as int? ?? 0);
        break;
      case "onReceivedError":
        final Map? args = call.arguments as Map?;
        onWebResourceError?.call(args?["message"] as String? ?? "unknown error");
        break;
      case "onJavascriptChannelMessageReceived":
        final Map args = call.arguments as Map;
        final String channelName = args["channelName"] as String;
        final String message = args["message"] as String;
        
        // 1. Call channel-specific callback
        _javascriptChannels[channelName]?.call(message);
        
        // 2. Call generic callback
        onJavascriptChannelMessageReceived?.call(channelName, message);
        break;
      case "onNavigationRequest":
        final Map args = call.arguments as Map;
        final String url = args["url"] as String;
        if (onNavigationRequest != null) {
          return await onNavigationRequest!(url);
        }
        return true; // Default allow
      case "onJsAlert":
        final Map args = call.arguments as Map;
        onJsAlert?.call(args["url"] as String?, args["message"] as String?);
        break;
      case "onTitleChanged":
        final Map args = call.arguments as Map;
        onTitleChanged?.call(args["title"] as String? ?? "");
        break;
      default:
        debugPrint("Unhandled method call from native: ${call.method}");
    }
    return null;
  }

  /// Loads a URL in the native web view.
  Future<void> loadUrl(
    String url, {
    Map<String, String>? headers,
    List<String>? javaScriptChannelNames,
    bool? isChart,
    bool? zoomEnabled,
    bool? enableMultipleWindows,
  }) async {
    await _idCompleter.future;
    try {
      await _methodChannel.invokeMethod<void>("loadUrl", <String, dynamic>{
        "initialUrl": url,
        "headers": headers,
        "javaScriptChannelNames": javaScriptChannelNames,
        "isChart": isChart,
        "zoomEnabled": zoomEnabled,
        "enableMultipleWindows": enableMultipleWindows,
      });
    } on PlatformException catch (e) {
      debugPrint("Failed to load URL: ${e.message}");
      rethrow;
    }
  }

  /// Loads raw HTML data into the WebView.
  Future<void> loadHtmlData(
    String htmlString, {
    String? baseURL,
    List<String>? javaScriptChannelNames,
    bool allowMixedContent = false,
  }) async {
    await _idCompleter.future;
    try {
      await _methodChannel.invokeMethod<void>("loadHtmlData", <String, dynamic>{
        "htmlString": htmlString,
        "baseURL": baseURL,
        "javaScriptChannelNames": javaScriptChannelNames,
        "allowMixedContent": allowMixedContent,
      });
    } on PlatformException catch (e) {
      debugPrint("Failed to load HTML data: ${e.message}");
      rethrow;
    }
  }

  /// Adds a JavaScript channel to the web view with an optional callback.
  Future<void> addJavascriptChannel(String channelName, {JavaScriptMessageCallback? onMessageReceived}) async {
    await _idCompleter.future;
    if (onMessageReceived != null) {
      _javascriptChannels[channelName] = onMessageReceived;
    }
    try {
      await _methodChannel.invokeMethod<void>(
        "addJavascriptChannel",
        <String, dynamic>{"channelName": channelName},
      );
    } on PlatformException catch (e) {
      debugPrint("Failed to add JavaScript channel: ${e.message}");
      rethrow;
    }
  }

  /// Removes a JavaScript channel.
  Future<void> removeJavascriptChannel(String channelName) async {
    await _idCompleter.future;
    _javascriptChannels.remove(channelName);
    try {
      await _methodChannel.invokeMethod<void>(
        "removeJavascriptChannel",
        <String, dynamic>{"channelName": channelName},
      );
    } on PlatformException catch (e) {
      debugPrint("Failed to remove JavaScript channel: ${e.message}");
      rethrow;
    }
  }

  /// Reloads the current URL.
  Future<void> reloadUrl() async {
    await _idCompleter.future;
    try {
      await _methodChannel.invokeMethod<void>("reloadUrl");
    } on PlatformException catch (e) {
      debugPrint("Failed to reload URL: ${e.message}");
      rethrow;
    }
  }

  /// Executes JavaScript in the native web view.
  Future<dynamic> runJavaScript(String script) async {
    await _idCompleter.future;
    try {
      return await _methodChannel.invokeMethod<dynamic>(
        "runJavaScript",
        <String, dynamic>{"script": script},
      );
    } on PlatformException catch (e) {
      debugPrint("Failed to execute JavaScript: ${e.message}");
      rethrow;
    }
  }

  /// Returns the currently loaded URL.
  Future<String?> getCurrentUrl() async {
    await _idCompleter.future;
    try {
      return await _methodChannel.invokeMethod<String>("getCurrentUrl");
    } on PlatformException catch (e) {
      debugPrint("Failed to get current URL: ${e.message}");
      rethrow;
    }
  }

  /// Sets whether user interaction is enabled.
  Future<void> setUserInteractionEnabled(bool enabled) async {
    await _idCompleter.future;
    try {
      await _methodChannel.invokeMethod<void>(
        "setUserInteractionEnabled",
        <String, dynamic>{"enabled": enabled},
      );
    } on PlatformException catch (e) {
      debugPrint("Failed to set user interaction: ${e.message}");
      rethrow;
    }
  }

  /// Sets a custom user agent.
  Future<void> setCustomUserAgent(String? userAgent) async {
    await _idCompleter.future;
    try {
      await _methodChannel.invokeMethod<void>(
        "setCustomUserAgent",
        <String, dynamic>{"userAgent": userAgent},
      );
    } on PlatformException catch (e) {
      debugPrint("Failed to set custom user agent: ${e.message}");
      rethrow;
    }
  }

  /// Enables or disables multiple windows support.
  Future<void> enableMultipleWindows(bool enabled) async {
    await _idCompleter.future;
    try {
      await _methodChannel.invokeMethod<void>(
        "enableMultipleWindows",
        <String, dynamic>{"enabled": enabled},
      );
    } on PlatformException catch (e) {
      debugPrint("Failed to enable multiple windows: ${e.message}");
      rethrow;
    }
  }

  /// Returns whether the web view can navigate back in history.
  Future<bool> canGoBack() async {
    await _idCompleter.future;
    try {
      return await _methodChannel.invokeMethod<bool>("canGoBack") ?? false;
    } on PlatformException catch (e) {
      debugPrint("Failed to check canGoBack: ${e.message}");
      return false;
    }
  }

  /// Navigates back in the web view's history.
  Future<void> goBack() async {
    await _idCompleter.future;
    try {
      await _methodChannel.invokeMethod<void>("goBack");
    } on PlatformException catch (e) {
      debugPrint("Failed to go back: ${e.message}");
      rethrow;
    }
  }

  /// Sets the background color of the web view.
  Future<void> setBackgroundColor(int colorArgb) async {
    await _idCompleter.future;
    try {
      await _methodChannel.invokeMethod<void>(
        "setBackgroundColor",
        <String, dynamic>{"color": colorArgb},
      );
    } on PlatformException catch (e) {
      debugPrint("Failed to set background color: ${e.message}");
      rethrow;
    }
  }
}
