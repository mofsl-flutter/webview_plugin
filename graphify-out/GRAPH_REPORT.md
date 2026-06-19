# Graph Report - /Users/shikharjain/Development/Projects/webview_plugin  (2026-05-21)

## Corpus Check
- Corpus is ~6,562 words - fits in a single context window. You may not need a graph.

## Summary
- 148 nodes · 170 edges · 11 communities detected
- Extraction: 88% EXTRACTED · 12% INFERRED · 0% AMBIGUOUS · INFERRED: 21 edges (avg confidence: 0.88)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Android Factory & Bridge|Android Factory & Bridge]]
- [[_COMMUNITY_iOS WebView Manager|iOS WebView Manager]]
- [[_COMMUNITY_Android File & Platform Layer|Android File & Platform Layer]]
- [[_COMMUNITY_Android Chrome Client|Android Chrome Client]]
- [[_COMMUNITY_iOS Plugin Host|iOS Plugin Host]]
- [[_COMMUNITY_Android Advanced Behaviors|Android Advanced Behaviors]]
- [[_COMMUNITY_WebView Delegate Protocol|WebView Delegate Protocol]]
- [[_COMMUNITY_Coverage Tooling|Coverage Tooling]]
- [[_COMMUNITY_Test Layer|Test Layer]]
- [[_COMMUNITY_Documentation|Documentation]]
- [[_COMMUNITY_Release History|Release History]]

## God Nodes (most connected - your core abstractions)
1. `WebViewMoFlutter` - 27 edges
2. `WebViewManager` - 24 edges
3. `WebViewManager` - 20 edges
4. `CustomWebViewPlugin` - 14 edges
5. `WebViewControllerDelegate` - 10 edges
6. `iOS WebViewManager` - 9 edges
7. `iOS WebViewMoFlutter (PlatformView bridge)` - 8 edges
8. `Android WebViewManager` - 8 edges
9. `CustomWebViewFactory` - 7 edges
10. `Android CustomWebViewPlugin` - 6 edges

## Surprising Connections (you probably didn't know these)
- `iOS File Upload (UIDocumentPickerDelegate)` --semantically_similar_to--> `Android handleFileChooser`  [INFERRED] [semantically similar]
  ios/Classes/CustomWebViewPlugin.swift → android/src/main/kotlin/com/custom/webview_plugin/CustomWebViewFactory.kt
- `Thread Management Critical Notes` --rationale_for--> `iOS WebViewMoFlutter (PlatformView bridge)`  [INFERRED]
  CUSTOM_WEBVIEW_GUIDE.md → ios/Classes/CustomWebViewFactory.swift
- `CreationParams Performance Rationale` --rationale_for--> `iOS WebViewMoFlutter (PlatformView bridge)`  [INFERRED]
  CUSTOM_WEBVIEW_GUIDE.md → ios/Classes/CustomWebViewFactory.swift
- `Thread Management Critical Notes` --rationale_for--> `Android WebViewMoFlutter (PlatformView bridge)`  [INFERRED]
  CUSTOM_WEBVIEW_GUIDE.md → android/src/main/kotlin/com/custom/webview_plugin/CustomWebViewFactory.kt
- `Multi-Channel JavaScript Support` --rationale_for--> `Android WebViewManager`  [INFERRED]
  CUSTOM_WEBVIEW_GUIDE.md → android/src/main/kotlin/com/custom/webview_plugin/CustomWebViewFactory.kt

## Hyperedges (group relationships)
- **Cross-Platform WebView Bridge Pattern (Plugin + Factory + Manager)** — ios_customplugin_CustomWebViewPlugin, ios_factory_CustomWebViewFactory, ios_customplugin_WebViewManager, android_plugin_CustomWebViewPlugin, android_factory_CustomWebViewFactory, android_factory_WebViewManager [INFERRED 0.92]
- **Instance-Scoped Method Channel Pattern (Factory + MoFlutter + MethodChannel)** — ios_factory_WebViewMoFlutter, ios_factory_MethodChannel_instance, android_factory_WebViewMoFlutter, guide_instance_scoped_channels [INFERRED 0.90]
- **File Chooser Flow (WebViewManager triggers Plugin triggers ActivityResult)** — android_factory_handleFileChooser, android_plugin_launchFileChooser, android_plugin_activityResultListener, android_plugin_fileChooserCallback [EXTRACTED 0.95]

