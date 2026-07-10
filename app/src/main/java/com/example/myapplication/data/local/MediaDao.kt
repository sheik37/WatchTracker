package com.example.myapplication.data.local

import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Dao
interface MediaDao {
    @Query("""
        SELECT
            w.id,
            w.title,
            w.posterPath,
            w.mediaType,
            w.contentCategory,
            w.contentStatus,
            w.totalEpisodes,
            COUNT(CASE WHEN p.isWatched = 1 THEN 1 END) AS watchedEpisodes,
            MAX(CASE WHEN p.isWatched = 1 THEN p.updatedAt END) AS lastWatchedAt
        FROM watchlist w
        LEFT JOIN episode_progress p
            ON p.mediaId = w.id
        WHERE w.contentCategory = :category
        GROUP BY w.id, w.title, w.posterPath, w.mediaType, w.contentCategory, w.contentStatus, w.totalEpisodes, w.addedAt
        ORDER BY w.addedAt DESC
    """)
    fun getWatchlist(category: String): Flow<List<WatchlistProgressRow>>

    @Query("SELECT * FROM watchlist")
    suspend fun getAllWatchlist(): List<WatchlistEntity>

    @Query("DELETE FROM watchlist")
    suspend fun clearWatchlist()

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun addToWatchlist(entity: WatchlistEntity)

    @Delete
    suspend fun removeFromWatchlist(entity: WatchlistEntity)

    @Query("UPDATE watchlist SET contentStatus = :status WHERE id = :id AND mediaType = :type AND contentCategory = :category")
    suspend fun updateWatchStatus(id: Int, type: String, category: String, status: String)

    @Query("UPDATE watchlist SET totalEpisodes = :totalEpisodes WHERE id = :id AND mediaType = :type AND contentCategory = :category")
    suspend fun updateWatchProgressTotal(id: Int, type: String, category: String, totalEpisodes: Int)

    @Query("SELECT EXISTS(SELECT 1 FROM watchlist WHERE id = :id AND mediaType = :type AND contentCategory = :category)")
    suspend fun isInWatchlist(id: Int, type: String, category: String): Boolean

    @Query("SELECT contentStatus FROM watchlist WHERE id = :id AND mediaType = :type AND contentCategory = :category LIMIT 1")
    suspend fun getWatchStatus(id: Int, type: String, category: String): String?

    @Query("SELECT * FROM episode_progress WHERE mediaId = :mediaId")
    fun getEpisodeProgress(mediaId: Int): Flow<List<EpisodeProgressEntity>>

    @Query("SELECT * FROM episode_progress")
    suspend fun getAllEpisodeProgress(): List<EpisodeProgressEntity>

    @Query("DELETE FROM episode_progress")
    suspend fun clearAllEpisodeProgress()

    @Query("DELETE FROM episode_progress WHERE mediaId = :mediaId")
    suspend fun clearEpisodeProgress(mediaId: Int)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun updateEpisodeProgress(entity: EpisodeProgressEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun updateEpisodeProgress(entities: List<EpisodeProgressEntity>)
}
