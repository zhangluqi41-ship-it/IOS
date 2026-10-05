package com.xiaoqi.expiry_manager

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.OutputStream
import java.util.UUID

/**
 * 打印机型号（= 通信协议）。
 *
 * 以后要接新品牌，只要在这里加一个常量，并在 [PrinterCommands] 里补上对应的
 * 指令生成，App 界面会自动把它列进「打印机型号」选择里。
 */
object PrinterKind {
    /** 硕方 T50 Pro / T56 Pro / T50S / T50 Plus 等，走官方 SDK 私有协议。 */
    const val SUPVAN_T50PRO = "supvan_t50pro"

    /** 通用标签机：TSPL / TSPL2 指令集（佳博、汉印、芯烨、立象等大多数国产标签机）。 */
    const val GENERIC_TSPL = "generic_tspl"

    /** 通用热敏机：ESC/POS 光栅指令（票据机、部分便携标签机）。 */
    const val GENERIC_ESCPOS = "generic_escpos"

    fun isGeneric(kind: String): Boolean =
        kind == GENERIC_TSPL || kind == GENERIC_ESCPOS

    fun label(kind: String): String = when (kind) {
        SUPVAN_T50PRO -> "硕方 T50 Pro"
        GENERIC_TSPL -> "通用标签机"
        GENERIC_ESCPOS -> "通用热敏机"
        else -> "未知型号"
    }
}

/**
 * 位图工具：把标签 PDF 栅格化成打印机要的**单色点阵**。
 *
 * 走 PDF 而不是直接画 Bitmap 的原因：App 里标签本来就先渲染成 PDF，
 * 打印和预览共用同一份文件 → 纸面效果和屏幕上看到的严格一致。
 */
object RasterUtil {

    /** 203dpi 打印头 = 8 dots/mm。 */
    const val DOTS_PER_MM = 8

    /** 亮度阈值：低于它当作黑点。 */
    private const val THRESHOLD = 150

    /**
     * 把 PDF 第一页渲染成 [widthDots] × [heightDots] 的位图。
     * PdfRenderer 会把整页铺满目标位图，所以只要位图尺寸 = 纸面点阵就 1:1。
     */
    fun renderPdf(context: Context, pdf: ByteArray, widthDots: Int, heightDots: Int): Bitmap? {
        val tmp = File(context.cacheDir, "print_label.pdf")
        var pfd: ParcelFileDescriptor? = null
        var renderer: PdfRenderer? = null
        var page: PdfRenderer.Page? = null
        return try {
            tmp.writeBytes(pdf)
            pfd = ParcelFileDescriptor.open(tmp, ParcelFileDescriptor.MODE_READ_ONLY)
            renderer = PdfRenderer(pfd)
            if (renderer.pageCount <= 0) return null
            page = renderer.openPage(0)
            val bmp = Bitmap.createBitmap(widthDots, heightDots, Bitmap.Config.ARGB_8888)
            bmp.eraseColor(Color.WHITE)
            page.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_PRINT)
            bmp
        } catch (e: Throwable) {
            Log.w("RasterUtil", "PDF 栅格化失败", e)
            null
        } finally {
            runCatching { page?.close() }
            runCatching { renderer?.close() }
            runCatching { pfd?.close() }
            runCatching { tmp.delete() }
        }
    }

    /**
     * 把位图压成 1bpp 点阵：每行左对齐、高位在左，行字节数 = ceil(宽 / 8)。
     *
     * @param invert true = 黑白取反（个别机型 0 才是黑）。
     */
    fun toMono(bmp: Bitmap, invert: Boolean = false): ByteArray {
        val w = bmp.width
        val h = bmp.height
        val rowBytes = (w + 7) / 8
        val out = ByteArray(rowBytes * h)
        val px = IntArray(w)
        for (y in 0 until h) {
            bmp.getPixels(px, 0, w, 0, y, w, 1)
            val base = y * rowBytes
            for (x in 0 until w) {
                val c = px[x]
                val lum = (Color.red(c) * 299 + Color.green(c) * 587 + Color.blue(c) * 114) / 1000
                var black = lum < THRESHOLD
                if (invert) black = !black
                if (black) {
                    val i = base + (x shr 3)
                    out[i] = (out[i].toInt() or (0x80 ushr (x and 7))).toByte()
                }
            }
        }
        return out
    }
}

/**
 * 通用蓝牙打印机驱动（经典蓝牙 SPP）。
 *
 * 硕方机型是私有协议，连不上；但市面上绝大多数蓝牙标签机 / 热敏机走的都是
 * 标准 **SPP（串口）** 通道，配上 TSPL 或 ESC/POS 指令就能直接打。
 * 这里直接用 Android 自带的 BluetoothSocket，不依赖任何第三方 SDK。
 */
class GenericPrinter(private val context: Context) {

    companion object {
        private const val TAG = "GenericPrinter"

        /** 经典蓝牙 SPP 标准 UUID。 */
        private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

        /** 单次写入上限，避免一次塞太多把机型串口缓冲撑爆。 */
        private const val CHUNK = 1024
    }

    private var socket: BluetoothSocket? = null
    private var out: OutputStream? = null

