package com.rork.catchwordsandroid.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.List
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.rork.catchwordsandroid.data.Category
import com.rork.catchwordsandroid.data.DexState
import com.rork.catchwordsandroid.data.ReaderLanguage
import com.rork.catchwordsandroid.data.Sticker
import com.rork.catchwordsandroid.data.tr
import com.rork.catchwordsandroid.ui.DexLayout
import com.rork.catchwordsandroid.ui.DexViewModel
import com.rork.catchwordsandroid.ui.components.AppBackground
import com.rork.catchwordsandroid.ui.components.MemoryBadge
import com.rork.catchwordsandroid.ui.components.SectionCard
import com.rork.catchwordsandroid.ui.components.StickerImage
import com.rork.catchwordsandroid.ui.components.pressable
import com.rork.catchwordsandroid.ui.components.readingOf
import com.rork.catchwordsandroid.ui.theme.CW

/** 図鑑: every caught word grouped by category (room order), as tiles or as a list. */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun DexScreen(onOpenWord: (String) -> Unit, vm: DexViewModel = viewModel()) {
    val state by vm.state.collectAsStateWithLifecycle()
    val layout by vm.layout.collectAsStateWithLifecycle()
    val query by vm.query.collectAsStateWithLifecycle()
    val refreshing by vm.refreshing.collectAsStateWithLifecycle()

    val filtered = remember(state.stickers, query) {
        val q = query.trim()
        if (q.isEmpty()) state.stickers else state.stickers.filter { s ->
            val w = s.word
            w != null && (w.headword.contains(q) || w.meaning.contains(q, true) || (w.pinyin ?: "").contains(q, true))
        }
    }
    val groups = remember(filtered) {
        filtered.groupBy { it.categoryKey }.entries.sortedBy { Category.orderedKeys.indexOf(it.key) }
    }

    AppBackground {
        Column(Modifier.fillMaxSize().statusBarsPadding()) {
            Row(Modifier.padding(start = 20.dp, end = 16.dp, top = 12.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(tr("図鑑", "Dex", "圖鑑"), fontSize = 30.sp, fontWeight = FontWeight.Black, color = CW.foreground)
                    Text(tr("${state.stickers.size} 語", "${state.stickers.size} words", "${state.stickers.size} 個單字"), fontSize = 13.sp, color = CW.muted)
                }
                LayoutToggle(layout, vm::setLayout)
            }
            SearchField(query, vm::setQuery, Modifier.padding(horizontal = 16.dp))
            PullToRefreshBox(isRefreshing = refreshing, onRefresh = vm::refresh, modifier = Modifier.fillMaxSize()) {
                when {
                    !state.hasLoaded && state.isLoading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = CW.primary) }
                    state.error != null && state.stickers.isEmpty() -> EmptyDex(state.error.orEmpty())
                    state.stickers.isEmpty() -> EmptyDex(tr("まだ単語がありません。カメラで身の回りの物を撮ってみましょう。", "No words yet. Snap something around you with the camera.", "還沒有單字。用相機拍拍身邊的東西吧。"))
                    else -> LazyColumn(
                        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 110.dp),
                        verticalArrangement = Arrangement.spacedBy(14.dp),
                    ) {
                        if (layout == DexLayout.GRID) {
                            items(groups, key = { it.key }) { (key, list) -> CategoryCard(key, list, state, onOpenWord) }
                        } else {
                            items(filtered, key = { it.id }) { s -> WordRow(s, state, onOpenWord) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LayoutToggle(layout: DexLayout, onChange: (DexLayout) -> Unit) {
    Row(Modifier.clip(RoundedCornerShape(50)).background(CW.surface2).padding(4.dp)) {
        listOf(DexLayout.GRID to Icons.Outlined.GridView, DexLayout.LIST to Icons.AutoMirrored.Outlined.List).forEach { (l, icon) ->
            val on = l == layout
            Box(
                Modifier.size(40.dp).clip(CircleShape).background(if (on) CW.card else Color.Transparent).pressable { onChange(l) },
                contentAlignment = Alignment.Center,
            ) { Icon(icon, null, tint = if (on) CW.foreground else CW.muted, modifier = Modifier.size(20.dp)) }
        }
    }
}

@Composable
private fun SearchField(value: String, onChange: (String) -> Unit, modifier: Modifier = Modifier) {
    Row(
        modifier.fillMaxWidth().height(44.dp).clip(RoundedCornerShape(14.dp)).background(CW.card).border(1.dp, CW.border, RoundedCornerShape(14.dp)).padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Outlined.Search, null, tint = CW.muted, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(8.dp))
        Box(Modifier.weight(1f)) {
            if (value.isEmpty()) Text(tr("単語や意味で探す", "Search words or meanings", "搜尋單字或意思"), color = CW.muted, fontSize = 15.sp)
            BasicTextField(value, onChange, singleLine = true, textStyle = TextStyle(fontSize = 15.sp, color = CW.foreground), cursorBrush = SolidColor(CW.primary), modifier = Modifier.fillMaxWidth())
        }
    }
}

@Composable
private fun CategoryCard(key: String, stickers: List<Sticker>, state: DexState, onOpenWord: (String) -> Unit) {
    SectionCard(padding = 14.dp) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(Category.emoji(key), fontSize = 18.sp)
            Spacer(Modifier.width(6.dp))
            Text(Category.label(key), fontSize = 16.sp, fontWeight = FontWeight.Bold, color = CW.foreground, modifier = Modifier.weight(1f))
            Box(Modifier.size(8.dp).clip(CircleShape).background(Category.room(key).accent))
            Spacer(Modifier.width(6.dp))
            Text("${stickers.size}", fontSize = 14.sp, color = CW.muted, fontWeight = FontWeight.SemiBold)
        }
        Spacer(Modifier.height(10.dp))
        stickers.chunked(4).forEach { row ->
            Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { s -> Tile(s, state.memoryPercent(s), Modifier.weight(1f)) { onOpenWord(s.id) } }
                repeat(4 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

@Composable
private fun Tile(sticker: Sticker, memory: Int?, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Column(modifier.pressable(onClick = onClick), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.fillMaxWidth().aspectRatio(1f).clip(RoundedCornerShape(16.dp)).background(Color(0xFFEAF0F7))) {
            StickerImage(sticker, Modifier.fillMaxSize().padding(if (sticker.isCutout) 6.dp else 0.dp), contentScale = if (sticker.isCutout) ContentScale.Fit else ContentScale.Crop, emojiSize = 26)
            if (memory != null) MemoryBadge(memory, Modifier.align(Alignment.TopEnd).padding(3.dp))
        }
        Spacer(Modifier.height(4.dp))
        Text(sticker.word?.headword.orEmpty(), fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = CW.foreground, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun WordRow(sticker: Sticker, state: DexState, onOpenWord: (String) -> Unit) {
    val w = sticker.word
    Row(
        Modifier
            .fillMaxWidth()
            .shadow(4.dp, RoundedCornerShape(20.dp), ambientColor = Color(0x10000000), spotColor = Color(0x10000000))
            .clip(RoundedCornerShape(20.dp))
            .background(CW.card)
            .pressable(pressedScale = 0.98f) { onOpenWord(sticker.id) }
            .padding(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        StickerImage(sticker, Modifier.size(58.dp).clip(RoundedCornerShape(14.dp)).background(Color(0xFFEAF0F7)), contentScale = ContentScale.Crop, emojiSize = 24)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.Bottom) {
                Text(w?.headword.orEmpty(), fontSize = 19.sp, fontWeight = FontWeight.Bold, color = CW.foreground)
                Spacer(Modifier.width(8.dp))
                Text(readingOf(w?.readingZhuyin, w?.pinyin), fontSize = 13.sp, color = CW.primaryInk)
            }
            Text(ReaderLanguage.gloss(w?.meaning.orEmpty()), fontSize = 14.sp, color = CW.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        state.memoryPercent(sticker)?.let { MemoryBadge(it) }
    }
}

@Composable
private fun EmptyDex(text: String) {
    Box(Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text("📖", fontSize = 48.sp)
            Spacer(Modifier.height(12.dp))
            Text(text, color = CW.muted, fontSize = 15.sp, textAlign = TextAlign.Center)
        }
    }
}
