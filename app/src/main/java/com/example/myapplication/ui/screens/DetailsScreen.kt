package com.example.myapplication.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material.icons.rounded.RadioButtonUnchecked
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.platform.LocalDensity
import coil.compose.AsyncImage
import com.example.myapplication.data.model.Episode
import com.example.myapplication.data.model.MediaDetails
import com.example.myapplication.data.model.MediaType
import com.example.myapplication.data.model.Season
import com.example.myapplication.data.model.WatchStatus
import com.example.myapplication.data.model.TvStatus
import kotlinx.coroutines.launch
import androidx.compose.ui.window.Dialog

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DetailsScreen(
    id: Int,
    typeString: String,
    viewModel: DetailsViewModel,
    onBackClick: () -> Unit
) {
    val type = MediaType.fromString(typeString)
    val details by viewModel.details.collectAsState()
    val isInWatchlist by viewModel.isInWatchlist.collectAsState()
    val watchStatus by viewModel.watchStatus.collectAsState()
    val watchedEpisodes by viewModel.watchedEpisodes.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val listState = rememberLazyListState()
    var showMenu by remember { mutableStateOf(false) }
    var showRemoveDialog by remember { mutableStateOf(false) }

    LaunchedEffect(id, type) {
        viewModel.loadDetails(id, type)
    }

    Scaffold(
        topBar = {}
    ) { padding ->
        if (isLoading && details == null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            details?.let { media ->
                val orderedSeasons = remember(media.seasons) { orderSeasons(media.seasons) }
                val seasonOffsets = remember(orderedSeasons) { buildSeasonOffsets(orderedSeasons) }
                Box(Modifier.fillMaxSize()) {
                    val density = LocalDensity.current
                    val compactHeaderStartPx = with(density) { 320.dp.toPx() }
                    val compactHeaderEndPx = with(density) { 420.dp.toPx() }
                    val compactHeaderAlpha by remember(listState.firstVisibleItemIndex, listState.firstVisibleItemScrollOffset) {
                        derivedStateOf {
                            when {
                                listState.firstVisibleItemIndex > 0 -> 1f
                                compactHeaderEndPx <= compactHeaderStartPx -> 0f
                                listState.firstVisibleItemScrollOffset <= compactHeaderStartPx -> 0f
                                else -> ((listState.firstVisibleItemScrollOffset - compactHeaderStartPx) / (compactHeaderEndPx - compactHeaderStartPx))
                                    .coerceIn(0f, 1f)
                            }
                        }
                    }

                    LazyColumn(
                        state = listState,
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(padding)
                    ) {
                        item {
                            MediaHeader(
                                media = media,
                                onBackClick = onBackClick,
                                isInWatchlist = isInWatchlist,
                                showMenu = showMenu,
                                onMenuClick = { showMenu = true },
                                onDismissMenu = { showMenu = false },
                                onPrimaryAction = {
                                    showMenu = false
                                    if (isInWatchlist) {
                                        showRemoveDialog = true
                                    } else {
                                        viewModel.toggleWatchlist()
                                    }
                                }
                            )
                        }
                        item { MediaOverview(media) }
                        if (media.mediaType == MediaType.TV) {
                            items(orderedSeasons, key = { it.seasonNumber }) { season ->
                                SeasonSection(
                                    season = season,
                                    viewModel = viewModel,
                                    watchedEpisodes = watchedEpisodes,
                                    seasonOffset = seasonOffsets[season.seasonNumber] ?: 0,
                                    isSpecialSeason = season.seasonNumber == 0
                                )
                            }
                        }
                    }

                    if (compactHeaderAlpha > 0f) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(72.dp)
                                .padding(padding)
                                .background(Color.Transparent)
                        ) {
                            CompactStickyHeader(
                                media = media,
                                onBackClick = onBackClick,
                                isInWatchlist = isInWatchlist,
                                alpha = compactHeaderAlpha,
                                showMenu = showMenu,
                                onMenuClick = { showMenu = true },
                                onDismissMenu = { showMenu = false },
                                onPrimaryAction = {
                                    showMenu = false
                                    if (isInWatchlist) {
                                        showRemoveDialog = true
                                    } else {
                                        viewModel.toggleWatchlist()
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    if (showRemoveDialog) {
        AlertDialog(
            onDismissRequest = { showRemoveDialog = false },
            title = { Text("Supprimer la série") },
            text = { Text("Retirer cette série de vos suivis ?") },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.removeFromWatchlist()
                    showRemoveDialog = false
                }) { Text("Supprimer") }
            },
            dismissButton = {
                TextButton(onClick = { showRemoveDialog = false }) { Text("Annuler") }
            }
        )
    }
}

@Composable
fun MediaHeader(
    media: MediaDetails,
    onBackClick: () -> Unit,
    isInWatchlist: Boolean,
    showMenu: Boolean,
    onMenuClick: () -> Unit,
    onDismissMenu: () -> Unit,
    onPrimaryAction: () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(420.dp)
    ) {
        AsyncImage(
            model = media.backdropPath ?: media.posterPath,
            contentDescription = null,
            modifier = Modifier.fillMaxSize(),
            contentScale = ContentScale.Crop
        )
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        colors = listOf(Color.Transparent, Color.Black.copy(alpha = 0.7f)),
                        startY = 400f
                    )
                )
        )
        IconButton(
            onClick = onBackClick,
            modifier = Modifier.align(Alignment.TopStart)
        ) {
            Icon(
                Icons.AutoMirrored.Rounded.ArrowBack,
                contentDescription = "Retour",
                tint = Color.White
            )
        }
        Box(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(4.dp)
        ) {
            IconButton(onClick = onMenuClick) {
                Icon(
                    Icons.Rounded.MoreVert,
                    contentDescription = "Options",
                    tint = Color.White
                )
            }
            DropdownMenu(
                expanded = showMenu,
                onDismissRequest = onDismissMenu
            ) {
                DropdownMenuItem(
                    text = {
                        Text(
                            if (isInWatchlist) {
                                when (media.mediaType) {
                                    MediaType.MOVIE -> "Supprimer le film"
                                    else -> "Supprimer la série"
                                }
                            } else {
                                when (media.mediaType) {
                                    MediaType.MOVIE -> "Ajouter le film"
                                    else -> "Suivre la série"
                                }
                            }
                        )
                    },
                    onClick = {
                        onDismissMenu()
                        onPrimaryAction()
                    }
                )
            }
        }
        Column(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(16.dp)
        ) {
            Text(
                text = media.title,
                style = MaterialTheme.typography.headlineMedium,
                color = Color.White,
                fontWeight = FontWeight.Bold
            )
            if (media.mediaType == MediaType.TV) {
            SeriesHeaderSubtitle(
                seasonCount = media.seasons.count { it.seasonNumber != 0 },
                status = media.tvStatus
            )
            }
        }
    }
}

