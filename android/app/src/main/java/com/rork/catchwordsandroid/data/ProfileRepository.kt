package com.rork.catchwordsandroid.data

import io.ktor.http.ContentType
import io.ktor.http.HttpMethod
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject

/** The shared `profiles` row (same columns the web settings screen edits). */
data class Profile(
    val displayName: String = "",
    val avatarUrl: String? = null,
    val nativeLanguage: String = "ja",
    val targetLanguage: String = "zh-TW",
    val currentLevel: String = "TOCFL-1",
    val levelGoal: String = "TOCFL-2",
    val reviewDailyLimit: Int = 20,
    val onboarded: Boolean = false,
    val createdAtMs: Long? = null,
    val isLoaded: Boolean = false,
    val loadFailed: Boolean = false,
) {
    /** 0 = unlimited (1000 is the most one REST read returns). */
    val effectiveReviewLimit: Int get() = if (reviewDailyLimit == 0) 1000 else reviewDailyLimit
}

class ProfileRepository(private val client: SupabaseClient) {
    private val _profile = MutableStateFlow(Profile())
    val profile: StateFlow<Profile> = _profile.asStateFlow()

    /** The learning language (`profiles.target_language`), as the server functions expect it. */
    val target: String get() = _profile.value.targetLanguage.let { if (it == "en" || it == "ja") it else "zh-TW" }

    suspend fun load() {
        val uid = client.userId ?: run { _profile.update { it.copy(isLoaded = true) }; return }
        val row = readRow(uid)
        if (client.userId != uid) return
        if (row == null) {
            _profile.update { it.copy(isLoaded = true, loadFailed = true) }
            return
        }
        var p = _profile.value.copy(
            displayName = row.str("display_name") ?: "",
            avatarUrl = row.str("avatar_url"),
            onboarded = row.bool("onboarded") ?: false,
            createdAtMs = parseDate(row.str("created_at")),
            isLoaded = true,
            loadFailed = false,
        )
        if (row.containsKey("target_language")) {
            row.str("ui_language")?.let { L10n.set(it) }
            p = p.copy(
                nativeLanguage = row.str("native_language") ?: "ja",
                targetLanguage = row.str("target_language") ?: "zh-TW",
                currentLevel = row.str("current_level") ?: p.currentLevel,
                levelGoal = row.str("level_goal") ?: p.levelGoal,
                reviewDailyLimit = row.int("review_daily_limit")?.takeIf { it >= 0 } ?: p.reviewDailyLimit,
            )
        }
        _profile.value = p
    }

    /** `get_my_profile()` (only the caller's row, private columns included), else the public columns. */
    private suspend fun readRow(uid: String): JsonObject? {
        runCatching { client.rest(HttpMethod.Post, "rpc/get_my_profile", body = JsonObject(emptyMap())) }.getOrNull()?.let { text ->
            val el = runCatching { AppJson.parseToJsonElement(text) }.getOrNull()
            val row = (el as? JsonObject) ?: (el as? JsonArray)?.firstOrNull()?.jsonObject
            if (row?.str("id") != null) return row
        }
        if (client.userId != uid) return null
        val text = runCatching {
            client.rest(HttpMethod.Get, "profiles?id=eq.$uid&select=display_name,avatar_url,onboarded,created_at")
        }.getOrNull() ?: return null
        return (runCatching { AppJson.parseToJsonElement(text) }.getOrNull() as? JsonArray)?.firstOrNull() as? JsonObject
    }

    fun reset() {
        _profile.value = Profile()
    }

    fun setLocal(transform: (Profile) -> Profile) = _profile.update(transform)

    /** Saves profile columns; true when the server kept them. */
    suspend fun update(fields: Map<String, Any?>): Boolean {
        val uid = client.userId ?: return false
        val body = toJson(fields + ("updated_at" to isoNow()))
        return runCatching { client.rest(HttpMethod.Patch, "profiles?id=eq.$uid", body = body) }.isSuccess
    }

    suspend fun uploadAvatar(jpeg: ByteArray): Boolean {
        val uid = client.userId ?: return false
        val path = "$uid/avatar-${System.currentTimeMillis()}.jpg"
        return runCatching {
            client.upload(jpeg, path, ContentType.Image.JPEG, bucket = "avatars")
            val url = client.publicUrl("avatars", path)
            val previous = _profile.value.avatarUrl
            if (!update(mapOf("avatar_url" to url))) return false
            _profile.update { it.copy(avatarUrl = url) }
            ownAvatarPath(previous)?.let { runCatching { client.removeObject(it, "avatars") } }
            true
        }.getOrDefault(false)
    }

    suspend fun clearAvatar() {
        val previous = _profile.value.avatarUrl
        if (update(mapOf("avatar_url" to JsonNull))) {
            _profile.update { it.copy(avatarUrl = null) }
            ownAvatarPath(previous)?.let { runCatching { client.removeObject(it, "avatars") } }
        }
    }

    private fun ownAvatarPath(url: String?): String? {
        val uid = client.userId ?: return null
        val marker = "/storage/v1/object/public/avatars/"
        val i = url?.indexOf(marker) ?: return null
        if (i < 0) return null
        val obj = url.substring(i + marker.length)
        return if (obj.startsWith("$uid/") && !obj.contains("..")) obj else null
    }

    /** Deletes the whole account through the web's `deleteMyAccount`, then checks Auth itself that the login is gone. */
    suspend fun deleteAccount(api: NativeApi) {
        api.call("deleteMyAccount", jsonOf("confirm" to "削除"), timeoutMs = 60_000)
        if (client.verifyLoginDeleted() == false) {
            throw ApiException.Message(tr("アカウントのログイン情報を削除できませんでした。もう一度お試しください。", "Couldn't delete the sign-in for this account. Please try again.", "無法刪除此帳號的登入資訊，請再試一次。"))
        }
    }

    companion object {
        val levelOptions = (1..6).map { "TOCFL-$it" to "TOCFL Level $it" }
        val cefrOptions = listOf("A1", "A2", "B1", "B2", "C1", "C2").map { it to "CEFR $it" }
        val jlptOptions = listOf("N5", "N4", "N3", "N2", "N1", "N1+").map { "JLPT-$it" to "JLPT $it" }
        val nativeOptions = listOf("ja" to "日本語", "en" to "English", "zh-TW" to "繁體中文")

        fun levels(target: String): List<Pair<String, String>> = when (target) {
            "en" -> cefrOptions
            "ja" -> jlptOptions
            else -> levelOptions
        }

        fun targetLabel(code: String): String = when (code) {
            "en" -> "English"
            "ja" -> "日本語"
            else -> tr("繁體字（台灣）", "Traditional Chinese (Taiwan)", "繁體字（台灣）")
        }

        /** web `readerL1`: the display language when it differs from the learning language, else the old native one. */
        fun readerL1(native: String?, target: String): String {
            val choices = listOf("ja", "en", "zh-TW").filter { it != target }
            if (L10n.current in choices) return L10n.current
            if (native != null && native in choices) return native
            return choices.firstOrNull() ?: "ja"
        }
    }
}
