package com.rork.catchwordsandroid.ui.screens

import android.view.HapticFeedbackConstants
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.catchwordsandroid.data.AppGraph
import com.rork.catchwordsandroid.data.Candidate
import com.rork.catchwordsandroid.data.CatchObject
import com.rork.catchwordsandroid.data.Speech
import com.rork.catchwordsandroid.data.tr
import com.rork.catchwordsandroid.ui.CaptureUiState
import com.rork.catchwordsandroid.ui.CaptureViewModel
import com.rork.catchwordsandroid.ui.components.pressable
import com.rork.catchwordsandroid.ui.components.readingOf
import com.rork.catchwordsandroid.ui.scan.CatchScanPlan
import com.rork.catchwordsandroid.ui.scan.CatchScanSession
import com.rork.catchwordsandroid.ui.theme.CW
import kotlinx.coroutines.delay
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

private val TagInk = Color(0xFF0B121A)

/**
 * After the shot (iOS CandidatePickerView): the photo with the scan running over it, then each word as a tag ON its
 * object (deep inside its segmented subject), and 「違う単語を入力」 underneath. A tap on a tag goes straight on.
 */
@Composable
fun PickerStage(ui: CaptureUiState, scanning: Boolean, vm: CaptureViewModel) {
    val focus = LocalFocusManager.current
    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().statusBarsPadding().imePadding().padding(bottom = 84.dp)) {
            PickerTopBar(ui.scan, onRetake = vm::reset)
            Box(
                Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .padding(horizontal = 10.dp)
                    .clip(RoundedCornerShape(24.dp))
                    .background(Color.Black)
                    .pressable(pressedScale = 1f) { focus.clearFocus() },
            ) {
                PhotoStage(ui, vm)
            }
            Spacer(Modifier.height(12.dp))
            BottomPanel(
                ui = ui,
                enabled = !scanning,
                onSearch = { focus.clearFocus(); vm.search(it) },
                onPick = { vm.choose(it, null) },
                modifier = Modifier.padding(horizontal = 10.dp).padding(bottom = 8.dp),
            )
        }
        if (ui.isCheckingOwned) {
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.25f)), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = Color.White)
            }
        }
    }
}

@Composable
private fun PickerTopBar(scan: CatchScanSession?, onRetake: () -> Unit) {
    val hint = when (scan?.phase) {
        CatchScanSession.Phase.SCANNING -> tr("写真をスキャンしています", "Scanning the photo", "正在掃描照片")
        CatchScanSession.Phase.NAMING -> tr("名前を調べています", "Looking up names", "正在查詢名稱")
        else -> tr("覚えたいことばをタップ", "Tap a word to learn", "點選想記住的單字")
    }
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Row(
            Modifier.height(44.dp).clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = 0.12f)).pressable(onClick = onRetake).padding(horizontal = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Outlined.Refresh, null, tint = Color.White, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text(tr("撮り直す", "Retake", "重拍"), color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
        }
        Spacer(Modifier.weight(1f))
        androidx.compose.animation.AnimatedContent(hint, label = "hint", transitionSpec = { fadeIn(tween(250)) togetherWith fadeOut(tween(250)) }) {
            Text(it, color = Color.White.copy(alpha = 0.85f), fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
        }
    }
}

private data class Tag(val id: String, val obj: CatchObject, val word: Candidate, val main: Boolean, val mainIndex: Int?)
private data class Placed(val tag: Tag, val w: Float, val h: Float, val x: Float, val bottom: Float)

private fun registerRank(r: String?) = when (r) { "casual" -> 1; "specific" -> 2; "proper" -> 3; else -> 0 }