@Composable
fun CompactStickyHeader(
    media: MediaDetails,
    onBackClick: () -> Unit,
    isInWatchlist: Boolean,
    alpha: Float,
    showMenu: Boolean,
    onMenuClick: () -> Unit,
    onDismissMenu: () -> Unit,
    onPrimaryAction: () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(96.dp)
            .background(Color.Black.copy(alpha = 0.05f))
    ) {
        AsyncImage(
            model = media.backdropPath ?: media.posterPath,
            contentDescription = null,
            modifier = Modifier
                .fillMaxSize()
                .padding(0.dp),
            contentScale = ContentScale.Crop
        )
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        listOf(
                            Color.Black.copy(alpha = 0.10f * alpha),
                            Color.Black.copy(alpha = 0.40f * alpha)
                        )
                    )
                )
        )
        IconButton(
            onClick = onBackClick,
            modifier = Modifier.align(Alignment.CenterStart)
        ) {
            Icon(
                Icons.AutoMirrored.Rounded.ArrowBack,
                contentDescription = "Retour",
                tint = Color.White.copy(alpha = alpha)
            )
        }
        Text(
            text = media.title,
            modifier = Modifier.align(Alignment.Center),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = Color.White.copy(alpha = alpha),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Box(
            modifier = Modifier
                .align(Alignment.CenterEnd)
                .padding(end = 4.dp)
        ) {
            IconButton(onClick = onMenuClick) {
                Icon(
                    Icons.Rounded.MoreVert,
                    contentDescription = "Options",
                    tint = Color.White.copy(alpha = alpha)
                )
            }
            DropdownMenu(
                expanded = showMenu,
                onDismissRequest = onDismissMenu
            ) {
                DropdownMenuItem(
                    text = {
                        Text(
                            if (isInWatchlist) {
                                when (media.mediaType) {
                                    MediaType.MOVIE -> "Supprimer le film"
                                    else -> "Supprimer la série"
                                }
                            } else {
                                when (media.mediaType) {
                                    MediaType.MOVIE -> "Ajouter le film"
                                    else -> "Suivre la série"
                                }
                            }
                        )
                    },
                    onClick = {
                        onDismissMenu()
                        onPrimaryAction()
                    }
                )
            }
        }
    }
}

