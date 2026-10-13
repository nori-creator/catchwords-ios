package com.rork.catchwordsandroid.ui

import android.graphics.Bitmap
import android.graphics.PointF
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rork.catchwordsandroid.data.ApiException
import com.rork.catchwordsandroid.data.AppGraph
import com.rork.catchwordsandroid.data.Candidate
import com.rork.catchwordsandroid.data.CatchObject
import com.rork.catchwordsandroid.data.CutoutService
import com.rork.catchwordsandroid.data.ImageTools
import com.rork.catchwordsandroid.data.InstanceMasks
import com.rork.catchwordsandroid.data.OwnedWord
import com.rork.catchwordsandroid.data.PendingCatch
import com.rork.catchwordsandroid.data.Place
import com.rork.catchwordsandroid.data.Speech
import com.rork.catchwordsandroid.data.Sticker
import com.rork.catchwordsandroid.data.jsonOf
import com.rork.catchwordsandroid.data.objects
import com.rork.catchwordsandroid.data.obj
import com.rork.catchwordsandroid.data.toJson
import com.rork.catchwordsandroid.data.tr
import com.rork.catchwordsandroid.data.userMessage
import com.rork.catchwordsandroid.ui.scan.CatchScanSession
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject

enum class CaptureMode { SEARCH, PHOTO }

/** The catch, as on iOS: camera → (selfie) → processing (scan) → select → celebrate | reencounter → caught. */
sealed interface CaptureStep {
    data object Camera : CaptureStep
    data object Selfie : CaptureStep
    /** The scan runs over the photo; tags come up as the names arrive. */
    data object Processing : CaptureStep
    data object Select : CaptureStep
    /** A word typed from the camera's search, without a photo. */
    data class Typing(val query: String) : CaptureStep
    data class TypedList(val candidates: List<Candidate>) : CaptureStep
    data object Celebrate : CaptureStep
    data object Reencounter : CaptureStep
    data class Failed(val reason: String, val offline: Boolean) : CaptureStep
    data class Caught(val sticker: Sticker) : CaptureStep
}

data class CaptureUiState(
    val step: CaptureStep = CaptureStep.Camera,
    val mode: CaptureMode = CaptureMode.PHOTO,
    val photo: Bitmap? = null,
    val selfie: Bitmap? = null,
    val objects: List<CatchObject> = emptyList(),
    val candidates: List<Candidate> = emptyList(),
    val typedCandidates: List<Candidate> = emptyList(),
    val picked: Candidate? = null,
    val card: JsonObject? = null,
    val cutout: Bitmap? = null,
    val isCutting: Boolean = false,
    val isCheckingOwned: Boolean = false,
    val isLookingUp: Boolean = false,
    val isSaving: Boolean = false,
    val searchError: String? = null,
    val owned: OwnedWord? = null,
    val reencounterCount: Int? = null,
    val place: Place? = null,
    val toast: String? = null,
    val scan: CatchScanSession? = null,
    val pendingCount: Int = 0,
)

/** Port of iOS CaptureViewModel: one segmentation per photo (cut-outs, outlines, tag anchors) alongside the AI. */
class CaptureViewModel : ViewModel() {
    private val api = AppGraph.api
    private val dex = AppGraph.dex
    private val speech = AppGraph.speech
    private val pending = AppGraph.pending

    private val _ui = MutableStateFlow(CaptureUiState())
    val ui: StateFlow<CaptureUiState> = _ui.asStateFlow()

    private var runToken = 0
    private var masksTask: Deferred<InstanceMasks?>? = null
    private var cutoutJob: Job? = null
    private var detectOutcome: Result<List<Candidate>>? = null
    private var pendingId: String? = null
    private var restoredPendingId: String? = null
    private val cardCache = mutableMapOf<String, Deferred<JsonObject?>>()
    private val ownedChecks = mutableMapOf<String, Deferred<OwnedCheck>>()

    /** null owned = not in the dex; failed = the check itself failed (fail open). */
    private data class OwnedCheck(val owned: OwnedWord?, val failed: Boolean)

