package com.xiaoqi.expiry_manager

import android.annotation.TargetApi
import android.content.ContentValues
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "com.xiaoqi.expiry_manager/save"
        const val PRINTER_CHANNEL = "com.xiaoqi.expiry_manager/printer"
        const val PREFS_CHANNEL = "com.xiaoqi.expiry_manager/prefs"
        const val DIR_DOWNLOADS = "Download"

        /** App 级设置（制作人、最近标题等）统一放这里。 */
        const val PREFS_NAME = "expiry_app"
    }

    private var printerBridge: PrinterBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> {
                        val name = call.argument<String>("name") ?: "label.pdf"
                        val bytes = call.argument<ByteArray>("bytes")
                        if (bytes == null) {
                            result.error("NO_BYTES", "bytes argument is missing", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(writePdf(name, bytes))
                        } catch (e: Exception) {
                            result.error("SAVE_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // 硕方 T50 Pro 蓝牙打印通道
        val printerChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PRINTER_CHANNEL)
        val bridge = PrinterBridge(this, printerChannel)
        printerBridge = bridge
        printerChannel.setMethodCallHandler { call, result -> bridge.onMethodCall(call, result) }

        // 轻量偏好存储：用原生 SharedPreferences，省掉一个 Flutter 插件依赖
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PREFS_CHANNEL)
            .setMethodCallHandler { call, result ->
                val key = call.argument<String>("key") ?: ""
                when (call.method) {
                    "getString" -> result.success(prefs.getString(key, null))
                    "setString" -> {
                        prefs.edit().putString(key, call.argument<String>("value")).apply()
                        result.success(true)
                    }
                    "getStringList" -> result.success(prefs.getStringSet(key, emptySet())?.toList())
                    "setStringList" -> {
                        val list = call.argument<List<String>>("value")?.toSet() ?: emptySet()
                        prefs.edit().putStringSet(key, list).apply()
                        result.success(true)
                    }
                    "remove" -> {
                        prefs.edit().remove(key).apply()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        printerBridge?.onRequestPermissionsResult(requestCode, grantResults)
    }

    override fun onDestroy() {
        printerBridge?.dispose()
        printerBridge = null
        super.onDestroy()
    }

    /** 把 PDF 写入系统「下载」目录，返回可读的保存位置。 */
    private fun writePdf(name: String, bytes: ByteArray): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return writeViaMediaStore(name, bytes)
        }
        // API 24~28：应用专属外部目录，同样不需要权限
        val dir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: File(filesDir, DIR_DOWNLOADS)
        if (!dir.exists() && !dir.mkdirs()) {
            throw IllegalStateException("cannot create " + dir.absolutePath)
        }
        val file = File(dir, name)
        FileOutputStream(file).use { it.write(bytes) }
        MediaScannerConnection.scanFile(
            applicationContext,
            arrayOf(file.absolutePath),
            arrayOf("application/pdf"),
            null
        )
        return file.absolutePath
    }

    /** API 29+ 走 MediaStore.Downloads，免存储权限，文件对文件管理器可见。 */
    @TargetApi(Build.VERSION_CODES.Q)
    private fun writeViaMediaStore(name: String, bytes: ByteArray): String {
        val resolver = applicationContext.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, "application/pdf")
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("MediaStore insert returned null")

        val out = resolver.openOutputStream(uri)
            ?: throw IllegalStateException("openOutputStream returned null")
        out.use {
            it.write(bytes)
            it.flush()
        }

        val done = ContentValues().apply {
            put(MediaStore.MediaColumns.IS_PENDING, 0)
        }
        resolver.update(uri, done, null, null)
        return "下载/$name"
    }
}
