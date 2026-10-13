package com.rork.catchwordsandroid.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.rork.catchwordsandroid.R

/** Design tokens ported from the iOS app's Theme (the web app's `styles.css`, light "paper & sky"). */
object CW {
    val background = Color(0xFFF9FCFF)
    val backgroundDeep = Color(0xFFEEF3F9)
    val card = Color(0xFFFFFFFF)
    val surface2 = Color(0xFFEDF2F8)
    val accent = Color(0xFFD8EEFF)
    val primary = Color(0xFF0083FF)
    val primaryInk = Color(0xFF0053D4)
    val primaryBright = Color(0xFF2A9BFF)
    val primaryDeep = Color(0xFF0060E0)
    val foreground = Color(0xFF0B121A)
    val muted = Color(0xFF5C646F)
    val border = Color(0xFFE0E5EB)
    val gold = Color(0xFFF4B93C)
    val cyan = Color(0xFF64E0FF)
    val destructive = Color(0xFFE62B34)
    val ok = Color(0xFF00A95C)
    val toastInk = Color(0xFF0B121A)

    val navyDeep = Color(0xFF060D1C)
    val navyCard = Color(0xFF131E37)
    val navyTop = Color(0xFF0B1A33)

    /** Paper album (home). */
    val paper = Color(0xFFFCF6EC)
    val paperEdge = Color(0xFFF3E7D3)
    val wood = Color(0xFF6B4226)
    val woodLight = Color(0xFFB97A45)

    val memoryLevels = listOf(
        Color(0xFFF9262A), Color(0xFFF87300), Color(0xFFE5A500),
        Color(0xFF46BC24), Color(0xFF00B777), Color(0xFF0083FF),
    )

    val brandGradient: Brush get() = Brush.linearGradient(listOf(primaryBright, primaryDeep))

    val hand = FontFamily(Font(R.font.zen_kurenaido))
    val caveat = FontFamily(Font(R.font.caveat))
}

private val colors = lightColorScheme(
    primary = CW.primary,
    onPrimary = Color.White,
    secondary = CW.primaryInk,
    background = CW.background,
    onBackground = CW.foreground,
    surface = CW.card,
    onSurface = CW.foreground,
    surfaceVariant = CW.surface2,
    onSurfaceVariant = CW.muted,
    outline = CW.border,
    error = CW.destructive,
)

private val typography = Typography(
    headlineLarge = TextStyle(fontSize = 30.sp, fontWeight = FontWeight.Black, letterSpacing = (-0.5).sp),
    headlineMedium = TextStyle(fontSize = 24.sp, fontWeight = FontWeight.ExtraBold),
    titleLarge = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.Bold),
    titleMedium = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Bold),
    bodyLarge = TextStyle(fontSize = 16.sp, lineHeight = 24.sp),
    bodyMedium = TextStyle(fontSize = 14.sp, lineHeight = 21.sp),
    labelLarge = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.Bold),
    labelSmall = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.SemiBold),
)

@Composable
fun AppTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = colors, typography = typography, content = content)
}
