package com.myvault.myvault

import android.app.Activity
import android.content.Intent
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.TagLostException
import android.nfc.tech.IsoDep
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import net.sf.scuba.smartcards.CardServiceException
import net.sf.scuba.smartcards.IsoDepCardService
import org.bouncycastle.jce.provider.BouncyCastleProvider
import org.jmrtd.AccessKeySpec
import org.jmrtd.BACKey
import org.jmrtd.PACEKeySpec
import org.jmrtd.PassportService
import org.jmrtd.lds.CardAccessFile
import org.jmrtd.lds.PACEInfo
import org.jmrtd.lds.icao.DG1File
import java.security.Security

/**
 * Reads the chip in an e-passport or e-ID card (ICAO 9303) over NFC: the same
 * details as the machine-readable zone, straight from the chip. The chip only
 * opens with the document number, birth date and expiry date (or the 6-digit
 * card access number printed on some ID cards), so a stranger's phone can't
 * read it from your pocket. Uses JMRTD; nothing is sent anywhere.
 */
class NfcBridge(private val activity: Activity) {
    private var pending: MethodChannel.Result? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        val nfc = NfcAdapter.getDefaultAdapter(activity)
        when (call.method) {
            "status" -> result.success(if (nfc == null) "none" else if (nfc.isEnabled) "on" else "off")
            "settings" -> { activity.startActivity(Intent(Settings.ACTION_NFC_SETTINGS)); result.success(true) }
            "read" -> {
                if (nfc == null || !nfc.isEnabled) return result.error("off", "Turn on NFC first.", null)
                finish("cancelled", null)               // only one read at a time
                pending = result
                val number = call.argument<String>("number") ?: ""
                val birth = call.argument<String>("birth") ?: ""      // YYMMDD
                val expiry = call.argument<String>("expiry") ?: ""    // YYMMDD
                val can = call.argument<String>("can") ?: ""
                nfc.enableReaderMode(activity, { tag -> read(tag, number, birth, expiry, can) },
                    NfcAdapter.FLAG_READER_NFC_A or NfcAdapter.FLAG_READER_NFC_B or NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK, null)
            }
            "stop" -> { finish("cancelled", null); result.success(true) }
            else -> result.notImplemented()
        }
    }

    private fun finish(error: String?, mrz: String?) {
        val r = pending ?: return
        pending = null
        activity.runOnUiThread {
            NfcAdapter.getDefaultAdapter(activity)?.disableReaderMode(activity)
            if (error == null) r.success(mrz) else r.error(error, null, null)
        }
    }

    private fun read(tag: Tag, number: String, birth: String, expiry: String, can: String) {
        val iso = IsoDep.get(tag) ?: return finish("not_chip", null)
        // JMRTD needs the full BouncyCastle provider; Android's own is trimmed.
        // It's put first only for this read, then everything is put back.
        val own = Security.getProvider("BC")
        val at = Security.getProviders().indexOf(own) + 1
        Security.removeProvider("BC")
        Security.insertProviderAt(BouncyCastleProvider(), 1)
        try {
            iso.timeout = 10_000
            val card = IsoDepCardService(iso)
            card.open()
            val ps = PassportService(card, PassportService.NORMAL_MAX_TRANCEIVE_LENGTH,
                PassportService.DEFAULT_MAX_BLOCKSIZE, false, false)
            ps.open()
            val key: AccessKeySpec = if (can.isNotEmpty()) PACEKeySpec.createCANKey(can) else BACKey(number, birth, expiry)
            var pace = false
            try {
                val access = CardAccessFile(ps.getInputStream(PassportService.EF_CARD_ACCESS, PassportService.DEFAULT_MAX_BLOCKSIZE))
                val info = access.securityInfos.filterIsInstance<PACEInfo>().firstOrNull()
                if (info != null) {
                    ps.doPACE(key, info.objectIdentifier, PACEInfo.toParameterSpec(info.parameterId), null)
                    pace = true
                }
            } catch (_: Exception) {
                // no PACE on this chip: the older BAC below
            }
            ps.sendSelectApplet(pace)
            if (!pace) {
                if (key !is BACKey) return finish("needs_mrz", null)
                ps.doBAC(key)
            }
            val dg1 = DG1File(ps.getInputStream(PassportService.EF_DG1, PassportService.DEFAULT_MAX_BLOCKSIZE))
            finish(null, dg1.mrzInfo.toString())
        } catch (e: TagLostException) {
            finish("lost", null)
        } catch (e: CardServiceException) {
            // 0x6300 and friends: the chip refused the key, so a number or date is wrong
            finish(if (e.sw in listOf(0x6300, 0x6982, 0x6A80, 0x6A88)) "denied" else if (iso.isConnected) "failed" else "lost", null)
        } catch (e: Exception) {
            finish("failed", null)
        } finally {
            try { iso.close() } catch (_: Exception) {}
            Security.removeProvider("BC")
            if (own != null) Security.insertProviderAt(own, at)
        }
    }
}
