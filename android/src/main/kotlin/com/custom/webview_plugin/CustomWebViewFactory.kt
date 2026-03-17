package com.custom.webview_plugin

import android.annotation.SuppressLint
import android.app.Activity
import android.app.AlertDialog
import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Message
import android.util.Base64
import android.util.Log
import android.view.ViewGroup
import android.view.WindowManager
import android.webkit.ConsoleMessage
import android.webkit.JavascriptInterface
import android.webkit.JsResult
import android.webkit.PermissionRequest
import android.webkit.URLUtil
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory



class CustomWebViewFactory(
    private val messenger: BinaryMessenger,
    private val delegate: WebViewControllerDelegate?,
    private val webViewManager: WebViewManager
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return WebViewMoFlutter(context, viewId, args, messenger, delegate, webViewManager)
    }
}

class WebViewMoFlutter(
    context: Context,
    viewId: Int,
    args: Any?,
    messenger: BinaryMessenger,
    private val delegate: WebViewControllerDelegate?,
    private val webViewManager: WebViewManager
) : PlatformView {

    private val webView: WebView = webViewManager.getOrCreateWebView()

    init {
        // Initialization handled by WebViewManager
    }

    override fun getView(): WebView = webView

    override fun dispose() {
        Log.d("CustomWebViewPlugin", "dispose")
        webViewManager.destroyWebView()
    }
}

val FILECHOOSER_RESULTCODE = 1

class WebViewManager private constructor(
    private val context: Context,
    private val activity: Activity?
) {

    var delegate: WebViewControllerDelegate? = null
    var webView: WebView? = null
    private val configuredJavaScriptChannels: MutableSet<String> = mutableSetOf()
    private var isWebViewPaused: Boolean = false

    private var mUploadMessage: ValueCallback<Array<Uri>>? = null
    private var mUploadMessageArray: ValueCallback<Array<Uri?>>? = null
    val fileUri: Uri? = null
    val videoUri: Uri? = null


    private val fileChooserLauncher = activity?.let {
        (it as? ComponentActivity)?.registerForActivityResult(
            ActivityResultContracts.StartActivityForResult()
        ) { result: ActivityResult ->
            if (result.resultCode == Activity.RESULT_OK) {
                Log.d("CustomWebViewPlugin", "ActivityResult === ${result.data}")
                val data: Intent? = result.data
                val results: Array<Uri>? = data?.data?.let { arrayOf(it) }
                mUploadMessage?.onReceiveValue(results)
            } else {
                Log.d("CustomWebViewPlugin", "ActivityResult === ${result.data}")
                mUploadMessage?.onReceiveValue(null)
            }
        }
    }

    fun openFileChooser() {
        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }
        val chooserIntent = Intent.createChooser(intent, "Choose a file")

        fileChooserLauncher?.launch(chooserIntent)
    }

    fun setFilePathCallback(callback: ValueCallback<Array<Uri>>) {
        mUploadMessage = callback
    }


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
                fileChooserParams: FileChooserParams
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
        Log.d("CustomWebViewPlugin", "onShowFileChooser === ${fileChooserParams.mode}")
        val acceptTypes = arrayOf("application/pdf", "image/*", "video/*", "*/*")
        val mimeTypes = fileChooserParams.acceptTypes?.joinToString(",") ?: ""
        if (acceptTypes.contains(mimeTypes) && !mimeTypes.contains("text/vcard")) {
            setFilePathCallback(filePathCallback)
            openFileChooser()
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
                Log.d("WebPageActivity", "Popup WebView URL: ${request?.url}")
                val url = request?.url.toString()
                if (url.endsWith(".pdf") || url.contains("download")) {
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
                Log.d("WebPageActivity", "Popup WebView closed")
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
            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                delegate?.onPageFinished(url ?: "")
            }

            override fun shouldOverrideUrlLoading(
                view: WebView?,
                request: WebResourceRequest?
            ): Boolean {
                Log.d("CustomWebViewPlugin", "shouldOverrideUrlLoading === ${view?.url}")
                val url = request?.url.toString()
                when {
                    url.endsWith(".pdf") || url.contains("download") || url.contains("SH=") -> {
                        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                        return true
                    }
                    url.startsWith("tel:") -> {
                        context.startActivity(Intent(Intent.ACTION_DIAL, Uri.parse(url)))
                        return true
                    }
                    url.startsWith("mailto:") -> {
                        context.startActivity(Intent(Intent.ACTION_SENDTO, Uri.parse(url)))
                        return true
                    }
                }
                return false
            }

            override fun onReceivedError(
                view: WebView?,
                request: WebResourceRequest?,
                error: WebResourceError?
            ) {
                super.onReceivedError(view, request, error)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    if (error?.description.toString() != "net::ERR_NAME_NOT_RESOLVED") {
                        error?.let { delegate?.onReceivedError(it.description.toString()) }
                    }
                } else {
                    delegate?.onReceivedError("error")
                }
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


    fun loadHtmlContent(htmlContent: String, javaScriptChannelName: String?) {
        Log.d("CustomWebViewPlugin", "HTML content being loaded: $htmlContent")
        webView = getOrCreateWebView()
        if (htmlContent.isEmpty()) {
            Log.e("CustomWebViewPlugin", "HTML content is empty!")
            return
        }

        // Ensure JavaScript channel is added if specified
        if (!javaScriptChannelName.isNullOrEmpty()) {
            addJavascriptChannel(javaScriptChannelName)
        }

        // Load HTML content using loadDataWithBaseURL for better compatibility
        webView?.loadData( htmlContent, "text/html", "UTF-8")

        if (isWebViewPaused) {
            resumeWebView()
        }
    }


    fun loadURL(urlString: String, javaScriptChannelName: String?) {
        Log.d("CustomWebViewPlugin", "loadURL : $urlString")
        if (urlString.isNotEmpty()) {
            if (javaScriptChannelName != null) {
                addJavascriptChannel(javaScriptChannelName)
            }
            webView?.loadUrl(urlString)
        }
        if (isWebViewPaused) resumeWebView()
    }

    fun enableZoom(isZoomEnable: Boolean) {
        Log.d("CustomWebViewPlugin", "enableZoom : $isZoomEnable")
        webView?.settings?.setSupportZoom(isZoomEnable)
        webView?.settings?.builtInZoomControls = isZoomEnable
        webView?.getSettings()?.setSupportZoom(isZoomEnable)
        webView?.getSettings()?.builtInZoomControls = isZoomEnable
        webView?.getSettings()?.displayZoomControls = false
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
                delegate?.onJavascriptChannelMessageReceived(name, message)
            }
        }, name)
        configuredJavaScriptChannels.add(name)
        return true
    }

    fun destroyWebView() {
        isWebViewPaused = true
        Log.d("CustomWebViewPlugin", "destroyWebView")
        webView?.apply {
            destroy()
        }
        webView = null
    }

    fun resumeWebView() {
        isWebViewPaused = false
        webView?.onResume()
        webView?.resumeTimers()
    }

    companion object {
        private var INSTANCE: WebViewManager? = null

        fun getInstance(context: Context, activity: Activity?): WebViewManager {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: WebViewManager(context.applicationContext, activity).also {
                    INSTANCE = it
                }
            }
        }
    }

}

interface WebViewControllerDelegate {
    fun pageDidLoad()
    fun onMessageReceived(message: String)
    fun onJavascriptChannelMessageReceived(channelName: String, message: String)
    fun onNavigationRequest(url: String)
    fun onPageFinished(url: String)
    fun onReceivedError(message: String)
    fun onJsAlert(url: String?, message: String?)
}
