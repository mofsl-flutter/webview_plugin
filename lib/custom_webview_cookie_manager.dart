import "package:flutter/services.dart";

/// Manages cookies for all web views.
class CustomWebViewCookieManager {
  static const MethodChannel _channel = MethodChannel("custom_webview_flutter");

  /// Clears all cookies for all web views.
  static Future<void> clearCookies() async {
    try {
      await _channel.invokeMethod<void>("clearCookies");
    } on PlatformException catch (e) {
      print("Failed to clear cookies: ${e.message}");
      rethrow;
    }
  }
}
