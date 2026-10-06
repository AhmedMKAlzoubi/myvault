package com.myvault.myvault

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.pdf.PdfDocument
import android.graphics.pdf.PdfRenderer
import android.media.ExifInterface
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream
import kotlin.concurrent.thread

/**
 * The phone's side of personal documents (channel "myvault/docs"):
 * take a photo or pick files, find a document's corners in a photo and
 * straighten it, read the text (Tesseract, open source, built into the app:
 * nothing is sent anywhere, and no Google services are used), show a PDF's
 * first page, save a plain copy where you choose, and hand reminders to
 * ReminderJob. Files come back as bytes; the Dart side encrypts them at once.
 */
class DocsBridge(private val activity: Activity) {
    private var pending: MethodChannel.Result? = null
    private var pendingSave: ByteArray? = null
    private var photo: File? = null

    companion object {
        const val PICK = 7101
        const val CAMERA = 7102
        const val SAVE = 7103
        const val NOTIFY = 7104
        const val CAMERA_OK = 7106
        const val PICK_COPY = 7107
        const val MAX_SIDE = 2400        // photos are scaled down to this: sharp enough to read, small to sync
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pick" -> start(result, PICK, Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/jpeg", "image/png", "image/webp", "application/pdf"))
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            })
            // MyVault's own scanner (the Dart side's crop screen): where the document's
            // corners are, then the photo cut out and straightened, or turned.
            "detect" -> background(result) { corners(call.argument<ByteArray>("bytes")!!) }
            "warp" -> background(result) {
                warp(call.argument<ByteArray>("bytes")!!, call.argument<List<Double>>("points")!!)
            }
            "rotate" -> background(result) {
                jpeg(decode(call.argument<ByteArray>("bytes")!!, MAX_SIDE).let {
                    Bitmap.createBitmap(it, 0, 0, it.width, it.height, Matrix().apply { postRotate(90f) }, true)
                })
            }
            "testNotify" -> {
                ReminderJob.notifyNow(activity, "test", call.arguments as String)
                result.success(notifyAllowed())
            }
            "camera" -> {
                // Android refuses the camera app to an app that declares the camera
                // permission (MyVault does, for QR codes) until it's been allowed.
                if (activity.checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
                    pending?.success(null)
                    pending = result
                    activity.requestPermissions(arrayOf(Manifest.permission.CAMERA), CAMERA_OK)
                } else {
                    openCamera(result)
                }
            }
            "ocr" -> {
                val bytes = call.argument<ByteArray>("bytes")!!
                thread {
                    try {
                        val text = ocr(if (isPdf(bytes)) pdfPage(bytes, 2000) else decode(bytes, MAX_SIDE))
                        activity.runOnUiThread { result.success(text) }
                    } catch (e: Exception) {
                        activity.runOnUiThread { result.error("ocr", "That file couldn't be read.", null) }
                    }
                }
            }
            // The "scanned" look (or black and white) for a cropped page.
            "enhance" -> background(result) {
                enhance(call.argument<ByteArray>("bytes")!!, call.argument<String>("mode") ?: "scan")
            }
            // Download as PDF / Word (every page, like a photocopy) or PNG / JPEG.
            "export" -> background(result) {
                export(call.argument<List<ByteArray>>("files")!!, call.argument<String>("format")!!)
            }
            "pdfPreview" -> {
                val bytes = call.argument<ByteArray>("bytes")!!
                val width = call.argument<Int>("width") ?: 900
                thread {
                    try {
                        val out = ByteArrayOutputStream()
                        pdfPage(bytes, width).compress(Bitmap.CompressFormat.PNG, 100, out)
                        activity.runOnUiThread { result.success(out.toByteArray()) }
                    } catch (e: Exception) {
                        activity.runOnUiThread { result.error("pdf", "That PDF couldn't be shown.", null) }
                    }
                }
            }
            // A copy of a vault (.zip): picked whole, and made or read here.
            "pickCopy" -> start(result, PICK_COPY, Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/zip", "application/x-zip-compressed", "application/octet-stream"))
            })
            "zip" -> background(result) { zip(call.argument<Map<String, ByteArray>>("files")!!) }
            "unzip" -> background(result) { unzip(call.argument<ByteArray>("bytes")!!) }
            "saveCopy" -> {
                pendingSave = call.argument<ByteArray>("bytes")
                start(result, SAVE, Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = call.argument<String>("mime") ?: "application/octet-stream"
                    putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "document")
                })
            }
            "setReminders" -> {
                ReminderJob.save(activity, call.argument<String>("vault") ?: "default", call.argument<String>("json") ?: "[]")
                result.success(true)
            }
            "notifyAllowed" -> result.success(notifyAllowed())
            "askNotify" -> {
                if (notifyAllowed() || Build.VERSION.SDK_INT < 33) return result.success(notifyAllowed())
                pending = result
                activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFY)
            }
            else -> result.notImplemented()
        }
    }

    private fun notifyAllowed() = Build.VERSION.SDK_INT < 33 ||
        activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    private fun start(result: MethodChannel.Result, code: Int, intent: Intent) {
        pending?.success(null)            // a previous request that never came back
        pending = result
        try {
            activity.startActivityForResult(intent, code)
        } catch (e: Exception) {
            pending = null
            result.error("intent", "Your phone has no app for that.", null)
        }
    }

    private fun openCamera(result: MethodChannel.Result) {
        val dir = File(activity.cacheDir, "camera").apply { mkdirs() }
        val f = File(dir, "scan-${System.currentTimeMillis()}.jpg")
        photo = f
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", f)
        start(result, CAMERA, Intent(android.provider.MediaStore.ACTION_IMAGE_CAPTURE).apply {
            putExtra(android.provider.MediaStore.EXTRA_OUTPUT, uri)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
        })
    }

    fun onPermissionResult(code: Int): Boolean {
        val result = pending
        when (code) {
            NOTIFY -> { pending = null; result?.success(notifyAllowed()) }
            CAMERA_OK -> {
                pending = null
                if (result == null) return true
                if (activity.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) openCamera(result)
                else result.error("camera", "Allow the camera for MyVault to take a photo (Android settings › Apps › MyVault › Permissions).", null)
            }
            else -> return false
        }
        return true
    }

    fun onActivityResult(code: Int, resultCode: Int, data: Intent?): Boolean {
        if (code !in listOf(PICK, CAMERA, SAVE, PICK_COPY)) return false
        val result = pending ?: return true
        pending = null
        if (resultCode != Activity.RESULT_OK) {
            photo?.delete()
            return true.also { result.success(null) }
        }
        thread {
            try {
                val out: Any? = when (code) {
                    PICK -> {
                        val uris = data?.clipData?.let { c -> (0 until c.itemCount).map { c.getItemAt(it).uri } }
                            ?: listOfNotNull(data?.data)
                        uris.map { mapOf("name" to nameOf(it), "bytes" to shrink(read(it))) }
                    }
                    PICK_COPY -> data?.data?.let { read(it) }
                    CAMERA -> photo?.let { f ->
                        val bytes = shrink(f.readBytes())
                        f.delete()
                        listOf(mapOf("name" to "scan-${System.currentTimeMillis() / 1000}.jpg", "bytes" to bytes))
                    }
                    else -> {
                        data?.data?.let { uri -> activity.contentResolver.openOutputStream(uri)?.use { it.write(pendingSave) } }
                        pendingSave = null
                        true
                    }
                }
                activity.runOnUiThread { result.success(out) }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("file", "That file couldn't be opened.", null) }
            }
        }
        return true
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) = thread {
        try {
            val out = work()
            activity.runOnUiThread { result.success(out) }
        } catch (e: Exception) {
            activity.runOnUiThread { result.error("image", "That photo couldn't be used.", null) }
        }
    }

    private fun jpeg(bmp: Bitmap): ByteArray =
        ByteArrayOutputStream().also { bmp.compress(Bitmap.CompressFormat.JPEG, 90, it) }.toByteArray()

    // ---- reading text: Tesseract with its English and Arabic models (assets/tessdata) ----
    private fun tessDir(): File {
        val dir = File(activity.noBackupFilesDir, "ocr")
        val data = File(dir, "tessdata").apply { mkdirs() }
        val stamp = File(dir, "installed")
        val build = activity.packageManager.getPackageInfo(activity.packageName, 0).lastUpdateTime.toString()
        if (!stamp.exists() || stamp.readText() != build) {       // first use, or a new MyVault
            for (lang in listOf("eng", "ara")) {
                val tmp = File(data, "$lang.tmp")
                activity.assets.open("tessdata/$lang.traineddata").use { i -> tmp.outputStream().use { i.copyTo(it) } }
                tmp.renameTo(File(data, "$lang.traineddata"))
            }
            stamp.writeText(build)
        }
        return dir
    }

    private fun ocr(bmp: Bitmap): String {
        val dir = tessDir().path
        fun read(langs: String, mode: Int, only: String?): String {
            val api = TessBaseAPI()
            try {
                if (!api.init(dir, langs, TessBaseAPI.OEM_LSTM_ONLY)) throw IllegalStateException("no text reader")
                api.setPageSegMode(mode)
                if (only != null) api.setVariable(TessBaseAPI.VAR_CHAR_WHITELIST, only)
                api.setImage(bmp)
                return api.getUTF8Text() ?: ""
            } finally {
                api.recycle()
            }
        }
        val text = read("eng+ara", TessBaseAPI.PageSegMode.PSM_AUTO, null)
        // A machine-readable zone (<<<): read it again with only the characters it can have.
        if ("<<" !in text && "«" !in text) return text
        return text + "\n" + read("eng", TessBaseAPI.PageSegMode.PSM_SINGLE_BLOCK, "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789<")
    }

    // ---- MyVault's own scanner -------------------------------------------------------
    /** The document's corners in a photo (top-left, top-right, bottom-right,
     *  bottom-left, as fractions), or null. ponytail: a light/dark split and a flood
     *  from the photo's edges, not real edge detection; it finds a card on a
     *  contrasting surface, and the person drags the corners when it doesn't. */
    private fun corners(bytes: ByteArray): List<Double>? {
        val small = decode(bytes, 320)
        val w = small.width
        val h = small.height
        val px = IntArray(w * h).also { small.getPixels(it, 0, w, 0, 0, w, h) }
        val lum = IntArray(w * h) { ((px[it] shr 16 and 255) * 299 + (px[it] shr 8 and 255) * 587 + (px[it] and 255) * 114) / 1000 }
        // Otsu: the brightness that best splits the photo in two
        val hist = IntArray(256).also { hh -> lum.forEach { hh[it]++ } }
        val total = lum.size.toLong()
        val sumAll = (0..255).sumOf { it.toLong() * hist[it] }
        var wb = 0L
        var sb = 0L
        var best = -1.0
        var cut = 127
        for (i in 0..255) {
            wb += hist[i]
            if (wb == 0L || wb == total) continue
            sb += i.toLong() * hist[i]
            val d = sb.toDouble() / wb - (sumAll - sb).toDouble() / (total - wb)
            val v = wb.toDouble() * (total - wb) * d * d
            if (v > best) { best = v; cut = i }
        }
        val light = BooleanArray(w * h) { lum[it] > cut }
        // the background is whatever most of the photo's border is; flood it in from there
        val edge = (0 until w).flatMap { listOf(it, (h - 1) * w + it) } + (0 until h).flatMap { listOf(it * w, it * w + w - 1) }
        val bg = edge.count { light[it] } * 2 > edge.size
        val outside = BooleanArray(w * h)
        val q = ArrayDeque<Int>()
        fun flood(i: Int) { if (!outside[i] && light[i] == bg) { outside[i] = true; q.add(i) } }
        edge.forEach { flood(it) }
        while (q.isNotEmpty()) {
            val i = q.removeFirst()
            val x = i % w
            if (x > 0) flood(i - 1)
            if (x < w - 1) flood(i + 1)
            if (i >= w) flood(i - w)
            if (i < w * (h - 1)) flood(i + w)
        }
        // the biggest piece left is the document (a photo printed on it is inside it)
        val label = IntArray(w * h)
        var bestLabel = 0
        var bestSize = 0
        var next = 0
        for (start in 0 until w * h) {
            if (outside[start] || label[start] != 0) continue
            next++
            var size = 0
            label[start] = next
            q.add(start)
            while (q.isNotEmpty()) {
                val i = q.removeFirst()
                size++
                val x = i % w
                for (n in intArrayOf(if (x > 0) i - 1 else -1, if (x < w - 1) i + 1 else -1, i - w, if (i < w * (h - 1)) i + w else -1)) {
                    if (n >= 0 && !outside[n] && label[n] == 0) { label[n] = next; q.add(n) }
                }
            }
            if (size > bestSize) { bestSize = size; bestLabel = next }
        }
        if (bestSize < w * h * 0.15 || bestSize > w * h * 0.97) return null
        var tl = -1; var tr = -1; var br = -1; var bl = -1
        fun x(i: Int) = i % w
        fun y(i: Int) = i / w
        for (i in 0 until w * h) {
            if (label[i] != bestLabel) continue
            if (tl < 0 || x(i) + y(i) < x(tl) + y(tl)) tl = i
            if (br < 0 || x(i) + y(i) > x(br) + y(br)) br = i
            if (tr < 0 || x(i) - y(i) > x(tr) - y(tr)) tr = i
            if (bl < 0 || x(i) - y(i) < x(bl) - y(bl)) bl = i
        }
        return listOf(tl, tr, br, bl).flatMap { listOf((x(it) + .5) / w, (y(it) + .5) / h) }
    }

    /** The part of the photo inside the four corners, straightened into a rectangle. */
    private fun warp(bytes: ByteArray, p: List<Double>): ByteArray {
        val src = decode(bytes, MAX_SIDE)
        val pts = FloatArray(8) { (p[it] * if (it % 2 == 0) src.width else src.height).toFloat() }
        fun dist(a: Int, b: Int) = Math.hypot((pts[a] - pts[b]).toDouble(), (pts[a + 1] - pts[b + 1]).toDouble())
        var w = maxOf(dist(0, 2), dist(6, 4))
        var h = maxOf(dist(0, 6), dist(2, 4))
        val scale = minOf(1.0, MAX_SIDE / maxOf(w, h))
        w *= scale
        h *= scale
        val out = Bitmap.createBitmap(w.toInt().coerceAtLeast(1), h.toInt().coerceAtLeast(1), Bitmap.Config.ARGB_8888)
        val dst = floatArrayOf(0f, 0f, out.width.toFloat(), 0f, out.width.toFloat(), out.height.toFloat(), 0f, out.height.toFloat())
        val m = Matrix().apply { setPolyToPoly(pts, 0, dst, 0, 4) }
        Canvas(out).drawBitmap(src, m, Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG))
        return jpeg(out)
    }

    // ---- the "scanned" look ------------------------------------------------------------
    /** Like a flatbed scanner: the paper's colour becomes clean white (which also
     *  takes away a colour cast), the darkest ink becomes black, and the text gets a
     *  little sharper. The brightening is capped, so a photo on the card isn't
     *  washed out. "bw" also turns it into crisp black and white, for letters. */
    private fun enhance(bytes: ByteArray, mode: String): ByteArray {
        val src = decode(bytes, MAX_SIDE)
        if (mode == "original") return jpeg(src)
        val w = src.width
        val h = src.height
        val px = IntArray(w * h).also { src.getPixels(it, 0, w, 0, 0, w, h) }
        fun lum(c: Int) = ((c shr 16 and 255) * 299 + (c shr 8 and 255) * 587 + (c and 255) * 114) / 1000
        val hist = IntArray(256).also { hh -> px.forEach { hh[lum(it)]++ } }
        fun percentile(p: Double): Int {
            var n = 0L
            for (i in 0..255) { n += hist[i]; if (n >= px.size * p) return i }
            return 255
        }
        val paper = percentile(0.96)
        val ink = percentile(0.01)
        // the paper's own colour, from its brightest part
        var sr = 0L; var sg = 0L; var sb = 0L; var n = 0L
        for (c in px) if (lum(c) >= paper) { sr += c shr 16 and 255; sg += c shr 8 and 255; sb += c and 255; n++ }
        val gain = DoubleArray(3) { k -> minOf(1.6, 255.0 / maxOf(1L, listOf(sr, sg, sb)[k] / maxOf(1L, n))) }
        val black = ink * minOf(gain[0], gain[1], gain[2])
        val span = maxOf(40.0, 255.0 - black)
        val out = IntArray(w * h)
        for (i in px.indices) {
            val c = px[i]
            val v = IntArray(3) { k -> (((c shr (16 - 8 * k) and 255) * gain[k] - black) * 255.0 / span).toInt().coerceIn(0, 255) }
            out[i] = if (mode == "bw") {
                val l = (v[0] * 299 + v[1] * 587 + v[2] * 114) / 1000
                val g = ((l - 110) * 255 / 100).coerceIn(0, 255)        // a soft threshold
                Color.rgb(g, g, g)
            } else Color.rgb(v[0], v[1], v[2])
        }
        // a light sharpen: each pixel against its four neighbours
        val sharp = out.copyOf()
        for (y in 1 until h - 1) for (x in 1 until w - 1) {
            val i = y * w + x
            fun ch(j: Int, k: Int) = out[j] shr (16 - 8 * k) and 255
            val v = IntArray(3) { k ->
                val c = ch(i, k)
                (c + (4 * c - ch(i - 1, k) - ch(i + 1, k) - ch(i - w, k) - ch(i + w, k)) * 0.35).toInt().coerceIn(0, 255)
            }
            sharp[i] = Color.rgb(v[0], v[1], v[2])
        }
        return jpeg(Bitmap.createBitmap(sharp, w, h, Bitmap.Config.ARGB_8888))
    }

    // ---- downloading in another format (the same layout as the PC's export.py) ----------
    private val a4 = 595.28f to 841.89f
    private val margin = 36f
    private val card = 242.65f to 153.07f            // an ID card, 85.6 x 54 mm

    private fun isCard(b: Bitmap) = b.width.toFloat() / b.height in 1.45f..1.72f

    private fun pages(bytes: ByteArray): List<Bitmap> = if (!isPdf(bytes)) listOf(decode(bytes, MAX_SIDE)) else {
        val tmp = File.createTempFile("doc", ".pdf", activity.cacheDir)
        try {
            tmp.writeBytes(bytes)
            ParcelFileDescriptor.open(tmp, ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
                PdfRenderer(fd).use { r ->
                    (0 until r.pageCount).map { i ->
                        r.openPage(i).use { page ->
                            val width = 1700
                            Bitmap.createBitmap(width, width * page.height / page.width, Bitmap.Config.ARGB_8888).also {
                                it.eraseColor(Color.WHITE)
                                page.render(it, null, null, PdfRenderer.Page.RENDER_MODE_FOR_PRINT)
                            }
                        }
                    }
                }
            }
        } finally {
            tmp.delete()             // the plain PDF never stays on disk
        }
    }

    /** Sheets of (page, left, top, width, height) in points: card-shaped pages at
     *  real ID-card size, two to a sheet; anything else fits the sheet. */
    private fun layout(pages: List<Bitmap>): List<List<Pair<Bitmap, RectF>>> {
        val sheets = mutableListOf<List<Pair<Bitmap, RectF>>>()
        var i = 0
        while (i < pages.size) {
            val b = pages[i]
            if (isCard(b)) {
                val cards = listOfNotNull(b, pages.getOrNull(i + 1)?.takeIf { isCard(it) })
                val x = (a4.first - card.first) / 2
                sheets.add(cards.mapIndexed { n, c ->
                    val y = margin * 2 + n * (card.second + margin)
                    c to RectF(x, y, x + card.first, y + card.second)
                })
                i += cards.size
                continue
            }
            val s = minOf((a4.first - 2 * margin) / b.width, (a4.second - 2 * margin) / b.height)
            val x = (a4.first - b.width * s) / 2
            sheets.add(listOf(b to RectF(x, margin, x + b.width * s, margin + b.height * s)))
            i++
        }
        return sheets
    }

    private fun export(files: List<ByteArray>, format: String): ByteArray {
        if (format == "png" || format == "jpeg") {
            val b = pages(files.first()).first()
            return ByteArrayOutputStream().also {
                b.compress(if (format == "png") Bitmap.CompressFormat.PNG else Bitmap.CompressFormat.JPEG, 92, it)
            }.toByteArray()
        }
        val all = files.flatMap { pages(it) }
        return if (format == "pdf") pdf(all) else docx(all)
    }

    private fun pdf(pages: List<Bitmap>): ByteArray {
        val doc = PdfDocument()
        val paint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
        layout(pages).forEachIndexed { n, sheet ->
            val page = doc.startPage(PdfDocument.PageInfo.Builder(a4.first.toInt(), a4.second.toInt(), n + 1).create())
            for ((b, r) in sheet) {
                // about 200 dpi at its size on paper: sharp, and the PDF stays small
                val px = (r.width() / 72f * 200f).toInt().coerceAtMost(b.width)
                val small = if (px < b.width) Bitmap.createScaledBitmap(b, px, px * b.height / b.width, true) else b
                page.canvas.drawBitmap(small, null, r, paint)
            }
            doc.finishPage(page)
        }
        return ByteArrayOutputStream().also { doc.writeTo(it); doc.close() }.toByteArray()
    }

    private fun docx(pages: List<Bitmap>): ByteArray {
        val emu = 12700f                                  // per point
        val body = StringBuilder()
        pages.forEachIndexed { i, b ->
            val n = i + 1
            val (w, h) = if (isCard(b)) card else {
                val s = minOf((a4.first - 144f) / b.width, (a4.second - 144f) / b.height)   // Word's 1-inch margins
                b.width * s to b.height * s
            }
            val cx = (w * emu).toLong()
            val cy = (h * emu).toLong()
            body.append("<w:p><w:pPr><w:jc w:val=\"center\"/></w:pPr><w:r><w:drawing><wp:inline><wp:extent cx=\"$cx\" cy=\"$cy\"/>")
                .append("<wp:docPr id=\"$n\" name=\"Page $n\"/><a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\">")
                .append("<pic:pic><pic:nvPicPr><pic:cNvPr id=\"$n\" name=\"page$n.jpg\"/><pic:cNvPicPr/></pic:nvPicPr>")
                .append("<pic:blipFill><a:blip r:embed=\"rId$n\"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>")
                .append("<pic:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"$cx\" cy=\"$cy\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></pic:spPr>")
                .append("</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>")
        }
        val ns = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" " +
            "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" " +
            "xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" " +
            "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" " +
            "xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\""
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { z ->
            fun put(name: String, data: ByteArray) { z.putNextEntry(ZipEntry(name)); z.write(data); z.closeEntry() }
            put("[Content_Types].xml", ("<?xml version=\"1.0\" encoding=\"UTF-8\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">" +
                "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>" +
                "<Default Extension=\"xml\" ContentType=\"application/xml\"/><Default Extension=\"jpg\" ContentType=\"image/jpeg\"/>" +
                "<Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>").toByteArray())
            put("_rels/.rels", ("<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" +
                "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>").toByteArray())
            put("word/_rels/document.xml.rels", ("<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" +
                pages.indices.joinToString("") { "<Relationship Id=\"rId${it + 1}\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/page${it + 1}.jpg\"/>" } +
                "</Relationships>").toByteArray())
            put("word/document.xml", ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:document $ns><w:body>$body" +
                "<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\"/></w:sectPr>" +
                "</w:body></w:document>").toByteArray())
            pages.forEachIndexed { i, b -> put("word/media/page${i + 1}.jpg", jpeg(b)) }
        }
        return out.toByteArray()
    }

    private fun zip(files: Map<String, ByteArray>): ByteArray = ByteArrayOutputStream().also { out ->
        ZipOutputStream(out).use { z ->
            for ((name, bytes) in files) {
                z.putNextEntry(ZipEntry(name))
                z.write(bytes)
                z.closeEntry()
            }
        }
    }.toByteArray()

    // Every member by name; the Dart side checks the names before writing anything.
    // ponytail: whole copy in memory, stream it to disk if vaults outgrow a few hundred MB
    private fun unzip(bytes: ByteArray): Map<String, ByteArray> {
        val out = LinkedHashMap<String, ByteArray>()
        var total = 0L
        ZipInputStream(ByteArrayInputStream(bytes)).use { z ->
            while (true) {
                val e = z.nextEntry ?: break
                if (e.isDirectory) continue
                val b = z.readBytes()
                total += b.size
                if (total > 1_000_000_000L) throw IOException("That copy is too big.")
                out[e.name] = b
            }
        }
        return out
    }

    private fun read(uri: Uri): ByteArray = activity.contentResolver.openInputStream(uri)!!.use { it.readBytes() }

    private fun nameOf(uri: Uri): String =
        activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        } ?: "document"

    private fun isPdf(b: ByteArray) = b.size > 4 && b[0] == '%'.code.toByte() && b[1] == 'P'.code.toByte()

    /** Photos: upright and at most MAX_SIDE px, as JPEG. PDFs and small images as they are. */
    private fun shrink(bytes: ByteArray): ByteArray {
        if (isPdf(bytes)) return bytes
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        val rotation = rotationOf(bytes)
        if (maxOf(bounds.outWidth, bounds.outHeight) <= MAX_SIDE && rotation == 0) return bytes
        val out = ByteArrayOutputStream()
        decode(bytes, MAX_SIDE).compress(Bitmap.CompressFormat.JPEG, 88, out)
        return out.toByteArray()
    }

    private fun rotationOf(bytes: ByteArray): Int = try {
        when (ExifInterface(bytes.inputStream()).getAttributeInt(ExifInterface.TAG_ORIENTATION, 1)) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90
            ExifInterface.ORIENTATION_ROTATE_180 -> 180
            ExifInterface.ORIENTATION_ROTATE_270 -> 270
            else -> 0
        }
    } catch (e: Exception) { 0 }

    private fun decode(bytes: ByteArray, maxSide: Int): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxSide) sample *= 2
        var bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
            ?: throw IllegalArgumentException("not an image")
        val scale = maxSide.toFloat() / maxOf(bmp.width, bmp.height)
        val m = Matrix().apply {
            if (scale < 1f) postScale(scale, scale)
            postRotate(rotationOf(bytes).toFloat())
        }
        if (!m.isIdentity) bmp = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, m, true)
        return bmp
    }

    private fun pdfPage(bytes: ByteArray, width: Int): Bitmap {
        val tmp = File.createTempFile("doc", ".pdf", activity.cacheDir)
        try {
            tmp.writeBytes(bytes)
            ParcelFileDescriptor.open(tmp, ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
                PdfRenderer(fd).use { r ->
                    r.openPage(0).use { page ->
                        val bmp = Bitmap.createBitmap(width, width * page.height / page.width, Bitmap.Config.ARGB_8888)
                        bmp.eraseColor(Color.WHITE)
                        page.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        return bmp
                    }
                }
            }
        } finally {
            tmp.delete()         // the plain PDF never stays on disk
        }
    }
}
