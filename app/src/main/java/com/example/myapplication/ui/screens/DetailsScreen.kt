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
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.CalendarMonth
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material.icons.rounded.RadioButtonUnchecked
import androidx.compose.material.icons.rounded.Visibility
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
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
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
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.dp
import kotlin.math.min
import coil.compose.AsyncImage
import com.example.myapplication.data.model.Episode
import com.example.myapplication.data.model.MediaDetails
import com.example.myapplication.data.model.MediaType
import com.example.myapplication.data.model.Season
import com.example.myapplication.data.model.WatchCategory
import com.example.myapplication.data.model.WatchStatus
import com.example.myapplication.data.model.TvStatus
import com.example.myapplication.data.model.watchCategory
import kotlinx.coroutines.launch
import androidx.compose.ui.window.Dialog
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

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
    val movieWatchedAtMillis by viewModel.movieWatchedAtMillis.collectAsState()
    val watchedEpisodes by viewModel.watchedEpisodes.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val listState = rememberLazyListState()
    var showMenu by remember { mutableStateOf(false) }
    var showRemoveDialog by remember { mutableStateOf(false) }
    var tvSection by remember(id, typeString) { mutableStateOf(TvDetailsSection.ABOUT) }

    LaunchedEffect(id, type) {
        viewModel.loadDetails(id, type)
    }

    Scaffold(
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        topBar = {},
        bottomBar = {
            val media = details
            if (media != null && !isInWatchlist) {
                AddToWatchlistBottomBar(
                    media = media,
                    onAddClick = { viewModel.toggleWatchlist() }
                )
            }
        }
    ) { padding ->
        if (isLoading && details == null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            details?.let { media ->
                val orderedSeasons = remember(media.seasons) { orderSeasons(media.seasons) }
                val seasonOffsets = remember(orderedSeasons) { buildSeasonOffsets(orderedSeasons) }
                val mediaCategory = remember(media) { media.watchCategory() }
                Box(Modifier.fillMaxSize()) {
                    val density = LocalDensity.current
                    val tvTabsHeight = if (media.mediaType == MediaType.TV) 48.dp else 0.dp
                    val statusBarInsetDp = with(density) { WindowInsets.statusBars.getTop(density).toDp() }
                    val headerMaxHeight = 210.dp + statusBarInsetDp
                    val headerMinHeight = 59.dp + statusBarInsetDp
                    val headerCollapseRangePx = with(density) { (headerMaxHeight - headerMinHeight).toPx() }
                    val headerOffsetPx by remember(
                        listState.firstVisibleItemIndex,
                        listState.firstVisibleItemScrollOffset,
                        headerCollapseRangePx
                    ) {
                        derivedStateOf {
                            if (listState.firstVisibleItemIndex > 0) {
                                headerCollapseRangePx
                            } else {
                                min(listState.firstVisibleItemScrollOffset.toFloat(), headerCollapseRangePx)
                            }
                        }
                    }
                    val headerOffsetDp = with(density) { headerOffsetPx.toDp() }
                    val collapseProgress = if (headerCollapseRangePx <= 0f) 1f else (headerOffsetPx / headerCollapseRangePx).coerceIn(0f, 1f)
                    val centeredTitleAlpha = ((collapseProgress - 0.75f) / 0.25f).coerceIn(0f, 1f)
                    val bottomHeaderAlpha = (1f - centeredTitleAlpha).coerceIn(0f, 1f)
                    val headerProgressState = remember(media, isInWatchlist, watchStatus, watchedEpisodes) {
                        detailsHeaderProgressState(
                            media = media,
                            isInWatchlist = isInWatchlist,
                            watchStatus = watchStatus,
                            watchedEpisodes = watchedEpisodes
                        )
                    }

                    LazyColumn(
                        state = listState,
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(padding)
                    ) {
                        item {
                            Spacer(modifier = Modifier.height(headerMaxHeight + tvTabsHeight))
                        }
                        if (media.mediaType == MediaType.TV) {
                            if (tvSection == TvDetailsSection.ABOUT) {
                                item {
                                    TvAboutSection(
                                        media = media,
                                        category = mediaCategory
                                    )
                                }
                            } else {
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
                        } else {
                            item {
                                MovieInfoStrip(
                                    releaseDate = media.releaseDate,
                                    isWatched = watchStatus == WatchStatus.WATCHED,
                                    watchedAtMillis = movieWatchedAtMillis,
                                    onWatchedChange = { checked -> viewModel.setMovieWatched(checked) }
                                )
                            }
                            item { MediaOverview(media) }
                        }
                    }

                    Column(
                        modifier = Modifier
                            .align(Alignment.TopStart)
                            .offset(y = -headerOffsetDp)
                    ) {
                        MediaHeader(
                            media = media,
                            headerHeight = headerMaxHeight,
                            contentAlpha = bottomHeaderAlpha,
                            progressState = headerProgressState
                        )
                        if (media.mediaType == MediaType.TV) {
                            TvDetailsTabs(
                                selected = tvSection,
                                onSelectedChange = { tvSection = it }
                            )
                        }
                    }

                    DetailsTopActions(
                        title = media.title,
                        centeredTitleAlpha = centeredTitleAlpha,
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
private fun AddToWatchlistBottomBar(
    media: MediaDetails,
    onAddClick: () -> Unit
) {
    val label = when (media.watchCategory()) {
        WatchCategory.FILMS -> "le film"
        WatchCategory.ANIME -> "l'animé"
        WatchCategory.SERIES -> "la série"
    }
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .background(Color.Transparent),
        contentAlignment = Alignment.Center
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(59.dp)
                .background(Color(0xFFFFD400))
                .clickable(onClick = onAddClick),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = "+ Ajouter $label",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = Color.Black.copy(alpha = 0.78f)
            )
        }
    }
}

@Composable
private fun TvDetailsTabs(
    selected: TvDetailsSection,
    onSelectedChange: (TvDetailsSection) -> Unit
) {
    TabRow(
        selectedTabIndex = selected.ordinal,
        modifier = Modifier
            .fillMaxWidth()
            .background(Color.Black.copy(alpha = 0.42f))
    ) {
        Tab(
            selected = selected == TvDetailsSection.ABOUT,
            onClick = { onSelectedChange(TvDetailsSection.ABOUT) },
            text = { Text("À propos") }
        )
        Tab(
            selected = selected == TvDetailsSection.EPISODES,
            onClick = { onSelectedChange(TvDetailsSection.EPISODES) },
            text = { Text("Épisodes") }
        )
    }
}

@Composable
private fun TvAboutSection(
    media: MediaDetails,
    category: WatchCategory
) {
    val label = if (category == WatchCategory.ANIME) "l'animé" else "la série"
    Column(modifier = Modifier.padding(16.dp)) {
        Text(
            text = "Informations sur $label",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold
        )
        Spacer(Modifier.height(8.dp))
        Text(
            text = media.overview.ifBlank { "Aucun synopsis disponible." },
            style = MaterialTheme.typography.bodyMedium
        )
    }
}

@Composable
private fun MovieInfoStrip(
    releaseDate: String?,
    isWatched: Boolean,
    watchedAtMillis: Long?,
    onWatchedChange: (Boolean) -> Unit
) {
    val releaseLabel = releaseDate?.let { formatIsoDate(it) } ?: "Date inconnue"
    val watchedLabel = if (isWatched) {
        watchedAtMillis?.let { formatMillisDate(it) } ?: "Vu"
    } else {
        "Pas vu"
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f))
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(
            modifier = Modifier.weight(1f),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = Icons.Rounded.CalendarMonth,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(Modifier.size(6.dp))
            Text(releaseLabel, style = MaterialTheme.typography.bodyMedium)
            Spacer(Modifier.size(12.dp))
            Icon(
                imageVector = Icons.Rounded.Visibility,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(Modifier.size(6.dp))
            Text(watchedLabel, style = MaterialTheme.typography.bodyMedium)
        }
        Checkbox(
            checked = isWatched,
            onCheckedChange = onWatchedChange
        )
    }
}

@Composable
private fun MediaHeader(
    media: MediaDetails,
    headerHeight: Dp,
    contentAlpha: Float,
    progressState: DetailsHeaderProgressState?,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(headerHeight)
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
        Column(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(
                text = media.title,
                style = MaterialTheme.typography.headlineMedium,
                color = Color.White.copy(alpha = contentAlpha),
                fontWeight = FontWeight.Bold
            )
            if (media.mediaType == MediaType.TV && contentAlpha > 0.02f) {
            SeriesHeaderSubtitle(
                seasonCount = media.seasons.count { it.seasonNumber != 0 },
                status = media.tvStatus,
                alpha = contentAlpha
            )
            }
        }
        if (progressState != null) {
            LinearProgressIndicator(
                progress = { progressState.progress },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(6.dp)
                    .align(Alignment.BottomCenter),
                color = progressState.color,
                trackColor = Color.Black.copy(alpha = 0.35f)
            )
        }
    }
}

@Composable
private fun DetailsTopActions(
    title: String,
    centeredTitleAlpha: Float,
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
            .windowInsetsPadding(WindowInsets.statusBars)
            .padding(horizontal = 4.dp, vertical = 4.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onBackClick) {
                Icon(
                    Icons.AutoMirrored.Rounded.ArrowBack,
                    contentDescription = "Retour",
                    tint = Color.White
                )
            }
            Box(
                modifier = Modifier
                    .padding(end = 4.dp)
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
                                    "Retirer des suivis"
                                } else {
                                    "Ajouter aux suivis"
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
        if (centeredTitleAlpha > 0f) {
            Text(
                text = title,
                modifier = Modifier
                    .align(Alignment.Center)
                    .padding(horizontal = 64.dp),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = Color.White.copy(alpha = centeredTitleAlpha),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun SeriesHeaderSubtitle(
    seasonCount: Int,
    status: TvStatus?,
    alpha: Float
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(
            text = if (seasonCount <= 1) "1 saison" else "$seasonCount saisons",
            style = MaterialTheme.typography.bodyLarge,
            color = Color.White.copy(alpha = 0.85f * alpha)
        )
        if (status != null) {
            Text(
                text = "•",
                style = MaterialTheme.typography.bodyLarge,
                color = Color.White.copy(alpha = 0.85f * alpha),
                modifier = Modifier.padding(horizontal = 8.dp),
                fontSize = 18.sp,
                lineHeight = 18.sp
            )
            Text(
                text = status.label,
                style = MaterialTheme.typography.bodyLarge,
                color = Color.White.copy(alpha = 0.85f * alpha)
            )
        }
    }
}

private data class DetailsHeaderProgressState(val progress: Float, val color: Color)
private enum class TvDetailsSection { ABOUT, EPISODES }

private fun detailsHeaderProgressState(
    media: MediaDetails,
    isInWatchlist: Boolean,
    watchStatus: WatchStatus?,
    watchedEpisodes: Set<String>
): DetailsHeaderProgressState? {
    if (!isInWatchlist || media.mediaType != MediaType.TV) return null
    val status = watchStatus ?: return null
    if (status == WatchStatus.NOT_STARTED || status == WatchStatus.NOT_WATCHED) return null

    return when (status) {
        WatchStatus.IN_PROGRESS -> {
            val totalEpisodes = media.seasons
                .filter { it.seasonNumber != 0 }
                .sumOf { it.episodeCount }
            val watchedCount = watchedEpisodes.count { key -> !key.startsWith("0_") }
            val progress = if (totalEpisodes > 0) {
                watchedCount.coerceAtMost(totalEpisodes).toFloat() / totalEpisodes.toFloat()
            } else {
                0f
            }
            DetailsHeaderProgressState(progress.coerceIn(0f, 1f), Color(0xFFFFC107))
        }
        WatchStatus.UP_TO_DATE -> DetailsHeaderProgressState(1f, Color(0xFF4CAF50))
        WatchStatus.COMPLETED -> DetailsHeaderProgressState(1f, Color(0xFF9C27B0))
        WatchStatus.WATCHED -> DetailsHeaderProgressState(1f, Color(0xFF9C27B0))
        else -> null
    }
}

private fun formatIsoDate(value: String): String {
    val date = runCatching { LocalDate.parse(value) }.getOrNull() ?: return value
    return date.format(DateTimeFormatter.ofPattern("dd/MM/yyyy"))
}

private fun formatMillisDate(value: Long): String {
    val date = Instant.ofEpochMilli(value).atZone(ZoneId.systemDefault()).toLocalDate()
    return date.format(DateTimeFormatter.ofPattern("dd/MM/yyyy"))
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
                val watchedEpisodePositions = remember(watchedEpisodes) {
                    watchedEpisodes.mapNotNull { parseEpisodePositionKey(it) }.sorted()
                }
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
                            watchedEpisodePositions = watchedEpisodePositions,
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
    watchedEpisodePositions: List<Int>,
    seasonOffset: Int,
    isSpecialSeason: Boolean
) {
    var showDialog by remember { mutableStateOf(false) }
    var showConfirm by remember { mutableStateOf(false) }
    var dialogChecked by remember(isWatched) { mutableStateOf(isWatched) }
    val expectedPreviousCount = seasonOffset + episode.episodeNumber - 1
    val currentEpisodePosition = episodePositionKey(episode.seasonNumber, episode.episodeNumber)
    val watchedPreviousCount = watchedEpisodePositions.countLessThan(currentEpisodePosition)

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
                if (episode.airDate == null || isFutureEpisodeRelease(episode)) {
                    EpisodeReleaseStatus(episode = episode)
                } else {
                    Checkbox(
                        checked = isWatched,
                        onCheckedChange = { target -> requestCheckedChange(target) }
                    )
                }
            }
        }
    }
}

private fun isFutureEpisodeRelease(episode: Episode): Boolean {
    val airDate = episode.airDate?.let { runCatching { LocalDate.parse(it) }.getOrNull() } ?: return false
    return airDate.isAfter(LocalDate.now(ZoneId.systemDefault()))
}

@Composable
private fun EpisodeReleaseStatus(episode: Episode) {
    val today = LocalDate.now(ZoneId.systemDefault())
    val airDate = episode.airDate?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
    if (airDate == null) {
        Column(
            modifier = Modifier.wrapContentWidth(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = "A venir",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center
            )
        }
        return
    }

    val daysUntil = ChronoUnit.DAYS.between(today, airDate).toInt()
    val valueLabel = when {
        daysUntil <= 0 -> "0"
        else -> daysUntil.toString()
    }
    val unitLabel = when {
        daysUntil == 1 -> "jour"
        else -> "jours"
    }
    Column(
        modifier = Modifier.wrapContentWidth(),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = valueLabel,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
            fontSize = 22.sp,
            textAlign = TextAlign.Center
        )
        Text(
            text = unitLabel,
            style = MaterialTheme.typography.bodySmall,
            textAlign = TextAlign.Center
        )
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

private fun parseEpisodePositionKey(key: String): Int? {
    val separatorIndex = key.indexOf('_')
    if (separatorIndex <= 0 || separatorIndex >= key.length - 1) return null
    val seasonNumber = key.substring(0, separatorIndex).toIntOrNull() ?: return null
    val episodeNumber = key.substring(separatorIndex + 1).toIntOrNull() ?: return null
    return episodePositionKey(seasonNumber, episodeNumber)
}

private fun episodePositionKey(seasonNumber: Int, episodeNumber: Int): Int {
    return seasonNumber * 10_000 + episodeNumber
}

private fun List<Int>.countLessThan(value: Int): Int {
    var left = 0
    var right = size
    while (left < right) {
        val mid = (left + right) ushr 1
        if (this[mid] < value) {
            left = mid + 1
        } else {
            right = mid
        }
    }
    return left
}
