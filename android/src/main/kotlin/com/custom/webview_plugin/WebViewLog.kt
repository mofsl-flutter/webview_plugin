package com.custom.webview_plugin

import android.content.Context
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.util.Log

/**
 * Logging for the plugin.
 *
 * Warnings and errors are always written, in release builds too, so production webview
 * failures (load, HTTP, SSL, renderer and download errors) can be debugged.
 *
 * Verbose logs (navigation, page console, JS channel registration, lifecycle) are written when
 * the host app is debuggable, or after the host turns them on at runtime with
 * `CustomWebViewPlugin.setVerboseLogging(true)` (e.g. from Remote Config for a QA build).
 *
 * URLs carry session tokens (SSO links, signed redirect URLs), so outside a debuggable app every
 * URL passed through [url] is reduced to scheme, host and path, even with verbose logging on.
 *
 * Debuggability is read from the host app's ApplicationInfo rather than this library's
 * BuildConfig, which is not generated for library modules on recent AGP versions and would
 * reflect the library's build type, not the app's.
 */
internal object WebViewLog {
    const val TAG = "CustomWebViewPlugin"

    /** Host app is debuggable: verbose logs on and full URLs. */
    @Volatile
    private var debuggable: Boolean = false

    /** Verbose logging switched on at runtime by the host app. URLs stay redacted. */
    @Volatile
    private var runtimeVerbose: Boolean = false

    val verbose: Boolean
        get() = debuggable || runtimeVerbose

    fun init(context: Context) {
        debuggable = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
    }

    fun setVerbose(enabled: Boolean) {
        runtimeVerbose = enabled
        Log.i(TAG, "Verbose webview logging ${if (enabled) "on" else "off"}")
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
        if (debuggable) return url
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
