package com.rork.catchwordsandroid.ui

import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rork.catchwordsandroid.data.AppConfig
import com.rork.catchwordsandroid.data.AppGraph
import com.rork.catchwordsandroid.data.ConsentStatus
import com.rork.catchwordsandroid.data.L10n
import com.rork.catchwordsandroid.data.ProfileRepository
import com.rork.catchwordsandroid.data.tr
import com.rork.catchwordsandroid.data.userMessage
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.UUID

/** Which part of the app the user is in. */
sealed interface SessionPhase {
    data object Loading : SessionPhase
    data object SignedOut : SessionPhase
    data object Onboarding : SessionPhase
    data object Consent : SessionPhase
    data object Ready : SessionPhase
}

data class AuthUiState(
    val isWorking: Boolean = false,
    val error: String? = null,
    val info: String? = null,
)

/** Signs in / out (email or Google via the web bridge), reads the profile and the AI consent, and routes the app. */
class SessionViewModel : ViewModel() {
    private val client = AppGraph.client
    private val profileRepo = AppGraph.profile
    private val consent = AppGraph.consent

    private val _auth = MutableStateFlow(AuthUiState())
    val auth: StateFlow<AuthUiState> = _auth.asStateFlow()

    private val _bootstrapped = MutableStateFlow(false)

    val phase: StateFlow<SessionPhase> = combine(
        client.session, profileRepo.profile, consent.status, _bootstrapped,
    ) { session, profile, status, booted ->
        when {
            session == null -> SessionPhase.SignedOut
            !booted || !profile.isLoaded -> SessionPhase.Loading
            !profile.onboarded && !profile.loadFailed -> SessionPhase.Onboarding
            status == ConsentStatus.UNDECIDED -> SessionPhase.Consent
            else -> SessionPhase.Ready
        }
    }.stateIn(viewModelScope, SharingStarted.Eagerly, SessionPhase.Loading)

    val expiredNotice: StateFlow<Boolean> = client.expired

    private var pendingState: String? = null

    init {
        viewModelScope.launch {
            client.session.collect { s ->
                if (s == null) {
                    _bootstrapped.value = false
                    return@collect
                }
                if (_bootstrapped.value) return@collect
                bootstrap()
            }
        }
        viewModelScope.launch {
            DeepLinks.incoming.collect { uri -> uri?.let { handleCallback(it); DeepLinks.incoming.value = null } }
        }
    }

    private suspend fun bootstrap() {
        consent.load(client.userId)
        profileRepo.load()
        _bootstrapped.value = true
        viewModelScope.launch { consent.sync() }
        viewModelScope.launch { AppGraph.dex.load() }
    }

    fun clearMessages() = _auth.update { it.copy(error = null, info = null) }

    fun signIn(email: String, password: String) = perform {
        client.signIn(email.trim(), password)
        client.expired.value = false
    }

    fun signUp(email: String, password: String) = perform {
        val signedIn = client.signUp(email.trim(), password)
        if (!signedIn) {
            _auth.update {
                it.copy(info = tr("確認メールを送りました。メールのリンクを開いてからログインしてください。", "We sent a confirmation email. Open its link, then sign in.", "已寄出確認信，請開啟信中的連結後再登入。"))
            }
        }
    }

    fun resetPassword(email: String) = perform {
        client.sendPasswordReset(email.trim())
        _auth.update { it.copy(info = tr("パスワード再設定のメールを送りました。", "We sent a password reset email.", "已寄出重設密碼的信件。")) }
    }

    /** Opens the web bridge for Google; the session comes back on catchwords://auth-callback. */
    fun googleUrl(): Uri {
        val state = UUID.randomUUID().toString()
        pendingState = state
        return Uri.parse("${AppConfig.WEB_BASE_URL}/native-auth").buildUpon()
            .appendQueryParameter("provider", "google")
            .appendQueryParameter("state", state)
            .build()
    }

    private fun handleCallback(uri: Uri) {
        if (uri.scheme != AppConfig.AUTH_CALLBACK_SCHEME || uri.host != AppConfig.AUTH_CALLBACK_HOST) return
        val fragment = uri.fragment ?: uri.query ?: return
        val map = fragment.split("&").mapNotNull { part ->
            val i = part.indexOf('=')
            if (i <= 0) null else part.substring(0, i) to Uri.decode(part.substring(i + 1))
        }.toMap()
        val access = map["access_token"].orEmpty()
        val refresh = map["refresh_token"].orEmpty()
        val state = map["state"].orEmpty()
        if (access.isEmpty() || refresh.isEmpty()) {
            _auth.update { it.copy(error = tr("Googleでのログインに失敗しました。", "Google sign-in failed.", "Google 登入失敗。")) }
            return
        }
        if (pendingState != null && state != pendingState) return
        pendingState = null
        val expiresAt = map["expires_at"]?.toDoubleOrNull()?.let { (it * 1000).toLong() }
            ?: map["expires_in"]?.toDoubleOrNull()?.let { System.currentTimeMillis() + (it * 1000).toLong() }
        runCatching { client.adoptSession(access, refresh, expiresAt) }
            .onSuccess { client.expired.value = false }
            .onFailure { e -> _auth.update { it.copy(error = e.userMessage) } }
    }

    private fun perform(block: suspend () -> Unit) {
        if (_auth.value.isWorking) return
        _auth.value = AuthUiState(isWorking = true)
        viewModelScope.launch {
            try {
                block()
                _auth.update { it.copy(isWorking = false) }
            } catch (e: Exception) {
                _auth.value = AuthUiState(error = e.userMessage)
            }
        }
    }

    /** First-run setup: languages and goal, then `onboarded`. */
    fun finishOnboarding(uiLanguage: String, levelGoal: String, onError: (String) -> Unit) {
        viewModelScope.launch {
            val target = "zh-TW"
            L10n.set(uiLanguage)
            val l1 = ProfileRepository.readerL1(profileRepo.profile.value.nativeLanguage, target)
            val ok1 = profileRepo.update(mapOf("native_language" to l1, "target_language" to target, "ui_language" to uiLanguage))
            val ok2 = ok1 && profileRepo.update(mapOf("level_goal" to levelGoal, "onboarded" to true))
            if (!ok2) {
                onError(tr("保存できませんでした。通信を確かめてください。", "Couldn't save. Check your connection.", "無法儲存，請確認網路連線。"))
                return@launch
            }
            profileRepo.setLocal { it.copy(nativeLanguage = l1, targetLanguage = target, levelGoal = levelGoal, onboarded = true) }
            AppGraph.dex.load()
        }
    }

    fun decideConsent(agreed: Boolean) {
        viewModelScope.launch { if (agreed) consent.grant() else consent.decline() }
    }

    fun signOut() {
        viewModelScope.launch {
            client.signOutRevoking()
            resetLocal()
        }
    }

    private fun resetLocal() {
        consent.reset()
        profileRepo.reset()
        AppGraph.dex.reset()
    }

    fun deleteAccount(onDone: (String?) -> Unit) {
        viewModelScope.launch {
            try {
                profileRepo.deleteAccount(AppGraph.api)
                client.signOut()
                resetLocal()
                onDone(null)
            } catch (e: Exception) {
                onDone(e.userMessage)
            }
        }
    }
}

/** The auth callback handed to the activity (catchwords://auth-callback#…). */
object DeepLinks {
    val incoming = MutableStateFlow<Uri?>(null)

    /** In-app places from notifications and the widget: "review", or "word/<stickerId>". */
    val route = MutableStateFlow<String?>(null)
}