private fun tagsOf(objects: List<CatchObject>): List<Tag> {
    val mains = mutableListOf<Tag>()
    val others = mutableListOf<Tag>()
    for (o in objects) {
        val order = o.words.indices.sortedWith(compareBy({ registerRank(o.words[it].register) }, { it }))
        order.forEachIndexed { k, i ->
            val id = "${o.id}-$i"
            if (k == 0) mains += Tag(id, o, o.words[i], true, mains.size) else others += Tag(id, o, o.words[i], false, null)
        }
    }
    return mains + others
}

/** CCPickLayout: each tag at its object; one that would cover another moves just above or below. */
private fun layoutTags(anchors: List<Pair<Float, Float>>, sizes: List<Pair<Float, Float>>, minBottom: Float, maxBottom: Float): List<Float> {
    val gap = 6f
    val placed = mutableListOf<Rect>()
    val out = mutableListOf<Float>()
    anchors.forEachIndexed { i, a ->
        val (w, h) = sizes[i]
        fun frame(y: Float) = Rect(a.first - w / 2, y - h, a.first + w / 2, y)
        fun free(y: Float): Boolean {
            val f = frame(y).inflate(gap / 2)
            return placed.none { it.inflate(gap / 2).overlaps(f) }
        }
        var y = a.second
        if (!free(y)) {
            val options = placed.flatMap { listOf(it.bottom + gap + 1 + h, it.top - gap - 1) }
            val high = max(maxBottom, a.second)
            options.filter { it in minBottom..high && free(it) }.minByOrNull { abs(it - a.second) }?.let { y = it }
        }
        out += y
        placed += frame(y)
    }
    return out
}

@Composable
private fun PhotoStage(ui: CaptureUiState, vm: CaptureViewModel) {
    val photo = ui.photo ?: return
    val scan = ui.scan
    val view = LocalView.current
    val density = LocalDensity.current
    val measurer = rememberTextMeasurer()
    var frame by remember { mutableDoubleStateOf(0.0) }

    LaunchedEffect(scan) {
        scan ?: return@LaunchedEffect
        scan.onScanStart = { if (AppGraph.soundsOn) AppGraph.speech.play(Speech.Sfx.SCAN_START) }
        scan.onLock = {
            if (AppGraph.soundsOn) AppGraph.speech.play(Speech.Sfx.TICK, 0.5f)
            view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
        }
        scan.onFound = { if (AppGraph.soundsOn) AppGraph.speech.play(Speech.Sfx.FOUND) }
        scan.onPop = {
            if (AppGraph.soundsOn) AppGraph.speech.play(Speech.Sfx.POP)
            view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
        }
        scan.begin(System.nanoTime() / 1e9)
        while (!scan.idle()) {
            withFrameNanos { }
            val now = System.nanoTime() / 1e9
            scan.step(now)
            frame = now
            if (scan.settled) delay(16)
        }
    }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val wDp = maxWidth.value
        val hDp = maxHeight.value
        val stage = Size(wDp, hDp)
        val photoSize = Size(photo.width.toFloat(), photo.height.toFloat())
        val fill = remember(wDp, hDp, photo) { CatchScanPlan.fillRect(photoSize, stage) }
        LaunchedEffect(scan, wDp, hDp) { scan?.layout(stage, fill) }

        Image(photo.asImageBitmap(), null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        if (scan != null) {
            Canvas(Modifier.fillMaxSize()) {
                @Suppress("UNUSED_EXPRESSION") frame
                scan.draw(this, photoSize, if (frame == 0.0) System.nanoTime() / 1e9 else frame)
            }
        }

        val objects = ui.objects.ifEmpty {
            if (ui.candidates.isNotEmpty()) CatchObject.build(ui.candidates, null, photo.width, photo.height) else emptyList()
        }
        val tags = remember(objects) { tagsOf(objects) }
        if (tags.isNotEmpty()) {
            val style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.Black)
            val sizes = tags.map { t ->
                val m = measurer.measure(t.word.headword, style)
                with(density) { (m.size.width.toDp().value + 37f) to (ceil(m.size.height.toDp().value) + 14f) }
            }
            val tallest = sizes.maxOf { it.second }
            val minBottom = tallest + 6
            val maxBottom = max(minBottom, hDp - 6)
            val anchors = tags.mapIndexed { i, t ->
                val px = fill.left + t.obj.anchor.x * fill.width
                val py = fill.top + t.obj.anchor.y * fill.height
                val (w, h) = sizes[i]
                val side = w / 2 + 8
                val x = if (side * 2 > wDp) wDp / 2 else px.coerceIn(side, wDp - side)
                x to (py + h / 2).coerceIn(minBottom, maxBottom)
            }
            val bottoms = layoutTags(anchors, sizes, minBottom, maxBottom)
            tags.forEachIndexed { i, t ->
                val shown = scan?.revealed?.contains(t.obj.id) ?: true
                TagChip(
                    t, shown, scan != null,
                    Modifier.offset { with(density) { IntOffset((anchors[i].first - sizes[i].first / 2).dp.roundToPx(), (bottoms[i] - sizes[i].second).dp.roundToPx()) } },
                ) { vm.choose(t.word, t.obj) }
            }
        }
    }
}