    init {
        viewModelScope.launch { api.warmUp() }
        CutoutService.warmUp()
        viewModelScope.launch { pending.items.collect { list -> _ui.update { it.copy(pendingCount = list.size) } } }
    }

    fun setMode(m: CaptureMode) = _ui.update { it.copy(mode = m) }

    fun clearToast() = _ui.update { it.copy(toast = null) }

    private fun toast(text: String) = _ui.update { it.copy(toast = text) }

    private fun sfx(s: Speech.Sfx, volume: Float = 0.7f) {
        if (AppGraph.soundsOn) speech.play(s, volume)
    }

    // region Analyze

    fun analyze(image: Bitmap, askSelfie: Boolean = false) {
        sfx(Speech.Sfx.SHUTTER)
        runToken += 1
        val token = runToken
        cutoutJob?.cancel()
        masksTask?.cancel()
        cardCache.clear()
        ownedChecks.clear()
        detectOutcome = null
        val scan = CatchScanSession()
        _ui.update {
            it.copy(
                step = if (askSelfie) CaptureStep.Selfie else CaptureStep.Processing,
                photo = image, selfie = null, objects = emptyList(), candidates = emptyList(), typedCandidates = emptyList(),
                picked = null, card = null, cutout = null, isCutting = false, isCheckingOwned = false, searchError = null,
                owned = null, reencounterCount = null, scan = scan, isSaving = false,
            )
        }
        val masks = viewModelScope.async { runCatching { CutoutService.instanceMasks(image) }.getOrNull() }
        masksTask = masks
        // Cut-outs, anchors and outlines are worked out while the AI is still naming the things.
        viewModelScope.launch(Dispatchers.Default) {
            val m = masks.await()
            val lines = m?.let { mm ->
                mm.anchors()
                mm.outlines()
            } ?: emptyList()
            scan.setOutlines(lines, now())
            m?.prerenderCuts()
        }
        if (restoredPendingId != null) {
            pendingId = restoredPendingId
        } else {
            viewModelScope.launch { pendingId = pending.add(image, tr("解析中", "Analyzing", "分析中")) }
        }
        viewModelScope.launch {
            val placeJob = async { AppGraph.location.currentPlace() }
            try {
                val found = suggest(image)
                if (token != runToken) return@launch
                val m = masks.await()
                val built = withContext(Dispatchers.Default) { CatchObject.build(found, m, image.width, image.height) }
                if (token != runToken) return@launch
                _ui.update { it.copy(objects = built) }
                scan.setNames(built, now())
                detectOutcome = Result.success(found)
                prefetchOwned(found)
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                if (token != runToken) return@launch
                detectOutcome = Result.failure(e)
                pendingId?.let { id -> pending.updateReason(id, e.userMessage) }
            }
            if (_ui.value.step != CaptureStep.Selfie) advanceAfterDetect()
            val place = placeJob.await()
            if (token == runToken) _ui.update { it.copy(place = place) }
        }
    }

    private suspend fun suggest(image: Bitmap): List<Candidate> {
        val res = api.call(
            "suggestWords",
            jsonOf("imageBase64" to ImageTools.dataUrl(image), "targetLanguage" to AppGraph.profile.target),
            timeoutMs = 30_000,
        ) as? JsonObject
        val out = mutableListOf<Candidate>()
        res?.objects("suggestions")?.mapNotNull(Candidate::from)?.forEach { c ->
            if (out.none { it.headword == c.headword && it.group == c.group }) out += c
        }
        if (out.isEmpty()) {
            throw ApiException.Message(
                tr(
                    "写真から言葉を見つけられませんでした。明るい所で、撮りたい物に近づいて撮り直してください。",
                    "Couldn't find a word in this photo. Get closer in good light and try again.",
                    "無法從照片中找到單字，請在明亮處靠近拍攝後再試一次。",
                ),
            )
        }
        return out
    }

