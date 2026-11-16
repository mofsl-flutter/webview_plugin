package com.custom.webview_plugin

import android.content.Context
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.util.Log

/**
 * Logging for the plugin that stays out of release builds.
 *
 * URLs handled here carry session tokens (SSO links, signed redirect URLs), and pages log
 * freely to the console, so verbose logs are written only when the host app is debuggable.
 * Warnings and errors are always written, but with URLs reduced to scheme, host and path.
 *
 * Debuggability is read from the host app's ApplicationInfo rather than this library's
 * BuildConfig, which is not generated for library modules on recent AGP versions and would
 * reflect the library's build type, not the app's.
 */
internal object WebViewLog {
    const val TAG = "CustomWebViewPlugin"

    @Volatile
    var verbose: Boolean = false
        private set

    fun init(context: Context) {
        verbose = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
    }

    /** Debug-only log. The message is built only when verbose logging is on. */
    inline fun d(message: () -> String) {
        if (verbose) Log.d(TAG, message())
    }

    fun w(message: String) {
        Log.w(TAG, message)
    }

    fun e(message: String, throwable: Throwable? = null) {
        Log.e(TAG, message, throwable)
    }

    /** Full URL in debug builds; scheme://host/path (no query or fragment) otherwise. */
    fun url(url: String?): String {
        if (url == null) return "null"
        if (verbose) return url
        return try {
            val uri = Uri.parse(url)
            val scheme = uri.scheme ?: return "<url>"
            if (uri.host == null) "$scheme:<redacted>" else "$scheme://${uri.host}${uri.path ?: ""}"
        } catch (e: Exception) {
            "<url>"
        }
    }
}

/** One background thread shared by all webviews for download decoding and file writes. */
internal object WebViewIo {
    val executor: java.util.concurrent.ExecutorService by lazy {
        java.util.concurrent.Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "CustomWebViewIo").apply { isDaemon = true }
        }
    }
}
