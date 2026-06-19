import "package:flutter/foundation.dart";
import "package:flutter/gestures.dart";
import "package:flutter/rendering.dart";
import "package:flutter/services.dart";
import "package:flutter/widgets.dart";

import "custom_webview_controller.dart";

/// Global plugin class for non-instance specific actions.
class CustomWebViewPlugin {
  static const MethodChannel _channel = MethodChannel("custom_webview_flutter");

  /// Resets the web view's cache globally.
  static Future<void> resetCache() async {
    try {
      await _channel.invokeMethod<void>("resetCache");
    } on PlatformException catch (e) {
      debugPrint("Failed to reset cache: ${e.message}");
      rethrow;
    }
  }
}

/// A widget that displays a native web view.
class CustomWebViewWidget extends StatefulWidget {
  /// Creates a [CustomWebViewWidget].
  const CustomWebViewWidget({
    required this.controller,
    super.key,
    this.initialUrl,
    this.initialHeaders,
    this.javascriptChannelNames,
    this.isChart = true,
    this.zoomEnabled = true,
    this.enableMultipleWindows = true,
  });

  /// The controller that manages this web view.
  final CustomWebViewController controller;

  /// The initial URL to load.
  final String? initialUrl;

  /// The initial headers to send with the initial URL.
  final Map<String, String>? initialHeaders;

  /// The names of the initial JavaScript channels to add.
  final List<String>? javascriptChannelNames;

  /// Whether the web view is being used for a chart.
  final bool isChart;

  /// Whether zoom is enabled.
  final bool zoomEnabled;

  /// Whether multiple windows support is enabled.
  final bool enableMultipleWindows;

  @override
  State<CustomWebViewWidget> createState() => _CustomWebViewWidgetState();
}

class _CustomWebViewWidgetState extends State<CustomWebViewWidget> {
  @override
  Widget build(BuildContext context) {
    const String viewType = "custom_webview_flutter";
    final Map<String, dynamic> creationParams = <String, dynamic>{
      "initialUrl": widget.initialUrl,
      "headers": widget.initialHeaders,
      "javaScriptChannelNames": widget.javascriptChannelNames,
      "isChart": widget.isChart,
      "zoomEnabled": widget.zoomEnabled,
      "enableMultipleWindows": widget.enableMultipleWindows,
    };

    if (defaultTargetPlatform == TargetPlatform.android) {
      return PlatformViewLink(
        viewType: viewType,
        surfaceFactory: (context, controller) {
          return AndroidViewSurface(
            controller: controller as AndroidViewController,
            gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
          );
        },
        onCreatePlatformView: (params) {
          return PlatformViewsService.initSurfaceAndroidView(
            id: params.id,
            viewType: viewType,
            layoutDirection: TextDirection.ltr,
            creationParams: creationParams,
            creationParamsCodec: const StandardMessageCodec(),
            onFocus: () {
              params.onFocusChanged(true);
            },
          )
            ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
            ..addOnPlatformViewCreatedListener((int id) {
              widget.controller.setViewId(id);
            })
            ..create();
        },
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: viewType,
        onPlatformViewCreated: (int id) {
          widget.controller.setViewId(id);
        },
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
      );
    }

    return Text("${defaultTargetPlatform} is not yet supported by the webview_plugin");
  }
}
