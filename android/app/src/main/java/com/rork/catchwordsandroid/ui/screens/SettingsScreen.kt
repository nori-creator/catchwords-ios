package com.rork.catchwordsandroid.ui.screens

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.OpenInNew
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import coil3.compose.AsyncImage
import com.rork.catchwordsandroid.data.AppConfig
import com.rork.catchwordsandroid.data.ConsentStatus
import com.rork.catchwordsandroid.data.L10n
import com.rork.catchwordsandroid.data.ProfileRepository
import com.rork.catchwordsandroid.data.tr
import com.rork.catchwordsandroid.ui.SessionViewModel
import com.rork.catchwordsandroid.ui.SettingsViewModel
import com.rork.catchwordsandroid.ui.components.AppBackground
import com.rork.catchwordsandroid.ui.components.SecondaryButton
import com.rork.catchwordsandroid.ui.components.Toast
import com.rork.catchwordsandroid.ui.components.pressable
import com.rork.catchwordsandroid.ui.theme.CW
import kotlinx.coroutines.delay

/** 設定: profile, languages and levels, review, sounds, AI consent, legal pages and the account. */
@Composable
fun SettingsScreen(session: SessionViewModel, vm: SettingsViewModel = viewModel()) {
    val profile by vm.profile.collectAsStateWithLifecycle()
    val consent by vm.consent.collectAsStateWithLifecycle()
    val ui by vm.ui.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val focus = LocalFocusManager.current
    var name by remember(profile.displayName) { mutableStateOf(profile.displayName) }
    var askSignOut by remember { mutableStateOf(false) }
    var askDelete by remember { mutableStateOf(false) }
    var showConsent by remember { mutableStateOf(false) }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri -> uri?.let { vm.uploadAvatar(context, it) } }

    LaunchedEffect(ui.notice) {
        if (ui.notice != null) {
            delay(2200)
            vm.clearNotice()
        }
    }

    AppBackground {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).statusBarsPadding().padding(horizontal = 16.dp).padding(top = 8.dp, bottom = 110.dp)) {
            Text(tr("設定", "Settings", "設定"), fontSize = 30.sp, fontWeight = FontWeight.Black, color = CW.foreground)

            Group(tr("プロフィール", "Profile", "個人資料")) {
                Label(tr("プロフィール写真", "Profile photo", "大頭貼"))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        Modifier.size(64.dp).shadow(6.dp, CircleShape).clip(CircleShape).background(CW.surface2).border(2.dp, Color.White, CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        when {
                            ui.savingAvatar -> CircularProgressIndicator(Modifier.size(24.dp), color = CW.primary, strokeWidth = 2.dp)
                            profile.avatarUrl != null -> AsyncImage(profile.avatarUrl, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                            else -> Icon(Icons.Outlined.Person, null, tint = CW.muted, modifier = Modifier.size(30.dp))
                        }
                    }
                    Spacer(Modifier.width(14.dp))
                    SecondaryButton(tr("選ぶ", "Choose", "選擇"), tint = CW.foreground) { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
                    if (profile.avatarUrl != null) {
                        Spacer(Modifier.width(8.dp))
                        SecondaryButton(tr("外す", "Remove", "移除"), tint = CW.destructive, onClick = vm::clearAvatar)
                    }
                }
                Spacer(Modifier.height(14.dp))
                Label(tr("表示名", "Display name", "顯示名稱"))
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it.take(40) },
                    placeholder = { Text(tr("名前", "Name", "名稱"), color = CW.muted) },
                    singleLine = true,
                    shape = RoundedCornerShape(16.dp),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { vm.setDisplayName(name); focus.clearFocus() }),
                    colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = CW.primary, unfocusedBorderColor = CW.border, unfocusedContainerColor = CW.card, focusedContainerColor = CW.card),
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            Group(tr("言語", "Language", "語言")) {
                Picker(tr("表示言語", "Display language", "顯示語言"), L10n.current, ProfileRepository.nativeOptions, vm::setUiLanguage)
                StaticRow(tr("学習言語", "Learning", "學習語言"), ProfileRepository.targetLabel(profile.targetLanguage))
                Picker(tr("今のレベル", "Current level", "目前程度"), profile.currentLevel, ProfileRepository.levels(profile.targetLanguage), vm::setCurrentLevel)
                Picker(tr("目標レベル", "Goal level", "目標程度"), profile.levelGoal, ProfileRepository.levels(profile.targetLanguage), vm::setGoal)
                Picker(
                    tr("発音表記", "Reading", "發音標示"), ui.readingStyle,
                    listOf("zhuyin" to tr("注音（ㄅㄆㄇ）", "Zhuyin (ㄅㄆㄇ)", "注音（ㄅㄆㄇ）"), "pinyin" to tr("ピンイン", "Pinyin", "拼音")),
                    vm::setReadingStyle,
                )
            }

            Group(tr("復習", "Review", "複習")) {
                Picker(
                    tr("1日に復習する数", "Reviews per day", "每天複習數量"), profile.reviewDailyLimit.toString(),
                    listOf(10, 20, 30, 50, 100, 0).map { it.toString() to if (it == 0) tr("無制限", "Unlimited", "無限制") else tr("${it}問", "$it", "${it} 題") },
                ) { vm.setDailyLimit(it.toInt()) }
                ToggleRow(tr("効果音", "Sound effects", "音效"), ui.soundsOn, vm::setSounds)
            }

            Group(tr("AI", "AI", "AI")) {
                ToggleRow(
                    tr("AIへのデータ送信に同意する", "Allow sending data to AI", "同意傳送資料給 AI"),
                    consent == ConsentStatus.GRANTED,
                ) { on -> if (on) showConsent = true else vm.setConsent(false) }
                Text(
                    tr("オフにすると、カメラや単語の解説など AI を使う機能が止まります。", "When off, AI features such as the camera and explanations stop.", "關閉後，相機與單字解說等 AI 功能將停止。"),
                    fontSize = 12.sp, color = CW.muted,
                )
            }

            Group(tr("情報", "About", "資訊")) {
                LinkRow(tr("お問い合わせ・サポート", "Contact & support", "聯絡與支援"), AppConfig.SUPPORT_URL)
                LinkRow(tr("利用規約", "Terms of Use", "使用條款"), AppConfig.TERMS_URL)
                LinkRow(tr("プライバシーポリシー", "Privacy Policy", "隱私權政策"), AppConfig.PRIVACY_URL)
                LinkRow(tr("特定商取引法に基づく表記", "Legal notice (Japan)", "特定商業交易法標示"), AppConfig.TOKUSHOHO_URL)
                StaticRow(tr("バージョン", "Version", "版本"), runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }.getOrNull() ?: "1.0.0")
            }

            Group(tr("アカウント", "Account", "帳號")) {
                vm.email?.let { StaticRow(tr("メール", "Email", "電子郵件"), it) }
                ActionRow(tr("ログアウト", "Sign out", "登出"), CW.primaryInk) { askSignOut = true }
                ActionRow(tr("アカウントを削除", "Delete account", "刪除帳號"), CW.destructive) { askDelete = true }
            }
        }
        ui.notice?.let { Toast(it, Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(top = 12.dp)) }
    }

    if (askSignOut) {
        AlertDialog(
            onDismissRequest = { askSignOut = false },
            title = { Text(tr("ログアウトしますか？", "Sign out?", "要登出嗎？")) },
            confirmButton = { TextButton(onClick = { askSignOut = false; session.signOut() }) { Text(tr("ログアウト", "Sign out", "登出")) } },
            dismissButton = { TextButton(onClick = { askSignOut = false }) { Text(tr("キャンセル", "Cancel", "取消")) } },
        )
    }
    if (askDelete) DeleteAccountDialog(session) { askDelete = false }
    if (showConsent) {
        androidx.compose.ui.window.Dialog(
            onDismissRequest = { showConsent = false },
            properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false),
        ) {
            AiConsentScreen(onDecided = { agreed -> showConsent = false; vm.setConsent(agreed) })
        }
    }
}

