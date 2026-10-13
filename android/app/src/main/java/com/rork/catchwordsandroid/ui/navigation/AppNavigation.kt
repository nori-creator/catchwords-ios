package com.rork.catchwordsandroid.ui.navigation

import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.rork.catchwordsandroid.ui.SessionPhase
import com.rork.catchwordsandroid.ui.SessionViewModel
import com.rork.catchwordsandroid.ui.components.AppBackground
import com.rork.catchwordsandroid.ui.screens.AiConsentScreen
import com.rork.catchwordsandroid.ui.screens.AuthScreen
import com.rork.catchwordsandroid.ui.screens.MainScreen
import com.rork.catchwordsandroid.ui.screens.OnboardingScreen
import com.rork.catchwordsandroid.ui.theme.CW

private object Root {
    const val LOADING = "loading"
    const val AUTH = "auth"
    const val ONBOARDING = "onboarding"
    const val CONSENT = "consent"
    const val MAIN = "main"
}

/** Root navigation: sign-in → first-run setup → AI consent → the tabbed app, driven by the session phase. */
@Composable
fun AppNavigation(session: SessionViewModel = viewModel()) {
    val phase by session.phase.collectAsStateWithLifecycle()
    val nav = rememberNavController()

    val target = when (phase) {
        SessionPhase.Loading -> Root.LOADING
        SessionPhase.SignedOut -> Root.AUTH
        SessionPhase.Onboarding -> Root.ONBOARDING
        SessionPhase.Consent -> Root.CONSENT
        SessionPhase.Ready -> Root.MAIN
    }

    LaunchedEffect(target) {
        if (nav.currentDestination?.route != target) {
            nav.navigate(target) {
                popUpTo(nav.graph.id) { inclusive = true }
                launchSingleTop = true
            }
        }
    }

        NavHost(
            navController = nav,
            startDestination = Root.LOADING,
            enterTransition = { fadeIn() },
            exitTransition = { fadeOut() },
        ) {
            composable(Root.LOADING) {
                AppBackground {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = CW.primary) }
                }
            }
            composable(Root.AUTH) { AuthScreen(session) }
            composable(Root.ONBOARDING) { OnboardingScreen(session) }
            composable(Root.CONSENT) { AiConsentScreen(onDecided = { session.decideConsent(it) }) }
            composable(Root.MAIN) { MainScreen(session) }
        }
}