    private fun advanceAfterDetect() {
        val outcome = detectOutcome ?: return
        outcome.fold(
            onSuccess = { found -> _ui.update { it.copy(candidates = found, step = CaptureStep.Select) } },
            onFailure = { e ->
                val offline = e is ApiException.Offline
                _ui.update { it.copy(step = CaptureStep.Failed(e.userMessage, offline)) }
            },
        )
    }

    fun finishSelfie(image: Bitmap?) {
        if (_ui.value.step != CaptureStep.Selfie) return
        _ui.update { it.copy(selfie = image) }
        if (detectOutcome == null) _ui.update { it.copy(step = CaptureStep.Processing) } else advanceAfterDetect()
    }

    fun retry() {
        val p = _ui.value.photo ?: return reset()
        val keptSelfie = _ui.value.selfie
        restoredPendingId = pendingId
        analyze(p)
        _ui.update { it.copy(selfie = keptSelfie) }
    }

    fun restore(item: PendingCatch) {
        viewModelScope.launch {
            val img = pending.image(item) ?: run { pending.remove(item.id); return@launch }
            restoredPendingId = item.id
            pendingId = item.id
            analyze(img)
        }
    }

    fun removePending(item: PendingCatch) {
        viewModelScope.launch { pending.remove(item.id) }
    }

    // endregion

    // region Search

    /** 「違う単語を入力」 under the photo, or the camera's search without a photo. */
    fun search(text: String) {
        val q = text.trim().take(60)
        if (q.isEmpty()) return
        runToken += 1
        val token = runToken
        ownedChecks.clear()
        val fromCamera = _ui.value.photo == null || _ui.value.step == CaptureStep.Camera
        if (fromCamera) {
            _ui.update { it.copy(photo = null, scan = null, objects = emptyList(), step = CaptureStep.Typing(q)) }
        }
        _ui.update { it.copy(isLookingUp = true, searchError = null) }
        viewModelScope.launch {
            try {
                val res = api.call(
                    "suggestWordCandidates",
                    toJson(mapOf("query" to q, "targetLanguage" to AppGraph.profile.target, "scene" to _ui.value.place?.name)) as JsonObject,
                    timeoutMs = 30_000,
                ) as? JsonObject
                if (token != runToken) return@launch
                val list = res?.objects("candidates")?.mapNotNull(Candidate::from).orEmpty()
                if (list.isEmpty()) throw ApiException.Message(notTargetLang)
                _ui.update { it.copy(isLookingUp = false) }
                when {
                    list.size == 1 -> choose(list.first(), null)
                    fromCamera -> _ui.update { it.copy(step = CaptureStep.TypedList(list)) }
                    else -> _ui.update { it.copy(typedCandidates = list) }
                }
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                if (token != runToken) return@launch
                val msg = if (e is ApiException.Message) notTargetLang else e.userMessage
                if (fromCamera) {
                    _ui.update { it.copy(isLookingUp = false, step = CaptureStep.Camera, toast = msg) }
                } else {
                    _ui.update { it.copy(isLookingUp = false, searchError = msg) }
                }
            }
        }
    }

    private val notTargetLang: String
        get() = tr(
            "学習している言語の単語が見つかりませんでした。別の言い方で調べてみてください。",
            "Couldn't find a word in the language you're learning. Try another way of saying it.",
            "找不到你正在學習的語言的單字，請換個說法試試。",
        )

    // endregion

    // region Choose → celebrate / reencounter

    private fun ownedCheck(headword: String): Deferred<OwnedCheck> = ownedChecks.getOrPut(headword) {
        viewModelScope.async {
            try {
                val res = api.call("checkOwnedWord", jsonOf("headword" to headword, "language" to AppGraph.profile.target), timeoutMs = 15_000) as? JsonObject
                OwnedCheck(res?.obj("owned")?.let(OwnedWord::from), false)
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                OwnedCheck(dex.owned(headword)?.let(OwnedWord::fromSticker), true)
            }
        }
    }

    private fun prefetchOwned(found: List<Candidate>) {
        CatchObject.groups(found).forEach { w -> w.firstOrNull()?.let { ownedCheck(it.headword) } }
    }

