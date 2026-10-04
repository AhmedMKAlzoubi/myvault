package com.myvault.myvault

import android.app.PendingIntent
import android.app.assist.AssistStructure
import android.content.Context
import android.content.Intent
import android.os.CancellationSignal
import android.service.autofill.AutofillService
import android.service.autofill.Dataset
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.SaveCallback
import android.service.autofill.SaveInfo
import android.service.autofill.SaveRequest
import android.text.InputType
import android.view.View
import android.view.autofill.AutofillId
import android.widget.RemoteViews
import org.json.JSONObject

/**
 * MyVault as Android's autofill provider (Settings > Passwords & autofill).
 *
 * Fill: shows one "Fill with MyVault" suggestion; tapping it opens MyVault's
 * unlock screen (AutofillAuthActivity), and only after unlocking and picking an
 * account are the boxes filled. Save: when Android offers "Save to MyVault?",
 * the login is sealed into the Keystore-encrypted inbox (CaptureInbox) and added
 * to the vault the next time it's unlocked. The service itself never holds the
 * vault or the master password.
 */
class MyVaultAutofillService : AutofillService() {

    override fun onFillRequest(request: FillRequest, cancellationSignal: CancellationSignal, callback: FillCallback) {
        val structure = request.fillContexts.lastOrNull()?.structure ?: return callback.onSuccess(null)
        val f = AutofillParser.parse(structure, this)
        if (f.packageName == packageName || (f.username == null && f.password == null)) {
            return callback.onSuccess(null)
        }
        val auth = Intent(this, AutofillAuthActivity::class.java).apply {
            putExtra(AutofillAuthActivity.EXTRA_TARGET, f.target)
            putExtra(AutofillAuthActivity.EXTRA_IS_WEB, f.webDomain != null)
            putExtra(AutofillAuthActivity.EXTRA_LABEL, f.label)
            putExtra(AutofillAuthActivity.EXTRA_USERNAME_ID, f.username)
            putExtra(AutofillAuthActivity.EXTRA_PASSWORD_ID, f.password)
        }
        val pending = PendingIntent.getActivity(
            this, (System.nanoTime() and 0xffffff).toInt(), auth,
            PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_MUTABLE)
        val dataset = Dataset.Builder(presentation(this, getString(R.string.fill_with_myvault)))
        listOfNotNull(f.username, f.password).forEach { dataset.setValue(it, null) }
        dataset.setAuthentication(pending.intentSender)

        val response = FillResponse.Builder().addDataset(dataset.build())
        f.password?.let { pw ->
            val type = SaveInfo.SAVE_DATA_TYPE_PASSWORD or
                (if (f.username != null) SaveInfo.SAVE_DATA_TYPE_USERNAME else 0)
            val save = SaveInfo.Builder(type, arrayOf(pw))
            f.username?.let { save.setOptionalIds(arrayOf(it)) }
            response.setSaveInfo(save.build())
        }
        callback.onSuccess(response.build())
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        // Multi-page logins put the username on an earlier screen: read every context.
        var user: String? = null
        var pass: String? = null
        var last: AutofillParser.Result? = null
        for (ctx in request.fillContexts) {
            val f = AutofillParser.parse(ctx.structure, this)
            if (!f.usernameValue.isNullOrBlank()) user = f.usernameValue
            if (!f.passwordValue.isNullOrEmpty()) pass = f.passwordValue
            last = f
        }
        val f = last
        if (f != null && !pass.isNullOrEmpty() && f.packageName != packageName) {
            CaptureInbox.add(this, JSONObject().apply {
                put("target", f.target)
                put("web", f.webDomain != null)
                put("label", f.label)
                put("username", user ?: "")
                put("password", pass)
                put("at", System.currentTimeMillis() / 1000.0)
            })
        }
        callback.onSuccess()
    }

    companion object {
        fun presentation(c: Context, text: String) =
            RemoteViews(c.packageName, android.R.layout.simple_list_item_1).apply {
                setTextViewText(android.R.id.text1, text)
            }
    }
}

