package com.xiaoqi.expiry_manager

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.util.Log
import com.supvan.supvanlibrary.PrintingControlInfo.PrintPage
import com.supvan.supvanlibrary.PrintingControlInfo.PrintParameter
import com.supvan.supvanlibrary.directprinttools.BluetoothManager
import com.supvan.supvanlibrary.directprinttools.Callback
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.LinkedHashMap
import java.util.Locale
import java.util.concurrent.Executors

/**
 * 打印机桥 —— 把「扫描设备 / 连接 / 断开 / 状态 / 打印」暴露给 Flutter 侧。
 *
 * 支持两类通道：
 * 1. **硕方官方 SDK**（[BluetoothManager]，私有协议）—— T50 Pro 系列；
 * 2. **通用蓝牙 SPP**（[GenericPrinter]，TSPL / ESC-POS 指令）—— 其他品牌机器。
 *
 * 选哪条通道由「打印机型号」决定，连接时一并传下来并跟着设备一起存盘。
 */
class PrinterBridge(
    private val activity: Activity,
    private val channel: MethodChannel,
) : Callback {

    companion object {
        private const val TAG = "PrinterBridge"

        /** 请求蓝牙权限用的 requestCode，MainActivity 转发结果时按它匹配。 */
        const val REQ_BT_PERMISSION = 0x9E01

        /** 标签机打印头分辨率：8 dots/mm（203 dpi）。 */
        private const val DOTS_PER_MM = 8f

        /** 已添加打印机列表的存放位置（原生 SharedPreferences，无需额外插件）。 */
        private const val PREFS_NAME = "expiry_printer"
        private const val KEY_SAVED = "saved_printers"
    }

    private val main = Handler(Looper.getMainLooper())

    /** 蓝牙/串口都是阻塞 IO，统一丢到单线程池里排队，避免卡主线程。 */
    private val io = Executors.newSingleThreadExecutor { r ->
        Thread(r, "printer-io").apply { isDaemon = true }
    }

    private val adapter: BluetoothAdapter? get() = BluetoothAdapter.getDefaultAdapter()

    /**
     * 硕方 SDK 单例。设备没有蓝牙（部分模拟器）时构造会失败，此处兜底为 null，
     * 上层通过 isSupported 判断。
     */
    private val supvan: BluetoothManager? by lazy {
        if (adapter == null) {
            null
        } else {
            runCatching {
                BluetoothManager(activity).also { it.setCallback(this) }
            }.onFailure { Log.w(TAG, "初始化硕方 SDK 失败", it) }.getOrNull()
        }
    }

    /** 通用 SPP 驱动（按需创建，用不到就不建）。 */
    private val generic: GenericPrinter by lazy { GenericPrinter(activity) }

    /** 当前连接走的通道。 */
    @Volatile
    private var activeKind: String = PrinterKind.SUPVAN_T50PRO

    /** 扫描过程中发现的设备（按 MAC 去重）。 */
    private val discovered = LinkedHashMap<String, BluetoothDevice>()
    private var receiver: BroadcastReceiver? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    /**
     * 最近一次发起连接的设备。
     * 硕方 SDK 的回调只给一个 bool，不带设备信息，靠它把「谁连上了」补回给 Flutter。
     */
    private var lastAddress: String? = null
    private var lastName: String? = null

    /** 已添加的打印机就存在这里（原生 SharedPreferences，不引第三方插件）。 */
    private val prefs
        get() = activity.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    // ---------------------------------------------------------------- 对外入口

    fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(adapter != null)
            "isEnabled" -> result.success(runCatching { adapter?.isEnabled }.getOrNull() ?: false)
            "hasPermission" -> result.success(hasBtPermission())
            "requestPermission" -> requestBtPermission(result)
            "openBluetoothSettings" -> result.success(openBluetoothSettings())
            "listDevices" -> result.success(listDevices())
            "startScan" -> result.success(startScan())
            "stopScan" -> result.success(stopScan())
            "connect" -> result.success(
                connect(call.argument<String>("address"), call.argument<String>("kind")),
            )
            "disconnect" -> result.success(disconnect())
            "status" -> result.success(status())
            "printLabel" -> result.success(printLabel(call))
            "printTest" -> result.success(printTest(call))
            "listSavedPrinters" -> result.success(listSaved())
            "savePrinter" -> result.success(savePrinterManual(call))
            "renamePrinter" -> result.success(
                renamePrinter(call.argument<String>("address"), call.argument<String>("name")),
            )
            "removePrinter" -> result.success(removePrinter(call.argument<String>("address")))
            "connectedAddress" -> result.success(
                if (activeKind.let { PrinterKind.isGeneric(it) }) generic.address else lastAddress,
            )
            else -> result.notImplemented()
        }
    }

    /** MainActivity 的 onRequestPermissionsResult 转发过来。 */
    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != REQ_BT_PERMISSION) return
        val granted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
        emit("permission", granted)
    }

    /** Activity 销毁时释放资源。 */
    fun dispose() {
        stopScan()
        receiver?.let { runCatching { activity.unregisterReceiver(it) } }
        receiver = null
        runCatching { generic.disconnect() }
        runCatching { supvan?.onDestroy() }
        runCatching { io.shutdownNow() }
    }

    // ------------------------------------------------------------------ 权限

    private fun requiredPermissions(): List<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+：扫描与连接拆成两个运行时权限
            listOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            // Android 11 及以下：经典蓝牙发现需要定位权限
            listOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }

    private fun hasBtPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        if (adapter == null) return true
        return requiredPermissions().all {
            activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestBtPermission(result: MethodChannel.Result) {
        if (hasBtPermission()) {
            result.success(true)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(true)
            return
        }
        pendingPermissionResult = result
        activity.requestPermissions(requiredPermissions().toTypedArray(), REQ_BT_PERMISSION)
    }

    /** 跳到系统蓝牙设置页（开关没打开时给个直达入口）。 */
    private fun openBluetoothSettings(): Boolean = runCatching {
        activity.startActivity(
            Intent(android.provider.Settings.ACTION_BLUETOOTH_SETTINGS)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        true
    }.getOrElse { false }

    // ------------------------------------------------------------------ 设备

    private fun deviceMap(device: BluetoothDevice, bonded: Boolean): Map<String, Any?> {
        val raw = runCatching { device.name }.getOrNull()
        return mapOf(
            "name" to if (TextUtils.isEmpty(raw)) "未知设备" else raw,
            "address" to device.address,
            "bonded" to bonded,
        )
    }

    private fun listDevices(): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        val a = adapter ?: return out
        if (!hasBtPermission()) return out

        val bonded = runCatching { a.bondedDevices }.getOrNull().orEmpty()
        for (d in bonded) out.add(deviceMap(d, true))
        for (d in discovered.values) {
            if (bonded.none { it.address == d.address }) out.add(deviceMap(d, false))
        }
        return out
    }

    private fun ensureReceiver() {
        if (receiver != null) return
        val r = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    BluetoothDevice.ACTION_FOUND -> {
                        @Suppress("DEPRECATION")
                        val d = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                        if (d != null && !TextUtils.isEmpty(runCatching { d.name }.getOrNull())) {
                            discovered[d.address] = d
                            emit("deviceFound", deviceMap(d, d.bondState == BluetoothDevice.BOND_BONDED))
                        }
                    }
                    BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> emit("scanFinished", null)
                }
            }
        }
        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(r, filter, Context.RECEIVER_EXPORTED)
        } else {
            activity.registerReceiver(r, filter)
        }
        receiver = r
    }

    private fun startScan(): Boolean {
        val a = adapter ?: return false
        if (!hasBtPermission()) return false
        if (runCatching { a.isEnabled }.getOrNull() != true) return false
        ensureReceiver()
        discovered.clear()
        if (a.isDiscovering) a.cancelDiscovery()
        return runCatching { a.startDiscovery() }.getOrElse { false }
    }

    private fun stopScan(): Boolean {
        val a = adapter ?: return true
        return runCatching { if (a.isDiscovering) a.cancelDiscovery() else true }.getOrElse { true }
    }

    // ------------------------------------------------------------------ 连接

    private fun connect(address: String?, kind: String?): Boolean {
        if (address.isNullOrEmpty()) return false
        if (!hasBtPermission()) return false
        val k = kind ?: PrinterKind.SUPVAN_T50PRO
        activeKind = k
        val device = runCatching { adapter?.getRemoteDevice(address) }.getOrNull() ?: return false
        val name = runCatching { device.name }.getOrNull()
        lastAddress = device.address
        lastName = if (TextUtils.isEmpty(name)) "未知设备" else name

        if (PrinterKind.isGeneric(k)) {
            // SPP 连接是阻塞的，丢后台线程；结果用事件回传。
            io.execute {
                val ok = runCatching { generic.connect(device.address) }.getOrElse { false }
                if (ok) savePrinter(lastName ?: "打印机", device.address, k)
                post(
                    "connected",
                    mapOf("ok" to ok, "address" to device.address, "name" to lastName, "kind" to k),
                )
            }
            return true
        }

        val bt = supvan ?: return false
        Log.i(TAG, "连接硕方 ${device.address} ($name)")
        return runCatching { bt.openPrinter(device) }.getOrElse { false }
    }

    private fun disconnect(): Boolean {
        runCatching { generic.disconnect() }
        val bt = supvan ?: return true
        return runCatching { bt.closePrinter() }.getOrElse { false }
    }

    private fun status(): Int {
        if (PrinterKind.isGeneric(activeKind)) {
            // 通用机型没有统一的查询指令，界面按「未知」显示即可。
            return -1
        }
        return runCatching { supvan?.status ?: -1 }.getOrElse { -1 }
    }

    // ---------------------------------------------------------- 已添加的打印机

    /** 已添加的打印机列表，最近连接的排最前。 */
    private fun listSaved(): List<Map<String, Any?>> {
        val raw = prefs.getString(KEY_SAVED, null) ?: return emptyList()
        return runCatching {
            val arr = JSONArray(raw)
            (0 until arr.length()).mapNotNull { i ->
                val o = arr.optJSONObject(i) ?: return@mapNotNull null
                val address = o.optString("address")
                if (address.isEmpty()) {
                    null
                } else {
                    mapOf(
                        "name" to o.optString("name", "打印机"),
                        "address" to address,
                        "kind" to o.optString("kind", PrinterKind.SUPVAN_T50PRO),
                    )
                }
            }
        }.getOrElse {
            Log.w(TAG, "读取已添加打印机失败", it)
            emptyList()
        }
    }

    private fun writeSaved(items: List<Map<String, Any?>>, target: String) {
        val arr = JSONArray()
        items.forEach { item ->
            arr.put(JSONObject().apply {
                put("name", item["name"] as? String ?: "打印机")
                put("address", item["address"] as? String ?: "")
                put("kind", item["kind"] as? String ?: PrinterKind.SUPVAN_T50PRO)
            })
        }
        prefs.edit().putString(KEY_SAVED, arr.toString()).apply()
        emit("savedChanged", target)
    }

    /** 添加（或把已有的顶到最前）。同一 MAC 只留一条。 */
    private fun savePrinter(name: String, address: String, kind: String) {
        if (address.isEmpty()) return
        runCatching {
            val kept = listSaved().filterNot { it["address"] == address }
            writeSaved(
                listOf(
                    mapOf(
                        "name" to if (name.isEmpty()) "打印机" else name,
                        "address" to address,
                        "kind" to kind,
                    ),
                ) + kept,
                address,
            )
            Log.i(TAG, "已添加打印机 $name ($address) [$kind]")
        }.onFailure { Log.w(TAG, "保存打印机失败", it) }
    }

    /**
     * 手动按 MAC 添加一台打印机。
     *
     * 有些通用机型不做经典蓝牙可发现（或名称是乱的），扫描扫不到，
     * 只能拿系统蓝牙设置里看到的 MAC 手动添进来。硕方机型同样适用。
     */
    private fun savePrinterManual(call: MethodCall): Boolean {
        val address = normalizeMac(call.argument<String>("address") ?: "") ?: return false
        val kind = call.argument<String>("kind") ?: PrinterKind.SUPVAN_T50PRO
        val name = (call.argument<String>("name") ?: "").trim()
            .ifEmpty { PrinterKind.label(kind) }
        savePrinter(name, address, kind)
        return true
    }

    /** 把 `AABBCCDDEEFF` / `aa-bb-cc-dd-ee-ff` 之类统一成 `AA:BB:CC:DD:EE:FF`。 */
    private fun normalizeMac(raw: String): String? {
        val hex = raw.replace(Regex("[^0-9A-Fa-f]"), "")
        if (hex.length != 12) return null
        return hex.chunked(2).joinToString(":").uppercase()
    }

    private fun renamePrinter(address: String?, name: String?): Boolean {
        if (address.isNullOrEmpty() || name.isNullOrEmpty()) return false
        return runCatching {
            val list = listSaved().map { item ->
                if (item["address"] == address) {
                    mapOf(
                        "name" to name,
                        "address" to address,
                        "kind" to (item["kind"] ?: PrinterKind.SUPVAN_T50PRO),
                    )
                } else {
                    item
                }
            }
            writeSaved(list, address)
            true
        }.getOrElse { false }
    }

    private fun removePrinter(address: String?): Boolean {
        if (address.isNullOrEmpty()) return false
        return runCatching {
            val kept = listSaved().filterNot { it["address"] == address }
            writeSaved(kept, address)
            true
        }.getOrElse { false }
    }

    // ------------------------------------------------------------------ 打印

    /**
     * 打印一张真实标签。
     *
     * 入参：
     * - `pdf`        —— 标签 PDF 字节（和预览用的是同一份）
     * - `widthMm` / `heightMm` —— 纸张尺寸，默认 50 × 30
     * - `copies`     —— 份数
     * - `density`    —— 浓度（硕方 1~9；TSPL 0~15）
     * - `speed`      —— 速度（仅 TSPL 有效，1~6）
     * - `paperType`  —— 仅硕方：1 间隙纸 / 2 普通黑标 / 5 黑标卡纸
     * - `gap`        —— 纸张间隙 mm（0~8）
     * - `headDots`   —— 通用机型打印头点数（384 / 400 / 576）
     * - `invert`     —— 通用机型黑白取反
     * - `feedLines`  —— 通用 ESC/POS 打完走纸行数
     */
    private fun printLabel(call: MethodCall): Boolean {
        val pdf = call.argument<ByteArray>("pdf") ?: return false
        val widthMm = call.argument<Int>("widthMm") ?: 50
        val heightMm = call.argument<Int>("heightMm") ?: 30
        val headDots = (call.argument<Int>("headDots") ?: widthMm * RasterUtil.DOTS_PER_MM)
            .coerceIn(64, 832)
        val kind = call.argument<String>("kind") ?: activeKind

        if (PrinterKind.isGeneric(kind)) {
            io.execute {
                val bmp = RasterUtil.renderPdf(
                    activity, pdf, headDots, heightMm * RasterUtil.DOTS_PER_MM,
                )
                val ok = bmp != null && sendGeneric(
                    bmp,
                    kind,
                    headDots,
                    heightMm * RasterUtil.DOTS_PER_MM,
                    call.argument<Int>("copies") ?: 1,
                    call.argument<Int>("gap") ?: 3,
                    call.argument<Int>("density") ?: 8,
                    call.argument<Int>("speed") ?: 3,
                    call.argument<Boolean>("invert") ?: false,
                    call.argument<Int>("feedLines") ?: 2,
                )
                bmp?.recycle()
                post("printDone", mapOf("ok" to ok, "kind" to kind))
            }
            return true
        }

        val bt = supvan ?: return false
        val bmp = RasterUtil.renderPdf(activity, pdf, headDots, heightMm * RasterUtil.DOTS_PER_MM)
            ?: return false
        return runCatching { bt.doPrintImage(listOf(bmp), supvanParam(call, widthMm, heightMm)) }
            .getOrElse { false }
    }

    /** 打一张标尺测试页，用来确认走纸定位和边距。 */
    private fun printTest(call: MethodCall): Boolean {
        val kind = call.argument<String>("kind") ?: activeKind
        val widthMm = call.argument<Int>("width") ?: 50
        val heightMm = call.argument<Int>("height") ?: 30
        val copies = (call.argument<Int>("copies") ?: 1).coerceIn(1, 99)
        val density = (call.argument<Int>("density") ?: 4).coerceIn(0, 15)
        val gap = (call.argument<Int>("gap") ?: 3).coerceIn(0, 8)
        val headDots = (call.argument<Int>("headDots") ?: widthMm * RasterUtil.DOTS_PER_MM)
            .coerceIn(64, 832)
        val heightDots = heightMm * RasterUtil.DOTS_PER_MM
        val bmp = buildTestBitmap(widthMm, heightMm, kind, density, gap, copies, headDots)

        if (PrinterKind.isGeneric(kind)) {
            io.execute {
                val ok = sendGeneric(
                    bmp,
                    kind,
                    headDots,
                    heightDots,
                    copies,
                    gap,
                    density,
                    call.argument<Int>("speed") ?: 3,
                    call.argument<Boolean>("invert") ?: false,
                    call.argument<Int>("feedLines") ?: 2,
                )
                bmp.recycle()
                post("printDone", mapOf("ok" to ok, "kind" to kind))
            }
            return true
        }

        val bt = supvan ?: return false
        val param = PrintParameter(
            widthMm, heightMm, copies, 0, density, 0, 0,
            call.argument<Int>("paperType") ?: 1, gap, true, 0,
            listOf(PrintPage(widthMm, heightMm, 1, null)),
        )
        return runCatching { bt.doPrintImage(listOf(bmp), param) }.getOrElse { false }
    }

    /** 硕方 SDK 的打印参数。 */
    private fun supvanParam(call: MethodCall, widthMm: Int, heightMm: Int): PrintParameter {
        val copies = (call.argument<Int>("copies") ?: 1).coerceIn(1, 99)
        val density = (call.argument<Int>("density") ?: 4).coerceIn(1, 9)
        val paperType = call.argument<Int>("paperType") ?: 1
        val gap = (call.argument<Int>("gap") ?: 3).coerceIn(0, 8)
        return PrintParameter(
            widthMm, heightMm, copies, 0, density, 0, 0,
            paperType, gap, true, 0,
            listOf(PrintPage(widthMm, heightMm, 1, null)),
        )
    }

    /** 通用机型：位图 → 指令流 → 串口写出去。 */
    private fun sendGeneric(
        bmp: Bitmap,
        kind: String,
        widthDots: Int,
        heightDots: Int,
        copies: Int,
        gap: Int,
        density: Int,
        speed: Int,
        invert: Boolean,
        feedLines: Int,
    ): Boolean {
        if (!generic.isConnected) return false
        val rowBytes = (widthDots + 7) / 8
        val body = RasterUtil.toMono(bmp, invert)
        val payload = if (kind == PrinterKind.GENERIC_ESCPOS) {
            // 通用热敏机：ESC/POS 光栅
            PrinterCommands.escposTail(
                copies, feedLines, body,
                PrinterCommands.escposHead(rowBytes, heightDots),
            )
        } else {
            // 通用标签机：TSPL
            val bos = java.io.ByteArrayOutputStream()
            bos.write(
                PrinterCommands.tsplHead(
                    widthDots / RasterUtil.DOTS_PER_MM,
                    heightDots / RasterUtil.DOTS_PER_MM,
                    gap, rowBytes, heightDots, density, speed,
                ),
            )
            bos.write(body)
            bos.write(PrinterCommands.tsplTail(copies))
            bos.toByteArray()
        }
        return generic.send(payload)
    }

    /** 生成标尺测试图（默认 400×240 px @203dpi）。 */
    private fun buildTestBitmap(
        widthMm: Int,
        heightMm: Int,
        kind: String,
        density: Int,
        gap: Int,
        copies: Int,
        widthDots: Int,
    ): Bitmap {
        val w = widthDots
        val h = heightMm * RasterUtil.DOTS_PER_MM
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        c.drawColor(Color.WHITE)

        val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.BLACK
            style = Paint.Style.STROKE
            strokeWidth = 2f
        }
        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.BLACK
            style = Paint.Style.FILL
        }
        val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.BLACK
            textAlign = Paint.Align.CENTER
        }
        val textLeft = Paint(text).apply { textAlign = Paint.Align.LEFT }

        // 外框贴边 + 1mm 内框：用来判断是否切边 / 是否偏移
        c.drawRect(RectF(1f, 1f, w - 1f, h - 1f), stroke)
        val inset = DOTS_PER_MM
        c.drawRect(RectF(inset, inset, w - inset, h - inset), stroke)

        text.textSize = 9f * DOTS_PER_MM * 0.42f
        text.isFakeBoldText = true
        c.drawText(PrinterKind.label(kind).uppercase(Locale.US), w / 2f, 5.2f * DOTS_PER_MM, text)

        text.isFakeBoldText = false
        text.textSize = 9f * DOTS_PER_MM * 0.28f
        c.drawText("${widthMm} x ${heightMm} mm", w / 2f, 7.6f * DOTS_PER_MM, text)

        // 横向刻度线：每 5mm 一条短刻度，中点画长刻度
        val rulerY = 9.6f * DOTS_PER_MM
        var mm = 5
        while (mm <= widthMm - 5) {
            val x = mm * DOTS_PER_MM
            val long = (mm == widthMm / 2)
            c.drawLine(x, rulerY, x, rulerY + (if (long) 2.4f else 1.2f) * DOTS_PER_MM, stroke)
            if (long) {
                text.textSize = 8f * DOTS_PER_MM * 0.22f
                c.drawText("$mm", x, rulerY + 4.0f * DOTS_PER_MM, text)
            }
            mm += 5
        }

        text.textSize = 9f * DOTS_PER_MM * 0.78f
        text.isFakeBoldText = true
        c.drawText("$widthMm x $heightMm", w / 2f, 17.9f * DOTS_PER_MM, text)

        text.isFakeBoldText = false
        text.textSize = 9f * DOTS_PER_MM * 0.26f
        c.drawText(
            "间隙 ${gap}mm   浓度 $density   份数 $copies",
            w / 2f, 21.2f * DOTS_PER_MM, text,
        )

        val stamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())
        textLeft.textSize = 9f * DOTS_PER_MM * 0.24f
        c.drawText(stamp, 2.0f * DOTS_PER_MM, 24.2f * DOTS_PER_MM, textLeft)

        text.textSize = 9f * DOTS_PER_MM * 0.24f
        c.drawText("PRINT CALIBRATION", w / 2f, 27.4f * DOTS_PER_MM, text)

        // 四角 L 形角标：定位是否偏移一眼可见
        val arm = 3f * DOTS_PER_MM
        val off = 1.6f * DOTS_PER_MM
        val thick = Paint(fill).apply { strokeWidth = 2.6f; style = Paint.Style.STROKE }
        c.drawLine(off, off, off + arm, off, thick)
        c.drawLine(off, off, off, off + arm, thick)
        c.drawLine(w - off, off, w - off - arm, off, thick)
        c.drawLine(w - off, off, w - off, off + arm, thick)
        c.drawLine(off, h - off, off + arm, h - off, thick)
        c.drawLine(off, h - off, off, h - off - arm, thick)
        c.drawLine(w - off, h - off, w - off - arm, h - off, thick)
        c.drawLine(w - off, h - off, w - off, h - off - arm, thick)

        return bmp
    }

    // ------------------------------------------------------- SDK 回调 → Flutter

    /** 连接成功即自动「添加」到打印机列表 —— 用户不用再点一次保存。 */
    override fun openPrinterResult(result: Boolean) {
        if (result) {
            val addr = lastAddress
            if (!addr.isNullOrEmpty()) {
                savePrinter(lastName ?: "打印机", addr, PrinterKind.SUPVAN_T50PRO)
            }
        }
        post(
            "connected",
            mapOf(
                "ok" to result,
                "address" to lastAddress,
                "name" to lastName,
                "kind" to PrinterKind.SUPVAN_T50PRO,
            ),
        )
    }

    override fun closePrinterResult(result: Boolean) =
        post("disconnected", mapOf("ok" to result, "address" to lastAddress))

    override fun getStatusResult(status: Int) = post("status", status)

    override fun doPrintImagesResult(result: Boolean) =
        post("printDone", mapOf("ok" to result, "kind" to activeKind))

    override fun doPrintTextsResult(result: Boolean) =
        post("printDone", mapOf("ok" to result, "kind" to activeKind))

    private fun post(type: String, value: Any?) {
        main.post { emit(type, value) }
    }

    private fun emit(type: String, value: Any?) {
        runCatching {
            channel.invokeMethod("onEvent", mapOf("type" to type, "value" to value))
        }.onFailure { Log.w(TAG, "回传事件失败: $type", it) }
    }
}
