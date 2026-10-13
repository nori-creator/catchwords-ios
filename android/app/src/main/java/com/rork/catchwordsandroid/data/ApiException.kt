package com.rork.catchwordsandroid.data

/** Every failure the app can show, with a message in the display language (never a raw server string). */
sealed class ApiException(open val detail: String = "") : Exception(detail) {
    object NotConfigured : ApiException()
    object Unauthorized : ApiException()
    object Timeout : ApiException()
    object Offline : ApiException()
    object Decoding : ApiException()
    object AiConsentRequired : ApiException()
    data class Server(val code: Int, override val detail: String) : ApiException(detail)
    data class Limit(override val detail: String) : ApiException(detail)
    data class Message(override val detail: String) : ApiException(detail)

    val userMessage: String
        get() = when (this) {
            NotConfigured -> tr("サーバーの設定が見つかりません。", "The server is not configured.", "找不到伺服器設定。")
            Unauthorized -> tr("ログインの有効期限が切れました。もう一度ログインしてください。", "Your sign-in expired. Please sign in again.", "登入已過期，請重新登入。")
            Timeout -> tr("通信が時間切れになりました。電波の良い場所でもう一度お試しください。", "The connection timed out. Please try again with a better signal.", "連線逾時，請在訊號良好的地方再試一次。")
            Offline -> tr("インターネットに接続できません。", "No internet connection.", "無法連上網路。")
            Decoding -> tr("データの読み込みに失敗しました。", "Couldn't read the data.", "資料讀取失敗。")
            AiConsentRequired -> tr("AIを使う機能は、AIへのデータ送信に同意すると使えます。", "AI features need your consent to send data to AI.", "同意將資料傳送給 AI 後，才能使用 AI 功能。")
            is Server -> readerSafe(detail) ?: tr("サーバーエラー（$code）", "Server error ($code)", "伺服器錯誤（$code）")
            is Limit -> readerSafe(detail) ?: tr("1日の利用上限に達しました。24時間以内に自動で回復します。", "You reached today's limit. It resets within 24 hours.", "已達今日使用上限，24 小時內會自動恢復。")
            is Message -> readerSafe(detail) ?: tr("うまくいきませんでした。もう一度お試しください。", "Something went wrong. Please try again.", "發生錯誤，請再試一次。")
        }

    /** A server message is shown only when it is in the display language (Japanese text on a Japanese screen). */
    private fun readerSafe(msg: String): String? {
        val m = msg.trim()
        if (m.isEmpty()) return null
        val hasKana = m.any { it in '\u3040'..'\u30FF' }
        val hasHan = m.any { Character.UnicodeScript.of(it.code) == Character.UnicodeScript.HAN }
        return when (L10n.current) {
            "ja" -> if (hasKana) m else null
            "zh-TW" -> if (hasHan && !hasKana) m else null
            else -> if (!hasKana && !hasHan) m else null
        }
    }
}

val Throwable.userMessage: String
    get() = (this as? ApiException)?.userMessage
        ?: tr("うまくいきませんでした。もう一度お試しください。", "Something went wrong. Please try again.", "發生錯誤，請再試一次。")
