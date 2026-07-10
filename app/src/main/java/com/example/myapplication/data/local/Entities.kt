package com.example.myapplication.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "watchlist", primaryKeys = ["id", "mediaType"])
data class WatchlistEntity(
    val id: Int,
    val title: String,
    val posterPath: String?,
    val mediaType: String,
    val contentCategory: String,
    val contentStatus: String,
    val totalEpisodes: Int = 0,
    val addedAt: Long = System.currentTimeMillis()
)

@Entity(tableName = "episode_progress", primaryKeys = ["mediaId", "seasonNumber", "episodeNumber"])
data class EpisodeProgressEntity(
    val mediaId: Int,
    val seasonNumber: Int,
    val episodeNumber: Int,
    val isWatched: Boolean,
    val updatedAt: Long = System.currentTimeMillis()
)

data class WatchlistProgressRow(
    val id: Int,
    val title: String,
    val posterPath: String?,
    val mediaType: String,
    val contentCategory: String,
    val contentStatus: String,
    val totalEpisodes: Int,
    val watchedEpisodes: Int,
    val lastWatchedAt: Long?
)