/** Finds the username and password boxes in another app's screen. */
object AutofillParser {
    // A web address is only believed when a real browser reports it; any other
    // app could claim to be "yourbank.com", so those are matched by app id instead.
    private val BROWSERS = setOf(
        "com.android.chrome", "com.chrome.beta", "com.chrome.dev", "org.chromium.chrome",
        "org.mozilla.firefox", "org.mozilla.firefox_beta", "org.mozilla.focus",
        "com.brave.browser", "com.microsoft.emmx", "com.sec.android.app.sbrowser",
        "com.opera.browser", "com.opera.mini.native", "com.duckduckgo.mobile.android",
        "com.vivaldi.browser", "com.kiwibrowser.browser", "ai.perplexity.comet",
    )
    private val USER_WORDS = Regex("user|login|email|e-mail|account|phone|mobile|identifier", RegexOption.IGNORE_CASE)
    private val PASS_WORDS = Regex("pass|pwd|pin", RegexOption.IGNORE_CASE)

    data class Result(
        val username: AutofillId?, val password: AutofillId?,
        val usernameValue: String?, val passwordValue: String?,
        val packageName: String, val webDomain: String?, val label: String,
    ) {
        val target get() = webDomain ?: packageName
    }

    fun parse(s: AssistStructure, c: Context): Result {
        val pkg = s.activityComponent.packageName
        var user: AssistStructure.ViewNode? = null
        var pass: AssistStructure.ViewNode? = null
        var domain: String? = null

        fun visit(n: AssistStructure.ViewNode) {
            if (domain == null && !n.webDomain.isNullOrBlank()) domain = n.webDomain
            if (n.autofillId != null && n.autofillType == View.AUTOFILL_TYPE_TEXT && n.visibility == View.VISIBLE) {
                when {
                    pass == null && isPassword(n) -> pass = n
                    user == null && pass == null && isUsername(n) -> user = n
                }
            }
            for (i in 0 until n.childCount) visit(n.getChildAt(i))
        }
        for (i in 0 until s.windowNodeCount) visit(s.getWindowNodeAt(i).rootViewNode)

        val label = try {
            c.packageManager.getApplicationLabel(c.packageManager.getApplicationInfo(pkg, 0)).toString()
        } catch (_: Exception) { pkg }
        val web = if (pkg in BROWSERS) domain?.removePrefix("www.") else null
        return Result(user?.autofillId, pass?.autofillId,
            user?.autofillValue?.textValue?.toString(), pass?.autofillValue?.textValue?.toString(),
            pkg, web, if (web != null) web else label)
    }

    private fun words(n: AssistStructure.ViewNode): String {
        val html = n.htmlInfo?.attributes?.joinToString(" ") { "${it.first}=${it.second}" } ?: ""
        return listOfNotNull(n.idEntry, n.hint, n.contentDescription?.toString(), html,
            n.autofillHints?.joinToString(" ")).joinToString(" ")
    }

    private fun isPassword(n: AssistStructure.ViewNode): Boolean {
        n.autofillHints?.let { h -> if (h.any { it.contains("password", true) }) return true }
        val variation = n.inputType and InputType.TYPE_MASK_VARIATION
        val cls = n.inputType and InputType.TYPE_MASK_CLASS
        if (cls == InputType.TYPE_CLASS_TEXT && variation in setOf(
                InputType.TYPE_TEXT_VARIATION_PASSWORD, InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD,
                InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD)) return true
        if (cls == InputType.TYPE_CLASS_NUMBER && variation == InputType.TYPE_NUMBER_VARIATION_PASSWORD) return true
        if (n.htmlInfo?.attributes?.any { it.first == "type" && it.second == "password" } == true) return true
        return PASS_WORDS.containsMatchIn(words(n)) && !USER_WORDS.containsMatchIn(n.idEntry ?: "")
    }

    private fun isUsername(n: AssistStructure.ViewNode): Boolean {
        n.autofillHints?.let { h ->
            if (h.any { it.contains("username", true) || it.contains("email", true) || it.contains("phone", true) }) return true
        }
        val variation = n.inputType and InputType.TYPE_MASK_VARIATION
        if (variation == InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS ||
            variation == InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS) return true
        return USER_WORDS.containsMatchIn(words(n))
    }
}
