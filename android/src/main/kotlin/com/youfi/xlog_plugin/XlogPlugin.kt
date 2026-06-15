package com.youfi.xlog_plugin

import android.content.Context
import com.tencent.mars.xlog.Log
import com.tencent.mars.xlog.Xlog
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Flutter <-> mars-xlog glue. Keeps the native surface tiny; HTTP upload lives in Dart. */
class XlogPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private lateinit var logDir: String

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        logDir = File(context.filesDir, "xlog").apply { mkdirs() }.absolutePath
        channel = MethodChannel(binding.binaryMessenger, "com.youfi/xlog_plugin")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> {
                System.loadLibrary("c++_shared")
                System.loadLibrary("marsxlog")
                val level = call.argument<Int>("level") ?: Xlog.LEVEL_INFO
                val prefix = call.argument<String>("namePrefix") ?: "mlog"
                val cacheDays = call.argument<Int>("cacheDays") ?: 0
                val pubKey = call.argument<String>("pubKey") ?: ""
                val cacheDir = File(logDir, "cache").apply { mkdirs() }.absolutePath
                Log.setLogImp(Xlog())
                Log.setConsoleLogOpen(call.argument<Boolean>("consoleLogOpen") ?: true)
                // appenderOpen rotates one file per day: <prefix>_YYYYMMDD.xlog
                // 1.2.6 API has no pubKey param; encryption not supported in this version
                Log.appenderOpen(level, Xlog.AppednerModeAsync, cacheDir, logDir, prefix, cacheDays)
                result.success(null)
            }
            "setLevel" -> { Log.setLevel(call.argument<Int>("level") ?: Xlog.LEVEL_INFO, false); result.success(null) }
            "log" -> {
                val tag = call.argument<String>("tag") ?: "MLog"
                val msg = call.argument<String>("msg") ?: ""
                when (call.argument<Int>("level") ?: Xlog.LEVEL_INFO) {
                    Xlog.LEVEL_VERBOSE -> Log.v(tag, msg)
                    Xlog.LEVEL_DEBUG -> Log.d(tag, msg)
                    Xlog.LEVEL_WARNING -> Log.w(tag, msg)
                    Xlog.LEVEL_ERROR -> Log.e(tag, msg)
                    Xlog.LEVEL_FATAL -> Log.f(tag, msg)
                    else -> Log.i(tag, msg)
                }
                result.success(null)
            }
            "flush" -> {
                val sync = call.argument<Boolean>("sync") ?: true
                if (sync) Log.appenderFlushSync(true) else Log.appenderFlush()
                result.success(null)
            }
            "close" -> { Log.appenderClose(); result.success(null) }
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
