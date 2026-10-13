package com.rork.catchwordsandroid.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.NoPhotography
import androidx.compose.material.icons.outlined.Policy
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.rork.catchwordsandroid.data.tr
import com.rork.catchwordsandroid.ui.components.AppBackground
import com.rork.catchwordsandroid.ui.components.PrimaryButton
import com.rork.catchwordsandroid.ui.theme.CW

/** The camera tab without the AI consent: the camera stays off, with the way to read the consent again and agree. */
@Composable
fun AiConsentGateScreen(onAgree: () -> Unit, modifier: Modifier = Modifier) {
    var showConsent by remember { mutableStateOf(false) }
    AppBackground(modifier) {
        Box(Modifier.fillMaxSize().padding(horizontal = 32.dp).padding(bottom = 90.dp), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Icon(Icons.Outlined.NoPhotography, null, tint = CW.primary, modifier = Modifier.size(48.dp))
                Text(tr("AIの機能は止まっています", "AI features are off", "AI 功能已停用"), fontSize = 22.sp, fontWeight = FontWeight.ExtraBold, color = CW.foreground, textAlign = TextAlign.Center)
                Text(
                    tr(
                        "カメラで撮った写真や写真アプリから選んだ画像は、単語を見つけるために外部のAIサービスに送られます。AIへのデータ送信に同意すると、カメラと単語の解説が使えます。",
                        "Photos you take or pick are sent to external AI services to find words. Agree to sending data to AI to use the camera and word explanations.",
                        "拍攝或選擇的照片會傳送給外部 AI 服務以找出單字。同意傳送資料給 AI 後，即可使用相機與單字解說。",
                    ),
                    fontSize = 15.sp, color = CW.muted, textAlign = TextAlign.Center,
                )
                PrimaryButton(tr("内容を確認して同意する", "Review and agree", "確認內容並同意"), icon = Icons.Outlined.Policy) { showConsent = true }
                Text(tr("集めた単語を見ることや復習は、同意しなくても使えます。", "You can view and review your words without agreeing.", "即使不同意，也能瀏覽與複習已收集的單字。"), fontSize = 13.sp, color = CW.muted, textAlign = TextAlign.Center)
            }
        }
    }
    if (showConsent) {
        Dialog(onDismissRequest = { showConsent = false }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            AiConsentScreen(onDecided = { agreed ->
                showConsent = false
                if (agreed) onAgree()
            })
        }
    }
}
