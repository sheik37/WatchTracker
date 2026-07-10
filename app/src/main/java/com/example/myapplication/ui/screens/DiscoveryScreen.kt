package com.example.myapplication.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.example.myapplication.data.model.Media

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DiscoveryScreen(
    viewModel: MediaViewModel,
    onMediaClick: (Media) -> Unit
) {
    val mediaList by viewModel.discoveryState.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val errorMessage by viewModel.errorMessage.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Découverte", fontWeight = FontWeight.Bold) },
            )
        },
        contentWindowInsets = WindowInsets.systemBars
    ) { padding ->
        if (errorMessage != null) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = androidx.compose.ui.Alignment.Center) {
                Text(errorMessage!!, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(16.dp))
            }
        } else if (isLoading && mediaList.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = androidx.compose.ui.Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            LazyVerticalGrid(
                columns = GridCells.Adaptive(160.dp),
                contentPadding = PaddingValues(8.dp),
                modifier = Modifier.padding(padding).fillMaxSize(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                items(mediaList, key = { "${it.mediaType.value}_${it.id}" }) { media ->
                    MediaCard(media = media, onClick = { onMediaClick(media) })
                }
            }
        }
    }
}

@Composable
fun MediaCard(
    media: Media,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    showTitle: Boolean = true,
    bottomContent: (@Composable BoxScope.() -> Unit)? = null
) {
    MediaCard(media = media, onClick = onClick, modifier = modifier, actions = null, showTitle = showTitle, bottomContent = bottomContent)
}

@Composable
fun MediaCard(
    media: Media,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    actions: (@Composable BoxScope.() -> Unit)?,
    showTitle: Boolean = true,
    bottomContent: (@Composable BoxScope.() -> Unit)? = null
) {
    Card(
        modifier = modifier
            .fillMaxWidth()
            .aspectRatio(0.7f)
            .clickable(onClick = onClick),
        shape = MaterialTheme.shapes.medium
    ) {
        Box {
            AsyncImage(
                model = media.posterPath,
                contentDescription = media.title,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop
            )
            actions?.invoke(this)
            bottomContent?.invoke(this)
            if (showTitle) {
                Surface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .align(androidx.compose.ui.Alignment.BottomCenter),
                    color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.8f)
                ) {
                    Text(
                        text = media.title,
                        modifier = Modifier.padding(8.dp),
                        style = MaterialTheme.typography.labelMedium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
        }
    }
}
