package com.rork.catchwordsandroid.ui.screens

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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material.icons.outlined.PanTool
import androidx.compose.material.icons.outlined.PhotoLibrary
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.catchwordsandroid.data.AppConfig
import com.rork.catchwordsandroid.data.tr
import com.rork.catchwordsandroid.ui.components.AppBackground
import com.rork.catchwordsandroid.ui.components.PrimaryButton
import com.rork.catchwordsandroid.ui.components.pressable
import com.rork.catchwordsandroid.ui.theme.CW

/** The AI consent: what is sent, to whom, why, and what happens without it — same text as the iOS app. */
@Composable
fun AiConsentScreen(onDecided: (Boolean) -> Unit, modifier: Modifier = Modifier) {
    AppBackground(modifier) {
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
            Column(
                Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 22.dp, vertical = 24.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Box(Modifier.size(56.dp).clip(RoundedCornerShape(16.dp)).background(CW.brandGradient), contentAlignment = Alignment.Center) {
                    Icon(Icons.Outlined.AutoAwesome, null, tint = Color.White, modifier = Modifier.size(28.dp))
                }
                Text(tr("AIへのデータ送信について", "About sending data to AI", "關於將資料傳送給 AI"), fontSize = 26.sp, fontWeight = FontWeight.ExtraBold, color = CW.foreground)
                Text(
                    tr(
                        "CatchWords は、写真から単語を見つけたり、単語の解説や例文を作ったりするために、外部のAIサービスを使います。使い始める前に、送る内容を確かめて、同意するかを選んでください。",
                        "CatchWords uses external AI services to find words in your photos and to write explanations and example sentences. Before you start, check what is sent and choose whether you agree.",
                        "CatchWords 會使用外部 AI 服務，從照片中找出單字，並產生單字解說與例句。開始使用前，請確認傳送的內容並選擇是否同意。",
                    ),
                    color = CW.muted, fontSize = 15.sp,
                )
                Point(Icons.Outlined.PhotoLibrary, tr("送るもの", "What is sent", "傳送的內容"), tr(
                    "撮った写真、写真アプリから選んだ画像、入力した単語、学ぶ言語やレベルなどの設定。メールアドレスや名前は送りません。",
                    "Photos you take, images you pick from your gallery, words you type, and settings such as your learning language and level. Your email address and name are never sent.",
                    "拍攝的照片、從相簿選擇的圖片、輸入的單字，以及學習語言、程度等設定。不會傳送電子郵件地址或姓名。",
                ))
                Point(Icons.Outlined.Public, tr("送り先", "Where it goes", "傳送對象"), tr(
                    "当社のサーバを通して、外部のAIサービス（Google など）に送ります。送り先の会社と国は、プライバシーポリシーに書いてあります。",
                    "Through our server to external AI services (such as Google). The companies and countries are listed in the Privacy Policy.",
                    "透過本公司的伺服器傳送給外部 AI 服務（例如 Google）。對象公司與國家記載於隱私權政策。",
                ))
                Point(Icons.Outlined.Lightbulb, tr("使い道", "How it is used", "用途"), tr(
                    "写っている物や入力した単語の判定、単語の解説と例文の作成のためだけに使います。当社が写真や入力した文章を AI の学習に使うことはありません。",
                    "Only to recognize what's in the photo or the word you typed, and to write explanations and examples. We never use your photos or text to train AI.",
                    "僅用於辨識照片中的物品或輸入的單字，以及產生解說與例句。本公司不會將您的照片或文字用於 AI 訓練。",
                ))
                Point(Icons.Outlined.PanTool, tr("同意しない場合", "If you don't agree", "若不同意"), tr(
                    "カメラ、写真アプリの画像、単語の入力、単語の解説と例文の作成など、AI を使う機能は使えません（何も送りません）。集めた単語を見ることや復習は、そのまま使えます。あとから「設定」で同意することも、取り消すこともできます。",
                    "AI features (camera, gallery images, typing a word, explanations and examples) stay off and nothing is sent. You can still view your words and review them. You can agree or withdraw later in Settings.",
                    "相機、相簿圖片、輸入單字、解說與例句等 AI 功能將無法使用（不會傳送任何資料）。仍可瀏覽已收集的單字並複習。之後可在「設定」中同意或撤回。",
                ))
                Row(horizontalArrangement = Arrangement.Center, modifier = Modifier.fillMaxWidth()) {
                    LegalLink(tr("プライバシーポリシー", "Privacy Policy", "隱私權政策"), AppConfig.PRIVACY_URL)
                    LegalLink(tr("利用規約", "Terms", "使用條款"), AppConfig.TERMS_URL)
                }
            }
            Column(Modifier.background(CW.background.copy(alpha = 0.95f)).padding(horizontal = 22.dp, vertical = 10.dp)) {
                PrimaryButton(tr("同意して始める", "Agree and start", "同意並開始"), icon = Icons.Outlined.Check) { onDecided(true) }
                Box(
                    Modifier.fillMaxWidth().heightIn(min = 48.dp).pressable { onDecided(false) },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(tr("同意しない", "Don't agree", "不同意"), color = CW.primaryInk, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

@Composable
private fun Point(icon: ImageVector, title: String, text: String) {
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(20.dp))
            .background(CW.card)
            .border(1.dp, CW.border, RoundedCornerShape(20.dp))
            .padding(16.dp),
    ) {
        Box(Modifier.size(40.dp).clip(RoundedCornerShape(12.dp)).background(CW.accent), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = CW.primary, modifier = Modifier.size(20.dp))
        }
        Spacer(Modifier.width(14.dp))
        Column {
            Text(title, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = CW.foreground)
            Spacer(Modifier.height(4.dp))
            Text(text, fontSize = 14.sp, color = CW.foreground, lineHeight = 21.sp)
        }
    }
}
