package com.rork.catchwordsandroid.ui.screens

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
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
import androidx.compose.foundation.layout.imePadding
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
import androidx.compose.material.icons.outlined.AddPhotoAlternate
import androidx.compose.material.icons.outlined.CameraAlt
import androidx.compose.material.icons.outlined.Cameraswitch
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.VideocamOff
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.rork.catchwordsandroid.data.ImageTools
import com.rork.catchwordsandroid.data.tr
import com.rork.catchwordsandroid.ui.CaptureMode
import com.rork.catchwordsandroid.ui.CaptureStage
import com.rork.catchwordsandroid.ui.CaptureViewModel
import com.rork.catchwordsandroid.ui.components.Toast
import com.rork.catchwordsandroid.ui.components.pressable
import com.rork.catchwordsandroid.ui.theme.CW
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** カメラ: the deep-navy "machine" — shoot, pick from the gallery, or type a word — then pick a name and catch it. */
@Composable
fun CaptureScreen(onOpenWord: (String) -> Unit, vm: CaptureViewModel = viewModel()) {
    val ui by vm.ui.collectAsStateWithLifecycle()

    LaunchedEffect(ui.toast) {
        if (ui.toast != null) {
            delay(3500)
            vm.clearToast()
        }
    }

    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(CW.navyTop, CW.navyDeep)))) {
        AnimatedContent(
            targetState = ui.stage,
            contentKey = { it::class },
            transitionSpec = { fadeIn() togetherWith fadeOut() },
            label = "stage",
        ) { stage ->
            when (stage) {
                CaptureStage.Camera -> CameraStage(ui.mode, vm)
                is CaptureStage.Analyzing -> AnalyzingStage(stage)
                is CaptureStage.Picking -> PickingStage(stage, onPick = { vm.pick(stage.photo, it, stage.candidates) }, onBack = vm::reset)
                is CaptureStage.Card -> CardStage(stage, onSave = vm::save, onBack = vm::backToPicking, onRetake = vm::reset)
                is CaptureStage.Caught -> CaughtStage(stage, onOpen = { onOpenWord(stage.sticker.id); vm.reset() }, onAgain = vm::reset)
            }
        }
        AnimatedVisibility(ui.toast != null, enter = fadeIn(), exit = fadeOut(), modifier = Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(top = 56.dp, start = 24.dp, end = 24.dp)) {
            Toast(ui.toast.orEmpty())
        }
    }
}

@Composable
private fun CameraStage(mode: CaptureMode, vm: CaptureViewModel) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val handle = remember { CameraHandle() }
    var granted by remember { mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) }
    var asked by rememberSaveable { mutableStateOf(false) }
    var available by remember { mutableStateOf(true) }
    var lens by rememberSaveable { mutableIntStateOf(CameraSelector.LENS_FACING_BACK) }
    var zoom by remember { mutableFloatStateOf(1f) }
    var busy by remember { mutableStateOf(false) }

    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok -> granted = ok; asked = true }
    val gallery = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scope.launch { ImageTools.decode(context, uri)?.let(vm::analyze) }
    }

    LaunchedEffect(Unit) { if (!granted && !asked) permission.launch(Manifest.permission.CAMERA) }

    Column(Modifier.fillMaxSize().statusBarsPadding().imePadding().padding(bottom = 84.dp)) {
        Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp)) {
            Text("CatchWords", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold, modifier = Modifier.align(Alignment.Center))
        }
        Box(
            Modifier
                .weight(1f)
                .fillMaxWidth()
                .padding(horizontal = 12.dp)
                .clip(RoundedCornerShape(30.dp))
                .background(Color.Black),
        ) {
            when {
                mode == CaptureMode.SEARCH -> SearchPanel(onSearch = vm::search)
                !granted -> CameraPlaceholder(
                    title = tr("カメラへのアクセスが許可されていません", "Camera access is off", "未允許使用相機"),
                    body = tr("設定でカメラを許可すると、撮った物の名前を学べます。写真から選ぶこともできます。", "Allow the camera in Settings to learn the names of what you shoot. You can also pick a photo.", "在設定中允許相機後，就能學習拍攝物品的名稱。也可以從相簿選擇照片。"),
                    action = tr("設定を開く", "Open Settings", "開啟設定"),
                ) {
                    context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null)))
                }
                !available -> CameraPlaceholder(
                    title = tr("カメラが見つかりません", "No camera found", "找不到相機"),
                    body = tr("「写真」から画像を選んで、単語を見つけられます。", "Pick an image with “Photos” to find words.", "可以從「照片」選擇圖片來找單字。"),
                    action = null,
                ) {}
                else -> {
                    CameraViewfinder(handle, lens, onAvailability = { available = it }, modifier = Modifier.fillMaxSize())
                    FinderCorners(Modifier.fillMaxSize().padding(26.dp))
                    ZoomChips(zoom, Modifier.align(Alignment.BottomCenter).padding(bottom = 14.dp)) { z -> zoom = z; handle.setZoom(z) }
                }
            }
        }
        Spacer(Modifier.height(14.dp))
        ModeSwitch(mode, vm::setMode)
        Spacer(Modifier.height(12.dp))
        Row(Modifier.fillMaxWidth().padding(horizontal = 34.dp), verticalAlignment = Alignment.CenterVertically) {
            SideButton(Icons.Outlined.AddPhotoAlternate, tr("写真", "Photos", "照片")) {
                gallery.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
            }
            Spacer(Modifier.weight(1f))
            Shutter(enabled = mode == CaptureMode.PHOTO && granted && available && !busy) {
                busy = true
                scope.launch {
                    val bmp = handle.takePhoto()
                    busy = false
                    if (bmp != null) vm.analyze(bmp)
                }
            }
            Spacer(Modifier.weight(1f))
            SideButton(Icons.Outlined.Cameraswitch, tr("切替", "Flip", "切換")) {
                lens = if (lens == CameraSelector.LENS_FACING_BACK) CameraSelector.LENS_FACING_FRONT else CameraSelector.LENS_FACING_BACK
                zoom = 1f
            }
        }
    }
}

