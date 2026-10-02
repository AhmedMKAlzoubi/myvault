package com.myvault.myvault

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.os.Bundle
import android.os.PersistableBundle
import android.view.WindowManager
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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
        // Updates: hand a downloaded/received APK to Android's own installer.
        // Android refuses it unless it's signed with the same key as this app.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "myvault/update").setMethodCallHandler { call, result ->
            if (call.method != "installApk") return@setMethodCallHandler result.notImplemented()
            if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
                // First time only: the user allows "Install unknown apps" for MyVault.
                startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                return@setMethodCallHandler result.success(false)
            }
            val apk = File(call.arguments as String)
            val uri = FileProvider.getUriForFile(this, "$packageName.updates", apk)
            startActivity(Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            })
            result.success(true)
        }
    }
}
