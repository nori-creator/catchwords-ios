package com.rork.catchwordsandroid.ui.screens

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.VolumeUp
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.rork.catchwordsandroid.data.Category
import com.rork.catchwordsandroid.data.L10n
import com.rork.catchwordsandroid.data.Sticker
import com.rork.catchwordsandroid.data.objects
import com.rork.catchwordsandroid.data.str
import com.rork.catchwordsandroid.data.strings
import com.rork.catchwordsandroid.data.tr
import com.rork.catchwordsandroid.ui.DexViewModel
import com.rork.catchwordsandroid.ui.components.AppBackground
import com.rork.catchwordsandroid.ui.components.Chip
import com.rork.catchwordsandroid.ui.components.MemoryBadge
import com.rork.catchwordsandroid.ui.components.SectionCard
import com.rork.catchwordsandroid.ui.components.StickerImage
import com.rork.catchwordsandroid.ui.components.Toast
import com.rork.catchwordsandroid.ui.components.pressable
import com.rork.catchwordsandroid.ui.components.readingOf
import com.rork.catchwordsandroid.ui.theme.CW
import kotlinx.serialization.json.JsonObject
import java.text.DateFormat
import java.util.Date

/** The word page: picture, reading, meaning, example and every note the card has, in the reader's language. */
@Composable
fun WordDetailScreen(stickerId: String, onClose: () -> Unit, vm: DexViewModel = viewModel()) {
    val state by vm.state.collectAsStateWithLifecycle()
    val message by vm.message.collectAsStateWithLifecycle()
    val sticker = state.sticker(stickerId)
    var confirmDelete by remember { mutableStateOf(false) }
    var editCaption by remember { mutableStateOf(false) }

    LaunchedEffect(sticker?.wordId) { sticker?.let { vm.loadExplanation(it) } }
    LaunchedEffect(message) {
        if (message != null) {
            kotlinx.coroutines.delay(3500)
            vm.clearMessage()
        }
    }

    AppBackground {
        if (sticker == null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(tr("この単語は見つかりません。", "This word isn't available.", "找不到這個單字。"), color = CW.muted)
            }
            CloseButton(onClose, Modifier.statusBarsPadding().padding(16.dp))
            return@AppBackground
        }
        val w = sticker.word
        val generating = w?.id in state.generating
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).statusBarsPadding().navigationBarsPadding().padding(bottom = 32.dp)) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                CloseButton(onClose)
                Spacer(Modifier.weight(1f))
                CircleIcon(Icons.Outlined.DeleteOutline, CW.destructive) { confirmDelete = true }
            }
            Hero(sticker, state.memoryPercent(sticker))
            Column(Modifier.padding(horizontal = 20.dp)) {
                Spacer(Modifier.height(16.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(readingOf(w?.readingZhuyin, w?.pinyin), fontSize = 16.sp, color = CW.primaryInk, fontWeight = FontWeight.SemiBold)
                        Text(w?.headword.orEmpty(), fontSize = 44.sp, fontWeight = FontWeight.Black, color = CW.foreground, letterSpacing = 1.sp)
                    }
                    Box(
                        Modifier.size(56.dp).shadow(10.dp, CircleShape, spotColor = CW.primary).clip(CircleShape).background(CW.brandGradient)
                            .pressable { vm.speak(w?.headword.orEmpty()) },
                        contentAlignment = Alignment.Center,
                    ) { Icon(Icons.AutoMirrored.Outlined.VolumeUp, tr("発音を聞く", "Listen", "聆聽發音"), tint = Color.White) }
                }
                Spacer(Modifier.height(6.dp))
                Text(w?.meaning?.ifBlank { null } ?: if (generating) tr("解説を作っています…", "Writing the explanation…", "正在產生解說…") else "", fontSize = 19.sp, color = CW.foreground, fontWeight = FontWeight.Medium)
                Spacer(Modifier.height(10.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Chip("${Category.emoji(sticker.categoryKey)} ${Category.label(sticker.categoryKey)}")
                    w?.partOfSpeech?.let { Chip(it) }
                }
                Spacer(Modifier.height(16.dp))
                CaptionCard(sticker) { editCaption = true }

                val ex = w?.exampleSentence
                if (!ex.isNullOrBlank()) {
                    Spacer(Modifier.height(12.dp))
                    SectionCard {
                        SectionTitle(tr("例文", "Example", "例句"))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(ex, fontSize = 18.sp, color = CW.foreground, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
                            Icon(Icons.AutoMirrored.Outlined.VolumeUp, null, tint = CW.primary, modifier = Modifier.size(36.dp).clip(CircleShape).pressable { vm.speak(ex) }.padding(7.dp))
                        }
                        w?.exampleTranslation?.let { Text(it, fontSize = 14.sp, color = CW.muted, modifier = Modifier.padding(top = 4.dp)) }
                    }
                }
                Spacer(Modifier.height(12.dp))
                ExtrasSections(w?.extras, generating) { vm.speak(it) }
                Spacer(Modifier.height(16.dp))
                Text(
                    tr("キャッチした日: ", "Caught: ", "收集日期：") + DateFormat.getDateInstance(DateFormat.MEDIUM, L10n.locale).format(Date(sticker.takenAtMs)),
                    fontSize = 12.sp, color = CW.muted,
                )
            }
        }
        message?.let { Toast(it, Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(top = 12.dp)) }
    }

    if (confirmDelete && sticker != null) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text(tr("図鑑から削除しますか？", "Delete from your dex?", "要從圖鑑刪除嗎？")) },
            text = { Text(tr("写真と復習の記録も消えます。元に戻せません。", "Its photos and review history are deleted too. This can't be undone.", "照片與複習紀錄也會一併刪除，無法復原。")) },
            confirmButton = {
                TextButton(onClick = { confirmDelete = false; vm.delete(sticker, onClose) }) { Text(tr("削除", "Delete", "刪除"), color = CW.destructive) }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text(tr("キャンセル", "Cancel", "取消")) } },
        )
    }
    if (editCaption && sticker != null) {
        var text by remember { mutableStateOf(sticker.caption.orEmpty()) }
        AlertDialog(
            onDismissRequest = { editCaption = false },
            title = { Text(tr("ひとこと", "Note", "備註")) },
            text = { OutlinedTextField(text, { text = it.take(80) }, placeholder = { Text(tr("どこで見つけた？", "Where did you find it?", "在哪裡發現的？")) }) },
            confirmButton = { TextButton(onClick = { editCaption = false; vm.saveCaption(sticker, text) }) { Text(tr("保存", "Save", "儲存")) } },
            dismissButton = { TextButton(onClick = { editCaption = false }) { Text(tr("キャンセル", "Cancel", "取消")) } },
        )
    }
}