@Composable
private fun TagChip(t: Tag, shown: Boolean, scanned: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val spec = spring<Float>(dampingRatio = 0.68f, stiffness = Spring.StiffnessMediumLow)
    val scale by animateFloatAsState(if (shown) 1f else if (scanned) 0.86f else 0.6f, spec, label = "s")
    val alpha by animateFloatAsState(if (shown) 1f else 0f, tween(if (t.main) 220 else 280, delayMillis = if (t.main) 0 else 60), label = "a")
    val rise by animateDpAsState(if (shown) 0.dp else 6.dp, spring(dampingRatio = 0.68f), label = "r")
    val blur by animateDpAsState(if (shown || !scanned) 0.dp else 3.dp, tween(300), label = "b")
    Row(
        modifier
            .offset(y = rise)
            .scale(scale)
            .alpha(alpha)
            .blur(blur)
            .shadow(10.dp, RoundedCornerShape(50), ambientColor = Color.Black.copy(alpha = 0.3f), spotColor = Color.Black.copy(alpha = 0.3f))
            .clip(RoundedCornerShape(50))
            .background(Color.White.copy(alpha = if (t.main) 0.96f else 0.8f))
            .pressable(enabled = shown, pressedScale = 0.94f, onClick = onClick)
            .padding(start = 8.dp, end = 12.dp, top = 7.dp, bottom = 7.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(10.dp).clip(CircleShape).background(if (t.main) Color(0xFF2A9BFF) else Color(0xFF9AA6B5)))
        Spacer(Modifier.width(7.dp))
        Text(t.word.headword, color = TagInk, fontSize = 13.sp, fontWeight = FontWeight.Black, maxLines = 1, softWrap = false)
    }
}

