package com.rork.catchwordsandroid.ui

import android.graphics.Bitmap
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rork.catchwordsandroid.data.ApiException
import com.rork.catchwordsandroid.data.AppGraph
import com.rork.catchwordsandroid.data.Candidate
import com.rork.catchwordsandroid.data.ImageTools
import com.rork.catchwordsandroid.data.Speech
import com.rork.catchwordsandroid.data.Sticker
import com.rork.catchwordsandroid.data.jsonOf
import com.rork.catchwordsandroid.data.objects
import com.rork.catchwordsandroid.data.tr
import com.rork.catchwordsandroid.data.userMessage
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject

enum class CaptureMode { SEARCH, PHOTO }

/** The camera's steps: viewfinder → analyzing → names → card → caught. */
sealed interface CaptureStage {
    data object Camera : CaptureStage
    data class Analyzing(val photo: Bitmap?, val query: String? = null) : CaptureStage
    data class Picking(val photo: Bitmap?, val candidates: List<Candidate>) : CaptureStage
    data class Card(
        val photo: Bitmap?,
        val candidate: Candidate,
        val card: JsonObject?,
        val owned: Sticker?,
        val others: List<Candidate>,
        val isSaving: Boolean = false,
    ) : CaptureStage
    data class Caught(val sticker: Sticker, val reencounter: Boolean, val count: Int?) : CaptureStage
}

data class CaptureUiState(
    val stage: CaptureStage = CaptureStage.Camera,
    val mode: CaptureMode = CaptureMode.PHOTO,
    val toast: String? = null,
)

/** Photo / typed word → candidates (`suggestWords` / `suggestWordCandidates`) → card (`generateCard`) → saved (`saveSticker`). */
class CaptureViewModel : ViewModel() {
    private val api = AppGraph.api
    private val dex = AppGraph.dex
    private val speech = AppGraph.speech

    private val _ui = MutableStateFlow(CaptureUiState())
    val ui: StateFlow<CaptureUiState> = _ui.asStateFlow()

    private var job: Job? = null

    init {
        viewModelScope.launch { api.warmUp() }
    }

    fun setMode(m: CaptureMode) = _ui.update { it.copy(mode = m) }

    fun clearToast() = _ui.update { it.copy(toast = null) }

    fun reset() {
        job?.cancel()
        _ui.update { it.copy(stage = CaptureStage.Camera) }
    }

    private fun sfx(s: Speech.Sfx) {
        if (AppGraph.soundsOn) speech.play(s)
    }

    fun analyze(photo: Bitmap) {
        sfx(Speech.Sfx.SHUTTER)
        job?.cancel()
        _ui.update { it.copy(stage = CaptureStage.Analyzing(photo)) }
        job = viewModelScope.launch {
            try {
                val res = api.call(
                    "suggestWords",
                    jsonOf("imageBase64" to ImageTools.dataUrl(photo), "targetLanguage" to AppGraph.profile.target),
                    timeoutMs = 25_000,
                ) as? JsonObject
                val out = mutableListOf<Candidate>()
                res?.objects("suggestions")?.mapNotNull(Candidate::from)?.forEach { c ->
                    if (out.none { it.headword == c.headword && it.group == c.group }) out += c
                }
                if (out.isEmpty()) throw ApiException.Message(tr("写真から言葉を見つけられませんでした。明るい所で、撮りたい物に近づいて撮り直してください。", "Couldn't find a word in this photo. Get closer in good light and try again.", "無法從照片中找到單字，請在明亮處靠近拍攝後再試一次。"))
                sfx(Speech.Sfx.POP)
                _ui.update { it.copy(stage = CaptureStage.Picking(photo, out)) }
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                _ui.update { it.copy(stage = CaptureStage.Camera, toast = e.userMessage) }
            }
        }
    }

    fun search(query: String) {
        val q = query.trim().take(60)
        if (q.isEmpty()) return
        job?.cancel()
        _ui.update { it.copy(stage = CaptureStage.Analyzing(null, q)) }
        job = viewModelScope.launch {
            try {
                val res = api.call(
                    "suggestWordCandidates",
                    jsonOf("query" to q, "targetLanguage" to AppGraph.profile.target),
                    timeoutMs = 30_000,
                ) as? JsonObject
                val list = res?.objects("candidates")?.mapNotNull(Candidate::from).orEmpty()
                when {
                    list.isEmpty() -> _ui.update { it.copy(stage = CaptureStage.Camera, toast = tr("その言葉が見つかりませんでした。", "Couldn't find that word.", "找不到這個單字。")) }
                    list.size == 1 -> pick(null, list.first(), emptyList())
                    else -> _ui.update { it.copy(stage = CaptureStage.Picking(null, list)) }
                }
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                _ui.update { it.copy(stage = CaptureStage.Camera, toast = e.userMessage) }
            }
        }
    }

    fun pick(photo: Bitmap?, candidate: Candidate, all: List<Candidate>) {
        sfx(Speech.Sfx.TICK)
        val owned = dex.owned(candidate.headword)
        val others = all.filter { it.key != candidate.key }
        _ui.update { it.copy(stage = CaptureStage.Card(photo, candidate, null, owned, others)) }
        speech.speak(candidate.headword, AppGraph.profile.target)
        if (owned != null) return
        job?.cancel()
        job = viewModelScope.launch {
            val data = mutableMapOf<String, Any?>("headword" to candidate.headword, "targetLanguage" to AppGraph.profile.target)
            candidate.categoryKey?.let { data["hintCategory"] = it }
            val card = runCatching {
                api.call("generateCard", com.rork.catchwordsandroid.data.toJson(data) as JsonObject, timeoutMs = 60_000) as? JsonObject
            }
            _ui.update { st ->
                val cur = st.stage as? CaptureStage.Card ?: return@update st
                if (cur.candidate.key != candidate.key) return@update st
                card.fold(
                    onSuccess = { st.copy(stage = cur.copy(card = it ?: JsonObject(emptyMap()))) },
                    onFailure = { e -> st.copy(stage = cur.copy(card = JsonObject(emptyMap())), toast = e.userMessage) },
                )
            }
        }
    }

    fun backToPicking() {
        val cur = _ui.value.stage as? CaptureStage.Card ?: return
        val all = listOf(cur.candidate) + cur.others
        _ui.update { it.copy(stage = if (cur.others.isEmpty()) CaptureStage.Camera else CaptureStage.Picking(cur.photo, all)) }
    }

    fun save(caption: String) {
        val cur = _ui.value.stage as? CaptureStage.Card ?: return
        if (cur.isSaving) return
        _ui.update { it.copy(stage = cur.copy(isSaving = true)) }
        viewModelScope.launch {
            try {
                val jpeg = cur.photo?.let { async { ImageTools.jpeg(it) } }?.await()
                if (cur.owned != null) {
                    val count = dex.recordEncounter(cur.owned, jpeg)
                    sfx(Speech.Sfx.CATCH)
                    _ui.update { it.copy(stage = CaptureStage.Caught(cur.owned, true, count)) }
                } else {
                    val sticker = dex.save(cur.candidate, cur.card ?: JsonObject(emptyMap()), jpeg, caption)
                    sfx(Speech.Sfx.CATCH)
                    sfx(Speech.Sfx.CELEBRATE)
                    _ui.update { it.copy(stage = CaptureStage.Caught(sticker, false, null)) }
                }
            } catch (e: Exception) {
                _ui.update { st ->
                    val c = st.stage as? CaptureStage.Card
                    st.copy(stage = c?.copy(isSaving = false) ?: st.stage, toast = e.userMessage)
                }
            }
        }
    }
}
