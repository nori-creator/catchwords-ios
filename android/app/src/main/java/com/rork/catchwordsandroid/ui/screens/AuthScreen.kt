package com.rork.catchwordsandroid.ui.screens

import android.content.Intent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Email
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rork.catchwordsandroid.R
import com.rork.catchwordsandroid.data.AppConfig
import com.rork.catchwordsandroid.data.tr
import com.rork.catchwordsandroid.ui.SessionViewModel
import com.rork.catchwordsandroid.ui.components.AppBackground
import com.rork.catchwordsandroid.ui.components.PrimaryButton
import com.rork.catchwordsandroid.ui.components.pressable
import com.rork.catchwordsandroid.ui.theme.CW

/** Sign in / create an account (email + password, or Google through the web bridge), same accounts as iOS and the web. */
@Composable
fun AuthScreen(session: SessionViewModel) {
    val state by session.auth.collectAsStateWithLifecycle()
    val expired by session.expiredNotice.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var isSignUp by rememberSaveable { mutableStateOf(false) }
    var email by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }

    AppBackground {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .statusBarsPadding()
                .navigationBarsPadding()
                .imePadding()
                .padding(horizontal = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.height(24.dp))
            StickerHero()
            Spacer(Modifier.height(10.dp))
            Text("CatchWords", fontSize = 34.sp, fontWeight = FontWeight.Black, color = CW.foreground, letterSpacing = (-0.8).sp)
            Text(
                tr("見つけたものが、単語になる。", "Everything you see becomes a word.", "看見的東西，都會變成單字。"),
                fontFamily = CW.hand, fontSize = 18.sp, color = CW.muted, textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(26.dp))

            if (expired) {
                Notice(tr("ログインの有効期限が切れました。もう一度ログインしてください。", "Your sign-in expired. Please sign in again.", "登入已過期，請重新登入。"), CW.muted)
            }

            Column(
                Modifier
                    .fillMaxWidth()
                    .shadow(10.dp, RoundedCornerShape(28.dp), ambientColor = Color(0x1A0060E0), spotColor = Color(0x1A0060E0))
                    .clip(RoundedCornerShape(28.dp))
                    .background(CW.card)
                    .border(1.dp, CW.border, RoundedCornerShape(28.dp))
                    .padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                ModeToggle(isSignUp) { isSignUp = it; session.clearMessages() }
                Field(email, { email = it }, tr("メールアドレス", "Email", "電子郵件"), Icons.Outlined.Email, KeyboardType.Email, ImeAction.Next)
                Field(password, { password = it }, tr("パスワード（6文字以上）", "Password (6+ characters)", "密碼（6 個字元以上）"), Icons.Outlined.Lock, KeyboardType.Password, ImeAction.Done, secret = true)
                AnimatedVisibility(state.error != null) { Notice(state.error.orEmpty(), CW.destructive) }
                AnimatedVisibility(state.info != null) { Notice(state.info.orEmpty(), CW.ok) }
                PrimaryButton(
                    title = if (isSignUp) tr("アカウントを作成", "Create account", "建立帳號") else tr("ログイン", "Sign in", "登入"),
                    enabled = email.contains("@") && password.length >= 6,
                    loading = state.isWorking,
                ) {
                    if (isSignUp) session.signUp(email, password) else session.signIn(email, password)
                }
                if (!isSignUp) {
                    Text(
                        tr("パスワードを忘れた場合", "Forgot your password?", "忘記密碼？"),
                        color = CW.primaryInk, fontSize = 14.sp, fontWeight = FontWeight.SemiBold,
                        modifier = Modifier
                            .align(Alignment.CenterHorizontally)
                            .pressable(enabled = email.contains("@")) { session.resetPassword(email) }
                            .padding(8.dp),
                    )
                }
            }

            Spacer(Modifier.height(16.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.weight(1f).height(1.dp).background(CW.border))
                Text(tr("または", "or", "或"), color = CW.muted, fontSize = 13.sp, modifier = Modifier.padding(horizontal = 12.dp))
                Box(Modifier.weight(1f).height(1.dp).background(CW.border))
            }
            Spacer(Modifier.height(16.dp))
            Row(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 54.dp)
                    .clip(RoundedCornerShape(50))
                    .background(CW.card)
                    .border(1.dp, CW.border, RoundedCornerShape(50))
                    .pressable { context.startActivity(Intent(Intent.ACTION_VIEW, session.googleUrl())) }
                    .padding(14.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("G", fontSize = 20.sp, fontWeight = FontWeight.Black, color = Color(0xFF4285F4))
                Spacer(Modifier.width(10.dp))
                Text(tr("Googleで続ける", "Continue with Google", "使用 Google 繼續"), fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = CW.foreground)
            }

            Spacer(Modifier.height(20.dp))
            Row(horizontalArrangement = Arrangement.Center, modifier = Modifier.fillMaxWidth()) {
                LegalLink(tr("利用規約", "Terms", "使用條款"), AppConfig.TERMS_URL)
                Text("・", color = CW.muted, fontSize = 12.sp)
                LegalLink(tr("プライバシーポリシー", "Privacy Policy", "隱私權政策"), AppConfig.PRIVACY_URL)
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
private fun StickerHero() {
    val t = rememberInfiniteTransition(label = "float")
    val bob by t.animateFloat(-6f, 6f, infiniteRepeatable(tween(2200), RepeatMode.Reverse), label = "bob")
    Box(Modifier.size(220.dp, 170.dp), contentAlignment = Alignment.Center) {
        Image(painterResource(R.drawable.welcome_sticker_coffee), null, Modifier.size(78.dp).align(Alignment.TopStart).graphicsLayer { translationY = bob }.rotate(-12f))
        Image(painterResource(R.drawable.welcome_sticker_croissant), null, Modifier.size(70.dp).align(Alignment.BottomStart).graphicsLayer { translationY = -bob }.rotate(10f))
        Image(painterResource(R.drawable.welcome_sticker_plant), null, Modifier.size(80.dp).align(Alignment.TopEnd).graphicsLayer { translationY = -bob * 0.7f }.rotate(8f))
        Image(painterResource(R.drawable.welcome_logo), null, Modifier.size(110.dp).graphicsLayer { translationY = bob * 0.4f })
    }
}

@Composable
private fun ModeToggle(isSignUp: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(50)).background(CW.surface2).padding(4.dp),
    ) {
        listOf(false to tr("ログイン", "Sign in", "登入"), true to tr("新規登録", "Sign up", "註冊")).forEach { (value, label) ->
            val on = value == isSignUp
            Box(
                Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(50))
                    .background(if (on) CW.card else Color.Transparent)
                    .pressable { onChange(value) }
                    .padding(vertical = 10.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(label, fontWeight = if (on) FontWeight.Bold else FontWeight.Medium, color = if (on) CW.foreground else CW.muted, fontSize = 15.sp)
            }
        }
    }
}

@Composable
private fun Field(
    value: String,
    onChange: (String) -> Unit,
    label: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    type: KeyboardType,
    ime: ImeAction,
    secret: Boolean = false,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        placeholder = { Text(label, color = CW.muted) },
        leadingIcon = { Icon(icon, null, tint = CW.muted) },
        singleLine = true,
        visualTransformation = if (secret) PasswordVisualTransformation() else androidx.compose.ui.text.input.VisualTransformation.None,
        keyboardOptions = KeyboardOptions(keyboardType = type, imeAction = ime),
        shape = RoundedCornerShape(16.dp),
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = CW.primary,
            unfocusedBorderColor = CW.border,
            focusedContainerColor = CW.background,
            unfocusedContainerColor = CW.background,
        ),
        modifier = Modifier.fillMaxWidth(),
    )
}

@Composable
private fun Notice(text: String, color: Color) {
    Text(
        text, color = color, fontSize = 14.sp,
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(color.copy(alpha = 0.08f)).padding(12.dp),
    )
}

@Composable
fun LegalLink(title: String, url: String) {
    val context = LocalContext.current
    Text(
        title, color = CW.primaryInk, fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
        modifier = Modifier
            .pressable { context.startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url))) }
            .padding(6.dp),
    )
}
