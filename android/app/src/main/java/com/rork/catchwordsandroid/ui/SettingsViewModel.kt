package com.rork.catchwordsandroid.ui

import android.content.Context
import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rork.catchwordsandroid.data.AppGraph
import com.rork.catchwordsandroid.data.ConsentStatus
import com.rork.catchwordsandroid.data.ImageTools
import com.rork.catchwordsandroid.data.L10n
import com.rork.catchwordsandroid.data.Profile
import com.rork.catchwordsandroid.data.ProfileRepository
import com.rork.catchwordsandroid.data.tr
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class SettingsUiState(
    val readingStyle: String = AppGraph.readingStyle,
    val soundsOn: Boolean = AppGraph.soundsOn,
    val savingAvatar: Boolean = false,
    val notice: String? = null,
)

/** 設定: profile columns (same as the web settings), reading style, sounds and the AI consent. */
class SettingsViewModel : ViewModel() {
    private val repo = AppGraph.profile
    val profile: StateFlow<Profile> = repo.profile
    val consent: StateFlow<ConsentStatus> = AppGraph.consent.status
    val email: String? get() = AppGraph.client.session.value?.email

    private val _ui = MutableStateFlow(SettingsUiState())
    val ui: StateFlow<SettingsUiState> = _ui.asStateFlow()

    fun clearNotice() = _ui.update { it.copy(notice = null) }

    private fun saved(ok: Boolean) = _ui.update {
        it.copy(notice = if (ok) tr("保存しました", "Saved", "已儲存") else tr("保存できませんでした。通信を確かめてください。", "Couldn't save. Check your connection.", "無法儲存，請確認網路連線。"))
    }

    fun setDisplayName(name: String) {
        val v = name.trim().take(40)
        if (v == profile.value.displayName) return
        repo.setLocal { it.copy(displayName = v) }
        viewModelScope.launch { saved(repo.update(mapOf("display_name" to v))) }
    }

    fun setUiLanguage(code: String) {
        val l1 = ProfileRepository.readerL1(profile.value.nativeLanguage, profile.value.targetLanguage)
        viewModelScope.launch {
            val ok = repo.update(mapOf("native_language" to l1, "ui_language" to code))
            repo.setLocal { it.copy(nativeLanguage = l1) }
            if (ok) L10n.set(code) else saved(false)
            AppGraph.dex.load()
        }
    }

    fun setCurrentLevel(v: String) {
        repo.setLocal { it.copy(currentLevel = v) }
        viewModelScope.launch { saved(repo.update(mapOf("current_level" to v))) }
    }

    fun setGoal(v: String) {
        repo.setLocal { it.copy(levelGoal = v) }
        viewModelScope.launch { saved(repo.update(mapOf("level_goal" to v))) }
    }

    fun setDailyLimit(n: Int) {
        repo.setLocal { it.copy(reviewDailyLimit = n) }
        viewModelScope.launch { saved(repo.update(mapOf("review_daily_limit" to n))) }
    }

    fun setReadingStyle(v: String) {
        AppGraph.readingStyle = v
        _ui.update { it.copy(readingStyle = v) }
    }

    fun setSounds(on: Boolean) {
        AppGraph.soundsOn = on
        _ui.update { it.copy(soundsOn = on) }
    }

    fun setConsent(agree: Boolean) {
        viewModelScope.launch { if (agree) AppGraph.consent.grant() else AppGraph.consent.decline() }
    }

    fun uploadAvatar(context: Context, uri: Uri) {
        _ui.update { it.copy(savingAvatar = true) }
        viewModelScope.launch {
            val bmp = ImageTools.decode(context, uri, 1024)
            val ok = bmp != null && repo.uploadAvatar(ImageTools.jpeg(bmp, 512, 85))
            _ui.update { it.copy(savingAvatar = false) }
            saved(ok)
        }
    }

    fun clearAvatar() {
        viewModelScope.launch { repo.clearAvatar() }
    }
}