    private fun logPick(word: Candidate, obj: CatchObject?) {
        val st = _ui.value
        val via: String
        val rank: Int
        val count: Int
        val i = st.candidates.indexOfFirst { it.headword == word.headword && it.group == word.group }
        if (obj != null && i >= 0) {
            via = "photo"; rank = i + 1; count = st.candidates.size
        } else if (obj == null && st.photo != null) {
            via = "native_search"
            rank = (st.typedCandidates.indexOfFirst { it.headword == word.headword }.coerceAtLeast(0)) + 1
            count = maxOf(st.typedCandidates.size, rank)
        } else return
        viewModelScope.launch {
            runCatching { api.call("logCandidatePick", jsonOf("via" to via, "rank" to minOf(rank, 50), "n" to minOf(maxOf(count, rank), 50)), timeoutMs = 15_000) }
        }
    }

    fun choose(word: Candidate, obj: CatchObject?) {
        if (_ui.value.isCheckingOwned) return
        val token = runToken
        logPick(word, obj)
        sfx(Speech.Sfx.TICK)
        cutoutJob?.cancel()
        _ui.update { it.copy(picked = word, card = null, searchError = null, cutout = obj?.cut, isCutting = false, isCheckingOwned = true) }
        if (obj?.cut == null) startCutout(obj?.anchor)
        loadCard(word)
        viewModelScope.launch {
            var found = ownedCheck(word.headword).await()
            if (found.failed && token == runToken) {
                ownedChecks.remove(word.headword)
                found = ownedCheck(word.headword).await()
            }
            if (token != runToken || _ui.value.picked != word) return@launch
            val o = found.owned
            if (o != null) {
                cardCache.remove(cardKey(word))?.cancel()
                _ui.update { it.copy(isCheckingOwned = false, owned = o, reencounterCount = null, step = CaptureStep.Reencounter) }
                recordReencounter(o, token)
            } else {
                _ui.update { it.copy(isCheckingOwned = false, step = CaptureStep.Celebrate) }
                sfx(Speech.Sfx.CELEBRATE, 0.55f)
                kotlinx.coroutines.delay(450)
                if (token == runToken && _ui.value.picked == word) speech.speak(word.headword, AppGraph.profile.target)
            }
        }
    }

    private fun startCutout(point: PointF?) {
        val photo = _ui.value.photo ?: return
        _ui.update { it.copy(isCutting = true) }
        cutoutJob = viewModelScope.launch {
            val m = masksTask?.await()
            val lifted = if (m != null) {
                withContext(Dispatchers.Default) {
                    val label = point?.let { p -> m.instances(p).firstOrNull()?.label } ?: m.largestLabel()
                    label?.let { m.cut(it)?.image }
                }
            } else {
                CutoutService.liftSubject(photo, point)
            }
            _ui.update { it.copy(isCutting = false, cutout = lifted ?: it.cutout) }
        }
    }

    private fun cardKey(c: Candidate) = c.headword + "|" + (c.categoryKey ?: "")

    private fun loadCard(c: Candidate) {
        val token = runToken
        val key = cardKey(c)
        val task = cardCache.getOrPut(key) {
            viewModelScope.async {
                val data = mutableMapOf<String, Any?>("headword" to c.headword, "targetLanguage" to AppGraph.profile.target)
                c.categoryKey?.let { data["hintCategory"] = it }
                runCatching { api.call("generateCard", toJson(data) as JsonObject, timeoutMs = 60_000) as? JsonObject }.getOrNull()
            }
        }
        viewModelScope.launch {
            val d = task.await()
            if (d == null && cardCache[key] == task) cardCache.remove(key)
            if (token != runToken || _ui.value.picked != c) return@launch
            if (d != null) _ui.update { it.copy(card = d) }
        }
    }

    fun backToCandidates() {
        runToken += 1
        cutoutJob?.cancel()
        _ui.update {
            it.copy(
                picked = null, card = null, cutout = null, isCutting = false, isCheckingOwned = false, isSaving = false,
                step = if (it.photo != null) CaptureStep.Select else CaptureStep.Camera,
            )
        }
    }

    // endregion

