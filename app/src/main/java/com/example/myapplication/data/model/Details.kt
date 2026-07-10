package com.example.myapplication.data.model

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class GenreDto(
    val id: Int,
    val name: String
)

@JsonClass(generateAdapter = true)
data class MovieDetailsDto(
    val id: Int,
    val title: String,
    @Json(name = "poster_path") val posterPath: String?,
    @Json(name = "backdrop_path") val backdropPath: String?,
    val overview: String,
    @Json(name = "release_date") val releaseDate: String?,
    @Json(name = "vote_average") val voteAverage: Double,
    val runtime: Int?,
    @Json(name = "genres") val genres: List<GenreDto> = emptyList()
)

@JsonClass(generateAdapter = true)
data class TvDetailsDto(
    val id: Int,
    val name: String,
    @Json(name = "poster_path") val posterPath: String?,
    @Json(name = "backdrop_path") val backdropPath: String?,
    val overview: String,
    @Json(name = "first_air_date") val firstAirDate: String?,
    @Json(name = "vote_average") val voteAverage: Double,
    @Json(name = "status") val status: String? = null,
    val seasons: List<SeasonDto>,
    @Json(name = "genres") val genres: List<GenreDto> = emptyList()
)

@JsonClass(generateAdapter = true)
data class SeasonDto(
    val id: Int,
    val name: String,
    @Json(name = "overview") val overview: String,
    @Json(name = "poster_path") val posterPath: String?,
    @Json(name = "season_number") val seasonNumber: Int,
    @Json(name = "episode_count") val episodeCount: Int
)

@JsonClass(generateAdapter = true)
data class SeasonDetailsDto(
    val id: Int,
    @Json(name = "season_number") val seasonNumber: Int,
    val episodes: List<EpisodeDto>
)

@JsonClass(generateAdapter = true)
data class EpisodeDto(
    val id: Int,
    val name: String,
    val overview: String,
    @Json(name = "episode_number") val episodeNumber: Int,
    @Json(name = "season_number") val seasonNumber: Int,
    @Json(name = "still_path") val stillPath: String?,
    @Json(name = "air_date") val airDate: String?,
    @Json(name = "runtime") val runtime: Int? = null
)

data class MediaDetails(
    val id: Int,
    val title: String,
    val overview: String,
    val posterPath: String?,
    val backdropPath: String?,
    val releaseDate: String?,
    val voteAverage: Double,
    val mediaType: MediaType,
    val tvStatus: TvStatus? = null,
    val genres: List<String> = emptyList(),
    val seasons: List<Season> = emptyList()
)

data class Season(
    val id: Int,
    val name: String,
    val seasonNumber: Int,
    val episodeCount: Int = 0,
    val episodes: List<Episode> = emptyList()
)

data class Episode(
    val id: Int,
    val name: String,
    val overview: String,
    val episodeNumber: Int,
    val seasonNumber: Int,
    val stillPath: String?,
    val airDate: String? = null,
    val runtime: Int? = null,
    val isWatched: Boolean = false
)

fun MovieDetailsDto.toDomain() = MediaDetails(
    id = id,
    title = title,
    overview = overview,
    posterPath = posterPath?.let { "https://image.tmdb.org/t/p/w500$it" },
    backdropPath = backdropPath?.let { "https://image.tmdb.org/t/p/w780$it" },
    releaseDate = releaseDate,
    voteAverage = voteAverage,
    mediaType = MediaType.MOVIE,
    genres = genres.map { it.name }
)

fun TvDetailsDto.toDomain() = MediaDetails(
    id = id,
    title = name,
    overview = overview,
    posterPath = posterPath?.let { "https://image.tmdb.org/t/p/w500$it" },
    backdropPath = backdropPath?.let { "https://image.tmdb.org/t/p/w780$it" },
    releaseDate = firstAirDate,
    voteAverage = voteAverage,
    mediaType = MediaType.TV,
    tvStatus = TvStatus.fromApiValue(status),
    genres = genres.map { it.name },
    seasons = seasons.map { it.toDomain() }
)

fun SeasonDto.toDomain() = Season(
    id = id,
    name = name,
    seasonNumber = seasonNumber,
    episodeCount = episodeCount
)

fun EpisodeDto.toDomain() = Episode(
    id = id,
    name = name,
    overview = overview,
    episodeNumber = episodeNumber,
    seasonNumber = seasonNumber,
    stillPath = stillPath?.let { "https://image.tmdb.org/t/p/w300$it" },
    airDate = airDate,
    runtime = runtime
)

fun MediaDetails.watchCategory() = when {
    mediaType == MediaType.MOVIE -> WatchCategory.FILMS
    genres.any { it.equals("Animation", ignoreCase = true) || it.contains("anime", ignoreCase = true) } -> WatchCategory.ANIME
    else -> WatchCategory.SERIES
}

fun WatchCategory.defaultStatus() = when (this) {
    WatchCategory.SERIES, WatchCategory.ANIME -> WatchStatus.NOT_STARTED
    WatchCategory.FILMS -> WatchStatus.NOT_WATCHED
}

fun WatchCategory.statuses() = when (this) {
    WatchCategory.SERIES, WatchCategory.ANIME -> listOf(
        WatchStatus.NOT_STARTED,
        WatchStatus.IN_PROGRESS,
        WatchStatus.UP_TO_DATE,
        WatchStatus.COMPLETED
    )
    WatchCategory.FILMS -> listOf(
        WatchStatus.NOT_WATCHED,
        WatchStatus.WATCHED
    )
}

enum class TvStatus(val apiValue: String, val label: String) {
    RETURNING_SERIES("Returning Series", "Série en cours"),
    ENDED("Ended", "Terminée"),
    CANCELED("Canceled", "Annulée"),
    PLANNED("Planned", "Prévue"),
    IN_PRODUCTION("In Production", "En production");

    companion object {
        fun fromApiValue(value: String?): TvStatus? = entries.find { it.apiValue.equals(value, ignoreCase = true) }
    }
}
