package com.rork.catchwordsandroid.data

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.json.JsonObject

enum class ConsentStatus { UNDECIDED, GRANTED, DECLINED }

/**
 * Consent to send photos, words and text to third-party AI (asked once per account, before the camera or any AI
 * feature). Kept on this device per account and mirrored to the server (`recordAiConsent` / `getAiConsent`), so an
 * answer given on iOS or the web counts here too.
 */
class AiConsentStore(context: Context, private val client: SupabaseClient, private val api: () -> NativeApi) {
    private val prefs = context.getSharedPreferences("cw.consent", Context.MODE_PRIVATE)
    private val _status = MutableStateFlow(ConsentStatus.UNDECIDED)
    val status: StateFlow<ConsentStatus> = _status.asStateFlow()
    private var userId: String? = null

    val isGranted: Boolean get() = _status.value == ConsentStatus.GRANTED

    fun load(uid: String?) {
        userId = uid
        val state = prefs.getString("status.$uid", null)
        val version = prefs.getInt("version.$uid", 0)
        _status.value = when {
            state == "granted" && version >= CURRENT_VERSION -> ConsentStatus.GRANTED
            state == "declined" -> ConsentStatus.DECLINED
            else -> ConsentStatus.UNDECIDED
        }
    }

    fun reset() {
        userId = null
        _status.value = ConsentStatus.UNDECIDED
    }

    suspend fun grant() = decide(true)

    suspend fun decline() = decide(false)

    private suspend fun decide(agreed: Boolean) {
        val uid = userId ?: return
        save(uid, if (agreed) "granted" else "declined", pending = true)
        _status.value = if (agreed) ConsentStatus.GRANTED else ConsentStatus.DECLINED
        if (send(agreed, uid)) prefs.edit().putBoolean("pending.$uid", false).apply()
    }

    /** Sends a local agreement the server refused for want of a record; true when it now has one. */
    suspend fun pushGrant(): Boolean {
        val uid = userId ?: return false
        return send(true, uid)
    }

    /** After sign-in: an unsent answer goes first; else an agreement made on another device is adopted. */
    suspend fun sync() {
        val uid = userId ?: return
        if (prefs.getBoolean("pending.$uid", false)) {
            if (send(isGranted, uid)) prefs.edit().putBoolean("pending.$uid", false).apply()
            return
        }
        val server = runCatching { api().call("getAiConsent", timeoutMs = 15_000) as? JsonObject }.getOrNull() ?: return
        if (server.bool("recorded") == false || userId != uid) return
        val agreed = server.bool("agreed") == true && (server.int("version") ?: 0) >= CURRENT_VERSION
        if (agreed && _status.value != ConsentStatus.GRANTED) {
            save(uid, "granted", pending = false)
            _status.value = ConsentStatus.GRANTED
        } else if (!agreed && _status.value == ConsentStatus.GRANTED && server.str("revoked_at") != null) {
            save(uid, "declined", pending = false)
            _status.value = ConsentStatus.DECLINED
        }
    }

    private fun save(uid: String, state: String, pending: Boolean) {
        prefs.edit()
            .putString("status.$uid", state)
            .putInt("version.$uid", CURRENT_VERSION)
            .putBoolean("pending.$uid", pending)
            .apply()
    }

    private suspend fun send(agreed: Boolean, uid: String): Boolean {
        if (client.userId != uid) return false
        return runCatching {
            api().call("recordAiConsent", jsonOf("version" to CURRENT_VERSION, "agreed" to agreed), timeoutMs = 15_000, asUser = uid)
        }.isSuccess
    }

    companion object {
        const val CURRENT_VERSION = 1
    }
}