@Composable
private fun SeriesHeaderSubtitle(
    seasonCount: Int,
    status: TvStatus?
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(
            text = if (seasonCount <= 1) "1 saison" else "$seasonCount saisons",
            style = MaterialTheme.typography.bodyLarge,
            color = Color.White.copy(alpha = 0.85f)
        )
        if (status != null) {
            Text(
                text = "•",
                style = MaterialTheme.typography.bodyLarge,
                color = Color.White.copy(alpha = 0.85f),
                modifier = Modifier.padding(horizontal = 8.dp),
                fontSize = 18.sp,
                lineHeight = 18.sp
            )
            Text(
                text = status.label,
                style = MaterialTheme.typography.bodyLarge,
                color = Color.White.copy(alpha = 0.85f)
            )
        }
    }
}

@Composable
fun MediaOverview(media: MediaDetails) {
    Column(Modifier.padding(16.dp)) {
        Text(
            text = "Synopsis",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold
        )
        Spacer(Modifier.height(8.dp))
        Text(
            text = media.overview,
            style = MaterialTheme.typography.bodyMedium
        )
    }
}

@Composable
fun SeasonSection(
    season: Season,
    viewModel: DetailsViewModel,
    watchedEpisodes: Set<String>,
    seasonOffset: Int,
    isSpecialSeason: Boolean
) {
    var expanded by remember { mutableStateOf(false) }
    var episodes by remember { mutableStateOf<List<Episode>>(emptyList()) }
    var loadingEpisodes by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    val watchedCount = watchedEpisodes.count { it.startsWith("${season.seasonNumber}_") }
    val totalCount = season.episodeCount
    val progress = if (totalCount > 0) watchedCount.toFloat() / totalCount.toFloat() else 0f
    val showProgress = watchedCount > 0 && totalCount > 0
    val progressColor = when {
        totalCount > 0 && watchedCount >= totalCount -> Color(0xFF4CAF50)
        watchedCount > 0 -> Color(0xFFFFC107)
        else -> Color.Transparent
    }
    val seasonTitle = if (isSpecialSeason) "Épisodes spéciaux" else seasonLabel(season.seasonNumber)

    LaunchedEffect(expanded) {
        if (expanded && episodes.isEmpty()) {
            loadingEpisodes = true
            episodes = viewModel.getEpisodesForSeason(season.seasonNumber)
            loadingEpisodes = false
        }
    }

    Column(Modifier.fillMaxWidth()) {
        Card(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 6.dp)
                .clickable { expanded = !expanded },
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f))
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    modifier = Modifier.weight(1f),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = seasonTitle,
                        fontWeight = FontWeight.Bold
                    )
                    Spacer(Modifier.size(6.dp))
                    Icon(
                        imageVector = if (expanded) Icons.Rounded.KeyboardArrowUp else Icons.Rounded.KeyboardArrowDown,
                        contentDescription = if (expanded) "Réduire" else "Développer",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                if (totalCount > 0) {
                    Text(
                        text = "$watchedCount/$totalCount",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodySmall
                    )
                    Spacer(Modifier.size(8.dp))
                }
                Checkbox(
                    checked = totalCount > 0 && watchedCount >= totalCount,
                    onCheckedChange = { checked ->
                        viewModel.markSeasonWatched(season.seasonNumber, checked)
                    }
                )
            }
            if (showProgress) {
                LinearProgressIndicator(
                    progress = { progress },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(4.dp),
                    color = progressColor,
                    trackColor = MaterialTheme.colorScheme.surfaceVariant
                )
            }
        }

        if (expanded) {
            if (loadingEpisodes) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator()
                }
            } else {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(max = 520.dp)
                ) {
                    items(episodes, key = { "${it.seasonNumber}_${it.episodeNumber}" }) { episode ->
                        val isWatched = watchedEpisodes.contains("${episode.seasonNumber}_${episode.episodeNumber}")
                        EpisodeRow(
                            viewModel = viewModel,
                            episode = episode,
                            isWatched = isWatched,
                            watchedEpisodes = watchedEpisodes,
                            seasonOffset = seasonOffset,
                            isSpecialSeason = isSpecialSeason
                        )
                    }
                }
            }
        }
        Spacer(Modifier.height(8.dp))
    }
}

