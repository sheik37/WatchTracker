package com.example.myapplication

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.TextButton
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.LiveTv
import androidx.compose.material.icons.rounded.Movie
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.VideoLibrary
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi
import androidx.compose.material3.adaptive.layout.ListDetailPaneScaffold
import androidx.compose.material3.adaptive.layout.ListDetailPaneScaffoldRole
import androidx.compose.material3.adaptive.navigation.rememberListDetailPaneScaffoldNavigator
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavDestination.Companion.hasRoute
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.example.myapplication.data.AuthSessionStore
import com.example.myapplication.data.model.WatchCategory
import com.example.myapplication.data.repository.MediaRepository
import com.example.myapplication.ui.navigation.Destination
import com.example.myapplication.ui.screens.AuthScreen
import com.example.myapplication.ui.screens.DetailsScreen
import com.example.myapplication.ui.screens.DetailsViewModel
import com.example.myapplication.ui.screens.MediaViewModel
import com.example.myapplication.ui.screens.ProfileScreen
import com.example.myapplication.ui.screens.SearchScreen
import com.example.myapplication.ui.screens.WatchlistScreen
import com.example.myapplication.ui.screens.WatchlistViewModel
import com.example.myapplication.ui.theme.MyApplicationTheme
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import retrofit2.HttpException
import org.json.JSONException
import org.json.JSONObject

