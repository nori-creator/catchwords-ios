package com.rork.catchwordsandroid.data

import android.content.Context
import android.util.Base64
import io.ktor.client.HttpClient
import io.ktor.client.engine.android.Android
import io.ktor.client.plugins.HttpRequestTimeoutException
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.timeout
import io.ktor.client.request.HttpRequestBuilder
import io.ktor.client.request.header
import io.ktor.client.request.request
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.content.ByteArrayContent
import io.ktor.http.ContentType
import io.ktor.http.HttpMethod
import io.ktor.http.content.TextContent
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.io.IOException

@Serializable
data class AuthSession(
    val accessToken: String,
    val refreshToken: String,
    val expiresAtMs: Long,
    val userId: String,
    val email: String? = null,
)

/** One answer from the server: status code and body text. */
data class RawResponse(val status: Int, val body: String)

/**
 * Minimal Supabase client talking to the SAME project as the web and iOS apps (auth, REST, storage).
 * RLS (`auth.uid() = user_id`) protects every row.
 */
class SupabaseClient(context: Context) {
    private val prefs = context.getSharedPreferences("cw.session", Context.MODE_PRIVATE)
    private val base = AppConfig.SUPABASE_URL.trimEnd('/')
    private val key = AppConfig.SUPABASE_KEY
    private val refreshMutex = Mutex()

    val http: HttpClient = HttpClient(Android) {
        expectSuccess = false
        install(HttpTimeout) {
            requestTimeoutMillis = 30_000
            connectTimeoutMillis = 15_000
        }
    }

    private val _session = MutableStateFlow(loadSession())
    val session: StateFlow<AuthSession?> = _session.asStateFlow()

    /** Emits when the login is over (dead refresh token): the app returns to the sign-in screen. */
    val expired = MutableStateFlow(false)

    val userId: String? get() = _session.value?.userId

    private fun loadSession(): AuthSession? {
        val raw = prefs.getString("session", null) ?: return null
        return runCatching { AppJson.decodeFromString(AuthSession.serializer(), raw) }.getOrNull()
    }

    private fun persist(s: AuthSession) {
        _session.value = s
        prefs.edit().putString("session", AppJson.encodeToString(AuthSession.serializer(), s)).apply()
    }

    // region Auth

    suspend fun signIn(email: String, password: String) {
        val json = authRequest("token?grant_type=password", buildJsonObject { put("email", email); put("password", password) })
        storeSession(json)
    }

    /** True when a session was created at once (email confirmation off). */
    suspend fun signUp(email: String, password: String): Boolean {
        val json = authRequest("signup", buildJsonObject { put("email", email); put("password", password) })
        if (json["access_token"] != null) {
            storeSession(json)
            return true
        }
        return false
    }

    suspend fun sendPasswordReset(email: String) {
        authRequest(
            "recover?redirect_to=${AppConfig.WEB_BASE_URL}/reset-password",
            buildJsonObject { put("email", email) },
        )
    }

    /** Takes over a session handed back by the web bridge (Google). User id, email and expiry come from the JWT. */
    fun adoptSession(accessToken: String, refreshToken: String, expiresAtMs: Long?) {
        val claims = jwtClaims(accessToken)
        val uid = claims["sub"]?.jsonPrimitive?.contentOrNull ?: throw ApiException.Unauthorized
        val email = claims["email"]?.jsonPrimitive?.contentOrNull
        val exp = claims["exp"]?.jsonPrimitive?.doubleOrNull?.let { (it * 1000).toLong() }
        persist(AuthSession(accessToken, refreshToken, expiresAtMs ?: exp ?: (System.currentTimeMillis() + 3_600_000), uid, email))
    }

    private suspend fun authRequest(path: String, body: JsonObject): JsonObject {
        val res = send(HttpMethod.Post, "$base/auth/v1/$path", textBody = body.toString(), token = null)
        val json = parseObject(res.body)
        if (res.status !in 200..299) {
            val msg = json.str("error_description") ?: json.str("msg") ?: json.str("message") ?: ""
            throw ApiException.Message(localizeAuthError(msg, res.status))
        }
        return json
    }

    private fun storeSession(json: JsonObject) {
        val access = json.str("access_token") ?: throw ApiException.Decoding
        val refresh = json.str("refresh_token") ?: throw ApiException.Decoding
        val user = json["user"] as? JsonObject ?: throw ApiException.Decoding
        val uid = user.str("id") ?: throw ApiException.Decoding
        val expiresIn = json["expires_in"]?.jsonPrimitive?.doubleOrNull ?: 3600.0
        persist(AuthSession(access, refresh, System.currentTimeMillis() + (expiresIn * 1000).toLong(), uid, user.str("email")))
    }

