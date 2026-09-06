package com.custom.webview_harness

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Exposes the launch intent's extras to Dart.
 *
 * Lets the harness be configured from the host without rebuilding and without typing on the
 * device:
 *
 *     adb shell am start -n com.custom.webview_harness/.MainActivity \
 *       --es xapikey <key> --es clientcode T06794
 *
 * This exists because the two alternatives both failed in practice. A `--dart-define` did not
 * survive Flutter's incremental build, so the key silently came up empty; and typing the key with
 * `adb shell input` is tap-coordinate dependent, which once put a stray character into the key
 * field and corrupted a run.
 *
 * `singleTop` relaunches arrive at [onNewIntent] rather than a fresh `onCreate`, so the new intent
 * is forwarded over the same channel — otherwise a second `am start` would silently do nothing.
 */
class MainActivity : FlutterActivity() {
    private var launchChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "webview_harness/launch"
        )
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getLaunchArgs" -> result.success(extrasOf(intent))
                else -> result.notImplemented()
            }
        }
        launchChannel = channel
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        launchChannel?.invokeMethod("onNewIntent", extrasOf(intent))
    }

    private fun extrasOf(intent: Intent?): Map<String, Any?> {
        val extras = intent?.extras ?: return emptyMap()
        val map = HashMap<String, Any?>()
        for (key in extras.keySet()) {
            map[key] = extras.get(key)
        }
        return map
    }
}
