package com.myvault.myvault

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.service.autofill.Dataset
import android.view.WindowManager
import android.view.autofill.AutofillId
import android.view.autofill.AutofillManager
import android.view.autofill.AutofillValue
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Opened when you tap "Fill with MyVault" in another app. Runs MyVault's own
 * unlock screen; once you unlock and pick an account, the Dart side calls
 * "fill" and this activity hands Android the values for just those two boxes.
 */
class AutofillAuthActivity : FlutterFragmentActivity() {
    private val biometric by lazy { BiometricBridge(this) }
    companion object {
        const val EXTRA_TARGET = "mv_target"
        const val EXTRA_IS_WEB = "mv_is_web"
        const val EXTRA_LABEL = "mv_label"
        const val EXTRA_USERNAME_ID = "mv_user_id"
        const val EXTRA_PASSWORD_ID = "mv_pass_id"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
    }

    @Suppress("DEPRECATION")
    private fun id(extra: String): AutofillId? =
        if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(extra, AutofillId::class.java)
        else intent.getParcelableExtra(extra)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "myvault/biometric").setMethodCallHandler { call, result ->
            biometric.handle(call, result)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "myvault/autofill").setMethodCallHandler { call, result ->
            when (call.method) {
                "request" -> result.success(mapOf(
                    "target" to (intent.getStringExtra(EXTRA_TARGET) ?: ""),
                    "web" to intent.getBooleanExtra(EXTRA_IS_WEB, false),
                    "label" to (intent.getStringExtra(EXTRA_LABEL) ?: ""),
                    "hasUser" to (id(EXTRA_USERNAME_ID) != null),
                ))
                "fill" -> {
                    val user = call.argument<String>("username") ?: ""
                    val pass = call.argument<String>("password") ?: ""
                    val ds = Dataset.Builder(MyVaultAutofillService.presentation(this, "MyVault"))
                    id(EXTRA_USERNAME_ID)?.let { if (user.isNotEmpty()) ds.setValue(it, AutofillValue.forText(user)) }
                    id(EXTRA_PASSWORD_ID)?.let { ds.setValue(it, AutofillValue.forText(pass)) }
                    setResult(RESULT_OK, Intent().putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT, ds.build()))
                    result.success(true)
                    finish()
                }
                "cancel" -> {
                    setResult(RESULT_CANCELED)
                    result.success(true)
                    finish()
                }
                else -> result.notImplemented()
            }
        }
    }
}
