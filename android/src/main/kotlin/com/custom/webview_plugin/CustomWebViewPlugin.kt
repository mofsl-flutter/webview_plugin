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


class CustomWebViewPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {

    private lateinit var methodChannel: MethodChannel
    private var activity: Activity? = null
    private lateinit var context: Context
    private lateinit var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        this.flutterPluginBinding = flutterPluginBinding
        context = flutterPluginBinding.applicationContext

        methodChannel =
            MethodChannel(flutterPluginBinding.binaryMessenger, "custom_webview_flutter").apply {
                setMethodCallHandler(this@CustomWebViewPlugin)
            }
    }


    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        flutterPluginBinding.platformViewRegistry.registerViewFactory(
            "custom_webview_flutter",
            CustomWebViewFactory(flutterPluginBinding.binaryMessenger, activity)
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
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "resetCache" -> {
                // Global cache reset logic if needed
                android.webkit.CookieManager.getInstance().removeAllCookies(null)
                android.webkit.WebStorage.getInstance().deleteAllData()
                result.success(null)
            }
            "clearCookies" -> {
                android.webkit.CookieManager.getInstance().removeAllCookies(null)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

}