private const val RESEND_VERIFICATION_COOLDOWN_SECONDS = 60
private const val FORGOT_PASSWORD_COOLDOWN_SECONDS = 60
private const val ADMIN_2FA_EMAIL = "admin@watchtracker.net"
private const val GITHUB_LATEST_RELEASE_URL = "https://api.github.com/repos/sheik37/WatchTracker/releases/latest"

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val container = (application as WatchTrackerApp).container

        setContent {
            MyApplicationTheme {
                RootScreen(
                    activity = this@MainActivity,
                    repository = container.repository,
                    authSessionStore = container.authSessionStore
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3AdaptiveApi::class)
@Composable
fun RootScreen(
    activity: ComponentActivity,
    repository: MediaRepository,
    authSessionStore: AuthSessionStore
) {
    val scope = rememberCoroutineScope()
    val savedToken by authSessionStore.tokenFlow.collectAsState(initial = null)
    val savedRefreshToken by authSessionStore.refreshTokenFlow.collectAsState(initial = null)
    val tokenExpiresAtMillis by authSessionStore.tokenExpiresAtMillisFlow.collectAsState(initial = null)
    val savedAccountEmail by authSessionStore.accountEmailFlow.collectAsState(initial = null)
    val savedDisplayName by authSessionStore.displayNameFlow.collectAsState(initial = null)
    val savedUserId by authSessionStore.userIdFlow.collectAsState(initial = null)
    val profileSyncedAtMillis by authSessionStore.profileSyncedAtMillisFlow.collectAsState(initial = null)
    val retryBlockedUntilMillis by authSessionStore.retryBlockedUntilMillisFlow.collectAsState(initial = null)
    var authInProgress by remember { mutableStateOf(false) }
    var authErrorMessage by remember { mutableStateOf<String?>(null) }
    var authInfoMessage by remember { mutableStateOf<String?>(null) }
    var authRetryAfterSeconds by remember { mutableStateOf<Int?>(null) }
    var authAttemptsRemaining by remember { mutableStateOf<Int?>(null) }
    var showResendVerification by remember { mutableStateOf(false) }
    var showOtpCodeField by remember { mutableStateOf(false) }
    var resendVerificationCooldownSeconds by remember { mutableStateOf<Int?>(null) }
    var forgotPasswordCooldownSeconds by remember { mutableStateOf<Int?>(null) }

    LaunchedEffect(savedToken) {
        repository.setBackendAuthToken(savedToken)
    }

    LaunchedEffect(savedToken, savedRefreshToken, tokenExpiresAtMillis) {
        val token = savedToken ?: return@LaunchedEffect
        val refreshToken = savedRefreshToken ?: return@LaunchedEffect
        if (token.isBlank() || refreshToken.isBlank()) return@LaunchedEffect
        val expiresAt = tokenExpiresAtMillis ?: return@LaunchedEffect
        val shouldRefresh = expiresAt <= (System.currentTimeMillis() + 30_000L)
        if (!shouldRefresh) return@LaunchedEffect
        runCatching { repository.refresh(refreshToken) }
            .onSuccess { refreshed ->
                authSessionStore.saveTokens(
                    token = refreshed.accessToken,
                    refreshToken = refreshed.refreshToken,
                    expiresInSeconds = refreshed.expiresInSeconds
                )
                repository.setBackendAuthToken(refreshed.accessToken)
            }
            .onFailure {
                repository.clearLocalSessionData()
                authSessionStore.clearTokens()
                authSessionStore.clearUserProfile()
                repository.setBackendAuthToken(null)
            }
    }

    LaunchedEffect(savedToken, savedUserId, profileSyncedAtMillis) {
        val token = savedToken ?: return@LaunchedEffect
        if (token.isBlank()) return@LaunchedEffect
        val maxProfileAgeMillis = 6 * 60 * 60 * 1000L
        val isProfileStale = (profileSyncedAtMillis ?: 0L) < (System.currentTimeMillis() - maxProfileAgeMillis)
        val needsProfileRefresh = savedUserId == null || isProfileStale
        if (!needsProfileRefresh) return@LaunchedEffect
        runCatching { repository.getCurrentUserProfile() }
            .onSuccess { profile ->
                if (profile != null) {
                    authSessionStore.saveUserProfile(profile.email, profile.userId, profile.displayName)
                }
            }
    }

    LaunchedEffect(savedToken, retryBlockedUntilMillis) {
        if (!savedToken.isNullOrBlank()) return@LaunchedEffect
        val blockedUntil = retryBlockedUntilMillis ?: return@LaunchedEffect
        val remainingMs = blockedUntil - System.currentTimeMillis()
        if (remainingMs > 0) {
            authRetryAfterSeconds = ((remainingMs + 999L) / 1000L).toInt()
            authAttemptsRemaining = null
        } else {
            authSessionStore.clearRetryBlockedUntil()
        }
    }

    LaunchedEffect(authRetryAfterSeconds) {
        while ((authRetryAfterSeconds ?: 0) > 0) {
            delay(1000)
            authRetryAfterSeconds = (authRetryAfterSeconds ?: 0) - 1
        }
        if ((authRetryAfterSeconds ?: 0) == 0) {
            authRetryAfterSeconds = null
            authAttemptsRemaining = null
            authSessionStore.clearRetryBlockedUntil()
        }
    }

    LaunchedEffect(resendVerificationCooldownSeconds) {
        while ((resendVerificationCooldownSeconds ?: 0) > 0) {
            delay(1000)
            resendVerificationCooldownSeconds = (resendVerificationCooldownSeconds ?: 0) - 1
        }
        if ((resendVerificationCooldownSeconds ?: 0) == 0) {
            resendVerificationCooldownSeconds = null
        }
    }

    LaunchedEffect(forgotPasswordCooldownSeconds) {
        while ((forgotPasswordCooldownSeconds ?: 0) > 0) {
            delay(1000)
            forgotPasswordCooldownSeconds = (forgotPasswordCooldownSeconds ?: 0) - 1
        }
        if ((forgotPasswordCooldownSeconds ?: 0) == 0) {
            forgotPasswordCooldownSeconds = null
        }
    }

    if (savedToken.isNullOrBlank()) {
        AuthScreen(
            isLoading = authInProgress,
            errorMessage = authErrorMessage,
            infoMessage = authInfoMessage,
            retryAfterSeconds = authRetryAfterSeconds,
            attemptsRemaining = authAttemptsRemaining,
            showResendVerification = showResendVerification,
            admin2faEmail = ADMIN_2FA_EMAIL,
            showOtpCodeField = showOtpCodeField,
            resendCooldownSeconds = resendVerificationCooldownSeconds,
            forgotPasswordCooldownSeconds = forgotPasswordCooldownSeconds,
            onLogin = { email, password, otpCode ->
                scope.launch {
                    authInProgress = true
                    authErrorMessage = null
                    authInfoMessage = null
                    authRetryAfterSeconds = null
                    authAttemptsRemaining = null
                    runCatching { repository.login(email, password, otpCode) }
                        .onSuccess { tokens ->
                            authRetryAfterSeconds = null
                            authAttemptsRemaining = null
                            authSessionStore.clearRetryBlockedUntil()
                            repository.clearLocalSessionData()
                            authSessionStore.saveTokens(
                                token = tokens.accessToken,
                                refreshToken = tokens.refreshToken,
                                expiresInSeconds = tokens.expiresInSeconds
                            )
                            repository.setBackendAuthToken(tokens.accessToken)
                            showResendVerification = false
                            showOtpCodeField = false
                            resendVerificationCooldownSeconds = null
                            authSessionStore.saveAccountEmail(email.trim())
                        }
                        .onFailure { error ->
                            val authError = error.toAuthUiError()
                            authErrorMessage = authError.message
                            if (authError.requiresOtp) {
                                showOtpCodeField = true
                            }
                            authRetryAfterSeconds = authError.retryAfterSeconds
                            if ((authError.retryAfterSeconds ?: 0) > 0) {
                                authSessionStore.saveRetryBlockedUntil(
                                    authError.retryBlockedUntilMillis
                                        ?: (System.currentTimeMillis() + (authError.retryAfterSeconds!! * 1000L))
                                )
                            } else {
                                authSessionStore.clearRetryBlockedUntil()
                            }
                            authAttemptsRemaining = if ((authError.retryAfterSeconds ?: 0) > 0) {
                                null
                            } else {
                                authError.attemptsRemaining
                            }
                        }
                    authInProgress = false
                }
            },
            onRegister = { email, password ->
                scope.launch {
                    authInProgress = true
                    authErrorMessage = null
                    authInfoMessage = null
                    authRetryAfterSeconds = null
                    authAttemptsRemaining = null
                    runCatching { repository.register(email, password) }
                        .onSuccess {
                            authRetryAfterSeconds = null
                            authAttemptsRemaining = null
                            authSessionStore.clearRetryBlockedUntil()
                            authInfoMessage = "Inscription réussie. Vérifie ton email pour activer ton compte."
                            showResendVerification = true
                            resendVerificationCooldownSeconds = RESEND_VERIFICATION_COOLDOWN_SECONDS
                        }
                        .onFailure { error ->
                            val authError = error.toAuthUiError()
                            authErrorMessage = authError.message
                            authRetryAfterSeconds = authError.retryAfterSeconds
                            if ((authError.retryAfterSeconds ?: 0) > 0) {
                                authSessionStore.saveRetryBlockedUntil(
                                    authError.retryBlockedUntilMillis
                                        ?: (System.currentTimeMillis() + (authError.retryAfterSeconds!! * 1000L))
                                )
                            } else {
                                authSessionStore.clearRetryBlockedUntil()
                            }
                            authAttemptsRemaining = if ((authError.retryAfterSeconds ?: 0) > 0) {
                                null
                            } else {
                                authError.attemptsRemaining
                            }
                        }
                    authInProgress = false
                }
            },
            onResendVerification = { email ->
                scope.launch {
                    if (!email.contains("@")) {
                        authErrorMessage = "Saisis une adresse email valide."
                        return@launch
                    }
                    if (!showResendVerification) {
                        return@launch
                    }
                    if ((resendVerificationCooldownSeconds ?: 0) > 0) {
                        return@launch
                    }
                    authInProgress = true
                    authErrorMessage = null
                    authInfoMessage = null
                    runCatching { repository.resendVerification(email) }
                        .onSuccess { message ->
                            authInfoMessage = message
                            resendVerificationCooldownSeconds = RESEND_VERIFICATION_COOLDOWN_SECONDS
                        }
                        .onFailure { error ->
                            authErrorMessage = error.toAuthUiError().message
                        }
                    authInProgress = false
                }
            },
            onForgotPassword = { email ->
                scope.launch {
                    if (!email.contains("@")) {
                        authErrorMessage = "Saisis une adresse email valide."
                        return@launch
                    }
                    if ((forgotPasswordCooldownSeconds ?: 0) > 0) {
                        return@launch
                    }
                    authInProgress = true
                    authErrorMessage = null
                    authInfoMessage = null
                    runCatching { repository.forgotPassword(email) }
                        .onSuccess { message ->
                            authInfoMessage = message
                            forgotPasswordCooldownSeconds = FORGOT_PASSWORD_COOLDOWN_SECONDS
                        }
                        .onFailure { error ->
                            val authError = error.toAuthUiError()
                            authErrorMessage = authError.message
                            if ((authError.retryAfterSeconds ?: 0) > 0) {
                                forgotPasswordCooldownSeconds = authError.retryAfterSeconds
                            }
                        }
                    authInProgress = false
                }
            }
        )
        return
    }

    MainScreen(
        repository = repository,
        accountEmail = savedAccountEmail,
        displayName = savedDisplayName,
        userId = savedUserId,
        onDisplayNameChange = { newDisplayName ->
            scope.launch {
                val updated = runCatching { repository.updateCurrentUserDisplayName(newDisplayName) }.getOrNull()
                if (updated != null) {
                    authSessionStore.saveUserProfile(updated.email, updated.userId, updated.displayName)
                } else {
                    authSessionStore.saveDisplayName(newDisplayName)
                }
            }
        },
        onDeleteAccount = {
            repository.deleteCurrentUserAccount()
            repository.clearLocalSessionData()
            authSessionStore.clearTokens()
            authSessionStore.clearUserProfile()
            repository.setBackendAuthToken(null)
            "Compte supprimé"
        },
        onCheckForUpdates = {
            checkForAppUpdates()
        },
        onInstallUpdate = { update ->
            installAppUpdate(activity, update)
        },
        onLogout = {
            scope.launch {
                runCatching { repository.logout(savedRefreshToken) }
                repository.clearLocalSessionData()
                authSessionStore.clearTokens()
                authSessionStore.clearUserProfile()
                repository.setBackendAuthToken(null)
            }
        }
    )
}

@OptIn(ExperimentalMaterial3AdaptiveApi::class)
@Composable
fun MainScreen(
    repository: MediaRepository,
    accountEmail: String?,
    displayName: String?,
    userId: Int?,
    onDisplayNameChange: (String?) -> Unit,
    onDeleteAccount: suspend () -> String,
    onCheckForUpdates: suspend () -> UpdateCheckResult,
    onInstallUpdate: suspend (UpdateCheckResult) -> String,
    onLogout: () -> Unit
) {
    val navController = rememberNavController()
    val scope = rememberCoroutineScope()

    var autoUpdateDialog by remember { mutableStateOf<UpdateCheckResult?>(null) }
    var autoUpdateInstalling by remember { mutableStateOf(false) }

    LaunchedEffect(userId) {
        if (userId == null) return@LaunchedEffect
        val result = runCatching { onCheckForUpdates() }.getOrNull()
        if (result?.updateAvailable == true) {
            autoUpdateDialog = result
        }
    }

    LaunchedEffect(repository, userId) {
        if (userId == null) return@LaunchedEffect
        repository.synchronizeWithBackend()
    }

    val mediaViewModel: MediaViewModel = viewModel { MediaViewModel(repository) }
    val watchlistViewModel: WatchlistViewModel = viewModel { WatchlistViewModel(repository) }
    val detailsViewModel: DetailsViewModel = viewModel { DetailsViewModel(repository) }

    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = navBackStackEntry?.destination
    val navigator = rememberListDetailPaneScaffoldNavigator<Nothing>()
    val selectedMedia by mediaViewModel.selectedMedia.collectAsState()
    var hideMainNavigation by remember { mutableStateOf(false) }
    var detailOriginDestination by remember { mutableStateOf<Any?>(null) }

    fun isOnDestination(destination: Any?): Boolean {
        return when (destination) {
            Destination.Series -> currentDestination?.hierarchy?.any { it.hasRoute<Destination.Series>() } == true
            Destination.Films -> currentDestination?.hierarchy?.any { it.hasRoute<Destination.Films>() } == true
            Destination.Anime -> currentDestination?.hierarchy?.any { it.hasRoute<Destination.Anime>() } == true
            Destination.Search -> currentDestination?.hierarchy?.any { it.hasRoute<Destination.Search>() } == true
            Destination.Profile -> currentDestination?.hierarchy?.any { it.hasRoute<Destination.Profile>() } == true
            else -> false
        }
    }

    LaunchedEffect(currentDestination, selectedMedia) {
        val onProfileScreen = currentDestination?.hierarchy?.any { it.hasRoute<Destination.Profile>() } == true
        if (!onProfileScreen && selectedMedia == null && hideMainNavigation) {
            hideMainNavigation = false
        }
    }

    LaunchedEffect(currentDestination, selectedMedia, detailOriginDestination) {
        val origin = detailOriginDestination
        if (selectedMedia != null && origin != null && !isOnDestination(origin)) {
            navController.navigate(origin) {
                popUpTo(navController.graph.findStartDestination().id) {
                    saveState = true
                }
                launchSingleTop = true
                restoreState = true
            }
            mediaViewModel.selectMedia(null)
            if (navigator.canNavigateBack()) {
                scope.launch { navigator.navigateBack() }
            }
        }
    }

    val onNavItemClick = { destination: Any ->
        hideMainNavigation = false
        navController.navigate(destination) {
            popUpTo(navController.graph.findStartDestination().id) {
                saveState = true
            }
            launchSingleTop = true
            restoreState = true
        }
        detailOriginDestination = null
        mediaViewModel.selectMedia(null)
        mediaViewModel.refreshTrackedMedia()
        scope.launch {
            if (navigator.canNavigateBack()) {
                navigator.navigateBack()
            }
        }
    }

    val mainContent: @Composable () -> Unit = {
        val onProfileScreen = currentDestination?.hierarchy?.any { it.hasRoute<Destination.Profile>() } == true
        val shouldHandleBackToCloseDetail = !onProfileScreen && (selectedMedia != null || navigator.canNavigateBack())
        BackHandler(shouldHandleBackToCloseDetail) {
            scope.launch {
                if (navigator.canNavigateBack()) {
                    navigator.navigateBack()
                }
                mediaViewModel.selectMedia(null)
                mediaViewModel.refreshTrackedMedia()
                hideMainNavigation = false
            }
        }

        ListDetailPaneScaffold(
            directive = navigator.scaffoldDirective,
            value = navigator.scaffoldValue,
            listPane = {
                NavHost(
                    navController = navController,
                    startDestination = Destination.Series,
                    modifier = Modifier.fillMaxSize()
                ) {
                    composable<Destination.Series> {
                        WatchlistScreen(
                            viewModel = watchlistViewModel,
                            category = WatchCategory.SERIES,
                            onMediaClick = {
                                detailOriginDestination = Destination.Series
                                hideMainNavigation = true
                                detailsViewModel.prepareForNewSelection()
                                mediaViewModel.selectMedia(it)
                                scope.launch { navigator.navigateTo(ListDetailPaneScaffoldRole.Detail) }
                            }
                        )
                    }
                    composable<Destination.Films> {
                        WatchlistScreen(
                            viewModel = watchlistViewModel,
                            category = WatchCategory.FILMS,
                            onMediaClick = {
                                detailOriginDestination = Destination.Films
                                hideMainNavigation = true
                                detailsViewModel.prepareForNewSelection()
                                mediaViewModel.selectMedia(it)
                                scope.launch { navigator.navigateTo(ListDetailPaneScaffoldRole.Detail) }
                            }
                        )
                    }
                    composable<Destination.Anime> {
                        WatchlistScreen(
                            viewModel = watchlistViewModel,
                            category = WatchCategory.ANIME,
                            onMediaClick = {
                                detailOriginDestination = Destination.Anime
                                hideMainNavigation = true
                                detailsViewModel.prepareForNewSelection()
                                mediaViewModel.selectMedia(it)
                                scope.launch { navigator.navigateTo(ListDetailPaneScaffoldRole.Detail) }
                            }
                        )
                    }
                    composable<Destination.Search> {
                        SearchScreen(
                            viewModel = mediaViewModel,
                            onMediaClick = {
                                detailOriginDestination = Destination.Search
                                hideMainNavigation = true
                                detailsViewModel.prepareForNewSelection()
                                mediaViewModel.selectMedia(it)
                                scope.launch { navigator.navigateTo(ListDetailPaneScaffoldRole.Detail) }
                            }
                        )
                    }
                    composable<Destination.Profile> {
                        ProfileScreen(
                            accountEmail = accountEmail,
                            displayName = displayName,
                            userId = userId,
                            settingsVisible = hideMainNavigation,
                            onDisplayNameChange = onDisplayNameChange,
                            onChangePassword = { currentPassword, newPassword ->
                                repository.changePassword(currentPassword, newPassword)
                            },
                            onPasswordChanged = onLogout,
                            onCheckForUpdates = {
                                onCheckForUpdates()
                            },
                            onInstallUpdate = { update ->
                                onInstallUpdate(update)
                            },
                            onDeleteAccount = onDeleteAccount,
                            onSettingsVisibilityChanged = { isSettingsVisible ->
                                hideMainNavigation = isSettingsVisible
                            },
                            onLogout = onLogout
                        )
                    }
                }
            },
            detailPane = {
                Box(Modifier.fillMaxSize()) {
                    AnimatedVisibility(
                        visible = selectedMedia != null,
                        enter = slideInVertically(
                            initialOffsetY = { fullHeight -> fullHeight },
                            animationSpec = tween(durationMillis = 520, easing = FastOutSlowInEasing)
                        ) + fadeIn(animationSpec = tween(durationMillis = 300)),
                        exit = slideOutVertically(
                            targetOffsetY = { fullHeight -> fullHeight },
                            animationSpec = tween(durationMillis = 240)
                        ) + fadeOut(animationSpec = tween(durationMillis = 180))
                    ) {
                        val media = selectedMedia ?: return@AnimatedVisibility
                        key("${media.mediaType.value}_${media.id}") {
                            DetailsScreen(
                                id = media.id,
                                typeString = media.mediaType.value,
                                viewModel = detailsViewModel,
                                onBackClick = {
                                    scope.launch {
                                        if (navigator.canNavigateBack()) {
                                            navigator.navigateBack()
                                        }
                                        mediaViewModel.selectMedia(null)
                                        mediaViewModel.refreshTrackedMedia()
                                        detailOriginDestination = null
                                        hideMainNavigation = false
                                    }
                                }
                            )
                        }
                    }
                }
            }
        )
    }

    if (hideMainNavigation) {
        mainContent()
    } else {
        NavigationSuiteScaffold(
            navigationSuiteItems = {
                item(
                    selected = currentDestination?.hierarchy?.any { it.hasRoute<Destination.Series>() } == true,
                    onClick = { onNavItemClick(Destination.Series) },
                    icon = { Icon(Icons.Rounded.VideoLibrary, contentDescription = "Séries") },
                    label = { Text("Séries") }
                )
                item(
                    selected = currentDestination?.hierarchy?.any { it.hasRoute<Destination.Films>() } == true,
                    onClick = { onNavItemClick(Destination.Films) },
                    icon = { Icon(Icons.Rounded.Movie, contentDescription = "Films") },
                    label = { Text("Films") }
                )
                item(
                    selected = currentDestination?.hierarchy?.any { it.hasRoute<Destination.Anime>() } == true,
                    onClick = { onNavItemClick(Destination.Anime) },
                    icon = { Icon(Icons.Rounded.LiveTv, contentDescription = "Animé") },
                    label = { Text("Animé") }
                )
                item(
                    selected = currentDestination?.hierarchy?.any { it.hasRoute<Destination.Search>() } == true,
                    onClick = { onNavItemClick(Destination.Search) },
                    icon = { Icon(Icons.Rounded.Search, contentDescription = "Recherche") },
                    label = { Text("Recherche") }
                )
                item(
                    selected = currentDestination?.hierarchy?.any { it.hasRoute<Destination.Profile>() } == true,
                    onClick = { onNavItemClick(Destination.Profile) },
                    icon = { Icon(Icons.Rounded.Person, contentDescription = "Profil") },
                    label = { Text("Profil") }
                )
            }
        ) {
            mainContent()
        }
    }

    val updateToShow = autoUpdateDialog
    if (updateToShow != null) {
            AlertDialog(
                onDismissRequest = { autoUpdateDialog = null },
                title = { Text("Nouvelle version disponible !") },
                text = {
                    ReleaseNotesContent(updateToShow)
                },
                confirmButton = {
                    Column(modifier = Modifier.fillMaxWidth().padding(bottom = 4.dp)) {
                        Button(
                            onClick = {
                                scope.launch {
                                    autoUpdateInstalling = true
                                    runCatching { onInstallUpdate(updateToShow) }
                                        .onFailure { autoUpdateDialog = null }
                                    autoUpdateInstalling = false
                                }
                            },
                            enabled = !autoUpdateInstalling,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(if (autoUpdateInstalling) "Téléchargement..." else "Télécharger")
                        }
                        TextButton(
                            onClick = { autoUpdateDialog = null },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text("Pas maintenant")
                        }
                    }
                }
            )
    }
}

@Composable
private fun ReleaseNotesContent(update: UpdateCheckResult) {
    Column {
        Text(
            text = update.versionName ?: "",
            style = androidx.compose.material3.MaterialTheme.typography.titleMedium
        )
        if (!update.releaseNotes.isNullOrBlank()) {
            Spacer(modifier = Modifier.height(8.dp))
            Column(
                modifier = Modifier
                    .heightIn(max = 240.dp)
                    .verticalScroll(rememberScrollState())
            ) {
                var skippedFirstVersionLine = false
                val normalizedVersion = normalizeReleaseNoteText(update.versionName.orEmpty())
                update.releaseNotes
                    .lineSequence()
                    .forEach { rawLine ->
                        val line = rawLine.trim()
                        if (!skippedFirstVersionLine && line.isNotBlank()) {
                            val normalizedLine = normalizeReleaseNoteText(line)
                            if (normalizedLine == normalizedVersion) {
                                skippedFirstVersionLine = true
                                return@forEach
                            }
                            skippedFirstVersionLine = true
                        }
                        when {
                            line.isBlank() -> Spacer(modifier = Modifier.height(8.dp))
                            line.startsWith("### ") -> ReleaseNotesHeading(
                                text = normalizeReleaseNoteText(line.removePrefix("### ")),
                                style = androidx.compose.material3.MaterialTheme.typography.titleSmall.copy(
                                    fontWeight = FontWeight.Bold,
                                    fontSize = 16.sp
                                )
                            )
                            line.startsWith("## ") -> ReleaseNotesHeading(
                                text = normalizeReleaseNoteText(line.removePrefix("## ")),
                                style = androidx.compose.material3.MaterialTheme.typography.titleMedium.copy(
                                    fontWeight = FontWeight.Bold,
                                    fontSize = 18.sp
                                )
                            )
                            line.startsWith("# ") -> ReleaseNotesHeading(
                                text = normalizeReleaseNoteText(line.removePrefix("# ")),
                                style = androidx.compose.material3.MaterialTheme.typography.titleLarge.copy(
                                    fontWeight = FontWeight.Bold,
                                    fontSize = 20.sp
                                )
                            )
                            line.startsWith("**") && line.endsWith("**") && line.length > 4 -> ReleaseNotesHeading(
                                text = normalizeReleaseNoteText(line),
                                style = androidx.compose.material3.MaterialTheme.typography.titleMedium.copy(
                                    fontWeight = FontWeight.Bold,
                                    fontSize = 18.sp
                                )
                            )
                            else -> Text(
                                text = line,
                                style = androidx.compose.material3.MaterialTheme.typography.bodySmall
                            )
                        }
                    }
            }
        }
    }
}

@Composable
private fun ReleaseNotesHeading(text: String, style: androidx.compose.ui.text.TextStyle) {
    Text(text = text, style = style)
}

private fun normalizeReleaseNoteText(value: String): String {
    return value
        .trim()
        .removePrefix("?")
        .trim()
        .removePrefix("###")
        .removePrefix("##")
        .removePrefix("#")
        .trim()
        .removePrefix("**")
        .removeSuffix("**")
        .removePrefix("*")
        .removeSuffix("*")
        .trim()
}

private data class AuthUiError(
    val message: String,
    val retryAfterSeconds: Int? = null,
    val attemptsRemaining: Int? = null,
    val retryBlockedUntilMillis: Long? = null,
    val requiresOtp: Boolean = false
)

private fun HttpException.backendDetailMessage(): String? {
    val raw = response()?.errorBody()?.string() ?: return null
    val detailRegex = Regex("\"detail\"\\s*:\\s*\"([^\"]+)\"")
    return detailRegex.find(raw)?.groupValues?.getOrNull(1)
}

private fun String.toFriendlyAuthMessage(): String {
    return when (this) {
        "Password must contain at least 10 characters" -> "Le mot de passe doit contenir au moins 10 caractères."
        "Password must include lower, upper, digit, and symbol" -> "Le mot de passe doit inclure une minuscule, une majuscule, un chiffre et un symbole."
        "Password was already used recently" -> "Ce mot de passe a déjà été utilisé récemment."
        "New password must be different from current password" -> "Le nouveau mot de passe doit être différent du mot de passe actuel."
        "Invalid or expired reset token" -> "Le lien de réinitialisation est invalide ou expiré."
        "Email already exists" -> "Cet email est déjà utilisé."
        "Invalid credentials" -> "Identifiants invalides."
        "Two-factor code required" -> "Le code 2FA est requis pour ce compte."
        "Invalid two-factor code" -> "Le code 2FA est invalide."
        "Admin two-factor authentication is not configured" -> "Le 2FA admin n'est pas configuré côté serveur."
        else -> this
    }
}

private suspend fun checkForAppUpdates(): UpdateCheckResult = withContext(Dispatchers.IO) {
    val release = fetchLatestReleaseInfo()
        ?: return@withContext UpdateCheckResult(
            message = "Impossible de déterminer la dernière version.",
            updateAvailable = false
        )
    val installedVersion = BuildConfig.VERSION_NAME
    val comparison = compareVersions(installedVersion, release.tagName)
    if (comparison < 0 && !release.downloadUrl.isNullOrBlank()) {
        UpdateCheckResult(
            message = "Nouvelle version disponible : ${release.tagName} (installée : $installedVersion).",
            updateAvailable = true,
            versionName = release.tagName,
            downloadUrl = release.downloadUrl,
            expectedSha256 = release.expectedSha256,
            releaseNotes = release.releaseNotes
        )
    } else if (comparison < 0) {
        UpdateCheckResult(
            message = "Nouvelle version disponible : ${release.tagName}, mais l'APK n'est pas disponible.",
            updateAvailable = false,
            versionName = release.tagName,
            releaseNotes = release.releaseNotes
        )
    } else {
        UpdateCheckResult(
            message = "Aucune mise à jour disponible. Version installée : $installedVersion.",
            updateAvailable = false,
            versionName = installedVersion
        )
    }
}

private suspend fun installAppUpdate(activity: Activity, update: UpdateCheckResult): String = withContext(Dispatchers.IO) {
    val downloadUrl = update.downloadUrl ?: return@withContext "Lien de téléchargement indisponible."
    val targetFile = File(activity.cacheDir, "updates/${sanitizeFileName(update.versionName ?: "latest")}.apk")
    targetFile.parentFile?.mkdirs()
    downloadApk(downloadUrl, targetFile)
    verifyApkDigest(targetFile, update.expectedSha256)
    withContext(Dispatchers.Main) {
        val apkUri = FileProvider.getUriForFile(activity, "${activity.packageName}.fileprovider", targetFile)
        val installIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            clipData = ClipData.newRawUri("WatchTracker APK", apkUri)
        }
        activity.startActivity(installIntent)
    }
    "Installation de la nouvelle version lancée."
}

private data class ReleaseInfo(
    val tagName: String,
    val downloadUrl: String?,
    val expectedSha256: String?,
    val releaseNotes: String?
)

private fun fetchLatestReleaseInfo(): ReleaseInfo? {
    val releaseResponse = fetchGithubJson(GITHUB_LATEST_RELEASE_URL) ?: return null
    if (releaseResponse.first !in 200..299) {
        return null
    }
    val releaseJson = try {
        JSONObject(releaseResponse.second)
    } catch (_: JSONException) {
        return null
    }
    val tagName = releaseJson.optString("tag_name").trim()
    if (tagName.isBlank()) {
        return null
    }
    val releaseNotes = releaseJson.optString("body").trim().takeIf { it.isNotBlank() }
    val assets = releaseJson.optJSONArray("assets") ?: return ReleaseInfo(tagName, null, null, releaseNotes)
    for (index in 0 until assets.length()) {
        val asset = assets.optJSONObject(index) ?: continue
        val downloadUrl = asset.optString("browser_download_url").trim()
        if (downloadUrl.isBlank()) {
            continue
        }
        val name = asset.optString("name").trim()
        val contentType = asset.optString("content_type").trim()
        if (name.endsWith(".apk", ignoreCase = true) || contentType == "application/vnd.android.package-archive") {
            return ReleaseInfo(
                tagName = tagName,
                downloadUrl = downloadUrl,
                expectedSha256 = asset.optString("digest").substringAfter("sha256:", "").takeIf { it.isNotBlank() },
                releaseNotes = releaseNotes
            )
        }
    }
    return ReleaseInfo(tagName, null, null, releaseNotes)
}

private fun fetchGithubJson(url: String): Pair<Int, String>? {
    val connection = (URL(url).openConnection() as HttpURLConnection).apply {
        requestMethod = "GET"
        connectTimeout = 5000
        readTimeout = 5000
        setRequestProperty("Accept", "application/vnd.github+json")
        setRequestProperty("User-Agent", "WatchTracker-Android")
    }
    return try {
        val statusCode = connection.responseCode
        val stream = if (statusCode in 200..299) connection.inputStream else connection.errorStream
        val body = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
        statusCode to body
    } finally {
        connection.disconnect()
    }
}

private fun downloadApk(downloadUrl: String, targetFile: File) {
    val connection = (URL(downloadUrl).openConnection() as HttpURLConnection).apply {
        requestMethod = "GET"
        connectTimeout = 10_000
        readTimeout = 30_000
        setRequestProperty("User-Agent", "WatchTracker-Android")
    }
    try {
        val statusCode = connection.responseCode
        if (statusCode !in 200..299) {
            throw IOException("Téléchargement impossible (${statusCode}).")
        }
        connection.inputStream.use { input ->
            targetFile.outputStream().use { output ->
                input.copyTo(output)
            }
        }
    } finally {
        connection.disconnect()
    }
}

private fun verifyApkDigest(file: File, expectedSha256: String?) {
    if (expectedSha256.isNullOrBlank()) {
        return
    }
    val digest = MessageDigest.getInstance("SHA-256")
    file.inputStream().use { input ->
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        while (true) {
            val read = input.read(buffer)
            if (read <= 0) {
                break
            }
            digest.update(buffer, 0, read)
        }
    }
    val actualDigest = digest.digest().joinToString("") { byte -> "%02x".format(byte) }
    if (!actualDigest.equals(expectedSha256, ignoreCase = true)) {
        throw IOException("Le fichier téléchargé ne correspond pas au hash attendu.")
    }
}

private fun sanitizeFileName(value: String): String {
    return value.replace(Regex("""[^A-Za-z0-9._-]"""), "_")
}

private fun compareVersions(current: String, latest: String): Int {
    val currentParts = normalizeVersion(current)
    val latestParts = normalizeVersion(latest)
    val maxSize = maxOf(currentParts.size, latestParts.size)
    for (index in 0 until maxSize) {
        val currentValue = currentParts.getOrElse(index) { 0 }
        val latestValue = latestParts.getOrElse(index) { 0 }
        if (currentValue != latestValue) {
            return currentValue.compareTo(latestValue)
        }
    }
    return 0
}

private fun normalizeVersion(rawVersion: String): List<Int> {
    return rawVersion
        .trim()
        .removePrefix("v")
        .split(Regex("[^0-9]+"))
        .mapNotNull { part -> part.toIntOrNull() }
        .ifEmpty { listOf(0) }
}

private fun Throwable.toAuthUiError(): AuthUiError {
    return when (this) {
        is HttpException -> {
            val retryAfter = response()?.headers()?.get("Retry-After")?.toIntOrNull()
            val attemptsRemaining = response()?.headers()?.get("X-Auth-Attempts-Remaining")?.toIntOrNull()
            val resetAtEpochSeconds = response()?.headers()?.get("X-RateLimit-Reset")?.toLongOrNull()
            val retryBlockedUntilMillis = resetAtEpochSeconds?.times(1000L)
            val backendDetail = backendDetailMessage()
            val backendMessage = backendDetail?.toFriendlyAuthMessage()
            val requiresOtp = backendDetail == "Two-factor code required" || backendDetail == "Invalid two-factor code"
            when (code()) {
                400 -> AuthUiError(backendMessage ?: "Le mot de passe ne respecte pas les règles de sécurité.")
                401 -> AuthUiError(
                    message = backendMessage ?: "Identifiants invalides.",
                    retryAfterSeconds = retryAfter,
                    attemptsRemaining = attemptsRemaining,
                    retryBlockedUntilMillis = retryBlockedUntilMillis,
                    requiresOtp = requiresOtp
                )
                409 -> AuthUiError(
                    message = "Cet email est déjà utilisé.",
                    retryAfterSeconds = retryAfter,
                    attemptsRemaining = attemptsRemaining,
                    retryBlockedUntilMillis = retryBlockedUntilMillis
                )
                403 -> AuthUiError("Ton email n'est pas encore vérifié.")
                429 -> AuthUiError(
                    message = "Identifiants invalides à répétition : protection anti-bruteforce activée.",
                    retryAfterSeconds = retryAfter,
                    retryBlockedUntilMillis = retryBlockedUntilMillis
                )
                503 -> AuthUiError(backendMessage ?: "Service temporairement indisponible.")
                else -> AuthUiError("Erreur serveur (${code()}).")
            }
        }
        is IOException -> AuthUiError("Impossible de contacter l'API.")
        else -> AuthUiError(message ?: "Une erreur est survenue.")
    }
}