@Composable
private fun FinderCorners(modifier: Modifier = Modifier) {
    Canvas(modifier) {
        val l = 30.dp.toPx()
        val w = 3.dp.toPx()
        val c = Color.White.copy(alpha = 0.85f)
        listOf(
            Offset(0f, 0f) to Pair(Offset(l, 0f), Offset(0f, l)),
            Offset(size.width, 0f) to Pair(Offset(size.width - l, 0f), Offset(size.width, l)),
            Offset(0f, size.height) to Pair(Offset(l, size.height), Offset(0f, size.height - l)),
            Offset(size.width, size.height) to Pair(Offset(size.width - l, size.height), Offset(size.width, size.height - l)),
        ).forEach { (corner, ends) ->
            drawLine(c, corner, ends.first, w, StrokeCap.Round)
            drawLine(c, corner, ends.second, w, StrokeCap.Round)
        }
    }
}

@Composable
private fun ZoomChips(current: Float, modifier: Modifier = Modifier, onZoom: (Float) -> Unit) {
    Row(
        modifier.clip(RoundedCornerShape(50)).background(Color(0x99131E37)).border(1.dp, Color(0x22FFFFFF), RoundedCornerShape(50)).padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        listOf(1f, 2f, 3f, 5f).forEach { z ->
            val on = current == z
            Box(
                Modifier.size(42.dp, 34.dp).clip(RoundedCornerShape(50)).background(if (on) Color(0x33FFFFFF) else Color.Transparent).pressable { onZoom(z) },
                contentAlignment = Alignment.Center,
            ) { Text("${z.toInt()}×", color = if (on) CW.gold else Color.White, fontSize = 13.sp, fontWeight = FontWeight.Bold) }
        }
    }
}

@Composable
private fun ModeSwitch(mode: CaptureMode, onChange: (CaptureMode) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 40.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        listOf(CaptureMode.SEARCH to tr("検索", "Search", "搜尋"), CaptureMode.PHOTO to tr("撮影", "Photo", "拍攝")).forEach { (m, label) ->
            val on = m == mode
            Box(
                Modifier
                    .weight(1f)
                    .height(46.dp)
                    .clip(RoundedCornerShape(50))
                    .background(if (on) Brush.verticalGradient(listOf(Color(0xFF1E6FD9), Color(0xFF0E4FB0))) else SolidColor(Color.Transparent))
                    .then(if (on) Modifier.border(1.dp, Color(0x55FFFFFF), RoundedCornerShape(50)) else Modifier)
                    .pressable { onChange(m) },
                contentAlignment = Alignment.Center,
            ) { Text(label, color = if (on) Color.White else Color(0xB3FFFFFF), fontSize = 16.sp, fontWeight = if (on) FontWeight.Bold else FontWeight.Medium) }
        }
    }
}

@Composable
private fun Shutter(enabled: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .size(88.dp)
            .shadow(if (enabled) 22.dp else 0.dp, CircleShape, spotColor = CW.primary, ambientColor = CW.primary)
            .clip(CircleShape)
            .background(Color.White)
            .padding(5.dp)
            .clip(CircleShape)
            .background(if (enabled) CW.brandGradient else SolidColor(Color(0xFF3A4660)))
            .pressable(enabled = enabled, pressedScale = 0.9f, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { Icon(Icons.Outlined.CameraAlt, tr("撮影", "Shoot", "拍攝"), tint = Color.White, modifier = Modifier.size(32.dp)) }
}

@Composable
private fun SideButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, onClick: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.pressable(onClick = onClick)) {
        Box(
            Modifier.size(52.dp).clip(RoundedCornerShape(16.dp)).background(Color(0x1FFFFFFF)).border(1.dp, Color(0x22FFFFFF), RoundedCornerShape(16.dp)),
            contentAlignment = Alignment.Center,
        ) { Icon(icon, null, tint = Color.White, modifier = Modifier.size(26.dp)) }
        Spacer(Modifier.height(4.dp))
        Text(label, color = Color.White, fontSize = 12.sp)
    }
}

