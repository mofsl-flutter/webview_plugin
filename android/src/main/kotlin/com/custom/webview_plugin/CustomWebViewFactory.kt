package com.custom.webview_plugin

import android.annotation.SuppressLint
import android.app.Activity
import android.app.AlertDialog
import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.http.SslError
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.util.Base64
import android.util.Log
import android.view.ViewGroup
import android.view.WindowManager
import android.webkit.ConsoleMessage
import android.webkit.JavascriptInterface
import android.webkit.JsResult
import android.webkit.PermissionRequest
import android.webkit.SslErrorHandler
import android.webkit.URLUtil
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory


class CustomWebViewFactory(
    private val messenger: BinaryMessenger,
    private val activity: Activity?,
    private val plugin: CustomWebViewPlugin
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return WebViewMoFlutter(context, viewId, args, messenger, activity, plugin)
    }
}

class WebViewMoFlutter(
    context: Context,
    viewId: Int,
    args: Any?,
    messenger: BinaryMessenger,
    private val activity: Activity?,
    private val plugin: CustomWebViewPlugin
) : PlatformView, MethodChannel.MethodCallHandler, WebViewControllerDelegate {

    private val webViewManager: WebViewManager = WebViewManager(context, activity, plugin)
    private val webView: WebView = webViewManager.getOrCreateWebView()
    private val methodChannel: MethodChannel = MethodChannel(messenger, "custom_webview_flutter_$viewId")
    private var isReloadingFromDart = false

    init {
        methodChannel.setMethodCallHandler(this)
        webViewManager.delegate = this

        if (args is Map<*, *>) {
            val initialUrl = args["initialUrl"] as? String
            val headers = args["headers"] as? Map<String, String>
            val jsChannels = (args["javaScriptChannelNames"] as? List<*>)?.filterIsInstance<String>() ?: emptyList()
            val zoomEnabled = args["zoomEnabled"] as? Boolean ?: true
            val multipleWindows = args["enableMultipleWindows"] as? Boolean ?: true

            webViewManager.enableZoom(zoomEnabled)
            webViewManager.enableMultipleWindows(multipleWindows)
            if (initialUrl != null) {
                webViewManager.loadURL(initialUrl, jsChannels, headers)
            }
        }
    }

    override fun getView(): WebView = webView

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadUrl" -> handleLoadUrl(call, result)
            "loadHtmlData" -> handleLoadHtmlData(call, result)
            "runJavaScript" -> handleRunJavaScript(call, result)
            "reloadUrl" -> { webViewManager.webView?.reload(); result.success(null) }
            "resetCache" -> { webViewManager.resetWebViewCache(); result.success(null) }
            "addJavascriptChannel" -> handleAddJavascriptChannel(call, result)
            "removeJavascriptChannel" -> {
                val channelName = call.argument<String>("channelName")
                if (channelName != null) {
                    webViewManager.webView?.removeJavascriptInterface(channelName)
                }
                result.success(null)
            }
            "getCurrentUrl" -> result.success(webViewManager.webView?.url)
            "canGoBack" -> result.success(webViewManager.webView?.canGoBack() ?: false)
            "goBack" -> { webViewManager.webView?.goBack(); result.success(null) }
            "setCustomUserAgent" -> {
                val userAgent = call.argument<String>("userAgent")
                webViewManager.webView?.settings?.userAgentString = userAgent
                result.success(null)
            }
            "enableMultipleWindows" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                webViewManager.enableMultipleWindows(enabled)
                result.success(null)
            }
            "setUserInteractionEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: true
                webViewManager.webView?.isClickable = enabled
                webViewManager.webView?.isEnabled = enabled
                result.success(null)
            }
            "setBackgroundColor" -> {
                val color = call.argument<Int>("color")
                if (color != null) {
                    activity?.runOnUiThread {
                        webViewManager.webView?.setBackgroundColor(color)
                    }
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun handleLoadUrl(call: MethodCall, result: MethodChannel.Result) {
        val urlString = call.argument<String>("initialUrl")
        if (urlString != null) {
            val jsChannels = call.argument<List<String>>("javaScriptChannelNames") ?: emptyList()
            val zoomEnabled = call.argument<Boolean>("zoomEnabled")
            val enableMultipleWindows = call.argument<Boolean>("enableMultipleWindows")
            val headers = call.argument<Map<String, String>>("headers")
            webViewManager.loadURL(urlString, jsChannels, headers)
            webViewManager.enableZoom(zoomEnabled ?: false)
            webViewManager.enableMultipleWindows(enableMultipleWindows ?: false)
            result.success(null)
        } else {
            result.error("INVALID_ARGUMENT", "URL is required", null)
        }
    }

    private fun handleLoadHtmlData(call: MethodCall, result: MethodChannel.Result) {
        val htmlContent = call.argument<String>("htmlString") ?: run {
            result.error("INVALID_ARGUMENT", "HTML content is required", null)
            return
        }
        val jsChannels = call.argument<List<String>>("javaScriptChannelNames") ?: emptyList()
        val baseURL = call.argument<String>("baseURL")
        val allowMixedContent = call.argument<Boolean>("allowMixedContent") ?: false

        if (allowMixedContent && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            webViewManager.webView?.settings?.mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
        }
        webViewManager.loadHtmlContent(htmlContent, jsChannels, baseURL)
        result.success(null)
    }

    private fun handleRunJavaScript(call: MethodCall, result: MethodChannel.Result) {
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

    private fun handleAddJavascriptChannel(call: MethodCall, result: MethodChannel.Result) {
        val channelName = call.argument<String>("channelName")
        if (channelName != null) {
            webViewManager.addJavascriptChannel(channelName)
            result.success(null)
        } else {
            result.error("INVALID_ARGUMENT", "Channel name is required", null)
        }
    }

    override fun dispose() {
        Log.d("CustomWebViewPlugin", "dispose")
        methodChannel.setMethodCallHandler(null)
        webViewManager.destroyWebView()
    }

    override fun pageDidLoad() {
        methodChannel.invokeMethod("pageLoaded", null)
    }

    override fun onMessageReceived(message: String) {
        methodChannel.invokeMethod("onMessageReceived", message)
    }

    override fun onJavascriptChannelMessageReceived(channelName: String, message: String) {
        methodChannel.invokeMethod(
            "onJavascriptChannelMessageReceived",
            mapOf("channelName" to channelName, "message" to message)
        )
    }

    override fun onNavigationRequest(url: String): Boolean {
        if (isReloadingFromDart) {
            isReloadingFromDart = false
            return true
        }

        activity?.runOnUiThread {
            methodChannel.invokeMethod("onNavigationRequest", mapOf("url" to url), object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (result as? Boolean == true) {
                        isReloadingFromDart = true
                        webViewManager.webView?.loadUrl(url)
                    }
                }
                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}
                override fun notImplemented() {}
            })
        }
        return false
    }

    override fun onPageStarted(url: String) {
        methodChannel.invokeMethod("onPageStarted", mapOf("url" to url))
    }

    override fun onPageFinished(url: String) {
        methodChannel.invokeMethod("onPageFinished", mapOf("url" to url))
    }

    override fun onProgress(progress: Int) {
        methodChannel.invokeMethod("onProgress", mapOf("progress" to progress))
    }

    override fun onReceivedError(message: String) {
        methodChannel.invokeMethod("onReceivedError", mapOf("message" to message))
    }

    override fun onJsAlert(url: String?, message: String?) {
        methodChannel.invokeMethod("onJsAlert", mapOf("url" to url, "message" to message))
    }
}

