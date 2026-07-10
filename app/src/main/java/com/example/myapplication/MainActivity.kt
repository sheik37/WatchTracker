package com.example.myapplication

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material.icons.automirrored.rounded.Logout
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.LiveTv
import androidx.compose.material.icons.rounded.Movie
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
import com.example.myapplication.ui.screens.SearchScreen
import com.example.myapplication.ui.screens.WatchlistScreen
import com.example.myapplication.ui.screens.WatchlistViewModel
import com.example.myapplication.ui.theme.MyApplicationTheme
import java.io.IOException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import retrofit2.HttpException

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val container = (application as WatchTrackerApp).container

        setContent {
            MyApplicationTheme {
                RootScreen(
                    repository = container.repository,
                    authSessionStore = container.authSessionStore
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3AdaptiveApi::class)
@Composable
fun RootScreen(repository: MediaRepository, authSessionStore: AuthSessionStore) {
    val scope = rememberCoroutineScope()
    val savedToken by authSessionStore.tokenFlow.collectAsState(initial = null)
    val retryBlockedUntilMillis by authSessionStore.retryBlockedUntilMillisFlow.collectAsState(initial = null)
    var authInProgress by remember { mutableStateOf(false) }
    var authErrorMessage by remember { mutableStateOf<String?>(null) }
    var authRetryAfterSeconds by remember { mutableStateOf<Int?>(null) }
    var authAttemptsRemaining by remember { mutableStateOf<Int?>(null) }

    LaunchedEffect(savedToken) {
        repository.setBackendAuthToken(savedToken)
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

    if (savedToken.isNullOrBlank()) {
        AuthScreen(
            isLoading = authInProgress,
            errorMessage = authErrorMessage,
            retryAfterSeconds = authRetryAfterSeconds,
            attemptsRemaining = authAttemptsRemaining,
            onLogin = { username, password ->
                scope.launch {
                    authInProgress = true
                    authErrorMessage = null
                    authRetryAfterSeconds = null
                    authAttemptsRemaining = null
                    runCatching { repository.login(username, password) }
                        .onSuccess { token ->
                            authRetryAfterSeconds = null
                            authAttemptsRemaining = null
                            authSessionStore.clearRetryBlockedUntil()
                            authSessionStore.saveToken(token)
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
            onRegister = { username, password ->
                scope.launch {
                    authInProgress = true
                    authErrorMessage = null
                    authRetryAfterSeconds = null
                    authAttemptsRemaining = null
                    runCatching { repository.register(username, password) }
                        .onSuccess { token ->
                            authRetryAfterSeconds = null
                            authAttemptsRemaining = null
                            authSessionStore.clearRetryBlockedUntil()
                            authSessionStore.saveToken(token)
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
            }
        )
        return
    }

    MainScreen(
        repository = repository,
        onLogout = {
            scope.launch {
                runCatching { repository.logout() }
                authSessionStore.clearToken()
            }
        }
    )
}

@OptIn(ExperimentalMaterial3AdaptiveApi::class)
@Composable
fun MainScreen(repository: MediaRepository, onLogout: () -> Unit) {
    val navController = rememberNavController()
    val scope = rememberCoroutineScope()

    LaunchedEffect(repository) {
        repository.synchronizeWithBackend()
    }

    val mediaViewModel: MediaViewModel = viewModel { MediaViewModel(repository) }
    val watchlistViewModel: WatchlistViewModel = viewModel { WatchlistViewModel(repository) }
    val detailsViewModel: DetailsViewModel = viewModel { DetailsViewModel(repository) }

    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = navBackStackEntry?.destination
    val navigator = rememberListDetailPaneScaffoldNavigator<Nothing>()
    val selectedMedia by mediaViewModel.selectedMedia.collectAsState()

    val onNavItemClick = { destination: Any ->
        navController.navigate(destination) {
            popUpTo(navController.graph.findStartDestination().id) {
                saveState = true
            }
            launchSingleTop = true
            restoreState = true
        }
        mediaViewModel.selectMedia(null)
        scope.launch {
            if (navigator.canNavigateBack()) {
                navigator.navigateBack()
            }
        }
    }

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
                selected = false,
                onClick = onLogout,
                icon = { Icon(Icons.AutoMirrored.Rounded.Logout, contentDescription = "Déconnexion") },
                label = { Text("Déconnexion") }
            )
        }
    ) {
        BackHandler(navigator.canNavigateBack()) {
            scope.launch {
                navigator.navigateBack()
                mediaViewModel.selectMedia(null)
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
                                mediaViewModel.selectMedia(it)
                                scope.launch { navigator.navigateTo(ListDetailPaneScaffoldRole.Detail) }
                            }
                        )
                    }
                    composable<Destination.Search> {
                        SearchScreen(
                            viewModel = mediaViewModel,
                            onMediaClick = {
                                mediaViewModel.selectMedia(it)
                                scope.launch { navigator.navigateTo(ListDetailPaneScaffoldRole.Detail) }
                            }
                        )
                    }
                }
            },
            detailPane = {
                selectedMedia?.let { media ->
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
                            }
                        }
                    )
                } ?: Box(Modifier.fillMaxSize()) {
                    Text("Sélectionnez un titre", modifier = Modifier.align(Alignment.Center))
                }
            }
        )
    }
}

private data class AuthUiError(
    val message: String,
    val retryAfterSeconds: Int? = null,
    val attemptsRemaining: Int? = null,
    val retryBlockedUntilMillis: Long? = null
)

private fun Throwable.toAuthUiError(): AuthUiError {
    return when (this) {
        is HttpException -> {
            val retryAfter = response()?.headers()?.get("Retry-After")?.toIntOrNull()
            val attemptsRemaining = response()?.headers()?.get("X-Auth-Attempts-Remaining")?.toIntOrNull()
            val resetAtEpochSeconds = response()?.headers()?.get("X-RateLimit-Reset")?.toLongOrNull()
            val retryBlockedUntilMillis = resetAtEpochSeconds?.times(1000L)
            when (code()) {
                401 -> AuthUiError(
                    message = "Identifiants invalides.",
                    retryAfterSeconds = retryAfter,
                    attemptsRemaining = attemptsRemaining,
                    retryBlockedUntilMillis = retryBlockedUntilMillis
                )
                409 -> AuthUiError(
                    message = "Ce nom d'utilisateur existe déjà.",
                    retryAfterSeconds = retryAfter,
                    attemptsRemaining = attemptsRemaining,
                    retryBlockedUntilMillis = retryBlockedUntilMillis
                )
                429 -> AuthUiError(
                    message = "Identifiants invalides à répétition : protection anti-bruteforce activée.",
                    retryAfterSeconds = retryAfter,
                    retryBlockedUntilMillis = retryBlockedUntilMillis
                )
                else -> AuthUiError("Erreur serveur (${code()}).")
            }
        }
        is IOException -> AuthUiError("Impossible de contacter l'API.")
        else -> AuthUiError(message ?: "Une erreur est survenue.")
    }
}