    suspend fun refreshIfNeeded(force: Boolean = false, withinMs: Long = 120_000) {
        val current = _session.value ?: throw ApiException.Unauthorized
        if (!force && current.expiresAtMs - System.currentTimeMillis() > withinMs) return
        refreshMutex.withLock {
            val now = _session.value ?: throw ApiException.Unauthorized
            // Another caller refreshed while this one waited: refresh tokens rotate, so never use the old one twice.
            if (now.refreshToken != current.refreshToken) return
            val res = send(
                HttpMethod.Post, "$base/auth/v1/token?grant_type=refresh_token",
                textBody = buildJsonObject { put("refresh_token", now.refreshToken) }.toString(), token = null,
            )
            if (_session.value?.refreshToken != now.refreshToken) return
            val json = parseObject(res.body)
            if (res.status in 200..299) {
                storeSession(json)
                return
            }
            if (res.status in listOf(400, 401, 403)) {
                expireSession()
                throw ApiException.Unauthorized
            }
            throw ApiException.Server(res.status, json.str("error_description") ?: "")
        }
    }

    /** Refreshes an expiring token; a network hiccup is not an error here (the current token may still work). */
    suspend fun refreshForRequest() {
        try {
            refreshIfNeeded()
        } catch (e: ApiException.Unauthorized) {
            throw e
        } catch (_: Exception) {
        }
    }

    fun expireSession() {
        if (_session.value == null) return
        signOut()
        expired.value = true
    }

    fun signOut() {
        _session.value = null
        prefs.edit().remove("session").apply()
    }

    /** The user's own sign-out: local at once, the server session revoked best-effort. */
    suspend fun signOutRevoking() {
        val ended = _session.value
        signOut()
        if (ended == null) return
        runCatching {
            send(HttpMethod.Post, "$base/auth/v1/logout?scope=local", token = ended.accessToken, timeoutMs = 10_000)
        }
    }

    /** After `deleteMyAccount`: true = the login is proven gone, false = still there, null = could not ask. */
    suspend fun verifyLoginDeleted(): Boolean? {
        val s = _session.value ?: return null
        val user = runCatching { send(HttpMethod.Get, "$base/auth/v1/user", token = s.accessToken, timeoutMs = 15_000) }.getOrNull()
            ?: return null
        if (user.status in 200..299) return false
        if (user.status !in listOf(401, 403, 404)) return null
        val refresh = runCatching {
            send(
                HttpMethod.Post, "$base/auth/v1/token?grant_type=refresh_token",
                textBody = buildJsonObject { put("refresh_token", s.refreshToken) }.toString(), token = null,
            )
        }.getOrNull() ?: return null
        return refresh.status !in 200..299
    }

    // endregion

    // region REST / storage

    /** Runs a request with the current token; one forced refresh and a retry on 401. */
    suspend fun withTokenRetry(sendWith: suspend (String) -> RawResponse): RawResponse {
        val token = _session.value?.accessToken ?: throw ApiException.Unauthorized
        val uid = userId
        val first = sendWith(token)
        if (!isExpiredToken(first)) return first
        if (userId != uid) throw ApiException.Server(409, "account changed")
        refreshIfNeeded(force = true)
        val fresh = _session.value?.accessToken ?: throw ApiException.Unauthorized
        val second = sendWith(fresh)
        if (isExpiredToken(second)) {
            expireSession()
            throw ApiException.Unauthorized
        }
        return second
    }

    suspend fun rest(method: HttpMethod, path: String, body: JsonElement? = null, prefer: String? = null, timeoutMs: Long = 20_000): String {
        refreshForRequest()
        val res = withTokenRetry { token ->
            send(method, "$base/rest/v1/$path", textBody = body?.toString(), token = token, prefer = prefer, timeoutMs = timeoutMs)
        }
        if (res.status !in 200..299) {
            throw ApiException.Server(res.status, parseObject(res.body).str("message") ?: "")
        }
        return res.body
    }

    /** Every row of a GET, a page at a time (the server returns at most 1000 rows per request). */
    suspend fun restAll(path: String, pageSize: Int = 1000, maxPages: Int = 20): List<JsonObject> {
        val out = mutableListOf<JsonObject>()
        for (page in 0 until maxPages) {
            val text = rest(HttpMethod.Get, "$path&limit=$pageSize&offset=${page * pageSize}")
            val chunk = AppJson.parseToJsonElement(text).jsonArray.map { it.jsonObject }
            out += chunk
            if (chunk.size < pageSize) break
        }
        return out
    }

    suspend fun upload(bytes: ByteArray, path: String, contentType: ContentType = ContentType.Image.JPEG, bucket: String = "stickers") {
        refreshForRequest()
        val res = withTokenRetry { token ->
            send(HttpMethod.Post, "$base/storage/v1/object/$bucket/$path", bytes = bytes, bytesType = contentType, token = token,
                timeoutMs = 60_000, extraHeaders = mapOf("x-upsert" to "false"))
        }
        if (res.status !in 200..299) {
            throw ApiException.Server(res.status, parseObject(res.body).str("message") ?: "")
        }
    }

    suspend fun removeObject(path: String, bucket: String) {
        refreshForRequest()
        val res = withTokenRetry { token -> send(HttpMethod.Delete, "$base/storage/v1/object/$bucket/$path", token = token) }
        if (res.status in 200..299 || res.status == 404) return
        throw ApiException.Server(res.status, "")
    }

