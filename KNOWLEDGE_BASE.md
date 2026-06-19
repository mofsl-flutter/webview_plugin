# Custom WebView Plugin — Knowledge Base

**Package:** `custom_webview_plugin` · **Version:** `1.0.4+1`
**Dart SDK:** `>=3.3.1 <4.0.0` · **Flutter SDK:** `>=3.3.0`
**Platforms:** Android · iOS

> This document is the authoritative reference for AI agents and developers working on or consuming this plugin. Every method signature, parameter, callback, platform behaviour, and usage pattern is sourced directly from the Dart, Swift, and Kotlin implementation files.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Component: CustomWebViewWidget](#2-component-customwebviewwidget)
3. [Component: CustomWebViewController](#3-component-customwebviewcontroller)
4. [Component: CustomWebViewPlugin](#4-component-customwebviewplugin)
5. [Component: CustomWebViewCookieManager](#5-component-customwebviewcookiemanager)
6. [Type Definitions](#6-type-definitions)
7. [Platform Behaviour Reference](#7-platform-behaviour-reference)
8. [Usage Patterns](#8-usage-patterns)
9. [Known Limitations & Gotchas](#9-known-limitations--gotchas)
10. [Method Channel Reference](#10-method-channel-reference)

---

## 1. Architecture Overview

### Component Map

| Component | Type | Purpose |
|---|---|---|
| `CustomWebViewWidget` | `StatefulWidget` | Embeds the native WebView into the Flutter widget tree |
| `CustomWebViewController` | Class | Controls a single WebView instance; exposes all operations and callbacks |
| `CustomWebViewPlugin` | Static class | Global operations (cache reset) not tied to a widget instance |
| `CustomWebViewCookieManager` | Static class | Global cookie operations |
| `JavaScriptMessageCallback` | `typedef` | Callback signature for per-channel JS messages |

### Communication Layers

```
Flutter (Dart)
     │
     │  Global channel: "custom_webview_flutter"
     │  (resetCache, clearCookies)
     │
     │  Instance channel: "custom_webview_flutter_<viewId>"
     │  (all per-WebView operations)
     │
     ▼
Method Channel (Flutter Platform Channel)
     │
     ├── iOS:     WKWebView (Swift) — CustomWebViewPlugin.swift + CustomWebViewFactory.swift
     └── Android: WebView (Kotlin)  — CustomWebViewPlugin.kt + CustomWebViewFactory.kt
```

### Instance-Scoped Channel Pattern

Each `CustomWebViewWidget` gets a unique `viewId` assigned by the platform. The controller registers `MethodChannel("custom_webview_flutter_$viewId")` on that ID. This allows multiple WebView instances to run simultaneously without state leakage.

```dart
// Controller initializes its channel when the native view is ready
void setViewId(int id) {
  _methodChannel = MethodChannel("custom_webview_flutter_$id");
  _methodChannel.setMethodCallHandler(_handleMethodCall);
  _idCompleter.complete(id);
}
```

> **Critical threading rule:** All native → Dart callback invocations must run on the main thread.
> Android: `activity?.runOnUiThread { methodChannel.invokeMethod(...) }`
> iOS: `DispatchQueue.main.async { methodChannel.invokeMethod(...) }`

---

## 2. Component: `CustomWebViewWidget`

**File:** `lib/custom_webview_plugin.dart`
**Extends:** `StatefulWidget`

Embeds a native `WKWebView` (iOS) or `WebView` (Android) into the Flutter widget tree. On unsupported platforms it renders an error `Text` widget. The widget passes `creationParams` to the native side before the first frame, making initial configuration (URL, zoom, JS channels) available at creation time.

### Constructor

```dart
const CustomWebViewWidget({
  required this.controller,
  super.key,
  this.initialUrl,
  this.initialHeaders,
  this.javascriptChannelNames,
  this.isChart = true,
  this.zoomEnabled = true,
  this.enableMultipleWindows = true,
})
```

### Parameters

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `controller` | `CustomWebViewController` | ✅ Yes | — | The controller that drives all operations on this WebView. One controller per widget; do not share controllers between widgets. |
| `key` | `Key?` | No | `null` | Standard Flutter widget key. |
| `initialUrl` | `String?` | No | `null` | URL to load immediately when the native view is created. If `null`, the view is created blank and you call `controller.loadUrl()` later. |
| `initialHeaders` | `Map<String, String>?` | No | `null` | HTTP headers sent with the `initialUrl` request. Ignored if `initialUrl` is null. |
| `javascriptChannelNames` | `List<String>?` | No | `null` | JavaScript channel names injected into the page on creation. Equivalent to calling `addJavascriptChannel()` for each name, but cheaper because it happens before the first paint. |
| `isChart` | `bool` | No | `true` | Chart mode flag. **iOS only effect:** When `true`, iOS fires `pageLoaded` (no URL) instead of `onPageFinished`. On Android this flag is passed to native but has no effect on callbacks — `onPageFinished` always fires. Set to `false` on iOS if your code reads the URL in `onPageFinished`. |
| `zoomEnabled` | `bool` | No | `true` | Enables pinch-to-zoom on the WebView. On iOS, disabling this injects a viewport meta tag. On Android, it calls `setSupportZoom(false)`. |
| `enableMultipleWindows` | `bool` | No | `true` | Allows the page to open new windows via `window.open()` or `target="_blank"` links. See platform-specific popup behaviour in §7. |

### Rendering

| Platform | Widget Used | Notes |
|---|---|---|
| Android | `PlatformViewLink` + `AndroidViewSurface` | Uses `initSurfaceAndroidView` with `StandardMessageCodec` |
| iOS | `UiKitView` | Uses `StandardMessageCodec` |
| Other | `Text` | Displays: `"<platform> is not yet supported by the webview_plugin"` |

### Minimal Usage Example

```dart
final controller = CustomWebViewController();

CustomWebViewWidget(
  controller: controller,
  initialUrl: 'https://example.com',
)
```

### Full Usage Example

```dart
final controller = CustomWebViewController()
  ..onPageStarted = (url) => print('Started: $url')
  ..onPageFinished = (url) => print('Finished: $url')
  ..onProgress = (p) => print('Progress: $p%');

CustomWebViewWidget(
  controller: controller,
  initialUrl: 'https://example.com',
  initialHeaders: {'Authorization': 'Bearer $token'},
  javascriptChannelNames: const ['Bridge', 'Analytics'],
  isChart: false,
  zoomEnabled: false,
  enableMultipleWindows: false,
)
```

---

## 3. Component: `CustomWebViewController`

**File:** `lib/custom_webview_controller.dart`

The primary control surface for a WebView. One instance must be created per `CustomWebViewWidget`. All methods are asynchronous and wait internally for the native view to be ready before dispatching (via `_idCompleter.future`), so it is safe to call them immediately after controller creation.

### Constructor

```dart
CustomWebViewController()
```

No parameters. Create one instance and pass it to `CustomWebViewWidget.controller`.

---

### Callback Properties

All callbacks are nullable and set via plain assignment (not constructor params). They default to `null` (no-op).

| Property | Type | Fired when | Arguments |
|---|---|---|---|
| `onPageStarted` | `void Function(String url)?` | Navigation begins (before content loads) | `url`: the URL being navigated to |
| `onPageFinished` | `void Function(String url)?` | Page fully loaded. **iOS:** only fires with a non-empty URL when `isChart: false`; with `isChart: true` fires with `""`. **Android:** always fires with URL regardless of `isChart`. | `url`: the final URL (may be `""` on iOS with `isChart: true`) |
| `onProgress` | `void Function(int progress)?` | Load progress changes | `progress`: integer 0–100 |
| `onWebResourceError` | `void Function(String error)?` | A resource or navigation error occurs. On Android, **main-frame errors only** (sub-resource/iframe errors are suppressed). | `error`: platform error description string |
| `onJsAlert` | `void Function(String? url, String? message)?` | JavaScript `alert()` is called in the page | `url`: page URL (nullable), `message`: alert text (nullable) |
| `onTitleChanged` | `void Function(String title)?` | The page `<title>` changes | `title`: new document title |
| `onJavascriptChannelMessageReceived` | `void Function(String channelName, String message)?` | **Any** registered JS channel posts a message. Called after the per-channel callback (if any). | `channelName`: the channel name, `message`: the string payload |
| `onNavigationRequest` | `FutureOr<bool> Function(String url)?` | Before each navigation (every URL, including redirects). Return `true` to allow, `false` to block. Defaults to `true` (allow all) when not set. | `url`: the URL being navigated to |

**Setting callbacks:**
```dart
final controller = CustomWebViewController();
controller.onPageStarted = (url) { /* ... */ };
controller.onPageFinished = (url) { /* ... */ };
controller.onProgress = (progress) { /* ... */ };
controller.onWebResourceError = (error) { /* ... */ };
controller.onJsAlert = (url, message) { /* ... */ };
controller.onTitleChanged = (title) { /* ... */ };
controller.onJavascriptChannelMessageReceived = (channel, message) { /* ... */ };
controller.onNavigationRequest = (url) async {
  return url.startsWith('https://allowed-domain.com');
};
```

---

### Methods

All methods except `canGoBack` and `setViewId` throw `PlatformException` on native errors (caught and re-thrown after logging).

#### `loadUrl`

```dart
Future<void> loadUrl(
  String url, {
  Map<String, String>? headers,
  List<String>? javaScriptChannelNames,
  bool? isChart,
  bool? zoomEnabled,
  bool? enableMultipleWindows,
})
```

Loads the given URL in the WebView.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `url` | `String` | required | The URL to load. Must be a valid URL; invalid URLs trigger `onWebResourceError` on iOS. |
| `headers` | `Map<String, String>?` | `null` | HTTP request headers to include. |
| `javaScriptChannelNames` | `List<String>?` | `null` | JS channels to register before the page loads. |
| `isChart` | `bool?` | `null` | Overrides the widget-level `isChart` for this load. |
| `zoomEnabled` | `bool?` | `null` | Overrides the widget-level `zoomEnabled` for this load. |
| `enableMultipleWindows` | `bool?` | `null` | Overrides the widget-level `enableMultipleWindows` for this load. |

**Throws:** `PlatformException`

---

#### `loadHtmlData`

```dart
Future<void> loadHtmlData(
  String htmlString, {
  String? baseURL,
  List<String>? javaScriptChannelNames,
  bool allowMixedContent = false,
})
```

Loads raw HTML into the WebView.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `htmlString` | `String` | required | Full HTML content to render. |
| `baseURL` | `String?` | `null` | Base URL for resolving relative resources. On Android, uses `loadDataWithBaseURL`; on iOS, uses `loadHTMLString(baseURL:)`. |
| `javaScriptChannelNames` | `List<String>?` | `null` | JS channels to inject into the HTML context. |
| `allowMixedContent` | `bool` | `false` | Android only: sets `MIXED_CONTENT_ALWAYS_ALLOW` (API 21+). Ignored on iOS. |

**Throws:** `PlatformException`

---

#### `addJavascriptChannel`

```dart
Future<void> addJavascriptChannel(
  String channelName, {
  JavaScriptMessageCallback? onMessageReceived,
})
```

Registers a named JavaScript channel. After this call, JavaScript in the page can call `window.<channelName>.postMessage("data")` (iOS) or `<channelName>.postMessage("data")` (Android).

| Parameter | Type | Default | Description |
|---|---|---|---|
| `channelName` | `String` | required | The name of the channel. Must be a valid JavaScript identifier. |
| `onMessageReceived` | `JavaScriptMessageCallback?` | `null` | Per-channel callback. Called before `onJavascriptChannelMessageReceived`. |

**Throws:** `PlatformException`

---

#### `removeJavascriptChannel`

```dart
Future<void> removeJavascriptChannel(String channelName)
```

Unregisters a JavaScript channel. After this call, messages from that channel are no longer forwarded to Dart. The per-channel callback stored by `addJavascriptChannel` is also removed from the internal map.

**Throws:** `PlatformException`

---

#### `runJavaScript`

```dart
Future<dynamic> runJavaScript(String script)
```

Evaluates a JavaScript expression in the current page context and returns the result.

| Parameter | Type | Description |
|---|---|---|
| `script` | `String` | JavaScript code to execute. Can return a value. |

**Returns:** `Future<dynamic>` — the result of the expression, or `null`.
**Throws:** `PlatformException`

```dart
final title = await controller.runJavaScript('document.title');
await controller.runJavaScript('window.scrollTo(0, 0)');
```

---

#### `reloadUrl`

```dart
Future<void> reloadUrl()
```

Reloads the currently loaded URL. Equivalent to pressing the browser's refresh button.

**Throws:** `PlatformException`

---

#### `getCurrentUrl`

```dart
Future<String?> getCurrentUrl()
```

Returns the URL currently displayed in the WebView. Returns `null` if no URL is loaded.

**Throws:** `PlatformException`

---

#### `canGoBack`

```dart
Future<bool> canGoBack()
```

Returns `true` if the WebView has at least one entry in its back history. **Never throws** — returns `false` on any exception.

---

#### `goBack`

```dart
Future<void> goBack()
```

Navigates to the previous entry in the WebView's history. Call `canGoBack()` first to check if there is history to go back to.

**Throws:** `PlatformException`

---

#### `setUserInteractionEnabled`

```dart
Future<void> setUserInteractionEnabled(bool enabled)
```

Enables or disables touch/click interaction with the WebView content.

| Parameter | Type | Description |
|---|---|---|
| `enabled` | `bool` | `false` to make the WebView non-interactive (read-only/display). |

**Throws:** `PlatformException`

---

#### `setCustomUserAgent`

```dart
Future<void> setCustomUserAgent(String? userAgent)
```

Sets the HTTP `User-Agent` header sent with all requests from this WebView. Pass `null` to reset to the platform default.

**Throws:** `PlatformException`

---

#### `enableMultipleWindows`

```dart
Future<void> enableMultipleWindows(bool enabled)
```

Dynamically enables or disables multiple-window support (popup windows, `target="_blank"` links) after the view is already created. Equivalent to the constructor-level `enableMultipleWindows` param but callable at any time.

**Throws:** `PlatformException`

---

#### `setBackgroundColor`

```dart
Future<void> setBackgroundColor(int colorArgb)
```

Sets the WebView's background color. Useful for preventing a white flash before page content loads.

| Parameter | Type | Description |
|---|---|---|
| `colorArgb` | `int` | Color in ARGB format (e.g., `0xFF000000` for opaque black, `0x00000000` for transparent). |

**Throws:** `PlatformException`

---

#### `setViewId` (internal)

```dart
void setViewId(int id)
```

Called automatically by `CustomWebViewWidget` when the native platform view is created. **Do not call this manually.** Calling it a second time is a no-op (guarded by `_idCompleter.isCompleted`).

---

### Methods Quick Reference

| Method | Returns | Throws on Error |
|---|---|---|
| `loadUrl(url, {...})` | `Future<void>` | Yes |
| `loadHtmlData(html, {...})` | `Future<void>` | Yes |
| `addJavascriptChannel(name, {...})` | `Future<void>` | Yes |
| `removeJavascriptChannel(name)` | `Future<void>` | Yes |
| `runJavaScript(script)` | `Future<dynamic>` | Yes |
| `reloadUrl()` | `Future<void>` | Yes |
| `getCurrentUrl()` | `Future<String?>` | Yes |
| `canGoBack()` | `Future<bool>` | No — returns `false` |
| `goBack()` | `Future<void>` | Yes |
| `setUserInteractionEnabled(bool)` | `Future<void>` | Yes |
| `setCustomUserAgent(String?)` | `Future<void>` | Yes |
| `enableMultipleWindows(bool)` | `Future<void>` | Yes |
| `setBackgroundColor(int)` | `Future<void>` | Yes |
| `setViewId(int)` | `void` | No (internal) |

---

## 4. Component: `CustomWebViewPlugin`

**File:** `lib/custom_webview_plugin.dart`
**Type:** Static utility class (not instantiated)
**Method Channel:** `"custom_webview_flutter"` (global)

Provides operations that apply globally across all WebView instances, not tied to any specific widget.

### `resetCache`

```dart
static Future<void> CustomWebViewPlugin.resetCache()
```

Clears the full WebView cache, all cookies, and local storage on the current device.

**iOS implementation:** Calls `WKWebsiteDataStore.removeData(ofTypes: allWebsiteDataTypes, modifiedSince: Date(timeIntervalSince1970: 0))`.
**Android implementation:** Calls `CookieManager.getInstance().removeAllCookies(null)` + `WebStorage.getInstance().deleteAllData()`.

**Throws:** `PlatformException`

**When to use:** Call before loading a fresh session, after logout, or when you need to guarantee no cached credentials or stale content is present.

```dart
await CustomWebViewPlugin.resetCache();
```

---

## 5. Component: `CustomWebViewCookieManager`

**File:** `lib/custom_webview_cookie_manager.dart`
**Type:** Static utility class (not instantiated)
**Method Channel:** `"custom_webview_flutter"` (global)

Provides cookie-specific operations.

### `clearCookies`

```dart
static Future<void> CustomWebViewCookieManager.clearCookies()
```

Clears HTTP cookies only. Does not clear the cache, local storage, or other web data.

**iOS implementation:** Iterates `WKWebsiteDataStore.default().httpCookieStore`, deletes each cookie individually.
**Android implementation:** Calls `CookieManager.getInstance().removeAllCookies(null)`.

**Throws:** `PlatformException`

**When to use:** Use instead of `resetCache()` when you want to clear authentication cookies (e.g., logout) but preserve cached assets for faster reload.

```dart
await CustomWebViewCookieManager.clearCookies();
```

### `resetCache` vs `clearCookies`

| | `resetCache` | `clearCookies` |
|---|---|---|
| Clears cookies | ✅ | ✅ |
| Clears HTTP cache | ✅ | ❌ |
| Clears local storage / IndexedDB | ✅ | ❌ |
| Use case | Full session wipe | Logout only |

---

## 6. Type Definitions

### `JavaScriptMessageCallback`

**File:** `lib/custom_webview_controller.dart`

```dart
typedef JavaScriptMessageCallback = void Function(String message);
```

Callback signature for per-channel JavaScript messages. Used as the `onMessageReceived` parameter in `addJavascriptChannel`.

| Parameter | Type | Description |
|---|---|---|
| `message` | `String` | The message payload sent from JavaScript via `postMessage()`. Complex objects are serialized to JSON strings by the native layer. |

---

## 7. Platform Behaviour Reference

### Feature Matrix

| Feature | iOS | Android |
|---|---|---|
| **Underlying engine** | `WKWebView` | `WebView` (Chromium) |
| **JavaScript channels — inject syntax** | `webkit.messageHandlers.<name>` + `window.<name>` alias | `<name>` as `JavascriptInterface` |
| **Navigation blocking** | Async `decisionHandler` closure | Block-then-retry: returns `false` immediately, asks Dart async; if Dart allows, sets `isReloadingFromDart=true` and calls `loadUrl()` again |
| **Progress tracking** | KVO on `estimatedProgress` | `WebChromeClient.onProgressChanged` |
| **SSL: self-signed/invalid certs** | Accepted — returns `URLCredential(trust: serverTrust)` | Accepted — always calls `handler.proceed()` |
| **PDF files** | Opened externally via `UIApplication.shared.open()` | Opened externally OR enqueued to system `DownloadManager` |
| **File upload (`<input type="file">`)** | `UIDocumentPickerViewController` via `WKOpenPanelParameters` — **iOS 18.4+ only** (delegate method is `@available(iOS 18.4, *)`) | `Intent.ACTION_GET_CONTENT` via `ActivityResultListener` |
| **Accepted file types for upload** | All (document picker, multiple selection from `parameters`) | `application/pdf`, `image/*`, `video/*`, `*/*` |
| **Popup windows / `window.open()`** | Returns new `WKWebView` via `createWebViewWith` delegate | Shows `AlertDialog` with embedded `WebView` and Close button |
| **Custom URL schemes** | `tel:`, `mailto:` — opened via `UIApplication.shared.open()` | `upi:`, `intent:`, `tel:`, `mailto:`, `sms:`, `market:`, `whatsapp:` — dispatched via `Intent.ACTION_VIEW` |
| **`intent:` scheme fallback** | Not handled | Parses `browser_fallback_url` parameter |
| **Error reporting** | All navigation errors reported | Main-frame errors only (`isForMainFrame` check) |
| **Zoom disable** | Injects viewport meta tag script | `settings.setSupportZoom(false)` + disables built-in controls |
| **Background color** | Set on main thread via `DispatchQueue.main.async` | Set on UI thread via `activity.runOnUiThread` |
| **DevTools / Inspector** | Enabled for iOS 16.4+ (`webView.isInspectable = true`) | Not configured |
| **`isChart` flag** | `true` → fires `pageLoaded` (no URL); `false` → fires `onPageFinished` (with URL) | **Flag is ignored** — always fires `onPageFinished` with URL regardless of value |
| **Mixed content (HTTP in HTTPS)** | Not configurable | Set via `allowMixedContent` in `loadHtmlData` (API 21+) |
| **Cache clear scope** | All website data types from epoch | `CookieManager` + `WebStorage` |
| **Cookie clear scope** | Individual cookies via `httpCookieStore` | `CookieManager.removeAllCookies` |
| **Multiple instances** | Fully supported (instance-scoped channels) | Fully supported (instance-scoped channels) |

### `isChart` Flag Behaviour

**iOS:** When `isChart: true` (the default), the iOS native layer fires `pageLoaded` (no URL argument) instead of `onPageFinished`. The Dart handler maps both `"pageLoaded"` and `"onPageFinished"` to `onPageFinished?.call(url)`, but the `pageLoaded` path arrives with no URL so the callback receives `""`.

**Android:** The `isChart` flag has no effect on Android. The `pageDidLoad()` interface method exists in the Android delegate protocol but is never called by the Android WebViewManager. Android always fires `onPageFinished` with the URL via its `WebViewClient.onPageFinished` callback.

**Practical impact:** On iOS, set `isChart: false` if you need the URL argument in `onPageFinished`. On Android, `onPageFinished` always fires with the URL regardless of `isChart`.

### Android Permission Grants

Android's `WebChromeClient.onPermissionRequest` automatically grants all requested web permissions (camera, microphone, etc.) without prompting. Ensure your app's `AndroidManifest.xml` has the corresponding Android-level permissions.

---

## 8. Usage Patterns

### Pattern 1 — Minimal Setup

```dart
class WebPage extends StatelessWidget {
  final controller = CustomWebViewController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomWebViewWidget(
        controller: controller,
        initialUrl: 'https://example.com',
        isChart: false,
      ),
    );
  }
}
```

### Pattern 2 — Full Setup (All Callbacks)

```dart
class WebPage extends StatefulWidget {
  @override
  _WebPageState createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  late final CustomWebViewController _controller;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _controller = CustomWebViewController()
      ..onPageStarted = (url) => print('Loading: $url')
      ..onPageFinished = (url) => print('Done: $url')
      ..onProgress = (p) => setState(() => _progress = p / 100)
      ..onWebResourceError = (err) => print('Error: $err')
      ..onTitleChanged = (title) => print('Title: $title')
      ..onJsAlert = (url, msg) => showDialog(/* ... */)
      ..onJavascriptChannelMessageReceived = (channel, msg) {
          print('[$channel] $msg');
        }
      ..onNavigationRequest = (url) {
          // Block external navigation
          return url.startsWith('https://my-domain.com');
        };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          LinearProgressIndicator(value: _progress),
          Expanded(
            child: CustomWebViewWidget(
              controller: _controller,
              initialUrl: 'https://my-domain.com',
              isChart: false,
            ),
          ),
        ],
      ),
    );
  }
}
```

### Pattern 3 — JavaScript Bridge (Bidirectional Messaging)

**Dart side:**
```dart
// Register channels with per-channel callbacks
await controller.addJavascriptChannel(
  'FlutterBridge',
  onMessageReceived: (message) {
    final data = jsonDecode(message);
    handleEvent(data['type'], data['payload']);
  },
);

// Send data into the page
await controller.runJavaScript(
  'window.onFlutterData(${jsonEncode({'user': 'Alice', 'score': 42})})',
);
```

**JavaScript side (iOS):**
```javascript
// Receive from Flutter
window.onFlutterData = function(data) { /* ... */ };

// Send to Flutter
webkit.messageHandlers.FlutterBridge.postMessage(JSON.stringify({
  type: 'userAction',
  payload: { buttonId: 'submit' }
}));
```

**JavaScript side (Android):**
```javascript
FlutterBridge.postMessage(JSON.stringify({
  type: 'userAction',
  payload: { buttonId: 'submit' }
}));
```

> **Note:** The plugin injects a `window.FlutterBridge` alias on iOS so `window.FlutterBridge.postMessage(...)` also works, matching Android's syntax.

### Pattern 4 — Navigation Interceptor

```dart
controller.onNavigationRequest = (url) async {
  final uri = Uri.parse(url);

  // Allow the host domain and its subdomains
  if (uri.host.endsWith('myapp.com')) return true;

  // Block everything else, optionally open in system browser
  launchUrl(Uri.parse(url));
  return false;
};
```

### Pattern 5 — HTML Content Rendering

```dart
// Inline HTML with a base URL for relative asset resolution
await controller.loadHtmlData(
  '''
  <html>
    <head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
    <body>
      <img src="/assets/logo.png">
      <p>Hello from Dart!</p>
    </body>
  </html>
  ''',
  baseURL: 'https://my-domain.com',
  javaScriptChannelNames: ['Bridge'],
);

// HTML with mixed content (Android only — loads HTTP assets inside HTTPS page)
await controller.loadHtmlData(
  htmlString,
  allowMixedContent: true,
);
```

### Pattern 6 — Back Navigation with Hardware Button

```dart
// Flutter 3.x+ — use PopScope
PopScope(
  canPop: false,
  onPopInvoked: (didPop) async {
    if (didPop) return;
    if (await controller.canGoBack()) {
      await controller.goBack();
    } else {
      Navigator.of(context).pop();
    }
  },
  child: CustomWebViewWidget(controller: controller, isChart: false),
)
```

### Pattern 7 — Custom User Agent

```dart
// Set before loading (or after — takes effect on next request)
await controller.setCustomUserAgent(
  'MyApp/1.0 (Flutter; custom_webview_plugin/1.0.4)',
);
await controller.loadUrl('https://example.com');

// Reset to platform default
await controller.setCustomUserAgent(null);
```

### Pattern 8 — Cache & Cookie Management

```dart
// On logout: clear cookies only (keep cached assets)
Future<void> onLogout() async {
  await CustomWebViewCookieManager.clearCookies();
}

// On full reset / switch accounts: wipe everything
Future<void> onAccountSwitch() async {
  await CustomWebViewPlugin.resetCache();
}

// Transparent WebView (no white flash)
await controller.setBackgroundColor(0x00000000); // Transparent
// Or match the scaffold background
await controller.setBackgroundColor(0xFF1A1A2E); // Dark background
```

### Pattern 9 — Multiple WebView Instances

```dart
// Each widget requires its own controller instance
final controllerA = CustomWebViewController();
final controllerB = CustomWebViewController();

Row(
  children: [
    Expanded(child: CustomWebViewWidget(controller: controllerA, initialUrl: 'https://a.com', isChart: false)),
    Expanded(child: CustomWebViewWidget(controller: controllerB, initialUrl: 'https://b.com', isChart: false)),
  ],
)
```

---

## 9. Known Limitations & Gotchas

### `isChart: true` Suppresses `onPageFinished` URL (iOS Only)

On iOS, when `isChart: true` (the default), the native layer fires `pageLoaded` with no URL. The Dart handler maps this to `onPageFinished("")`. If your code reads the URL argument in `onPageFinished`, set `isChart: false` on iOS. On Android, `onPageFinished` always fires with the correct URL regardless of `isChart`.

### `canGoBack()` Never Throws

Unlike every other method, `canGoBack()` catches `PlatformException` internally and returns `false`. It will not propagate errors. This is intentional — it is safe to call without a try/catch.

### All Other Methods Throw `PlatformException`

Every other method re-throws on native errors after logging. Wrap calls in try/catch at the call site:
```dart
try {
  await controller.loadUrl('https://example.com');
} on PlatformException catch (e) {
  showErrorBanner(e.message);
}
```

### `onNavigationRequest` Defaults to Allow

If you do not set `onNavigationRequest`, all navigations are allowed. The default return value is `true`.

### Android Suppresses Sub-Resource Errors

`onWebResourceError` is only called for main-frame errors on Android. Errors in iframes, images, fonts, or tracking scripts do not fire this callback. iOS reports all navigation errors.

### SSL Errors Are Silently Accepted

Both platforms accept all SSL certificates, including self-signed and expired ones. This is intentional for enterprise/intranet use cases but is **not appropriate for security-sensitive applications** without additional validation.

### `setViewId` Is Internal

`setViewId(int id)` is called automatically by `CustomWebViewWidget` during platform view creation. Never call it manually. Calling it a second time is a no-op.

### Separate Controllers for Separate Widgets

Never share one `CustomWebViewController` instance between two `CustomWebViewWidget` instances. The controller's `_idCompleter` can only be completed once.

### Channel Registration Is Additive

Calling `addJavascriptChannel` with a name that was already registered in `javascriptChannelNames` registers it a second time on the native side. The behaviour is harmless (duplicate registrations are idempotent in practice) but avoid it for clarity.

### Android File Chooser Requires Activity

The Android file chooser (`<input type="file">`) requires a live `Activity` reference. If the plugin is used in a context without an `Activity` (e.g., a background service), the file chooser will silently fail.

### iOS File Upload Requires iOS 18.4+

The `WKUIDelegate` method `webView(_:runOpenPanelWith:initiatedByFrame:completionHandler:)` is decorated `@available(iOS 18.4, *)` in the plugin source. File input (`<input type="file">`) will silently fail (call `completionHandler(nil)`) on devices below iOS 18.4. Plan accordingly if your minimum deployment target is below that.

### `allowMixedContent` Is Android-Only

The `allowMixedContent: true` parameter in `loadHtmlData` is ignored on iOS. iOS enforces App Transport Security (ATS) rules independently.

---

## 10. Method Channel Reference

This section is intended for contributors extending the native layer.

### Global Channel: `"custom_webview_flutter"`

Used by `CustomWebViewPlugin` and `CustomWebViewCookieManager`.

| Direction | Method | Arguments | Returns |
|---|---|---|---|
| Dart → Native | `resetCache` | none | `null` |
| Dart → Native | `clearCookies` | none | `null` |

### Instance Channel: `"custom_webview_flutter_<viewId>"`

One channel per `CustomWebViewWidget`. `<viewId>` is the integer assigned by `PlatformViewsService`.

#### Dart → Native Calls

| Method | Dart Arguments (Map keys) | Returns |
|---|---|---|
| `loadUrl` | `initialUrl: String`, `headers: Map?`, `javaScriptChannelNames: List?`, `isChart: bool?`, `zoomEnabled: bool?`, `enableMultipleWindows: bool?` | `null` |
| `loadHtmlData` | `htmlString: String`, `baseURL: String?`, `javaScriptChannelNames: List?`, `allowMixedContent: bool` | `null` |
| `addJavascriptChannel` | `channelName: String` | `null` |
| `removeJavascriptChannel` | `channelName: String` | `null` |
| `runJavaScript` | `script: String` | `dynamic` (JS result) |
| `reloadUrl` | none | `null` |
| `getCurrentUrl` | none | `String?` |
| `canGoBack` | none | `bool` |
| `goBack` | none | `null` |
| `setUserInteractionEnabled` | `enabled: bool` | `null` |
| `setCustomUserAgent` | `userAgent: String?` | `null` |
| `enableMultipleWindows` | `enabled: bool` | `null` |
| `setBackgroundColor` | `color: int` (ARGB) | `null` |

#### Native → Dart Callbacks

| Method | Arguments (Map keys) | Description |
|---|---|---|
| `onPageStarted` | `url: String` | Navigation started |
| `pageLoaded` | _(none / null)_ | iOS only: page loaded when `isChart: true`. Android never fires this. |
| `onPageFinished` | `url: String` | iOS: page loaded when `isChart: false`. Android: always fires on page load. |
| `onProgress` | `progress: int` (0–100) | Load progress update |
| `onReceivedError` | `message: String` | Navigation/resource error |
| `onJavascriptChannelMessageReceived` | `channelName: String`, `message: String` | JS channel message |
| `onNavigationRequest` | `url: String` | Navigation intercept — **must return `bool`** |
| `onJsAlert` | `url: String?`, `message: String?` | JavaScript `alert()` |
| `onTitleChanged` | `title: String` | Document title changed |

> **Adding a new method:** Follow the pattern — implement in Kotlin/Swift, handle the method string in the `when`/`switch` block, add the corresponding Dart method to `CustomWebViewController`, and update this table.

---

*Document generated from source: `lib/`, `ios/Classes/`, `android/src/main/kotlin/`. Verified against version `1.0.4+1`.*