@Composable
private fun DeleteAccountDialog(session: SessionViewModel, onDismiss: () -> Unit) {
    var typed by remember { mutableStateOf("") }
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val keyword = tr("削除", "DELETE", "刪除")
    AlertDialog(
        onDismissRequest = { if (!working) onDismiss() },
        title = { Text(tr("アカウントを削除", "Delete account", "刪除帳號")) },
        text = {
            Column {
                Text(
                    tr(
                        "集めた単語、写真、復習の記録、ログイン情報がすべて削除され、元に戻せません。続けるには「削除」と入力してください。",
                        "All your words, photos, review history and your sign-in are deleted and can't be restored. Type DELETE to continue.",
                        "所有收集的單字、照片、複習紀錄與登入資訊都會被刪除，且無法復原。請輸入「刪除」以繼續。",
                    ),
                )
                Spacer(Modifier.height(12.dp))
                OutlinedTextField(typed, { typed = it }, singleLine = true, placeholder = { Text(keyword) })
                error?.let { Text(it, color = CW.destructive, fontSize = 13.sp, modifier = Modifier.padding(top = 6.dp)) }
            }
        },
        confirmButton = {
            TextButton(
                enabled = typed.trim().equals(keyword, ignoreCase = true) && !working,
                onClick = {
                    working = true
                    error = null
                    session.deleteAccount { msg ->
                        working = false
                        if (msg == null) onDismiss() else error = msg
                    }
                },
            ) { Text(if (working) tr("削除しています…", "Deleting…", "刪除中…") else tr("削除する", "Delete", "刪除"), color = CW.destructive) }
        },
        dismissButton = { TextButton(enabled = !working, onClick = onDismiss) { Text(tr("キャンセル", "Cancel", "取消")) } },
    )
}

