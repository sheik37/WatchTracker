package com.example.myapplication.data.api

import com.example.myapplication.data.model.AnimeStructureSeed
import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass
import retrofit2.Response
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.PATCH
import retrofit2.http.Path
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Query

interface BackendApiService {
    @POST("auth/register")
    suspend fun register(@Body payload: AuthRequestDto): AuthTokenDto

    @POST("auth/login")
    suspend fun login(@Body payload: AuthRequestDto): AuthTokenDto

    @POST("auth/logout")
    suspend fun logout()

    @GET("watchlist")
    suspend fun getWatchlist(
        @Query("content_category") contentCategory: String? = null
    ): List<RemoteWatchlistItemDto>

    @GET("sync/snapshot")
    suspend fun getSyncSnapshot(): SyncSnapshotDto

    @POST("watchlist")
    suspend fun upsertWatchlist(@Body item: RemoteWatchlistItemDto): RemoteWatchlistItemDto

    @DELETE("watchlist/{media_id}/{media_type}/{content_category}")
    suspend fun deleteWatchlist(
        @Path("media_id") mediaId: Int,
        @Path("media_type") mediaType: String,
        @Path("content_category") contentCategory: String
    )

    @PATCH("watchlist/{media_id}/{media_type}/{content_category}/status")
    suspend fun updateWatchStatus(
        @Path("media_id") mediaId: Int,
        @Path("media_type") mediaType: String,
        @Path("content_category") contentCategory: String,
        @Body payload: WatchStatusUpdateDto
    ): RemoteWatchlistItemDto

    @PATCH("watchlist/{media_id}/{media_type}/{content_category}/total-episodes")
    suspend fun updateWatchTotal(
        @Path("media_id") mediaId: Int,
        @Path("media_type") mediaType: String,
        @Path("content_category") contentCategory: String,
        @Body payload: WatchTotalUpdateDto
    ): RemoteWatchlistItemDto

    @GET("episode-progress/{media_id}")
    suspend fun getEpisodeProgress(@Path("media_id") mediaId: Int): List<RemoteEpisodeProgressDto>

    @PUT("episode-progress/{media_id}")
    suspend fun replaceEpisodeProgress(
        @Path("media_id") mediaId: Int,
        @Body items: List<RemoteEpisodeProgressDto>
    )

    @PUT("anime-structures")
    suspend fun upsertAnimeStructure(@Body item: BackendAnimeStructureDto): Response<Void>
}

@JsonClass(generateAdapter = true)
data class AuthRequestDto(
    val username: String,
    val password: String
)

@JsonClass(generateAdapter = true)
data class AuthTokenDto(
    val token: String
)

@JsonClass(generateAdapter = true)
data class RemoteWatchlistItemDto(
    val id: Int,
    val title: String,
    @Json(name = "poster_path") val posterPath: String? = null,
    @Json(name = "media_type") val mediaType: String,
    @Json(name = "content_category") val contentCategory: String,
    @Json(name = "content_status") val contentStatus: String,
    @Json(name = "total_episodes") val totalEpisodes: Int = 0
)

@JsonClass(generateAdapter = true)
data class WatchStatusUpdateDto(
    @Json(name = "content_status") val contentStatus: String
)

@JsonClass(generateAdapter = true)
data class WatchTotalUpdateDto(
    @Json(name = "total_episodes") val totalEpisodes: Int
)

@JsonClass(generateAdapter = true)
data class RemoteEpisodeProgressDto(
    @Json(name = "media_id") val mediaId: Int? = null,
    @Json(name = "season_number") val seasonNumber: Int,
    @Json(name = "episode_number") val episodeNumber: Int,
    @Json(name = "is_watched") val isWatched: Boolean
)

@JsonClass(generateAdapter = true)
data class SyncSnapshotDto(
    val watchlist: List<RemoteWatchlistItemDto> = emptyList(),
    @Json(name = "episode_progress") val episodeProgress: List<RemoteEpisodeProgressDto> = emptyList()
)

@JsonClass(generateAdapter = true)
data class BackendAnimeStructureDto(
    val title: String,
    val aliases: List<String> = emptyList(),
    val season: String? = null,
    @Json(name = "season_year") val seasonYear: Int? = null,
    val seasons: List<BackendAnimeStructureSeasonDto> = emptyList()
)

@JsonClass(generateAdapter = true)
data class BackendAnimeStructureSeasonDto(
    @Json(name = "season_number") val seasonNumber: Int,
    val name: String,
    @Json(name = "start_episode") val startEpisode: Int,
    @Json(name = "end_episode") val endEpisode: Int
)

fun AnimeStructureSeed.toBackendDto(): BackendAnimeStructureDto {
    return BackendAnimeStructureDto(
        title = title,
        aliases = aliases,
        season = season,
        seasonYear = seasonYear,
        seasons = seasons.map {
            BackendAnimeStructureSeasonDto(
                seasonNumber = it.seasonNumber,
                name = it.name,
                startEpisode = it.startEpisode,
                endEpisode = it.endEpisode
            )
        }
    )
}