@Composable
private fun CameraPlaceholder(title: String, body: String, action: String?, onAction: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(28.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(Icons.Outlined.VideocamOff, null, tint = CW.cyan, modifier = Modifier.size(44.dp))
        Spacer(Modifier.height(14.dp))
        Text(title, color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
        Spacer(Modifier.height(8.dp))
        Text(body, color = Color(0xB3FFFFFF), fontSize = 14.sp, textAlign = TextAlign.Center)
        if (action != null) {
            Spacer(Modifier.height(18.dp))
            Text(
                action, color = Color.White, fontWeight = FontWeight.Bold,
                modifier = Modifier.clip(RoundedCornerShape(50)).background(CW.primary).pressable(onClick = onAction).padding(horizontal = 20.dp, vertical = 12.dp),
            )
        }
    }
}

@Composable
private fun SearchPanel(onSearch: (String) -> Unit) {
    var text by rememberSaveable { mutableStateOf("") }
    Column(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(CW.navyCard, CW.navyDeep))).padding(24.dp), verticalArrangement = Arrangement.Center) {
        Text(tr("言葉で探す", "Look up a word", "用文字搜尋"), color = Color.White, fontSize = 24.sp, fontWeight = FontWeight.ExtraBold)
        Spacer(Modifier.height(6.dp))
        Text(
            tr("日本語・英語・中国語のどれで入力しても、台湾華語の言い方が見つかります。", "Type in Japanese, English or Chinese to find the Taiwanese Mandarin word.", "用日文、英文或中文輸入，都能找到台灣華語的說法。"),
            color = Color(0xB3FFFFFF), fontSize = 14.sp,
        )
        Spacer(Modifier.height(18.dp))
        Row(
            Modifier.fillMaxWidth().height(56.dp).clip(RoundedCornerShape(18.dp)).background(Color(0x1FFFFFFF)).border(1.dp, Color(0x33FFFFFF), RoundedCornerShape(18.dp)).padding(start = 16.dp, end = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.weight(1f)) {
                if (text.isEmpty()) Text(tr("例: マンゴー", "e.g. mango", "例：芒果"), color = Color(0x80FFFFFF), fontSize = 17.sp)
                BasicTextField(
                    text, { text = it.take(60) }, singleLine = true,
                    textStyle = TextStyle(color = Color.White, fontSize = 17.sp),
                    cursorBrush = SolidColor(CW.cyan),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                    keyboardActions = KeyboardActions(onSearch = { onSearch(text) }),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            Box(Modifier.size(44.dp).clip(CircleShape).background(CW.primary).pressable(enabled = text.isNotBlank()) { onSearch(text) }, contentAlignment = Alignment.Center) {
                Icon(Icons.Outlined.Search, tr("検索", "Search", "搜尋"), tint = Color.White)
            }
        }
    }
}

@Composable
private fun AnalyzingStage(stage: CaptureStage.Analyzing) {
    val t = androidx.compose.animation.core.rememberInfiniteTransition(label = "scan")
    val sweep by t.animateFloat(0f, 1f, androidx.compose.animation.core.infiniteRepeatable(androidx.compose.animation.core.tween(1400), androidx.compose.animation.core.RepeatMode.Reverse), label = "sweep")
    val spin by t.animateFloat(0f, 360f, androidx.compose.animation.core.infiniteRepeatable(androidx.compose.animation.core.tween(1100, easing = androidx.compose.animation.core.LinearEasing)), label = "spin")
    Column(Modifier.fillMaxSize().statusBarsPadding().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.height(30.dp))
        Box(Modifier.fillMaxWidth().weight(1f).clip(RoundedCornerShape(30.dp)).background(Color.Black)) {
            stage.photo?.let { Image(it.asImageBitmap(), null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize()) }
                ?: Text(stage.query.orEmpty(), color = Color.White, fontSize = 40.sp, fontWeight = FontWeight.Black, modifier = Modifier.align(Alignment.Center))
            Canvas(Modifier.fillMaxSize()) {
                val y = size.height * sweep
                drawRect(Brush.verticalGradient(listOf(Color.Transparent, CW.cyan.copy(alpha = 0.35f), Color.Transparent), startY = y - 120f, endY = y + 120f))
                drawLine(CW.cyan, Offset(0f, y), Offset(size.width, y), 3f)
            }
        }
        Spacer(Modifier.height(24.dp))
        Canvas(Modifier.size(40.dp)) {
            drawArc(CW.cyan, spin, 270f, false, style = Stroke(5f, cap = StrokeCap.Round))
        }
        Spacer(Modifier.height(10.dp))
        Text(tr("言葉を探しています…", "Finding words…", "正在尋找單字…"), color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(110.dp))
    }
}
