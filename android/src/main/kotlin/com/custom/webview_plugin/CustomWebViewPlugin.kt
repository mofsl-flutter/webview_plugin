package com.custom.webview_plugin

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import android.webkit.ValueCallback
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel


class CustomWebViewPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {

    private lateinit var methodChannel: MethodChannel
    private var activity: Activity? = null
    private lateinit var context: Context

    // Always-current Activity. Kept fresh by the Activity* lifecycle callbacks below, so the
    // platform view can resolve the LIVE Activity at WebView/dialog creation time instead of a
    // value frozen when the factory was first registered.
    val activeActivity: Activity? get() = activity
    private lateinit var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding
    private var activityPluginBinding: ActivityPluginBinding? = null

    internal var fileChooserCallback: ValueCallback<Array<Uri>>? = null

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
        activityPluginBinding = binding

        // Register the activity result listener here — before the Activity reaches STARTED.
        // This avoids the IllegalStateException caused by registerForActivityResult being
        // called in a platform view constructor (which fires when Activity is already RESUMED).
        binding.addActivityResultListener { requestCode, resultCode, data ->
            if (requestCode == FILECHOOSER_RESULTCODE) {
                val cb = fileChooserCallback
                fileChooserCallback = null
                if (resultCode == Activity.RESULT_OK) {
                    val results = data?.data?.let { arrayOf(it) }
                    cb?.onReceiveValue(results)
                } else {
                    cb?.onReceiveValue(null)
                }
                true
            } else {
                false
            }
        }

        flutterPluginBinding.platformViewRegistry.registerViewFactory(
            "custom_webview_flutter",
            CustomWebViewFactory(flutterPluginBinding.binaryMessenger, activity, this)
        )
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityPluginBinding = binding
    }

    override fun onDetachedFromActivity() {
        fileChooserCallback = null
        activityPluginBinding = null
        activity = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d("CustomWebViewPlugin", "onDetachedFromEngine")
        methodChannel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "resetCache" -> {
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

    @Suppress("DEPRECATION")
    internal fun launchFileChooser() {
        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }
        activity?.startActivityForResult(
            Intent.createChooser(intent, "Choose a file"),
            FILECHOOSER_RESULTCODE
        )
    }
}