    // region Save

    /** 「図鑑に追加」: waits for a cut-out still running, then saves (photo, cut-out, selfie, place, note). */
    fun add(caption: String) {
        val st = _ui.value
        val picked = st.picked ?: return
        if (st.isSaving) return
        _ui.update { it.copy(isSaving = true) }
        viewModelScope.launch {
            cutoutJob?.join()
            val cur = _ui.value
            val card = cur.card ?: cardCache[cardKey(picked)]?.let { d -> if (d.isCompleted) d.await() else null } ?: JsonObject(emptyMap())
            try {
                val base = cur.photo ?: textCard(picked.headword)
                val sticker = dex.save(
                    candidate = picked, card = card, photo = base, cutout = cur.cutout, selfie = cur.selfie,
                    caption = caption, place = cur.place,
                )
                // The card still being written fills the notes in behind the dex.
                if (cur.card == null) cardCache[cardKey(picked)]?.let { d -> viewModelScope.launch { d.await()?.let { dex.fillCard(sticker, it) } } }
                releasePending()
                sfx(Speech.Sfx.CATCH)
                sfx(Speech.Sfx.JAR_CORK)
                _ui.update { it.copy(isSaving = false, step = CaptureStep.Caught(sticker)) }
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                _ui.update { it.copy(isSaving = false, toast = e.userMessage) }
            }
        }
    }

    /** The re-encounter is recorded as soon as its screen opens (iOS ReencounterView.record). */
    private fun recordReencounter(o: OwnedWord, token: Int) {
        viewModelScope.launch {
            cutoutJob?.join()
            val cur = _ui.value
            try {
                val count = dex.recordEncounter(o.stickerId, cur.photo, cur.cutout, cur.place)
                releasePending()
                if (token == runToken) _ui.update { it.copy(reencounterCount = count ?: (o.encounterCount + 1)) }
                sfx(Speech.Sfx.LAND)
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                if (token == runToken) _ui.update { it.copy(toast = e.userMessage) }
            }
        }
    }

    private fun releasePending() {
        val id = pendingId ?: return
        pendingId = null
        restoredPendingId = null
        viewModelScope.launch { pending.remove(id) }
    }

    /** 「もう一枚撮る」 from the failure panel keeps the photo in 解析待ち. */
    fun keepPendingAndReset() {
        pendingId = null
        restoredPendingId = null
        reset()
    }

    fun reset() {
        runToken += 1
        cutoutJob?.cancel()
        masksTask?.cancel()
        masksTask = null
        pendingId?.let { id -> viewModelScope.launch { pending.remove(id) } }
        pendingId = null
        restoredPendingId = null
        detectOutcome = null
        cardCache.clear()
        ownedChecks.clear()
        _ui.update { CaptureUiState(mode = it.mode, pendingCount = it.pendingCount) }
    }

    /** After a catch: back to the camera without throwing anything away. */
    fun finishCaught() {
        pendingId = null
        reset()
    }

    // endregion

    private fun now(): Double = System.nanoTime() / 1e9

    companion object {
        /** A typed catch gets a generated word card so the dex always has a surface (iOS textCard). */
        fun textCard(text: String): Bitmap {
            val size = 900
            val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val c = android.graphics.Canvas(bmp)
            val p = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)
            p.shader = android.graphics.LinearGradient(0f, 0f, size.toFloat(), size.toFloat(), 0xFF299CFF.toInt(), 0xFF0061E0.toInt(), android.graphics.Shader.TileMode.CLAMP)
            c.drawRect(0f, 0f, size.toFloat(), size.toFloat(), p)
            p.shader = null
            p.color = android.graphics.Color.WHITE
            p.textAlign = android.graphics.Paint.Align.CENTER
            p.isFakeBoldText = true
            p.textSize = if (text.length > 3) 150f else 230f
            while (p.measureText(text) > size - 80 && p.textSize > 40) p.textSize -= 10
            val y = size / 2f - (p.descent() + p.ascent()) / 2
            c.drawText(text, size / 2f, y, p)
            return bmp
        }
    }
}