val FILECHOOSER_RESULTCODE = 1

class WebViewManager(
    private val context: Context,
    private val activity: Activity?,
    private val plugin: CustomWebViewPlugin
) {

    var delegate: WebViewControllerDelegate? = null
    var webView: WebView? = null
    private val configuredJavaScriptChannels: MutableSet<String> = mutableSetOf()
    private var isWebViewPaused: Boolean = false

    @SuppressLint("SetJavaScriptEnabled")
    fun getOrCreateWebView(): WebView {
        if (webView == null) {
            configuredJavaScriptChannels.clear()
            webView = WebView(activity ?: context).apply {
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.cacheMode = WebSettings.LOAD_DEFAULT
                settings.javaScriptCanOpenWindowsAutomatically = true
                webChromeClient = createWebChromeClient()
                webViewClient = createWebViewClient()
            }
            webView!!.setDownloadListener { url, userAgent, contentDisposition, mimeType, _ ->
                enqueueDownload(url, userAgent, contentDisposition, mimeType)
            }
        }
        return webView!!
    }

    private fun createWebChromeClient(): WebChromeClient {
        return object : WebChromeClient() {
            override fun onProgressChanged(view: WebView?, newProgress: Int) {
                super.onProgressChanged(view, newProgress)
                delegate?.onProgress(newProgress)
            }

            override fun onConsoleMessage(consoleMessage: ConsoleMessage): Boolean {
                Log.d(
                    "CustomWebViewPlugin",
                    "WebViewConsole: ${consoleMessage.message()} at " +
                        "${consoleMessage.sourceId()}:${consoleMessage.lineNumber()}"
                )
                return true
            }

            override fun onJsAlert(
                view: WebView?,
                url: String?,
                message: String?,
                result: JsResult?
            ): Boolean {
                delegate?.onJsAlert(url, message)
                return true
            }

            override fun onPermissionRequest(request: PermissionRequest?) {
                request?.grant(request.resources)
            }

            override fun onShowFileChooser(
                webView: WebView?,
                filePathCallback: ValueCallback<Array<Uri>>,
                fileChooserParams: WebChromeClient.FileChooserParams
            ): Boolean {
                handleFileChooser(filePathCallback, fileChooserParams)
                return true
            }

            override fun onCreateWindow(
                view: WebView?,
                isDialog: Boolean,
                isUserGesture: Boolean,
                resultMsg: Message?
            ): Boolean {
                return showPopupWebView(resultMsg)
            }
        }
    }

    private fun handleFileChooser(
        filePathCallback: ValueCallback<Array<Uri>>,
        fileChooserParams: WebChromeClient.FileChooserParams
    ) {
        val acceptTypes = arrayOf("application/pdf", "image/*", "video/*", "*/*")
        val mimeTypes = fileChooserParams.acceptTypes?.joinToString(",") ?: ""
        if (acceptTypes.contains(mimeTypes) && !mimeTypes.contains("text/vcard")) {
            plugin.fileChooserCallback = filePathCallback
            plugin.launchFileChooser()
        }
    }

    private fun showPopupWebView(resultMsg: Message?): Boolean {
        val popupWebView = WebView(activity ?: context).apply {
            settings.javaScriptEnabled = true
            settings.javaScriptCanOpenWindowsAutomatically = true
            settings.setSupportMultipleWindows(true)
        }
        popupWebView.webViewClient = createPopupWebViewClient()
        popupWebView.webChromeClient = createPopupWebChromeClient(popupWebView)
        val dialog = AlertDialog.Builder(activity ?: context).apply {
            setView(popupWebView)
            setOnDismissListener { popupWebView.destroy() }
        }.setPositiveButton("Close") { dialogInterface, _ ->
            (popupWebView.parent as ViewGroup).removeView(popupWebView)
            dialogInterface.dismiss()
        }.create()
        dialog.window?.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        dialog.show()
        val transport = resultMsg!!.obj as WebView.WebViewTransport
        transport.webView = popupWebView
        resultMsg.sendToTarget()
        return true
    }

    private fun createPopupWebViewClient(): WebViewClient {
        return object : WebViewClient() {
            override fun shouldOverrideUrlLoading(
                view: WebView?,
                request: WebResourceRequest?
            ): Boolean {
                val url = request?.url.toString()
                val scheme = request?.url?.scheme?.lowercase() ?: ""
                if (scheme !in setOf("http", "https", "file", "data", "javascript", "about", "chrome")) {
                    return handleCustomScheme(url, scheme)
                }
                if (isPdfUrl(url) || url.contains("download")) {
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                    return true
                }
                return false
            }
        }
    }

    private fun createPopupWebChromeClient(popupWebView: WebView): WebChromeClient {
        return object : WebChromeClient() {
            override fun onCloseWindow(window: WebView) {
                popupWebView.destroy()
            }

            override fun onJsAlert(
                view: WebView?,
                url: String?,
                message: String?,
                result: JsResult?
            ): Boolean {
                delegate?.onJsAlert(url, message)
                return true
            }

            override fun onPermissionRequest(request: PermissionRequest?) {
                request?.grant(request.resources)
            }

            override fun onShowFileChooser(
                webView: WebView?,
                filePathCallback: ValueCallback<Array<Uri>>,
                fileChooserParams: WebChromeClient.FileChooserParams
            ): Boolean {
                handleFileChooser(filePathCallback, fileChooserParams)
                return true
            }
        }
    }

    private fun createWebViewClient(): WebViewClient {
        return object : WebViewClient() {
            override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                super.onPageStarted(view, url, favicon)
                delegate?.onPageStarted(url ?: "")
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                delegate?.onPageFinished(url ?: "")
            }

            override fun shouldOverrideUrlLoading(
                view: WebView?,
                request: WebResourceRequest?
            ): Boolean {
                val url = request?.url.toString()
                val scheme = request?.url?.scheme?.lowercase() ?: ""
                Log.d("CustomWebViewPlugin", "shouldOverrideUrlLoading === $url")

                // Handle all non-web schemes natively BEFORE the Dart round-trip.
                // Covers upi:, intent:, tel:, mailto:, sms:, market:, whatsapp:, etc.
                if (scheme !in setOf("http", "https", "file", "data", "javascript", "about", "chrome")) {
                    return handleCustomScheme(url, scheme)
                }

                // PDF downloads — open externally
                if (isPdfUrl(url)) {
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                    return true
                }

                // For http/https: let Dart decide via onNavigationRequest
                if (delegate?.onNavigationRequest(url) == false) {
                    return true
                }

                return false
            }

            override fun onReceivedError(
                view: WebView?,
                request: WebResourceRequest?,
                error: WebResourceError?
            ) {
                super.onReceivedError(view, request, error)
                if (request?.isForMainFrame != true) return

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    error?.let { delegate?.onReceivedError(it.description.toString()) }
                } else {
                    delegate?.onReceivedError("error")
                }
            }

            override fun onReceivedSslError(view: WebView?, handler: SslErrorHandler?, error: SslError?) {
                handler?.proceed()
            }
        }
    }

    private fun enqueueDownload(
        url: String,
        userAgent: String,
        contentDisposition: String,
        mimeType: String
    ) {
        val request = DownloadManager.Request(Uri.parse(url))
        request.setMimeType(mimeType)
        request.addRequestHeader("User-Agent", userAgent)
        request.setTitle(URLUtil.guessFileName(url, contentDisposition, mimeType))
        request.setDescription("Downloading file...")
        request.setNotificationVisibility(
            DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED
        )
        request.setDestinationInExternalPublicDir(
            Environment.DIRECTORY_DOWNLOADS,
            URLUtil.guessFileName(url, contentDisposition, mimeType)
        )
        val dm = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        dm.enqueue(request)
    }

    fun loadHtmlContent(htmlContent: String, javaScriptChannelNames: List<String>, baseURL: String? = null) {
        webView = getOrCreateWebView()
        if (htmlContent.isEmpty()) return

        javaScriptChannelNames.forEach { addJavascriptChannel(it) }

        if (baseURL != null) {
            webView?.loadDataWithBaseURL(baseURL, htmlContent, "text/html", "UTF-8", null)
        } else {
            webView?.loadDataWithBaseURL(null, htmlContent, "text/html", "UTF-8", null)
        }

        if (isWebViewPaused) {
            resumeWebView()
        }
    }

    fun loadURL(urlString: String, javaScriptChannelNames: List<String>, headers: Map<String, String>? = null) {
        Log.d("CustomWebViewPlugin", "loadURL : $urlString")
        if (urlString.isNotEmpty()) {
            javaScriptChannelNames.forEach { addJavascriptChannel(it) }
            if (headers != null && headers.isNotEmpty()) {
                webView?.loadUrl(urlString, headers)
            } else {
                webView?.loadUrl(urlString)
            }
        }
        if (isWebViewPaused) resumeWebView()
    }

    fun enableZoom(isZoomEnable: Boolean) {
        webView?.settings?.setSupportZoom(isZoomEnable)
        webView?.settings?.builtInZoomControls = isZoomEnable
        webView?.settings?.displayZoomControls = false
    }

    fun enableMultipleWindows(isMultipleWindowsEnable: Boolean) {
        webView?.settings?.setSupportMultipleWindows(isMultipleWindowsEnable)
    }

    fun evaluateJavaScript(script: String, completionHandler: (Any?, Throwable?) -> Unit) {
        if (isWebViewPaused) resumeWebView()
        webView?.evaluateJavascript(script) { result ->
            completionHandler(result, null)
        }
    }

    fun resetWebViewCache() {
        webView?.clearCache(true)
    }

    fun addJavascriptChannel(name: String): Boolean {
        if (configuredJavaScriptChannels.contains(name)) return false
        Log.d("CustomWebViewPlugin", "addJavascriptChannel === $name")
        webView?.addJavascriptInterface(object : Any() {
            @JavascriptInterface
            fun postMessage(message: String) {
                Handler(Looper.getMainLooper()).post {
                    delegate?.onJavascriptChannelMessageReceived(name, message)
                }
            }
        }, name)
        configuredJavaScriptChannels.add(name)
        return true
    }

    private fun isPdfUrl(url: String) = url.lowercase().let {
        it.endsWith(".pdf") || it.contains(".pdf?") || it.contains("SH=")
    }

    private fun handleCustomScheme(url: String, scheme: String): Boolean {
        return try {
            val intent = if (scheme == "intent") {
                Intent.parseUri(url, Intent.URI_INTENT_SCHEME)
            } else {
                Intent(Intent.ACTION_VIEW, Uri.parse(url))
            }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

            if (intent.resolveActivity(context.packageManager) != null) {
                context.startActivity(intent)
            } else if (scheme == "intent") {
                val fallbackUrl = intent.getStringExtra("browser_fallback_url")
                if (!fallbackUrl.isNullOrEmpty()) {
                    webView?.loadUrl(fallbackUrl)
                } else {
                    Log.w("CustomWebViewPlugin", "No app for intent and no fallback: $url")
                }
            } else {
                Log.w("CustomWebViewPlugin", "No app found for scheme '$scheme': $url")
            }
            true
        } catch (e: Exception) {
            Log.e("CustomWebViewPlugin", "Failed to handle scheme '$scheme': $url", e)
            true
        }
    }

    fun destroyWebView() {
        isWebViewPaused = true
        Log.d("CustomWebViewPlugin", "destroyWebView")
        webView?.destroy()
        webView = null
    }

    fun resumeWebView() {
        isWebViewPaused = false
        webView?.onResume()
        webView?.resumeTimers()
    }
}

interface WebViewControllerDelegate {
    fun pageDidLoad()
    fun onMessageReceived(message: String)
    fun onJavascriptChannelMessageReceived(channelName: String, message: String)
    fun onNavigationRequest(url: String): Boolean
    fun onPageStarted(url: String)
    fun onPageFinished(url: String)
    fun onProgress(progress: Int)
    fun onReceivedError(message: String)
    fun onJsAlert(url: String?, message: String?)
}