@Composable
private fun EpisodeRow(
    viewModel: DetailsViewModel,
    episode: Episode,
    isWatched: Boolean,
    watchedEpisodes: Set<String>,
    seasonOffset: Int,
    isSpecialSeason: Boolean
) {
    var showDialog by remember { mutableStateOf(false) }
    var showConfirm by remember { mutableStateOf(false) }
    var dialogChecked by remember(isWatched) { mutableStateOf(isWatched) }
    val expectedPreviousCount = seasonOffset + episode.episodeNumber - 1
    val watchedPreviousCount = watchedEpisodes.count { key ->
        val parts = key.split("_")
        if (parts.size != 2) {
            false
        } else {
            val seasonNumber = parts[0].toIntOrNull()
            val episodeNumber = parts[1].toIntOrNull()
            seasonNumber != null && episodeNumber != null &&
                (seasonNumber < episode.seasonNumber ||
                    (seasonNumber == episode.seasonNumber && episodeNumber < episode.episodeNumber))
        }
    }

    fun requestCheckedChange(target: Boolean) {
        dialogChecked = target
        if (isSpecialSeason) {
            viewModel.setEpisodeWatched(episode, target)
            showDialog = false
            showConfirm = false
            return
        }
        if (!target) {
            viewModel.setEpisodeWatched(episode, false)
            showDialog = false
        } else {
            if (watchedPreviousCount < expectedPreviousCount) {
                showConfirm = true
            } else {
                viewModel.setEpisodeWatched(episode, true)
                showDialog = false
            }
        }
    }

    if (showDialog) {
        EpisodeDialog(
            episode = episode,
            checked = dialogChecked,
            onDismiss = {
                showDialog = false
                showConfirm = false
                dialogChecked = isWatched
            },
            onCheckedChange = { target -> requestCheckedChange(target) }
        )
    }

    if (showConfirm) {
        AlertDialog(
            onDismissRequest = {
                showConfirm = false
                dialogChecked = isWatched
            },
            title = { Text("Épisodes précédents manquants") },
            text = { Text("Des épisodes précédents ne sont pas cochés. Voulez-vous aussi les cocher ?") },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.markEpisodeUpTo(
                        seasonNumber = episode.seasonNumber,
                        episodeNumber = episode.episodeNumber,
                        watched = true
                    )
                    showConfirm = false
                    showDialog = false
                }) { Text("Valider") }
            },
            dismissButton = {
                TextButton(onClick = {
                    viewModel.setEpisodeWatched(episode, true)
                    showConfirm = false
                    showDialog = false
                }) { Text("Seulement celui-ci") }
            }
        )
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Card(
            modifier = Modifier
                .weight(1f)
                .clickable { showDialog = true },
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f))
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
        AsyncImage(
            model = episode.stillPath,
            contentDescription = null,
            modifier = Modifier
                .size(72.dp)
                .clickable { showDialog = true },
            contentScale = ContentScale.Crop
        )
                Spacer(Modifier.size(12.dp))
                Column(
                    modifier = Modifier.weight(1f)
                ) {
                    if (isSpecialSeason) {
                        Text(
                            text = episode.name,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                            style = MaterialTheme.typography.bodyLarge
                        )
                    } else {
                        Text(
                            text = episodeNumbers(seasonOffset, episode),
                            fontWeight = FontWeight.Bold,
                            maxLines = 1
                        )
                        Text(
                            text = episode.name,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
                Checkbox(
                    checked = isWatched,
                    onCheckedChange = { target -> requestCheckedChange(target) }
                )
            }
        }
    }
}

@Composable
private fun EpisodeDialog(
    episode: Episode,
    checked: Boolean,
    onDismiss: () -> Unit,
    onCheckedChange: (Boolean) -> Unit
) {
    Dialog(onDismissRequest = onDismiss) {
        Card {
            Column(Modifier.padding(16.dp)) {
                Text(episode.name, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(8.dp))
                Text("Titre : ${episode.name}")
                Text("Date de parution : ${episode.airDate ?: "Inconnue"}")
                Text("Durée : ${episode.runtime?.let { "$it min" } ?: "Inconnue"}")
                Spacer(Modifier.height(8.dp))
                Text(episode.overview.ifBlank { "Aucun synopsis disponible." })
                Spacer(Modifier.height(12.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(
                        checked = checked,
                        onCheckedChange = onCheckedChange
                    )
                    Text("Vu")
                }
            }
        }
    }
}

private fun buildSeasonOffsets(seasons: List<Season>): Map<Int, Int> {
    var offset = 0
    return seasons.filter { it.seasonNumber != 0 }.associate { season ->
        val current = offset
        offset += season.episodeCount.coerceAtLeast(0)
        season.seasonNumber to current
    }
}

private fun orderSeasons(seasons: List<Season>): List<Season> =
    seasons.sortedWith(compareBy<Season> { it.seasonNumber == 0 }.thenBy { it.seasonNumber })

private fun seasonLabel(seasonNumber: Int): String = when (seasonNumber) {
    0 -> "Épisodes spéciaux"
    else -> "Saison $seasonNumber"
}

private fun episodeNumbers(seasonOffset: Int, episode: Episode): String {
    val globalNumber = seasonOffset + episode.episodeNumber
    return "S%02d | E%02d (E%02d)".format(episode.seasonNumber, episode.episodeNumber, globalNumber)
}
