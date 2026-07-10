package com.example.myapplication.data.model

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class MediaResponse(
    val page: Int,
    val results: List<MediaDto>,
    @Json(name = "total_pages") val totalPages: Int,
    @Json(name = "total_results") val totalResults: Int
)

@JsonClass(generateAdapter = true)
data class MediaDto(
    val id: Int,
    val title: String?,
    val name: String?,
    @Json(name = "poster_path") val posterPath: String?,
    @Json(name = "backdrop_path") val backdropPath: String?,
    @Json(name = "overview") val overview: String?,
    @Json(name = "release_date") val releaseDate: String?,
    @Json(name = "first_air_date") val firstAirDate: String?,
    @Json(name = "vote_average") val voteAverage: Double? = null,
    @Json(name = "genre_ids") val genreIds: List<Int> = emptyList(),
    @Json(name = "media_type") val mediaType: String?
)

enum class MediaType(val value: String) {
    MOVIE("movie"),
    TV("tv");

    companion object {
        fun fromString(value: String?) = entries.find { it.value == value } ?: MOVIE
    }
}

enum class WatchCategory(val value: String, val label: String) {
    SERIES("series", "Séries"),
    FILMS("films", "Films"),
    ANIME("anime", "Animé");

    companion object {
        fun fromString(value: String?) = entries.find { it.value == value } ?: SERIES
    }
}

enum class WatchStatus(val value: String, val label: String) {
    NOT_STARTED("not_started", "Pas commencé"),
    IN_PROGRESS("in_progress", "En cours"),
    UP_TO_DATE("up_to_date", "À jour"),
    COMPLETED("completed", "Terminées"),
    WATCHED("watched", "Vu"),
    NOT_WATCHED("not_watched", "Pas encore vu");

    companion object {
        fun fromString(value: String?) = entries.find { it.value == value } ?: NOT_STARTED
    }
}

data class Media(
    val id: Int,
    val title: String,
    val posterPath: String?,
    val backdropPath: String?,
    val overview: String,
    val releaseDate: String?,
    val voteAverage: Double,
    val mediaType: MediaType,
    val genreIds: List<Int> = emptyList()
)

data class WatchlistItem(
    val media: Media,
    val status: WatchStatus,
    val watchedEpisodes: Int = 0,
    val totalEpisodes: Int = 0,
    val lastWatchedAt: Long? = null
)

fun MediaDto.toDomain(forceType: MediaType? = null): Media {
    return Media(
        id = id,
        title = title ?: name ?: "Unknown",
        posterPath = posterPath?.let { "https://image.tmdb.org/t/p/w500$it" },
        backdropPath = backdropPath?.let { "https://image.tmdb.org/t/p/w780$it" },
        overview = overview.orEmpty(),
        releaseDate = releaseDate ?: firstAirDate,
        voteAverage = voteAverage ?: 0.0,
        mediaType = forceType ?: MediaType.fromString(mediaType),
        genreIds = genreIds
    )
}
