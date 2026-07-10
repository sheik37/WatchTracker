package com.example.myapplication.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.myapplication.data.model.Media
import com.example.myapplication.data.model.WatchCategory
import com.example.myapplication.data.model.WatchStatus
import com.example.myapplication.data.model.WatchlistItem
import com.example.myapplication.data.model.statuses
import java.util.concurrent.TimeUnit

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WatchlistScreen(
    viewModel: WatchlistViewModel,
    category: WatchCategory,
    onMediaClick: (Media) -> Unit
) {
    val watchlist by viewModel.watchlist(category).collectAsState()
    val availableStatuses = category.statuses()
    val expandedStates = remember(category) {
        mutableStateMapOf<WatchStatus, Boolean>().apply {
            availableStatuses.forEach { put(it, true) }
        }
    }
    val staleSectionLabel = "Pas regardé depuis un moment"
    val staleItems = remember(watchlist, category) {
        if (category == WatchCategory.FILMS) {
            emptyList()
        } else {
            watchlist.filter { it.isStale() }
        }
    }
    val regularItems = remember(watchlist, staleItems) {
        watchlist.filterNot { staleItems.contains(it) }
    }
    val staleExpanded = remember(category) { mutableStateOf(true) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(category.label, fontWeight = FontWeight.Bold) },
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(bottom = 16.dp)
        ) {
            if (category != WatchCategory.FILMS) {
                item {
                    Column(modifier = Modifier.fillMaxWidth()) {
                        SectionHeader(
                            title = staleSectionLabel,
                            expanded = staleExpanded.value,
                            onToggle = { staleExpanded.value = !staleExpanded.value }
                        )
                        if (staleExpanded.value) {
                            if (staleItems.isEmpty()) {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(horizontal = 16.dp, vertical = 12.dp),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text("Aucun titre dans cette sous-liste", style = MaterialTheme.typography.bodyMedium)
                                }
                            } else {
                                SectionGrid(
                                    items = staleItems,
                                    onMediaClick = onMediaClick
                                )
                            }
                        }
                    }
                }
            }

            items(availableStatuses.size) { index ->
                val status = availableStatuses[index]
                val sectionItems = regularItems.filter { it.status == status }
                val expanded = expandedStates[status] ?: true

                Column(modifier = Modifier.fillMaxWidth()) {
                    SectionHeader(
                        title = status.label,
                        expanded = expanded,
                        onToggle = { expandedStates[status] = !expanded }
                    )
                    if (expanded) {
                        if (sectionItems.isEmpty()) {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 16.dp, vertical = 12.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                Text("Aucun titre dans cette sous-liste", style = MaterialTheme.typography.bodyMedium)
                            }
                        } else {
                            SectionGrid(
                                items = sectionItems,
                                onMediaClick = onMediaClick
                            )
                        }
                    }
                }
            }
        }
    }
}

private fun WatchlistItem.isStale(): Boolean {
    val watchedAt = lastWatchedAt ?: return false
    if (watchedEpisodes <= 0) return false
    val thirtyDaysMs = TimeUnit.DAYS.toMillis(30)
    return System.currentTimeMillis() - watchedAt > thirtyDaysMs
}

@Composable
private fun SectionHeader(
    title: String,
    expanded: Boolean,
    onToggle: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onToggle)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(text = title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
        Spacer(Modifier.weight(1f))
        Icon(
            imageVector = if (expanded) Icons.Rounded.KeyboardArrowUp else Icons.Rounded.KeyboardArrowDown,
            contentDescription = if (expanded) "Réduire" else "Développer"
        )
    }
}

@Composable
private fun SectionGrid(
    items: List<WatchlistItem>,
    onMediaClick: (Media) -> Unit
) {
    Column(modifier = Modifier.padding(horizontal = 8.dp)) {
        items.chunked(3).forEach { rowItems ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                rowItems.forEach { item ->
                    WatchlistCard(
                        item = item,
                        onMediaClick = onMediaClick
                    )
                }
                if (rowItems.size < 3) {
                    repeat(3 - rowItems.size) {
                        Spacer(modifier = Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

@Composable
private fun RowScope.WatchlistCard(
    item: WatchlistItem,
    onMediaClick: (Media) -> Unit
) {
    val media = item.media
    val progressState = item.progressState()
    MediaCard(
        media = media,
        onClick = { onMediaClick(media) },
        modifier = Modifier.weight(1f),
        showTitle = false,
        bottomContent = {
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
    )
}

private data class ProgressState(val progress: Float, val color: Color)

private fun WatchlistItem.progressState(): ProgressState? {
    if (status == WatchStatus.NOT_STARTED || status == WatchStatus.NOT_WATCHED) {
        return null
    }

    return when (status) {
        WatchStatus.IN_PROGRESS -> {
            val progress = if (totalEpisodes > 0) {
                watchedEpisodes.coerceAtMost(totalEpisodes).toFloat() / totalEpisodes.toFloat()
            } else {
                0f
            }
            ProgressState(progress.coerceIn(0f, 1f), Color(0xFFFFC107))
        }
        WatchStatus.UP_TO_DATE -> ProgressState(1f, Color(0xFF4CAF50))
        WatchStatus.COMPLETED -> ProgressState(1f, Color(0xFF9C27B0))
        WatchStatus.WATCHED -> ProgressState(1f, Color(0xFF9C27B0))
        else -> null
    }
}
