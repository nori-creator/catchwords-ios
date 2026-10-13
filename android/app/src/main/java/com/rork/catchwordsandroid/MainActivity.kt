package com.rork.catchwordsandroid

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import android.graphics.Color
import androidx.lifecycle.lifecycleScope
import com.rork.catchwordsandroid.data.L10n
import com.rork.catchwordsandroid.ui.DeepLinks
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch
import com.rork.catchwordsandroid.ui.navigation.AppNavigation
import com.rork.catchwordsandroid.ui.theme.AppTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT),
        )
        handle(intent)
        com.rork.catchwordsandroid.data.Reminders.recordAppOpen()
        // A new display language: the activity is redrawn so every screen reads its strings again.
        lifecycleScope.launch {
            L10n.lang.drop(1).distinctUntilChanged().collect { recreate() }
        }
        setContent {
            AppTheme {
                AppNavigation()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    private fun handle(intent: Intent?) {
        val data = intent?.data ?: return
        if (data.scheme != "catchwords") return
        when (data.host) {
            "review" -> DeepLinks.route.value = "review"
            "word" -> data.lastPathSegment?.let { DeepLinks.route.value = "word/$it" }
            else -> DeepLinks.incoming.value = data
        }
    }
}