@Composable
private fun Hero(sticker: Sticker, memory: Int?) {
    Box(
        Modifier
            .padding(horizontal = 20.dp)
            .fillMaxWidth()
            .height(300.dp)
            .shadow(16.dp, RoundedCornerShape(28.dp), ambientColor = Color(0x220060E0), spotColor = Color(0x220060E0))
            .clip(RoundedCornerShape(28.dp))
            .background(Brush.radialGradient(listOf(Color.White, CW.accent))),
    ) {
        StickerImage(
            sticker,
            Modifier.fillMaxSize().padding(if (sticker.isCutout) 24.dp else 0.dp),
            contentScale = if (sticker.isCutout) ContentScale.Fit else ContentScale.Crop,
            emojiSize = 90,
        )
        memory?.let { MemoryBadge(it, Modifier.align(Alignment.TopEnd).padding(12.dp)) }
    }
}

@Composable
private fun CaptionCard(sticker: Sticker, onEdit: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(CW.paper)
            .border(1.dp, CW.paperEdge, RoundedCornerShape(18.dp))
            .pressable(pressedScale = 0.98f, onClick = onEdit)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            sticker.caption ?: tr("ひとことを書く", "Add a note", "寫下備註"),
            fontFamily = CW.hand, fontSize = 18.sp,
            color = if (sticker.caption != null) CW.foreground else CW.muted,
            modifier = Modifier.weight(1f),
        )
        Icon(Icons.Outlined.Edit, null, tint = CW.muted, modifier = Modifier.size(18.dp))
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ExtrasSections(extras: JsonObject?, generating: Boolean, onSpeak: (String) -> Unit) {
    if (extras == null) {
        if (generating) GeneratingCard()
        return
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        val chunks = extras.objects("usage_chunks").mapNotNull { c ->
            val text = c.objects("parts").joinToString("") { it.str("text").orEmpty() }
            if (text.isBlank()) null else text to c.str("ja").orEmpty()
        }
        if (chunks.isNotEmpty()) {
            SectionCard {
                SectionTitle(tr("よく使うかたまり", "Common chunks", "常用搭配"))
                chunks.forEach { (zh, gloss) ->
                    Row(Modifier.fillMaxWidth().padding(vertical = 5.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(zh, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = CW.foreground)
                            if (gloss.isNotBlank()) Text(gloss, fontSize = 13.sp, color = CW.muted)
                        }
                        Icon(Icons.AutoMirrored.Outlined.VolumeUp, null, tint = CW.primary, modifier = Modifier.size(34.dp).clip(CircleShape).pressable { onSpeak(zh) }.padding(7.dp))
                    }
                }
            }
        }
        val measure = extras.objects("measure_words").mapNotNull { m -> m.str("word")?.let { it to (m.str("note") ?: m.str("zhuyin") ?: "") } }
        if (measure.isNotEmpty()) {
            SectionCard {
                SectionTitle(tr("量詞", "Measure words", "量詞"))
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    measure.forEach { (word, note) -> Chip(if (note.isBlank()) word else "$word · $note") }
                }
            }
        }
        val examples = extras.objects("examples_extra").mapNotNull { e -> e.str("zh")?.let { Triple(it, e.str("ja").orEmpty(), e.str("scene").orEmpty()) } }
        if (examples.isNotEmpty()) {
            SectionCard {
                SectionTitle(tr("ほかの例文", "More examples", "更多例句"))
                examples.forEach { (zh, gloss, scene) ->
                    Column(Modifier.padding(vertical = 6.dp).pressable(pressedScale = 0.99f, haptic = false) { onSpeak(zh) }) {
                        if (scene.isNotBlank()) Text(scene, fontSize = 12.sp, color = CW.primaryInk, fontWeight = FontWeight.SemiBold)
                        Text(zh, fontSize = 16.sp, color = CW.foreground)
                        if (gloss.isNotBlank()) Text(gloss, fontSize = 13.sp, color = CW.muted)
                    }
                }
            }
        }
        val related = extras.objects("related_words").mapNotNull { it.str("word")?.let { w -> w to (it.str("kind") ?: "rel") } }
            .ifEmpty { extras.strings("synonyms").map { it to "syn" } + extras.strings("antonyms").map { it to "ant" } }
        if (related.isNotEmpty()) {
            SectionCard {
                SectionTitle(tr("関連する言葉", "Related words", "相關詞"))
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    related.forEach { (word, kind) ->
                        val tag = when (kind) { "syn" -> tr("類", "≈", "近"); "ant" -> tr("対", "↔", "反"); else -> "" }
                        Chip(if (tag.isEmpty()) word else "$tag $word", onClick = { onSpeak(word) })
                    }
                }
            }
        }
        listOf(
            "usage_note" to tr("使い方", "Usage", "用法"),
            "taiwan_note" to tr("台湾では", "In Taiwan", "在台灣"),
            "mnemonic" to tr("覚え方", "Memory tip", "記憶方法"),
            "pronunciation_tips" to tr("発音のコツ", "Pronunciation", "發音技巧"),
            "synonym_diff" to tr("似た言葉との違い", "Vs. similar words", "與近義詞的差異"),
            "etymology" to tr("成り立ち", "Origin", "字源"),
            "culture_note" to tr("文化メモ", "Culture", "文化小知識"),
            "study_tips" to tr("学習のヒント", "Study tip", "學習提示"),
            "trivia" to tr("豆知識", "Trivia", "冷知識"),
        ).forEach { (key, title) ->
            extras.str(key)?.let { text ->
                SectionCard {
                    SectionTitle(title)
                    Text(text, fontSize = 15.sp, color = CW.foreground, lineHeight = 23.sp)
                }
            }
        }
        if (generating) GeneratingCard()
    }
}

