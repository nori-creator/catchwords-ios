package com.rork.catchwordsandroid.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rork.catchwordsandroid.data.AppGraph
import com.rork.catchwordsandroid.data.ReviewState
import com.rork.catchwordsandroid.data.Speech
import com.rork.catchwordsandroid.data.Sticker
import com.rork.catchwordsandroid.data.jsonOf
import com.rork.catchwordsandroid.data.parseDate
import com.rork.catchwordsandroid.data.str
import com.rork.catchwordsandroid.data.tr
import com.rork.catchwordsandroid.data.userMessage
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.net.URLEncoder
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

data class ReviewCard(val review: ReviewState, val sticker: Sticker) {
    val id: String get() = review.id ?: review.stickerId
}

data class QuizChoice(val headword: String, val reading: String?)

data class ReviewUiState(
    val queue: List<ReviewCard> = emptyList(),
    val index: Int = 0,
    val choices: List<QuizChoice> = emptyList(),
    val picked: String? = null,
    val isLoading: Boolean = false,
    val hasLoaded: Boolean = false,
    val error: String? = null,
    val gradeError: String? = null,
    val grading: Boolean = false,
    val doneToday: Int = 0,
    val streak: Int = 0,
    val correctCount: Int = 0,
    val missed: List<ReviewCard> = emptyList(),
    val isRetry: Boolean = false,
    val capped: Boolean = false,
    val moreAvailable: Boolean = false,
) {
    val current: ReviewCard? get() = queue.getOrNull(index)
    val isCorrect: Boolean? get() = picked?.let { it == current?.sticker?.word?.headword }
}

/** Today's review: due cards (`reviews.due_at <= now`), 4 choices, graded by the web's own `gradeReview`. */
class ReviewViewModel : ViewModel() {
    private val client = AppGraph.client
    private val dex = AppGraph.dex
    private val _ui = MutableStateFlow(ReviewUiState())
    val ui: StateFlow<ReviewUiState> = _ui.asStateFlow()
    private var shownAt = System.currentTimeMillis()
    private val taipei = ZoneId.of("Asia/Taipei")

    init {
        load()
    }

    fun load(extra: Int = 0) {
        if (_ui.value.isLoading) return
        _ui.update { it.copy(isLoading = true) }
        viewModelScope.launch {
            try {
                if (!dex.state.value.hasLoaded) dex.load()
                val now = URLEncoder.encode(Instant.now().toString(), "UTF-8")
                val rows = client.restAll(
                    "reviews?select=id,sticker_id,ease,interval_days,repetitions,last_reviewed_at,due_at&due_at=lte.$now&order=due_at.asc,id.asc",
                ).mapNotNull(ReviewState.Parse::from)
                val history = runCatching {
                    client.restAll("review_history?select=sticker_id,reviewed_at&order=reviewed_at.desc,id.desc", maxPages = 50)
                }.getOrDefault(emptyList())
                val mine = dex.state.value.stickers.associateBy { it.id }
                val days = history.filter { it.str("sticker_id") in mine }.mapNotNull { parseDate(it.str("reviewed_at")) }
                    .map { Instant.ofEpochMilli(it).atZone(taipei).toLocalDate() }
                val today = LocalDate.now(taipei)
                val doneToday = days.count { it == today }
                val cards = rows.mapNotNull { r -> mine[r.stickerId]?.takeIf { it.word != null }?.let { ReviewCard(r, it) } }
                val limit = AppGraph.profile.profile.value.effectiveReviewLimit + extra
                val room = (limit - doneToday).coerceAtLeast(0)
                val queue = cards.take(room)
                _ui.value = ReviewUiState(
                    queue = queue,
                    choices = queue.firstOrNull()?.let(::makeChoices).orEmpty(),
                    hasLoaded = true,
                    doneToday = doneToday,
                    streak = streak(days.toSet(), today),
                    capped = room == 0 && cards.isNotEmpty(),
                    moreAvailable = cards.size > queue.size,
                )
                shownAt = System.currentTimeMillis()
            } catch (e: Exception) {
                _ui.update { it.copy(isLoading = false, hasLoaded = true, error = e.userMessage) }
            }
        }
    }

    private fun streak(days: Set<LocalDate>, today: LocalDate): Int {
        var cursor = if (today in days) today else today.minusDays(1)
        var n = 0
        while (cursor in days && n < 366) {
            n++
            cursor = cursor.minusDays(1)
        }
        return n
    }