@Composable
private fun BottomPanel(ui: CaptureUiState, enabled: Boolean, onSearch: (String) -> Unit, onPick: (Candidate) -> Unit, modifier: Modifier = Modifier) {
    var typed by rememberSaveable { mutableStateOf("") }
    val panelAlpha by animateFloatAsState(if (enabled) 1f else 0.5f, tween(250), label = "p")
    Column(
        modifier.fillMaxWidth().alpha(panelAlpha).clip(RoundedCornerShape(22.dp)).background(CW.card).padding(14.dp).animateContentSize(),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        if (ui.typedCandidates.isNotEmpty()) {
            Column(Modifier.heightIn(max = 220.dp)) {
                ui.typedCandidates.forEachIndexed { i, c ->
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 50.dp).pressable(pressedScale = 0.98f) { onPick(c) }.padding(vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(readingOf(c.zhuyin, c.pinyin), color = CW.primaryInk, fontSize = 11.sp)
                            Text(c.headword, color = CW.foreground, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                            if (c.meaning.isNotBlank()) Text(c.meaning, color = CW.muted, fontSize = 12.sp, maxLines = 2)
                        }
                        Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, null, tint = CW.muted)
                    }
                    if (i < ui.typedCandidates.size - 1) HorizontalDivider(color = CW.border)
                }
            }
        }
        Text(tr("違う単語を入力", "Type a different word", "輸入其他單字"), color = CW.muted, fontSize = 13.sp, fontWeight = FontWeight.Medium)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier.weight(1f).height(46.dp).clip(RoundedCornerShape(12.dp)).background(CW.background)
                    .border(1.dp, CW.primary.copy(alpha = 0.3f), RoundedCornerShape(12.dp)).padding(horizontal = 14.dp),
                contentAlignment = Alignment.CenterStart,
            ) {
                if (typed.isEmpty()) Text(tr("例: マンゴー", "e.g. mango", "例：芒果"), color = CW.muted.copy(alpha = 0.7f), fontSize = 16.sp)
                BasicTextField(
                    typed, { typed = it.take(60) }, enabled = enabled, singleLine = true,
                    textStyle = TextStyle(color = CW.foreground, fontSize = 16.sp), cursorBrush = SolidColor(CW.primary),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                    keyboardActions = KeyboardActions(onSearch = { if (typed.isNotBlank() && !ui.isLookingUp) { onSearch(typed); typed = "" } }),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            Row(
                Modifier.height(46.dp).clip(RoundedCornerShape(12.dp)).background(CW.surface2)
                    .pressable(enabled = enabled && typed.isNotBlank() && !ui.isLookingUp) { onSearch(typed); typed = "" }
                    .padding(horizontal = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (ui.isLookingUp) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = CW.primary)
                else Icon(Icons.Outlined.Search, null, tint = CW.foreground, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text(tr("検索", "Search", "搜尋"), color = CW.foreground, fontSize = 15.sp, fontWeight = FontWeight.Medium)
            }
        }
        AnimatedVisibility(ui.searchError != null, enter = fadeIn(), exit = fadeOut()) {
            Text(ui.searchError.orEmpty(), color = CW.destructive, fontSize = 13.sp)
        }
    }
}

/** The camera's search without a photo: several words for what was typed. */
@Composable
fun TypedListStage(list: List<Candidate>, onPick: (Candidate) -> Unit, onBack: () -> Unit) {
    Column(Modifier.fillMaxSize().statusBarsPadding().padding(bottom = 84.dp)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Row(
                Modifier.height(44.dp).clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = 0.12f)).pressable(onClick = onBack).padding(horizontal = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) { Text(tr("戻る", "Back", "返回"), color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold) }
            Spacer(Modifier.width(12.dp))
            Text(tr("どれをキャッチする？", "Which one will you catch?", "要收集哪一個？"), color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.Bold)
        }
        Column(
            Modifier.padding(horizontal = 12.dp).fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(CW.card).padding(horizontal = 16.dp, vertical = 6.dp),
        ) {
            list.forEachIndexed { i, c ->
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 60.dp).pressable(pressedScale = 0.98f) { onPick(c) }.padding(vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(readingOf(c.zhuyin, c.pinyin), color = CW.primaryInk, fontSize = 12.sp)
                        Text(c.headword, color = CW.foreground, fontSize = 24.sp, fontWeight = FontWeight.Bold)
                        if (c.meaning.isNotBlank()) Text(c.meaning, color = CW.muted, fontSize = 13.sp)
                        if (c.distinction.isNotBlank()) Text(c.distinction, color = CW.muted.copy(alpha = 0.8f), fontSize = 12.sp)
                    }
                    if (AppGraph.dex.owned(c.headword) != null) Text(tr("取得済み", "Caught", "已收集"), color = CW.gold, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, null, tint = CW.muted)
                }
                if (i < list.size - 1) HorizontalDivider(color = CW.border)
            }
        }
    }
}