    fun publicUrl(bucket: String, path: String): String = "$base/storage/v1/object/public/$bucket/$path"

    /** Signed links for private sticker photos (6 hours). */
    suspend fun signedUrls(paths: List<String>, expiresIn: Int = 60 * 60 * 6): Map<String, String> {
        if (paths.isEmpty()) return emptyMap()
        refreshForRequest()
        val payload = buildJsonObject {
            put("expiresIn", expiresIn)
            put("paths", JsonArray(paths.map { kotlinx.serialization.json.JsonPrimitive(it) }))
        }
        val res = withTokenRetry { token ->
            send(HttpMethod.Post, "$base/storage/v1/object/sign/stickers", textBody = payload.toString(), token = token)
        }
        if (res.status !in 200..299) return emptyMap()
        val arr = runCatching { AppJson.parseToJsonElement(res.body).jsonArray }.getOrNull() ?: return emptyMap()
        val out = mutableMapOf<String, String>()
        for (item in arr) {
            val o = item as? JsonObject ?: continue
            val p = o.str("path") ?: continue
            val signed = o.str("signedURL") ?: o.str("signedUrl") ?: continue
            out[p] = "$base/storage/v1$signed"
        }
        return out
    }

    // endregion

    suspend fun send(
        method: HttpMethod,
        url: String,
        textBody: String? = null,
        bytes: ByteArray? = null,
        bytesType: ContentType = ContentType.Application.OctetStream,
        token: String?,
        prefer: String? = null,
        timeoutMs: Long = 20_000,
        extraHeaders: Map<String, String> = emptyMap(),
    ): RawResponse {
        try {
            val res: HttpResponse = http.request(url) {
                this.method = method
                timeout { requestTimeoutMillis = timeoutMs }
                header("apikey", key)
                if (token != null) header("Authorization", "Bearer $token")
                prefer?.let { header("Prefer", it) }
                extraHeaders.forEach { (k, v) -> header(k, v) }
                applyBody(textBody, bytes, bytesType)
            }
            return RawResponse(res.status.value, res.bodyAsText())
        } catch (e: HttpRequestTimeoutException) {
            throw ApiException.Timeout
        } catch (e: IOException) {
            throw ApiException.Offline
        }
    }

    private fun HttpRequestBuilder.applyBody(textBody: String?, bytes: ByteArray?, bytesType: ContentType) {
        when {
            bytes != null -> setBody(ByteArrayContent(bytes, bytesType))
            textBody != null -> setBody(TextContent(textBody, ContentType.Application.Json))
        }
    }

    companion object {
        fun isExpiredToken(r: RawResponse): Boolean {
            if (r.status == 401) return true
            if ((r.status != 400 && r.status != 403) || r.body.length > 4096) return false
            val b = r.body.lowercase()
            return b.contains("jwt expired") || b.contains("exp\" claim") || b.contains("exp claim") ||
                b.contains("invalidjwt") || b.contains("token is expired")
        }

        fun jwtClaims(token: String): JsonObject {
            val parts = token.split(".")
            if (parts.size < 2) return JsonObject(emptyMap())
            return runCatching {
                val bytes = Base64.decode(parts[1], Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
                AppJson.parseToJsonElement(String(bytes)).jsonObject
            }.getOrDefault(JsonObject(emptyMap()))
        }

        fun parseObject(text: String): JsonObject =
            runCatching { AppJson.parseToJsonElement(text) as? JsonObject }.getOrNull() ?: JsonObject(emptyMap())

        private fun localizeAuthError(msg: String, code: Int): String {
            val m = msg.lowercase()
            return when {
                m.contains("invalid login") -> tr("メールアドレスかパスワードが違います。", "Wrong email or password.", "電子郵件或密碼錯誤。")
                m.contains("already registered") -> tr("このメールアドレスは登録済みです。ログインしてください。", "This email is already registered. Please sign in.", "此電子郵件已註冊，請登入。")
                m.contains("weak") -> tr("このパスワードは推測されやすいため使えません。英字と数字を混ぜた、ほかのパスワードにしてください。", "This password is too easy to guess. Use another one mixing letters and numbers.", "此密碼太容易被猜到，請改用混合英文字母與數字的密碼。")
                m.contains("password should be") -> tr("パスワードは6文字以上にしてください。", "Use at least 6 characters for the password.", "密碼至少需要 6 個字元。")
                m.contains("email not confirmed") -> tr("確認メールのリンクを開いてからログインしてください。", "Open the link in the confirmation email, then sign in.", "請先開啟確認信中的連結再登入。")
                m.contains("rate limit") -> tr("しばらく時間をおいてからお試しください。", "Please wait a while and try again.", "請稍後再試。")
                else -> tr("ログインに失敗しました（$code）", "Sign-in failed ($code)", "登入失敗（$code）")
            }
        }
    }
}
