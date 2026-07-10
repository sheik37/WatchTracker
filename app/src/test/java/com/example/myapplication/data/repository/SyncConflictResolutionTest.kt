package com.example.myapplication.data.repository

import com.example.myapplication.data.api.RemoteEpisodeProgressDto
import com.example.myapplication.data.api.RemoteWatchlistItemDto
import com.example.myapplication.data.local.EpisodeProgressEntity
import com.example.myapplication.data.local.WatchlistEntity
import com.example.myapplication.data.model.MediaType
import com.example.myapplication.data.model.WatchCategory
import com.example.myapplication.data.model.WatchStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SyncConflictResolutionTest {

    @Test
    fun mergeEpisodeProgressByMediaId_unionsEpisodesAndPreservesWatched() {
        val local = mapOf(
            1 to listOf(
                EpisodeProgressEntity(mediaId = 1, seasonNumber = 1, episodeNumber = 1, isWatched = true, updatedAt = 100L),
                EpisodeProgressEntity(mediaId = 1, seasonNumber = 1, episodeNumber = 2, isWatched = false, updatedAt = 100L)
            )
        )
        val remote = mapOf(
            1 to listOf(
                RemoteEpisodeProgressDto(mediaId = 1, seasonNumber = 1, episodeNumber = 2, isWatched = true),
                RemoteEpisodeProgressDto(mediaId = 1, seasonNumber = 1, episodeNumber = 3, isWatched = true)
            )
        )

        val merged = mergeEpisodeProgressByMediaId(local, remote)
        val watchedMap = merged.getValue(1).associateBy { it.seasonNumber to it.episodeNumber }

        assertTrue(watchedMap.getValue(1 to 1).isWatched)
        assertTrue(watchedMap.getValue(1 to 2).isWatched)
        assertTrue(watchedMap.getValue(1 to 3).isWatched)
        assertEquals(3, watchedMap.size)
    }

    @Test
    fun mergeWatchlistEntities_keepsHighestProgressStatusOnConflict() {
        val local = listOf(
            WatchlistEntity(
                id = 42,
                title = "Show",
                posterPath = null,
                mediaType = MediaType.TV.value,
                contentCategory = WatchCategory.SERIES.value,
                contentStatus = WatchStatus.NOT_STARTED.value,
                totalEpisodes = 10
            )
        )
        val remote = listOf(
            RemoteWatchlistItemDto(
                id = 42,
                title = "Show",
                posterPath = null,
                mediaType = MediaType.TV.value,
                contentCategory = WatchCategory.SERIES.value,
                contentStatus = WatchStatus.UP_TO_DATE.value,
                totalEpisodes = 8
            )
        )

        val merged = mergeWatchlistEntities(
            localWatchlist = local,
            remoteWatchlist = remote,
            mergedProgressByMediaId = mapOf(
                42 to (1..5).map { episodeNumber ->
                    EpisodeProgressEntity(
                        mediaId = 42,
                        seasonNumber = 1,
                        episodeNumber = episodeNumber,
                        isWatched = true
                    )
                }
            )
        )

        val item = merged.single()
        assertEquals(10, item.totalEpisodes)
        assertEquals(WatchStatus.UP_TO_DATE.value, item.contentStatus)
    }

    @Test
    fun mergeWatchlistEntities_setsMovieToWatchedWhenAnyWatchedProgressExists() {
        val local = listOf(
            WatchlistEntity(
                id = 7,
                title = "Movie",
                posterPath = null,
                mediaType = MediaType.MOVIE.value,
                contentCategory = WatchCategory.FILMS.value,
                contentStatus = WatchStatus.NOT_WATCHED.value,
                totalEpisodes = 0
            )
        )

        val merged = mergeWatchlistEntities(
            localWatchlist = local,
            remoteWatchlist = emptyList(),
            mergedProgressByMediaId = mapOf(
                7 to listOf(
                    EpisodeProgressEntity(
                        mediaId = 7,
                        seasonNumber = 1,
                        episodeNumber = 1,
                        isWatched = true
                    )
                )
            )
        )

        assertEquals(WatchStatus.WATCHED.value, merged.single().contentStatus)
    }
}