@Composable
private fun GeneratingCard() {
    val t = rememberInfiniteTransition(label = "gen")
    val a by t.animateFloat(0.35f, 1f, infiniteRepeatable(tween(800), RepeatMode.Reverse), label = "a")
    SectionCard {
        Text(tr("あなたの言語で解説を作っています…", "Writing notes in your language…", "正在以你的語言產生解說…"), color = CW.primaryInk, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.alpha(a))
        Spacer(Modifier.height(10.dp))
        repeat(3) { i ->
            Box(Modifier.fillMaxWidth(if (i == 2) 0.6f else 1f).height(12.dp).padding(vertical = 2.dp).clip(RoundedCornerShape(6.dp)).background(CW.surface2.copy(alpha = a)))
            Spacer(Modifier.height(6.dp))
        }
    }
}

@Composable
private fun SectionTitle(text: String) {
    Text(text, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = CW.muted, modifier = Modifier.padding(bottom = 8.dp))
}

@Composable
private fun CloseButton(onClose: () -> Unit, modifier: Modifier = Modifier) {
    CircleIcon(Icons.Outlined.Close, CW.foreground, modifier, onClose)
}

@Composable
private fun CircleIcon(icon: androidx.compose.ui.graphics.vector.ImageVector, tint: Color, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Box(
        modifier.size(44.dp).shadow(4.dp, CircleShape).clip(CircleShape).background(CW.card).pressable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { Icon(icon, null, tint = tint, modifier = Modifier.size(22.dp)) }
}

