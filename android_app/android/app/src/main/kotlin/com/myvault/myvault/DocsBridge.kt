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
import java.io.ByteArrayOutputStream
import java.io.File
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
            "saveCopy" -> {
                pendingSave = call.argument<ByteArray>("bytes")
                start(result, SAVE, Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = call.argument<String>("mime") ?: "application/octet-stream"
                    putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "document")
                })
            }
            "setReminders" -> {
                ReminderJob.save(activity, call.arguments as String)
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
        if (code !in listOf(PICK, CAMERA, SAVE)) return false
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
