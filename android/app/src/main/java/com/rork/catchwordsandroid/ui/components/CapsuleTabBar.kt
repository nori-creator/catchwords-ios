package com.rork.catchwordsandroid.ui.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.CameraAlt
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.MenuBook
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.catchwordsandroid.data.tr
import com.rork.catchwordsandroid.ui.theme.CW

enum class AppTab(val route: String, val icon: ImageVector) {
    HOME("home", Icons.Outlined.Home),
    DEX("dex", Icons.Outlined.MenuBook),
    CAMERA("camera", Icons.Outlined.CameraAlt),
    REVIEW("review", Icons.Outlined.AutoAwesome),
    SETTINGS("settings", Icons.Outlined.Settings);

    val title: String
        get() = when (this) {
            HOME -> tr("ホーム", "Home", "首頁")
            DEX -> tr("図鑑", "Dex", "圖鑑")
            CAMERA -> tr("カメラ", "Camera", "相機")
            REVIEW -> tr("復習", "Review", "複習")
            SETTINGS -> tr("設定", "Settings", "設定")
        }
}

/** The floating capsule tab bar of the iOS app; dark glass over the camera. */
@Composable
fun CapsuleTabBar(selected: AppTab?, dark: Boolean, onSelect: (AppTab) -> Unit, modifier: Modifier = Modifier) {
    val bg = if (dark) Color(0xE6131E37) else Color(0xF2FFFFFF)
    val border = if (dark) Color(0x33FFFFFF) else CW.border
    Row(
        modifier
            .padding(horizontal = 16.dp)
            .fillMaxWidth()
            .height(62.dp)
            .shadow(18.dp, RoundedCornerShape(50), ambientColor = Color(0x22000000), spotColor = Color(0x33000000))
            .clip(RoundedCornerShape(50))
            .background(bg)
            .border(1.dp, border, RoundedCornerShape(50))
            .padding(horizontal = 6.dp, vertical = 5.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        AppTab.entries.forEach { tab ->
            val isOn = tab == selected
            val pill by animateColorAsState(
                when {
                    isOn && dark -> Color(0x330083FF)
                    isOn -> CW.accent
                    else -> Color.Transparent
                },
                label = "pill",
            )
            val ink = when {
                isOn -> if (dark) CW.cyan else CW.primary
                tab == AppTab.CAMERA -> if (dark) CW.cyan else CW.primary
                dark -> Color(0xCCFFFFFF)
                else -> CW.foreground
            }
            Box(
                Modifier
                    .weight(1f)
                    .height(52.dp)
                    .clip(RoundedCornerShape(50))
                    .background(pill)
                    .pressable(role = Role.Tab) { onSelect(tab) }
                    .semantics { contentDescription = tab.title },
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(tab.icon, null, tint = ink, modifier = Modifier.size(23.dp))
                    Text(tab.title, fontSize = 10.sp, fontWeight = if (isOn) FontWeight.Bold else FontWeight.Medium, color = ink, maxLines = 1)
                }
            }
        }
    }
}