## Communities

### Community 0 - "Android Factory & Bridge"
Cohesion: 0.07
Nodes (6): CustomWebViewFactory, WebViewMoFlutter, FlutterPlatformView, FlutterPlatformViewFactory, NSObject, WebViewControllerDelegate

### Community 1 - "iOS WebView Manager"
Cohesion: 0.11
Nodes (5): WebViewManager, UIDocumentPickerDelegate, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate

### Community 2 - "Android File & Platform Layer"
Cohesion: 0.12
Nodes (21): Android CustomWebViewFactory, Android WebViewControllerDelegate Interface, Android WebViewMoFlutter (PlatformView bridge), Android handleFileChooser, Android CustomWebViewPlugin, Android Activity Result Listener (FILECHOOSER_RESULTCODE), Android fileChooserCallback (ValueCallback), Android launchFileChooser (+13 more)

### Community 3 - "Android Chrome Client"
Cohesion: 0.1
Nodes (1): WebViewManager

### Community 4 - "iOS Plugin Host"
Cohesion: 0.12
Nodes (4): AnyObject, CustomWebViewPlugin, WebViewControllerDelegate, FlutterPlugin

### Community 5 - "Android Advanced Behaviors"
Cohesion: 0.16
Nodes (16): Android WebViewManager, Android enqueueDownload (DownloadManager), Android handleCustomScheme (upi/intent/tel/mailto), Android showPopupWebView (AlertDialog popup), Android SSL Error Handler (proceed on error), Multi-Channel JavaScript Support, Synchronous Navigation Blocking Design, SSL and Security Design Rationale (+8 more)

### Community 6 - "WebView Delegate Protocol"
Cohesion: 0.2
Nodes (1): WebViewControllerDelegate

### Community 7 - "Coverage Tooling"
Cohesion: 0.5
Nodes (5): Skill: coverage-check SKILL.md, Coverage Threshold 90% (skill overrides plan's 80%), Skill Plan: coverage-check, Coverage Gaps (canGoBack, goBack, removeJSChannel, onTitleChanged, onNavRequest, pageLoaded, Widget), Coverage Threshold (80% pass, 60-79% warning, <60% fail)

### Community 8 - "Test Layer"
Cohesion: 0.67
Nodes (1): IosWebviewPluginTest

### Community 9 - "Documentation"
Cohesion: 1.0
Nodes (1): Flutter Plugin README

### Community 10 - "Release History"
Cohesion: 1.0
Nodes (1): CHANGELOG

## Knowledge Gaps
- **14 isolated node(s):** `iOS Global Method Channel (custom_webview_flutter)`, `iOS resetCache Method`, `iOS clearCookies Method`, `iOS KVO Progress Observer`, `Android Activity Result Listener (FILECHOOSER_RESULTCODE)` (+9 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Documentation`** (1 nodes): `Flutter Plugin README`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Release History`** (1 nodes): `CHANGELOG`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `WebViewManager` connect `iOS WebView Manager` to `Android Factory & Bridge`, `iOS Plugin Host`?**
  _High betweenness centrality (0.189) - this node is a cross-community bridge._
- **Why does `WebViewManager` connect `Android Chrome Client` to `Android Factory & Bridge`?**
  _High betweenness centrality (0.159) - this node is a cross-community bridge._
- **What connects `iOS Global Method Channel (custom_webview_flutter)`, `iOS resetCache Method`, `iOS clearCookies Method` to the rest of the system?**
  _14 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Android Factory & Bridge` be split into smaller, more focused modules?**
  _Cohesion score 0.07 - nodes in this community are weakly interconnected._
- **Should `iOS WebView Manager` be split into smaller, more focused modules?**
  _Cohesion score 0.11 - nodes in this community are weakly interconnected._
- **Should `Android File & Platform Layer` be split into smaller, more focused modules?**
  _Cohesion score 0.12 - nodes in this community are weakly interconnected._
- **Should `Android Chrome Client` be split into smaller, more focused modules?**
  _Cohesion score 0.1 - nodes in this community are weakly interconnected._