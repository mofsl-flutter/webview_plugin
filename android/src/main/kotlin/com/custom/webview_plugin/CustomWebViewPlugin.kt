package com.custom.webview_plugin

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel


class CustomWebViewPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler, WebViewControllerDelegate {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    private lateinit var webViewManager: WebViewManager
    private var activity: Activity? = null
    private lateinit var context: Context
    private val uiThreadHandler: Handler = Handler(Looper.getMainLooper())
    private lateinit var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        this.flutterPluginBinding = flutterPluginBinding
        context = flutterPluginBinding.applicationContext

        methodChannel =
            MethodChannel(flutterPluginBinding.binaryMessenger, "custom_webview_flutter").apply {
                setMethodCallHandler(this@CustomWebViewPlugin)
            }
        eventChannel = EventChannel(
            flutterPluginBinding.binaryMessenger,
            "custom_webview_plugin_events"
        ).apply {
            setStreamHandler(this@CustomWebViewPlugin)
        }

    }


    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        webViewManager = WebViewManager.getInstance(context, activity)
        flutterPluginBinding.platformViewRegistry.registerViewFactory(
            "custom_webview_flutter",
            CustomWebViewFactory(flutterPluginBinding.binaryMessenger, this, webViewManager)
        )
    }

    override fun onDetachedFromActivityForConfigChanges() {

    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {

    }

    override fun onDetachedFromActivity() {

    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d("CustomWebViewPlugin", "onDetachedFromEngine")
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        webViewManager.destroyWebView()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadUrl" -> {
                val urlString = call.argument<String>("initialUrl")
                val javaScriptChannelName = call.argument<String>("javaScriptChannelName")
                val zoomEnabled = call.argument<Boolean>("zoomEnabled")
                val enableMultipleWindows = call.argument<Boolean>("enableMultipleWindows")
                if (urlString != null) {
                    webViewManager.loadURL(urlString, javaScriptChannelName)
                    webViewManager.enableZoom(zoomEnabled ?: false)
                    webViewManager.enableMultipleWindows(enableMultipleWindows ?: false)
                    result.success(null)
                } else {
                    result.error("INVALID_ARGUMENT", "URL is required", null)
                }
            }

            "loadHtmlData" -> {
                val htmlContent = call.argument<String>("htmlString")
                val javaScriptChannelName = call.argument<String>("javaScriptChannelName")
                if (htmlContent != null) {
                    webViewManager.loadHtmlContent(htmlContent, javaScriptChannelName)
                    result.success(null)
                } else {
                    result.error("INVALID_ARGUMENT", "HTML content is required", null)
                }
            }

            "runJavaScript" -> {
                val script = call.argument<String>("script")
                if (script != null) {
                    webViewManager.evaluateJavaScript(script) { response, error ->
                        if (error != null) {
                            result.error("JAVASCRIPT_ERROR", error.localizedMessage, null)
                        } else {
                            result.success(response)
                        }
                    }
                } else {
                    result.error("INVALID_ARGUMENT", "JavaScript code is required", null)
                }
            }

            "reloadUrl" -> {
                webViewManager.webView?.reload()
                result.success(null)
            }

            "resetCache" -> {
                webViewManager.resetWebViewCache()
                result.success(null)
            }

            "addJavascriptChannel" -> {
                val channelName = call.argument<String>("channelName")
                if (channelName != null) {
                    webViewManager.addJavascriptChannel(channelName)
                    result.success(null)
                } else {
                    result.error("INVALID_ARGUMENT", "Channel name is required", null)
                }
            }

            "getCurrentUrl" -> {
                result.success(webViewManager.webView?.url)
            }

            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        webViewManager.delegate = this
    }

    override fun onCancel(arguments: Any?) {
        Log.d("CustomWebViewPlugin", "onCancel")

        eventSink = null
        webViewManager.delegate = null
    }

    override fun pageDidLoad() {
        eventSink?.success("pageLoaded")
    }

    override fun onMessageReceived(message: String) {
        uiThreadHandler.post {
            eventSink?.success(message)
        }
    }

    override fun onJavascriptChannelMessageReceived(channelName: String, message: String) {
        uiThreadHandler.post {
            eventSink?.success(
                mapOf(
                    "event" to "javascriptChannelMessageReceived",
                    "channelName" to channelName,
                    "message" to message
                )
            )
        }
    }

    override fun onNavigationRequest(url: String) {
        uiThreadHandler.post {
            eventSink?.success(mapOf("event" to "navigationRequest", "url" to url))
        }
    }

    override fun onPageFinished(url: String) {
        uiThreadHandler.post {
            eventSink?.success(mapOf("event" to "pageFinished", "url" to url))
        }
    }

    override fun onReceivedError(message: String) {
        uiThreadHandler.post {
            eventSink?.success(mapOf("event" to "error", "message" to message))
        }
    }

    override fun onJsAlert(url: String?, message: String?) {
        uiThreadHandler.post {
            eventSink?.success(mapOf("event" to "onJsAlert", "url" to url, "message" to message))
        }
    }


}
