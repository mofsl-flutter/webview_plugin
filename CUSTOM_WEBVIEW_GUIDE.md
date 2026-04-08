# Custom WebView Plugin: Implementation & Extension Guide

This guide provides a technical overview of the **Custom WebView Plugin** architecture, its advanced features, and instructions for further extension.

---

## 1. Architectural Overview
This plugin is a high-performance, multi-instance replacement for `webview_flutter`. It uses **Instance-Scoped Method Channels** to allow multiple WebViews to coexist without state leakage.

### Key Components:
- **Dart Layer (`lib/`)**:
    - `CustomWebViewController`: The primary API. Manages instance-specific logic and callbacks.
    - `CustomWebViewWidget`: A `StatefulWidget` wrapping `PlatformViewLink` (Android) and `UiKitView` (iOS).
    - `CustomWebViewCookieManager`: Global singleton for cookie operations.
- **Native Layer (Android/iOS)**:
    - **Factory**: Registers the plugin and instantiates the `PlatformView`.
    - **WebViewMoFlutter**: The bridge class. It owns the `MethodChannel` (`custom_webview_flutter_$viewId`) and implements the `MethodCallHandler`.
    - **WebViewManager**: Encapsulates the actual `WebView`/`WKWebView` instance, its configuration, and delegate implementations.

---

## 2. Advanced Features Implemented

### A. Multi-Channel JavaScript Support
Unlike basic implementations, this plugin supports registering multiple JavaScript channels simultaneously during the `loadUrl` or `loadHtmlData` calls.
- **Dart**: Pass `List<String>? javaScriptChannelNames`.
- **Native**: Automatically iterates and injects `webkit.messageHandlers` (iOS) or `JavascriptInterface` (Android) for each name.

### B. Synchronous Navigation Blocking
The `onNavigationRequest` callback in Dart allows for real-time blocking of URLs.
- **Android**: Uses a `CountDownLatch(1)` to pause the UI thread briefly while waiting for Dart's boolean response.
- **iOS**: Uses the `decisionHandler` closure within `decidePolicyFor` to asynchronously receive the decision from Dart.

### C. SSL & Security
- **Server Trust**: Both platforms implement handlers to trust self-signed or internal CA certificates (essential for development and internal enterprise tools).
- **Mixed Content**: Android supports `MIXED_CONTENT_ALWAYS_ALLOW` when requested via `allowMixedContent` in `loadHtmlData`.
- **Sub-resource Filtering**: Android's `onReceivedError` is filtered to only report errors for the `isForMainFrame`, preventing app-level noise from failing tracking scripts or fonts.

### D. Media & UI
- **File Picker (iOS)**: Fully integrated with `UIDocumentPickerDelegate`. Webpages with `<input type="file">` will trigger the native iOS file selector.
- **Background Transparency**: `setBackgroundColor(int color)` supports ARGB values, allowing for perfectly transparent WebViews (ideal for overlaying charts).
- **Popup Windows**: Correctly handles `onCreateWindow` (Android) and `createWebViewWith` (iOS) to ensure links targeting `_blank` open in appropriate containers.

---

## 3. Communication Protocol
- **Dart to Native**: `methodChannel.invokeMethod("command", args)`
- **Native to Dart**: `methodChannel.invokeMethod("callback", args)`

---

## 4. How to add a New Native Method (Template)

### Step 1: Dart (lib/custom_webview_controller.dart)
```dart
Future<void> myNewMethod(String arg) async {
  await _idCompleter.future; // Always wait for view ID assignment
  await _methodChannel.invokeMethod('myNewMethod', {'arg': arg});
}
```

### Step 2: Android (CustomWebViewFactory.kt -> WebViewMoFlutter)
```kotlin
"myNewMethod" -> {
    val arg = call.argument<String>("arg")
    // Native implementation here
    result.success(null)
}
```

### Step 3: iOS (CustomWebViewFactory.swift -> WebViewMoFlutter)
```swift
case "myNewMethod":
    if let args = call.arguments as? [String: Any], let arg = args["arg"] as? String {
        // Native implementation here
        result(nil)
    }
```

---

## 5. Critical Maintenance Notes
- **Thread Management**: All calls from Native to Dart MUST be performed on the main thread (UI Thread). 
    - Android: `activity?.runOnUiThread { ... }`
    - iOS: `DispatchQueue.main.async { ... }`
- **Resource Cleanup**: Memory is managed by the `PlatformView` lifecycle. Ensure `webView.destroy()` (Android) and `progressObserver.invalidate()` (iOS) are called in the `dispose` or `deinit` blocks.
- **Performance**: Initial configuration (User Agent, Zoom, Mixed Content) is passed through `creationParams` to ensure the WebView is "warm" and correctly configured *before* the first frame renders.
