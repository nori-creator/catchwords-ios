package com.rork.catchwordsandroid.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import com.rork.catchwordsandroid.data.AppGraph
import com.rork.catchwordsandroid.data.Category
import com.rork.catchwordsandroid.data.ReviewState
import com.rork.catchwordsandroid.data.Sticker
import com.rork.catchwordsandroid.ui.theme.CW

/** The app's airy sky background: soft gradient with two blurred light pools. */
@Composable
fun AppBackground(modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit = {}) {
    Box(modifier.fillMaxSize().background(Brush.verticalGradient(listOf(CW.background, Color(0xFFF1F7FF), CW.backgroundDeep)))) {
        Canvas(Modifier.fillMaxSize()) {
            drawCircle(
                Brush.radialGradient(listOf(CW.accent.copy(alpha = 0.75f), Color.Transparent), center = Offset(size.width * 0.95f, size.height * 0.05f), radius = size.width * 0.8f),
                radius = size.width * 0.8f, center = Offset(size.width * 0.95f, size.height * 0.05f),
            )
            drawCircle(
                Brush.radialGradient(listOf(Color(0xFFE4F6FF).copy(alpha = 0.8f), Color.Transparent), center = Offset(0f, size.height * 0.75f), radius = size.width * 0.7f),
                radius = size.width * 0.7f, center = Offset(0f, size.height * 0.75f),
            )
        }
        content()
    }
}

/** Press-to-shrink feedback used on every tappable surface. */
@Composable
fun Modifier.pressable(
    enabled: Boolean = true,
    haptic: Boolean = true,
    pressedScale: Float = 0.96f,
    role: Role = Role.Button,
    onClick: () -> Unit,
): Modifier {
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    val s by animateFloatAsState(if (pressed) pressedScale else 1f, spring(dampingRatio = 0.6f, stiffness = 600f), label = "press")
    val feedback = LocalHapticFeedback.current
    return this
        .scale(s)
        .clickable(interactionSource = source, indication = null, enabled = enabled, role = role) {
            if (haptic) feedback.performHapticFeedback(HapticFeedbackType.TextHandleMove)
            onClick()
        }
}

@Composable
fun PrimaryButton(
    title: String,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    enabled: Boolean = true,
    loading: Boolean = false,
    onClick: () -> Unit,
) {
    Box(
        modifier
            .fillMaxWidth()
            .heightIn(min = 54.dp)
            .shadow(if (enabled) 14.dp else 0.dp, RoundedCornerShape(50), ambientColor = CW.primary, spotColor = CW.primary)
            .clip(RoundedCornerShape(50))
            .background(if (enabled) CW.brandGradient else Brush.linearGradient(listOf(CW.border, CW.border)))
            .pressable(enabled = enabled && !loading, onClick = onClick)
            .padding(horizontal = 20.dp, vertical = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        if (loading) {
            CircularProgressIndicator(Modifier.size(22.dp), color = Color.White, strokeWidth = 2.5.dp)
        } else {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
                if (icon != null) {
                    Icon(icon, null, tint = Color.White, modifier = Modifier.size(20.dp))
                    Spacer(Modifier.width(8.dp))
                }
                Text(title, color = if (enabled) Color.White else CW.muted, fontSize = 16.sp, fontWeight = FontWeight.Bold)
            }
        }
    }
}

@Composable
fun SecondaryButton(title: String, modifier: Modifier = Modifier, icon: ImageVector? = null, tint: Color = CW.primaryInk, onClick: () -> Unit) {
    Row(
        modifier
            .heightIn(min = 48.dp)
            .clip(RoundedCornerShape(50))
            .background(CW.surface2)
            .pressable(onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        if (icon != null) {
            Icon(icon, null, tint = tint, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
        }
        Text(title, color = tint, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
    }
}

/** White rounded card with a hairline border (settings groups, dex rooms). */
@Composable
fun SectionCard(modifier: Modifier = Modifier, padding: Dp = 16.dp, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier
            .fillMaxWidth()
            .shadow(6.dp, RoundedCornerShape(24.dp), ambientColor = Color(0x14000000), spotColor = Color(0x14000000))
            .clip(RoundedCornerShape(24.dp))
            .background(CW.card)
            .border(1.dp, CW.border, RoundedCornerShape(24.dp))
            .padding(padding),
        content = content,
    )
}

@Composable
fun ScreenHeader(title: String, subtitle: String? = null, modifier: Modifier = Modifier) {
    Column(modifier) {
        Text(title, fontSize = 30.sp, fontWeight = FontWeight.Black, color = CW.foreground, letterSpacing = (-0.5).sp)
        if (subtitle != null) Text(subtitle, fontSize = 14.sp, color = CW.muted)
    }
}

/** A sticker's picture from its signed link; the category emoji while it loads or when there is none. */
@Composable
fun StickerImage(sticker: Sticker, modifier: Modifier = Modifier, contentScale: ContentScale = ContentScale.Fit, emojiSize: Int = 34) {
    val signed by AppGraph.dex.state.collectAsState()
    val url = sticker.heroPath?.let { signed.signed[it] }
    Box(modifier, contentAlignment = Alignment.Center) {
        if (url == null) {
            Text(Category.emoji(sticker.categoryKey), fontSize = emojiSize.sp)
        } else {
            AsyncImage(model = url, contentDescription = sticker.word?.headword, contentScale = contentScale, modifier = Modifier.fillMaxSize())
        }
    }
}

/** Memory % pill (srs.ts levels). */
@Composable
fun MemoryBadge(percent: Int, modifier: Modifier = Modifier) {
    val c = CW.memoryLevels[ReviewState.level(percent)]
    Row(
        modifier
            .shadow(3.dp, CircleShape)
            .clip(CircleShape)
            .background(CW.card.copy(alpha = 0.95f))
            .padding(horizontal = 7.dp, vertical = 3.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(6.dp).clip(CircleShape).background(c))
        Spacer(Modifier.width(4.dp))
        Text("$percent%", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = CW.foreground.copy(alpha = 0.8f))
    }
}

/** The dark pill that shows a one-line notice over the screen. */
@Composable
fun Toast(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        color = Color.White,
        fontSize = 14.sp,
        fontWeight = FontWeight.SemiBold,
        modifier = modifier
            .shadow(10.dp, RoundedCornerShape(50))
            .clip(RoundedCornerShape(50))
            .background(CW.toastInk.copy(alpha = 0.92f))
            .padding(horizontal = 18.dp, vertical = 12.dp),
    )
}

/** Reading line under a headword: zhuyin by default, pinyin when chosen in settings. */
fun readingOf(zhuyin: String?, pinyin: String?): String {
    val z = zhuyin?.trim().orEmpty()
    val p = pinyin?.trim().orEmpty()
    return if (AppGraph.readingStyle == "pinyin") p.ifEmpty { z } else z.ifEmpty { p }
}

@Composable
fun Chip(text: String, modifier: Modifier = Modifier, selected: Boolean = false, onClick: (() -> Unit)? = null) {
    Text(
        text,
        fontSize = 14.sp,
        fontWeight = FontWeight.SemiBold,
        color = if (selected) Color.White else CW.foreground,
        modifier = modifier
            .clip(RoundedCornerShape(50))
            .background(if (selected) CW.primary else CW.surface2)
            .then(if (onClick != null) Modifier.pressable(onClick = onClick) else Modifier)
            .padding(horizontal = 14.dp, vertical = 8.dp),
    )
}