@Composable
private fun Group(title: String, content: @Composable () -> Unit) {
    Text(title, fontSize = 13.sp, color = CW.muted, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(start = 6.dp, top = 22.dp, bottom = 8.dp))
    Column(
        Modifier
            .fillMaxWidth()
            .shadow(6.dp, RoundedCornerShape(24.dp), ambientColor = Color(0x10000000), spotColor = Color(0x10000000))
            .clip(RoundedCornerShape(24.dp))
            .background(CW.card)
            .border(1.dp, CW.border, RoundedCornerShape(24.dp))
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) { content() }
}

@Composable
private fun Label(text: String) {
    Text(text, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = CW.foreground, modifier = Modifier.padding(bottom = 6.dp))
}

@Composable
private fun Picker(label: String, value: String, options: List<Pair<String, String>>, onPick: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Column {
        Label(label)
        Box {
            Row(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 54.dp)
                    .clip(RoundedCornerShape(18.dp))
                    .background(Brush.horizontalGradient(listOf(Color(0xFFF7FBFF), CW.surface2)))
                    .border(1.dp, Color(0xFFCFE6FA), RoundedCornerShape(18.dp))
                    .pressable(pressedScale = 0.98f) { open = true }
                    .padding(horizontal = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(options.firstOrNull { it.first == value }?.second ?: value, fontSize = 16.sp, color = CW.foreground, modifier = Modifier.weight(1f))
                Icon(Icons.Outlined.ExpandMore, null, tint = CW.muted)
            }
            DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                options.forEach { (code, text) ->
                    DropdownMenuItem(text = { Text(text, fontWeight = if (code == value) FontWeight.Bold else FontWeight.Normal) }, onClick = { open = false; if (code != value) onPick(code) })
                }
            }
        }
    }
}

@Composable
private fun StaticRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth().heightIn(min = 40.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = CW.foreground, modifier = Modifier.weight(1f))
        Text(value, fontSize = 15.sp, color = CW.muted)
    }
}

@Composable
private fun ToggleRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 44.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = CW.foreground, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange, colors = SwitchDefaults.colors(checkedTrackColor = CW.primary))
    }
}

@Composable
private fun LinkRow(label: String, url: String) {
    val context = LocalContext.current
    Row(
        Modifier.fillMaxWidth().heightIn(min = 44.dp).pressable(pressedScale = 0.98f) { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, fontSize = 16.sp, color = CW.foreground, modifier = Modifier.weight(1f))
        Icon(Icons.AutoMirrored.Outlined.OpenInNew, null, tint = CW.muted, modifier = Modifier.size(18.dp))
    }
}

@Composable
private fun ActionRow(label: String, color: Color, onClick: () -> Unit) {
    Box(Modifier.fillMaxWidth().heightIn(min = 48.dp).clip(RoundedCornerShape(14.dp)).background(color.copy(alpha = 0.07f)).pressable(onClick = onClick), contentAlignment = Alignment.Center) {
        Text(label, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = color)
    }
}
