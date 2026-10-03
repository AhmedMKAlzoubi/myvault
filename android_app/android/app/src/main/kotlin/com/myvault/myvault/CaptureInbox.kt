package com.myvault.myvault

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Logins Android captured ("Save to MyVault?") while the vault was locked.
 * Each one is sealed with AES-256-GCM under a key that lives in the Android
 * Keystore (hardware-backed where the phone has it) and can't leave it. The app
 * reads and empties the inbox after you unlock, and adds the logins to the vault.
 */
object CaptureInbox {
    private const val ALIAS = "myvault_capture_inbox"
    private fun file(c: Context) = File(c.filesDir, "capture_inbox.txt")

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build())
        return gen.generateKey()
    }

    @Synchronized
    fun add(c: Context, item: JSONObject) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val sealed = cipher.iv + cipher.doFinal(item.toString().toByteArray(Charsets.UTF_8))
        file(c).appendText(Base64.encodeToString(sealed, Base64.NO_WRAP) + "\n")
    }

    /** Returns every captured login (as JSON text) and empties the inbox. */
    @Synchronized
    fun take(c: Context): List<String> {
        val f = file(c)
        if (!f.exists()) return emptyList()
        val k = key()
        val out = f.readLines().filter { it.isNotBlank() }.mapNotNull { line ->
            try {
                val raw = Base64.decode(line, Base64.NO_WRAP)
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(Cipher.DECRYPT_MODE, k, GCMParameterSpec(128, raw, 0, 12))
                String(cipher.doFinal(raw, 12, raw.size - 12), Charsets.UTF_8)
            } catch (_: Exception) { null }       // damaged line: drop it
        }
        f.delete()
        return out
    }
}
