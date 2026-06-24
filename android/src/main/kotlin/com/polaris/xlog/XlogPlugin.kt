package com.polaris.xlog

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Flutter <-> mars-xlog glue.
 *
 * The channel only resolves the app sandbox log directories and loads the native
 * library; the appender is opened (and all logging happens) from Dart over FFI
 * (lib/src/xlog_ffi.dart -> libmarsxlog.so's xlog_ffi_* symbols). There is no
 * com.tencent.mars.* Java glue and no JNI-by-name, so consumer apps need no
 * special ProGuard/R8 keep rules. HTTP upload lives in Dart.
 */
class XlogPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private lateinit var logDir: String

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        logDir = File(context.filesDir, "xlog").apply { mkdirs() }.absolutePath
        channel = MethodChannel(binding.binaryMessenger, "com.polaris.xlog")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        // Only the cold paths (init / getLogDir / listLogFiles) run on the channel.
        // The hot path (log / setLevel / flush / close) and the appender open all
        // go straight to native via dart:ffi (see lib/src/xlog_ffi.dart).
        when (call.method) {
            "init" -> {
                // Load libmarsxlog.so (also runs JNI_OnLoad once); Dart then opens
                // the appender over FFI using the directories returned here.
                System.loadLibrary("marsxlog")
                val cacheDir = File(logDir, "cache").apply { mkdirs() }.absolutePath
                result.success(mapOf("logDir" to logDir, "cacheDir" to cacheDir))
            }
            "getLogDir" -> result.success(logDir)
            "listLogFiles" -> {
                // mars writes the current day's file into the cache dir when
                // cacheDays > 0 and only moves it to logDir after cacheDays.
                // Scan both so today's log is always listed (cache wins on dupes).
                val byName = LinkedHashMap<String, Map<String, Any>>()
                for (dir in listOf(File(logDir), File(logDir, "cache"))) {
                    (dir.listFiles { f -> f.isFile && f.name.endsWith(".xlog") } ?: emptyArray())
                        .forEach { byName[it.name] = mapOf("path" to it.absolutePath, "name" to it.name, "size" to it.length()) }
                }
                result.success(byName.values.toList())
            }
            else -> result.notImplemented()
        }
    }
}
