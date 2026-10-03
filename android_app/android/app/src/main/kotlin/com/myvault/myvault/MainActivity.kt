package com.myvault.myvault

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.os.Bundle
import android.os.PersistableBundle
import android.view.WindowManager
import androidx.core.content.FileProvider
import java.io.File
import java.security.MessageDigest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    /** Only ever hand Android's installer an APK that is this very app: the same
     *  package name and the same signing certificate as the installed MyVault.
     *  A look-alike with another package name would otherwise install beside it. */
    private fun isOwnUpdate(apk: File): Boolean {
        val archive = archiveInfo(apk) ?: return false
        if (archive.packageName != packageName) return false
        val theirs = certs(archive)
        val mine = certs(packageManager.getPackageInfo(packageName, signingFlags()))
        return theirs.isNotEmpty() && theirs == mine
    }

    private fun signingFlags(): Int =
        if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES
        else @Suppress("DEPRECATION") PackageManager.GET_SIGNATURES

    private fun archiveInfo(apk: File): PackageInfo? {
        val info = packageManager.getPackageArchiveInfo(apk.path, signingFlags())
        if (info != null && certs(info).isEmpty() && Build.VERSION.SDK_INT >= 28) {
            // Some Android versions only fill archive signatures for the older flag.
            @Suppress("DEPRECATION")
            return packageManager.getPackageArchiveInfo(apk.path, PackageManager.GET_SIGNATURES)
        }
        return info
    }

    private fun certs(p: PackageInfo): Set<String> {
        @Suppress("DEPRECATION")
        val sigs = if (Build.VERSION.SDK_INT >= 28 && p.signingInfo != null) p.signingInfo!!.apkContentsSigners
                   else p.signatures
        return sigs?.map { s ->
            MessageDigest.getInstance("SHA-256").digest(s.toByteArray()).joinToString("") { "%02x".format(it) }
        }?.toSet() ?: emptySet()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // No screenshots, screen recording, or preview in the recent-apps switcher.
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "myvault/clipboard").setMethodCallHandler { call, result ->
            val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            when (call.method) {
                "copySensitive" -> {
                    val clip = ClipData.newPlainText("MyVault", call.arguments as String)
                    // Android 13+: hide the value from the clipboard preview and keyboard history.
                    clip.description.extras = PersistableBundle().apply {
                        if (Build.VERSION.SDK_INT >= 33) putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
                        else putBoolean("android.content.extra.IS_SENSITIVE", true)
                    }
                    cm.setPrimaryClip(clip)
                    result.success(null)
                }
                "clear" -> {
                    if (Build.VERSION.SDK_INT >= 28) cm.clearPrimaryClip() else cm.setPrimaryClip(ClipData.newPlainText("", ""))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        // Autofill in other apps: is MyVault the autofill provider, open the
        // setting, and collect logins captured while the vault was locked.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "myvault/autofill_setup").setMethodCallHandler { call, result ->
            val afm = if (Build.VERSION.SDK_INT >= 26) getSystemService(android.view.autofill.AutofillManager::class.java) else null
            when (call.method) {
                "status" -> result.success(mapOf(
                    "supported" to (afm?.isAutofillSupported == true),
                    "enabled" to (afm?.hasEnabledAutofillServices() == true)))
                "open" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_REQUEST_SET_AUTOFILL_SERVICE, Uri.parse("package:$packageName")))
                    } catch (_: Exception) {
                        startActivity(Intent(Settings.ACTION_SETTINGS))
                    }
                    result.success(true)
                }
                "takeInbox" -> result.success(CaptureInbox.take(this))
                else -> result.notImplemented()
            }
        }
        // Updates: hand a downloaded/received APK to Android's own installer.
        // Android refuses it unless it's signed with the same key as this app.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "myvault/update").setMethodCallHandler { call, result ->
            if (call.method == "openDoc") {
                // Only MyVault's own published documents, never an arbitrary URL.
                val name = setOf("PRIVACY.md", "TERMS.md", "SECURITY.md", "CHANGELOG.md")
                    .firstOrNull { it == call.arguments }
                    ?: return@setMethodCallHandler result.error("bad_doc", "Unknown document.", null)
                startActivity(Intent(Intent.ACTION_VIEW,
                    Uri.parse("https://github.com/AhmedMKAlzoubi/myvault/blob/main/$name")))
                return@setMethodCallHandler result.success(true)
            }
            if (call.method != "installApk") return@setMethodCallHandler result.notImplemented()
            if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
                // First time only: the user allows "Install unknown apps" for MyVault.
                startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                return@setMethodCallHandler result.success(false)
            }
            val apk = File(call.arguments as String)
            if (!isOwnUpdate(apk)) {
                return@setMethodCallHandler result.error(
                    "not_myvault", "That file isn't MyVault signed with MyVault's key, so it won't be installed.", null)
            }
            val uri = FileProvider.getUriForFile(this, "$packageName.updates", apk)
            startActivity(Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            })
            result.success(true)
        }
    }
}