    /** 当前已连接的设备 MAC。 */
    @Volatile
    var address: String? = null
        private set

    val isConnected: Boolean get() = socket?.isConnected == true

    /** 连接设备（阻塞式，调用方放后台线程）。 */
    fun connect(mac: String): Boolean {
        disconnect()
        val adapter = BluetoothAdapter.getDefaultAdapter() ?: return false
        if (!adapter.isEnabled) return false
        runCatching { if (adapter.isDiscovering) adapter.cancelDiscovery() }
        val device = runCatching { adapter.getRemoteDevice(mac) }.getOrNull() ?: return false

        // 先试带鉴权的通道，失败再试不安全通道 —— 不同机型支持的不一样。
        val candidates = listOf(
            runCatching { device.createRfcommSocketToServiceRecord(SPP_UUID) }.getOrNull(),
            runCatching { device.createInsecureRfcommSocketToServiceRecord(SPP_UUID) }.getOrNull(),
        )
        for (s in candidates) {
            if (s == null) continue
            try {
                s.connect()
                socket = s
                out = s.outputStream
                address = mac
                Log.i(TAG, "SPP 连接成功 $mac")
                return true
            } catch (e: Throwable) {
                Log.w(TAG, "SPP 通道失败，换下一个", e)
                runCatching { s.close() }
            }
        }
        return false
    }

    fun disconnect() {
        runCatching { out?.close() }
        runCatching { socket?.close() }
        out = null
        socket = null
        address = null
    }

    /** 分片把指令流写出去（阻塞式）。 */
    fun send(data: ByteArray): Boolean {
        val o = out ?: return false
        return try {
            var off = 0
            while (off < data.size) {
                val n = minOf(CHUNK, data.size - off)
                o.write(data, off, n)
                off += n
            }
            o.flush()
            true
        } catch (e: Throwable) {
            Log.w(TAG, "写入失败", e)
            false
        }
    }
}

/**
 * 各协议的指令生成。
 *
 * 统一策略：**整张位图打印**（不逐元素排文本）。这样纸面效果和 App 预览
 * 像素级一致，也不用管各机型字库差异、中文编码差异。
 */
object PrinterCommands {

    private fun ascii(s: String) = s.toByteArray(Charsets.US_ASCII)

    /**
     * TSPL / TSPL2 头部：纸张、间隙、方向、浓度、速度、清屏 + BITMAP 指令头。
     * 之后直接跟点阵数据，再跟 [tsplTail]。
     */
    fun tsplHead(
        widthMm: Int,
        heightMm: Int,
        gapMm: Int,
        rowBytes: Int,
        heightDots: Int,
        density: Int,
        speed: Int,
    ): ByteArray {
        val sb = StringBuilder()
        sb.append("SIZE ").append(widthMm).append(" mm,").append(heightMm).append(" mm\r\n")
        sb.append("GAP ").append(gapMm.coerceIn(0, 8)).append(" mm,0 mm\r\n")
        sb.append("DIRECTION 1\r\n")
        sb.append("REFERENCE 0,0\r\n")
        sb.append("DENSITY ").append(density.coerceIn(0, 15)).append("\r\n")
        sb.append("SPEED ").append(speed.coerceIn(1, 6)).append("\r\n")
        sb.append("CLS\r\n")
        sb.append("BITMAP 0,0,").append(rowBytes).append(",").append(heightDots).append(",0,")
        return ascii(sb.toString())
    }

    /** TSPL 尾部：结束点阵 + 出纸。 */
    fun tsplTail(copies: Int): ByteArray =
        ascii("\r\nPRINT ${copies.coerceIn(1, 99)},1\r\n")

    /** ESC/POS 头部：初始化 + 居中 + `GS v 0` 光栅指令头。 */
    fun escposHead(rowBytes: Int, heightDots: Int): ByteArray {
        val bos = ByteArrayOutputStream()
        bos.write(byteArrayOf(0x1B, 0x40))            // ESC @  初始化
        bos.write(byteArrayOf(0x1B, 0x61, 0x01))      // ESC a 1 居中
        bos.write(byteArrayOf(0x1D, 0x76, 0x30, 0x00)) // GS v 0 m=0 光栅位图
        bos.write(rowBytes and 0xFF)
        bos.write((rowBytes shr 8) and 0xFF)
        bos.write(heightDots and 0xFF)
        bos.write((heightDots shr 8) and 0xFF)
        return bos.toByteArray()
    }

    /** ESC/POS 尾部：走纸到间隙 + 按份数重复。 */
    fun escposTail(copies: Int, feedLines: Int, body: ByteArray, head: ByteArray): ByteArray {
        val bos = ByteArrayOutputStream()
        repeat(feedLines.coerceIn(0, 8)) {
            bos.write(byteArrayOf(0x1B, 0x64, 0x01)) // ESC d 1 走纸 1 行
        }
        val tail = bos.toByteArray()
        val one = ByteArrayOutputStream()
        one.write(head)
        one.write(body)
        one.write(tail)
        val single = one.toByteArray()

        val all = ByteArrayOutputStream()
        repeat(copies.coerceIn(1, 99)) { all.write(single) }
        return all.toByteArray()
    }
}
