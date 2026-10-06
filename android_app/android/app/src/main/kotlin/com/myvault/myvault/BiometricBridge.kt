package com.myvault.myvault

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Unlock with a fingerprint or face: the master password is kept encrypted by a
 * key in Android's Keystore that only opens after a strong biometric check, and
 * stops working if a new fingerprint is enrolled. Nothing leaves the phone.
 * Android 10+ only, where the system draws the prompt itself.
 */
class BiometricBridge(private val activity: FragmentActivity) {
    // Each vault has its own Keystore key and stored password ("default" keeps
    // the original names), so turning it on for one never touches another.
    private var vault = "default"
    private val file get() = File(activity.noBackupFilesDir, if (vault == "default") "unlock.bin" else "unlock-$vault.bin")
    private val alias get() = if (vault == "default") "myvault_unlock" else "myvault_unlock_$vault"

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        vault = call.argument<String>("vault")?.takeIf { Regex("^(default|[0-9a-f]{32})$").matches(it) } ?: "default"
        when (call.method) {
            "status" -> result.success(mapOf("available" to available(), "enabled" to (available() && file.exists())))
            "enable" -> enable(call.argument<String>("password") ?: "", call, result)
            "unlock" -> unlock(call, result)
            "disable" -> { disable(); result.success(true) }
            else -> result.notImplemented()
        }
    }

    private fun available() = Build.VERSION.SDK_INT >= 29 &&
        BiometricManager.from(activity).canAuthenticate(BIOMETRIC_STRONG) == BiometricManager.BIOMETRIC_SUCCESS

    private fun keyStore() = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    private fun key(create: Boolean): SecretKey? {
        (keyStore().getKey(alias, null) as SecretKey?)?.let { return it }
        if (!create) return null
        val spec = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)
            .apply { if (Build.VERSION.SDK_INT >= 30) setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG) }
            .build()
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run { init(spec); generateKey() }
    }

    private fun prompt(cipher: Cipher, call: MethodCall, result: MethodChannel.Result, done: (Cipher) -> Any) {
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(call.argument<String>("title") ?: "MyVault")
            .setNegativeButtonText(call.argument<String>("cancel") ?: "Cancel")
            .setAllowedAuthenticators(BIOMETRIC_STRONG)
            .build()
        BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(r: BiometricPrompt.AuthenticationResult) {
                try { result.success(done(r.cryptoObject!!.cipher!!)) }
                catch (e: Exception) { result.error("failed", e.message, null) }
            }
            override fun onAuthenticationError(code: Int, msg: CharSequence) {
                val cancelled = code == BiometricPrompt.ERROR_NEGATIVE_BUTTON || code == BiometricPrompt.ERROR_USER_CANCELED ||
                    code == BiometricPrompt.ERROR_CANCELED
                result.error(if (cancelled) "cancelled" else "error", msg.toString(), null)
            }
        }).authenticate(info, BiometricPrompt.CryptoObject(cipher))
    }

    private fun enable(password: String, call: MethodCall, result: MethodChannel.Result) {
        try {
            disable()                                // a fresh key each time
            val c = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key(true)) }
            prompt(c, call, result) { ok ->
                file.writeBytes(ok.iv + ok.doFinal(password.toByteArray(Charsets.UTF_8)))
                true
            }
        } catch (e: Exception) {
            disable()
            result.error("error", e.message, null)
        }
    }

    private fun unlock(call: MethodCall, result: MethodChannel.Result) {
        val data = if (file.exists()) file.readBytes() else return result.error("off", "Fingerprint unlock is off.", null)
        try {
            val k = key(false) ?: throw KeyPermanentlyInvalidatedException()
            val c = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE, k, GCMParameterSpec(128, data, 0, 12)) }
            prompt(c, call, result) { ok -> String(ok.doFinal(data, 12, data.size - 12), Charsets.UTF_8) }
        } catch (e: KeyPermanentlyInvalidatedException) {
            disable()     // a fingerprint was added or removed: the password is needed once more
            result.error("changed", "Your fingerprints changed.", null)
        } catch (e: Exception) {
            result.error("error", e.message, null)
        }
    }

    private fun disable() {
        file.delete()
        try { keyStore().deleteEntry(alias) } catch (_: Exception) {}
    }
}
