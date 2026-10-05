package com.myvault.myvault

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.pdf.PdfRenderer
import android.media.ExifInterface
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.concurrent.thread

/**
 * The phone's side of personal documents (channel "myvault/docs"):
 * take a photo or pick files, read the text in them (Google's on-device text
 * reader, bundled with the app: nothing is sent anywhere), show a PDF's first
 * page, save a plain copy where you choose, and hand reminders to ReminderJob.
 * Files come back as bytes; the Dart side encrypts them straight away.
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
            "camera" -> {
                val dir = File(activity.cacheDir, "camera").apply { mkdirs() }
                val f = File(dir, "scan-${System.currentTimeMillis()}.jpg")
                photo = f
                val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", f)
                start(result, CAMERA, Intent(android.provider.MediaStore.ACTION_IMAGE_CAPTURE).apply {
                    putExtra(android.provider.MediaStore.EXTRA_OUTPUT, uri)
                    addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                })
            }
            "ocr" -> {
                val bytes = call.argument<ByteArray>("bytes")!!
                thread {
                    try {
                        val bmp = if (isPdf(bytes)) pdfPage(bytes, 2000) else decode(bytes, MAX_SIDE)
                        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                            .process(InputImage.fromBitmap(bmp, 0))
                            .addOnSuccessListener { activity.runOnUiThread { result.success(it.text) } }
                            .addOnFailureListener { activity.runOnUiThread { result.error("ocr", it.message, null) } }
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

    fun onPermissionResult(code: Int): Boolean {
        if (code != NOTIFY) return false
        pending?.success(notifyAllowed())
        pending = null
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
