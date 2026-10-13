package com.rork.catchwordsandroid.ui.screens

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.material.icons.automirrored.outlined.ArrowForward
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.catchwordsandroid.R
import com.rork.catchwordsandroid.data.L10n
import com.rork.catchwordsandroid.data.ProfileRepository
import com.rork.catchwordsandroid.data.tr
import com.rork.catchwordsandroid.ui.SessionViewModel
import com.rork.catchwordsandroid.ui.components.AppBackground
import com.rork.catchwordsandroid.ui.components.PrimaryButton
import com.rork.catchwordsandroid.ui.components.pressable
import com.rork.catchwordsandroid.ui.theme.CW

/** First-run setup: display language, then the goal level (learning language: Traditional Chinese, Taiwan). */
@Composable
fun OnboardingScreen(session: SessionViewModel) {
    var step by rememberSaveable { mutableIntStateOf(0) }
    var ui by rememberSaveable { mutableStateOf(L10n.current) }
    var goal by rememberSaveable { mutableStateOf("TOCFL-2") }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    AppBackground {
        Column(
            Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(horizontal = 24.dp),
        ) {
            Spacer(Modifier.height(16.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                repeat(2) { i ->
                    Box(Modifier.weight(1f).height(5.dp).clip(CircleShape).background(if (i <= step) CW.primary else CW.border))
                }
            }
            AnimatedContent(
                targetState = step,
                transitionSpec = { slideInHorizontally { it } togetherWith slideOutHorizontally { -it } },
                modifier = Modifier.weight(1f),
                label = "step",
            ) { s ->
                Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                    Spacer(Modifier.height(24.dp))
                    PhotoStrip(if (s == 0) R.drawable.first_catch_cafe else R.drawable.first_catch_flower)
                    Spacer(Modifier.height(20.dp))
                    if (s == 0) {
                        Text("Language / 言語 / 語言", fontSize = 28.sp, fontWeight = FontWeight.Black, color = CW.foreground)
                        Text(
                            tr("アプリを表示する言語を選んでください。学ぶのは台湾の繁體字（華語）です。", "Choose the app's language. You'll learn Taiwanese Mandarin (Traditional characters).", "請選擇 App 的顯示語言。學習內容為台灣華語（繁體字）。"),
                            color = CW.muted, fontSize = 15.sp, modifier = Modifier.padding(top = 6.dp, bottom = 18.dp),
                        )
                        ProfileRepository.nativeOptions.forEach { (code, label) ->
                            OptionRow(label, ui == code) { ui = code }
                        }
                    } else {
                        Text(tr("目標のレベル", "Your goal", "目標程度"), fontSize = 28.sp, fontWeight = FontWeight.Black, color = CW.foreground)
                        Text(
                            tr("例文はこのレベルに合わせて作られます。あとから設定で変えられます。", "Example sentences are written for this level. You can change it later in Settings.", "例句會依照這個程度產生，之後可以在設定中變更。"),
                            color = CW.muted, fontSize = 15.sp, modifier = Modifier.padding(top = 6.dp, bottom = 18.dp),
                        )
                        ProfileRepository.levelOptions.forEach { (code, label) ->
                            OptionRow(label, goal == code) { goal = code }
                        }
                    }
                    Spacer(Modifier.height(16.dp))
                }
            }
            error?.let { Text(it, color = CW.destructive, fontSize = 14.sp, modifier = Modifier.padding(bottom = 8.dp)) }
            PrimaryButton(
                title = if (step == 0) tr("次へ", "Next", "下一步") else tr("はじめる", "Get started", "開始"),
                icon = if (step == 0) Icons.AutoMirrored.Outlined.ArrowForward else Icons.Outlined.Check,
                loading = saving,
            ) {
                if (step == 0) {
                    step = 1
                } else {
                    saving = true
                    error = null
                    session.finishOnboarding(ui, goal) { msg -> saving = false; error = msg }
                }
            }
            Spacer(Modifier.height(16.dp))
        }
    }
}

@Composable
private fun PhotoStrip(res: Int) {
    Box(Modifier.fillMaxWidth().height(170.dp), contentAlignment = Alignment.Center) {
        Image(
            painterResource(res), null, contentScale = ContentScale.Crop,
            modifier = Modifier
                .size(240.dp, 160.dp)
                .rotate(-3f)
                .shadow(14.dp, RoundedCornerShape(18.dp))
                .clip(RoundedCornerShape(18.dp))
                .border(6.dp, Color.White, RoundedCornerShape(18.dp)),
        )
    }
}

@Composable
private fun OptionRow(label: String, selected: Boolean, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(vertical = 5.dp)
            .clip(RoundedCornerShape(18.dp))
            .background(if (selected) CW.accent else CW.card)
            .border(if (selected) 2.dp else 1.dp, if (selected) CW.primary else CW.border, RoundedCornerShape(18.dp))
            .pressable(onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = CW.foreground, modifier = Modifier.weight(1f))
        if (selected) {
            Box(Modifier.size(26.dp).clip(CircleShape).background(CW.primary), contentAlignment = Alignment.Center) {
                Icon(Icons.Outlined.Check, null, tint = Color.White, modifier = Modifier.size(16.dp))
            }
        } else {
            Spacer(Modifier.width(26.dp))
        }
    }
}
