package com.example.myapplication.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items as lazyItems
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Card
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import coil.compose.rememberAsyncImagePainter
import com.example.myapplication.data.model.Media

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SearchScreen(
    viewModel: MediaViewModel,
    onMediaClick: (Media) -> Unit
) {
    var query by remember { mutableStateOf("") }
    val discoveryResults by viewModel.discoveryState.collectAsState()
    val searchResults by viewModel.searchState.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val errorMessage by viewModel.errorMessage.collectAsState()
    val trackedMediaKeys by viewModel.trackedMediaKeys.collectAsState()

    val isSearching = query.isNotBlank()
    val displayedMedia = if (isSearching) searchResults else discoveryResults

    LaunchedEffect(Unit) {
        viewModel.loadDiscovery()
    }

    LaunchedEffect(searchResults) {
        if (isSearching) {
            viewModel.refreshTrackedMedia(searchResults)
        }
    }

    Scaffold(
        topBar = {
            TextField(
                value = query,
                onValueChange = {
                    query = it
                    viewModel.search(it)
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .statusBarsPadding()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                placeholder = { Text("Rechercher des films, séries...") },
                leadingIcon = { Icon(Icons.Rounded.Search, contentDescription = null) },
                trailingIcon = {
                    if (query.isNotBlank()) {
                        IconButton(onClick = {
                            query = ""
                            viewModel.search("")
                            viewModel.loadDiscovery()
                        }) {
                            Icon(Icons.Rounded.Close, contentDescription = "Effacer la recherche")
                        }
                    }
                },
                shape = MaterialTheme.shapes.large,
                colors = TextFieldDefaults.colors(
                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent
                )
            )
        }
    ) { padding ->
        if (errorMessage != null) {
            Box(
                Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    errorMessage!!,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(16.dp)
                )
            }
        } else if (isSearching && !isLoading && searchResults.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(
                    "Il n'y a aucun résultat pour cette recherche",
                    style = MaterialTheme.typography.bodyLarge,
                    modifier = Modifier.padding(16.dp)
                )
            }
        } else if (isLoading && displayedMedia.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            if (isSearching) {
                LazyColumn(
                    contentPadding = PaddingValues(8.dp),
                    modifier = Modifier
                        .padding(padding)
                        .fillMaxSize(),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    lazyItems(displayedMedia, key = { "${it.mediaType.value}_${it.id}" }) { media ->
                        SearchMediaRow(
                            media = media,
                            isTracked = trackedMediaKeys.contains("${media.mediaType.value}_${media.id}"),
                            onMediaClick = onMediaClick,
                            onToggleFollow = { tracked -> viewModel.toggleFollowMedia(media, tracked) }
                        )
                    }
                }
            } else {
                LazyVerticalGrid(
                    columns = GridCells.Fixed(3),
                    contentPadding = PaddingValues(8.dp),
                    modifier = Modifier
                        .padding(padding)
                        .fillMaxSize(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    items(displayedMedia, key = { "${it.mediaType.value}_${it.id}" }) { media ->
                        SearchMediaCard(
                            media = media,
                            isTracked = trackedMediaKeys.contains("${media.mediaType.value}_${media.id}"),
                            onMediaClick = onMediaClick,
                            onToggleFollow = { tracked -> viewModel.toggleFollowMedia(media, tracked) }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun SearchMediaCard(
    media: Media,
    isTracked: Boolean,
    onMediaClick: (Media) -> Unit,
    onToggleFollow: (Boolean) -> Unit
) {
    MediaCard(
        media = media,
        onClick = { onMediaClick(media) },
        showTitle = false,
        actions = {
            FollowCheckbox(
                checked = isTracked,
                onClick = { onToggleFollow(isTracked) },
                modifier = Modifier.align(Alignment.TopEnd)
            )
        }
    )
}

@Composable
private fun SearchMediaRow(
    media: Media,
    isTracked: Boolean,
    onMediaClick: (Media) -> Unit,
    onToggleFollow: (Boolean) -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = { onMediaClick(media) }),
        shape = MaterialTheme.shapes.medium
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Box(
                modifier = Modifier.size(width = 54.dp, height = 76.dp)
            ) {
                AsyncImage(
                    model = media.posterPath,
                    contentDescription = media.title,
                    modifier = Modifier.fillMaxSize()
                )
            }
            Column(
                modifier = Modifier.weight(1f)
            ) {
                Text(
                    text = media.title,
                    style = MaterialTheme.typography.titleMedium,
                    maxLines = 2
                )
            }
            FollowCheckbox(
                checked = isTracked,
                onClick = { onToggleFollow(isTracked) }
            )
        }
    }
}

@Composable
private fun FollowCheckbox(
    checked: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val shape = RoundedCornerShape(8.dp)
    val background = if (checked) {
        Color(0xFFFFD400)
    } else {
        Color.Black.copy(alpha = 0.45f)
    }
    val borderColor = if (checked) {
        Color.Black.copy(alpha = 0.65f)
    } else {
        Color(0xFFFFD400).copy(alpha = 0.85f)
    }
    val iconColor = if (checked) {
        Color.Black.copy(alpha = 0.75f)
    } else {
        Color(0xFFFFD400)
    }
    Box(
        modifier = modifier
            .padding(top = 10.dp, end = 10.dp)
            .size(34.dp)
            .clip(shape)
            .background(background)
            .border(1.5.dp, borderColor, shape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = if (checked) Icons.Rounded.Check else Icons.Rounded.Close,
            contentDescription = if (checked) "Déjà suivi" else "Suivre",
            tint = iconColor,
            modifier = Modifier.size(20.dp)
        )
    }
}
