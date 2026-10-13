package com.rork.catchwordsandroid.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rork.catchwordsandroid.data.AppGraph
import com.rork.catchwordsandroid.data.DexState
import com.rork.catchwordsandroid.data.Profile
import com.rork.catchwordsandroid.data.Sticker
import com.rork.catchwordsandroid.data.userMessage
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** Dex layouts (図鑑): rooms grid, or the plain list. */
enum class DexLayout { GRID, LIST }

/** Home, dex and word page state: the shared dex plus this screen's own choices. */
class DexViewModel : ViewModel() {
    private val dex = AppGraph.dex
    val state: StateFlow<DexState> = dex.state
    val profile: StateFlow<Profile> = AppGraph.profile.profile

    private val _layout = MutableStateFlow(DexLayout.GRID)
    val layout: StateFlow<DexLayout> = _layout.asStateFlow()

    private val _query = MutableStateFlow("")
    val query: StateFlow<String> = _query.asStateFlow()

    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

    private val _refreshing = MutableStateFlow(false)
    val refreshing: StateFlow<Boolean> = _refreshing.asStateFlow()

    fun setLayout(l: DexLayout) { _layout.value = l }
    fun setQuery(q: String) { _query.value = q }
    fun clearMessage() { _message.value = null }

    fun refresh() {
        viewModelScope.launch {
            _refreshing.value = true
            dex.load()
            _refreshing.value = false
        }
    }

    fun loadExplanation(sticker: Sticker) {
        val wordId = sticker.word?.id ?: return
        viewModelScope.launch { dex.loadExplanation(wordId, AppGraph.consent.isGranted) }
    }

    fun speak(text: String) = AppGraph.speech.speak(text, AppGraph.profile.target)

    fun saveCaption(sticker: Sticker, caption: String) {
        viewModelScope.launch {
            runCatching { dex.updateCaption(sticker, caption) }.onFailure { _message.value = it.userMessage }
        }
    }

    fun delete(sticker: Sticker, onDone: () -> Unit) {
        viewModelScope.launch {
            runCatching { dex.delete(sticker) }
                .onSuccess { onDone() }
                .onFailure { _message.value = it.userMessage }
        }
    }
}
