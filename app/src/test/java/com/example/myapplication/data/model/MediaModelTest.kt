package com.example.myapplication.data.model

import org.junit.Assert.assertEquals
import org.junit.Test

class MediaModelTest {

    @Test
    fun mediaType_fromString_defaultsToMovie() {
        assertEquals(MediaType.MOVIE, MediaType.fromString("unknown"))
        assertEquals(MediaType.MOVIE, MediaType.fromString(null))
    }

    @Test
    fun watchCategory_fromString_defaultsToSeries() {
        assertEquals(WatchCategory.SERIES, WatchCategory.fromString("invalid"))
        assertEquals(WatchCategory.SERIES, WatchCategory.fromString(null))
    }

    @Test
    fun watchStatus_fromString_defaultsToNotStarted() {
        assertEquals(WatchStatus.NOT_STARTED, WatchStatus.fromString("invalid"))
        assertEquals(WatchStatus.NOT_STARTED, WatchStatus.fromString(null))
    }

    @Test
    fun mediaDto_toDomain_mapsFallbacksAndImageUrls() {
        val dto = MediaDto(
            id = 7,
            title = null,
            name = "Nom TV",
            posterPath = "/poster.jpg",
            backdropPath = "/backdrop.jpg",
            overview = null,
            releaseDate = null,
            firstAirDate = "2024-03-01",
            voteAverage = null,
            genreIds = listOf(16, 35),
            mediaType = "tv"
        )

        val media = dto.toDomain()

        assertEquals(7, media.id)
        assertEquals("Nom TV", media.title)
        assertEquals("https://image.tmdb.org/t/p/w500/poster.jpg", media.posterPath)
        assertEquals("https://image.tmdb.org/t/p/w780/backdrop.jpg", media.backdropPath)
        assertEquals("", media.overview)
        assertEquals("2024-03-01", media.releaseDate)
        assertEquals(0.0, media.voteAverage, 0.0)
        assertEquals(MediaType.TV, media.mediaType)
        assertEquals(listOf(16, 35), media.genreIds)
    }

    @Test
    fun mediaDto_toDomain_honorsForcedType() {
        val dto = MediaDto(
            id = 10,
            title = "Film",
            name = null,
            posterPath = null,
            backdropPath = null,
            overview = "overview",
            releaseDate = "2025-01-01",
            firstAirDate = null,
            voteAverage = 7.2,
            mediaType = "tv"
        )

        val media = dto.toDomain(forceType = MediaType.MOVIE)

        assertEquals(MediaType.MOVIE, media.mediaType)
    }
}

