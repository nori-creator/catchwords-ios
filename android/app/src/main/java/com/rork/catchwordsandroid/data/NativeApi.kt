package com.rork.catchwordsandroid.data

import io.ktor.http.HttpMethod
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject

/**
 * Calls the web app's own server functions (`POST /api/native-fn`), exactly as the iOS app does: candidate naming,
 * card generation, saving, review grading and account deletion are decided on the web, so all three apps stay in step.
 */
class NativeApi(private val client: SupabaseClient, private val consent: () -> AiConsentStore) {

    /** Server functions that send the learner's photos, words or text on to an AI provider (consent required). */
    private val aiFunctions = setOf(
        "suggestWords", "detectScan", "rankScanCandidates", "suggestWordCandidates",
        "generateCard", "regenerateCardSection", "reportAndFixSection",
    )

    suspend fun call(fn: String, data: JsonObject = JsonObject(emptyMap()), timeoutMs: Long = 40_000, asUser: String? = null): JsonElement {
        if (fn in aiFunctions && !consent().isGranted) throw ApiException.AiConsentRequired
        return try {
            post(fn, data, timeoutMs, asUser)
        } catch (e: ApiException.AiConsentRequired) {
            // The server has no record of an agreement made on this device yet: send it, then try once more.
            if (fn == "recordAiConsent" || !consent().isGranted) throw e
            if (!consent().pushGrant()) throw e
            post(fn, data, timeoutMs, asUser)
        }
    }

    private suspend fun post(fn: String, data: JsonObject, timeoutMs: Long, asUser: String?): JsonElement {
        client.refreshForRequest()
        val payload = jsonOf("fn" to fn, "data" to data).toString()
        val res = client.withTokenRetry { token ->
            if (asUser != null && client.userId != asUser) throw ApiException.Server(409, "account changed")
            client.send(
                HttpMethod.Post, "${AppConfig.WEB_BASE_URL}/api/native-fn",
                textBody = payload, token = token, timeoutMs = timeoutMs,
                extraHeaders = mapOf("AI-Consent-Version" to AiConsentStore.CURRENT_VERSION.toString()),
            )
        }
        val json = SupabaseClient.parseObject(res.body)
        val message = json.str("error") ?: ""
        return when {
            res.status == 200 -> json["result"] ?: JsonNull
            res.status == 401 -> throw ApiException.Unauthorized
            res.status == 403 && message.startsWith("AI_CONSENT_REQUIRED") -> throw ApiException.AiConsentRequired
            res.status == 429 -> throw ApiException.Limit(message)
            else -> throw ApiException.Server(res.status, message)
        }
    }

    /** Warms the photo path on the server while the camera is open (no AI call, nothing counted). */
    private var lastWarmUp = 0L

    suspend fun warmUp() {
        val now = System.currentTimeMillis()
        if (now - lastWarmUp < 60_000 || client.userId == null) return
        lastWarmUp = now
        runCatching {
            client.refreshIfNeeded(withinMs = 600_000)
            call("warmUpCapture", timeoutMs = 10_000)
        }
    }

}