    private fun makeChoices(card: ReviewCard): List<QuizChoice> {
        val word = card.sticker.word ?: return emptyList()
        val correct = QuizChoice(word.headword, word.readingZhuyin ?: word.pinyin)
        val others = dex.state.value.stickers.mapNotNull { s ->
            val w = s.word ?: return@mapNotNull null
            if (w.headword == correct.headword) null else QuizChoice(w.headword, w.readingZhuyin ?: w.pinyin) to (s.categoryKey == card.sticker.categoryKey)
        }
        val ordered = others.filter { it.second }.map { it.first }.shuffled() + others.filter { !it.second }.map { it.first }.shuffled() + fallback.shuffled()
        val out = mutableListOf<QuizChoice>()
        for (c in ordered) {
            if (c.headword != correct.headword && out.none { it.headword == c.headword }) out += c
            if (out.size == 3) break
        }
        return (listOf(correct) + out).shuffled()
    }

    fun answer(choice: QuizChoice) {
        val st = _ui.value
        val card = st.current ?: return
        if (st.picked != null || st.grading) return
        val correct = choice.headword == card.sticker.word?.headword
        val ms = (System.currentTimeMillis() - shownAt).toInt()
        if (AppGraph.soundsOn) AppGraph.speech.play(if (correct) Speech.Sfx.POP else Speech.Sfx.TICK)
        AppGraph.speech.speak(card.sticker.word?.headword.orEmpty(), AppGraph.profile.target)
        if (st.isRetry) {
            _ui.update { s ->
                s.copy(
                    picked = choice.headword,
                    correctCount = s.correctCount + if (correct) 1 else 0,
                    missed = if (!correct && s.missed.none { it.id == card.id }) s.missed + card else s.missed,
                )
            }
            return
        }
        val rid = card.review.id ?: return
        _ui.update { it.copy(picked = choice.headword, grading = true, gradeError = null) }
        viewModelScope.launch {
            try {
                AppGraph.api.call(
                    "gradeReview",
                    jsonOf("review_id" to rid, "correct" to correct, "blur_seen" to false, "response_ms" to ms.coerceAtLeast(0)),
                    timeoutMs = 20_000,
                )
                _ui.update { s ->
                    s.copy(
                        grading = false,
                        doneToday = s.doneToday + 1,
                        streak = maxOf(s.streak, 1),
                        correctCount = s.correctCount + if (correct) 1 else 0,
                        missed = if (!correct && s.missed.none { it.id == card.id }) s.missed + card else s.missed,
                    )
                }
                dex.loadReviews()
            } catch (e: Exception) {
                _ui.update {
                    it.copy(
                        picked = null, grading = false,
                        gradeError = tr("採点を保存できませんでした。もう一度答えてください。", "Couldn't save your answer. Please answer again.", "無法儲存作答，請再回答一次。") + "\n" + e.userMessage,
                    )
                }
            }
        }
    }

    fun next() {
        _ui.update { s ->
            val i = s.index + 1
            s.copy(index = i, picked = null, choices = s.queue.getOrNull(i)?.let(::makeChoices).orEmpty())
        }
        shownAt = System.currentTimeMillis()
    }

    fun retryMissed() {
        _ui.update { s ->
            val q = s.missed.shuffled()
            s.copy(queue = q, index = 0, picked = null, missed = emptyList(), correctCount = 0, isRetry = true, choices = q.firstOrNull()?.let(::makeChoices).orEmpty())
        }
        shownAt = System.currentTimeMillis()
    }

    fun loadMore() = load(extra = 20 + _ui.value.queue.size)

    companion object {
        /** Everyday Taiwanese Mandarin words padding the four choices when the dex is still small. */
        private val fallback = listOf(
            "蘋果" to "ㄆㄧㄥˊ ㄍㄨㄛˇ", "香蕉" to "ㄒㄧㄤ ㄐㄧㄠ", "咖啡" to "ㄎㄚ ㄈㄟ", "茶" to "ㄔㄚˊ",
            "椅子" to "ㄧˇ ˙ㄗ", "桌子" to "ㄓㄨㄛ ˙ㄗ", "書" to "ㄕㄨ", "筆" to "ㄅㄧˇ", "杯子" to "ㄅㄟ ˙ㄗ",
            "手機" to "ㄕㄡˇ ㄐㄧ", "貓" to "ㄇㄠ", "狗" to "ㄍㄡˇ", "花" to "ㄏㄨㄚ", "樹" to "ㄕㄨˋ",
            "車子" to "ㄔㄜ ˙ㄗ", "公車" to "ㄍㄨㄥ ㄔㄜ", "衣服" to "ㄧ ˙ㄈㄨ", "鞋子" to "ㄒㄧㄝˊ ˙ㄗ",
            "包包" to "ㄅㄠ ㄅㄠ", "雨傘" to "ㄩˇ ㄙㄢˇ",
        ).map { QuizChoice(it.first, it.second) }
    }
}
