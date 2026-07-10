package com.example.myapplication.data.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DetailsModelTest {

    @Test
    fun movieDetailsDto_toDomain_mapsFieldsAndGenres() {
        val dto = MovieDetailsDto(
            id = 42,
            title = "Interstellar",
            posterPath = "/p.jpg",
            backdropPath = "/b.jpg",
            overview = "space",
            releaseDate = "2014-11-05",
            voteAverage = 8.7,
            runtime = 169,
            genres = listOf(GenreDto(1, "Science-Fiction"), GenreDto(2, "Drame"))
        )

        val details = dto.toDomain()

        assertEquals(MediaType.MOVIE, details.mediaType)
        assertEquals("Interstellar", details.title)
        assertEquals("https://image.tmdb.org/t/p/w500/p.jpg", details.posterPath)
        assertEquals("https://image.tmdb.org/t/p/w780/b.jpg", details.backdropPath)
        assertEquals(listOf("Science-Fiction", "Drame"), details.genres)
    }

    @Test
    fun tvDetailsDto_toDomain_mapsStatusAndSeasons() {
        val dto = TvDetailsDto(
            id = 11,
            name = "Mon Anime",
            posterPath = null,
            backdropPath = null,
            overview = "desc",
            firstAirDate = "2023-04-10",
            voteAverage = 7.1,
            status = "Ended",
            seasons = listOf(
                SeasonDto(
                    id = 101,
                    name = "Season 1",
                    overview = "",
                    posterPath = null,
                    seasonNumber = 1,
                    episodeCount = 12
                )
            ),
            genres = listOf(GenreDto(16, "Animation"))
        )

        val details = dto.toDomain()

        assertEquals(MediaType.TV, details.mediaType)
        assertEquals(TvStatus.ENDED, details.tvStatus)
        assertEquals(1, details.seasons.size)
        assertEquals("Animation", details.genres.first())
    }

    @Test
    fun episodeDto_toDomain_mapsStillPath() {
        val dto = EpisodeDto(
            id = 2,
            name = "Episode 2",
            overview = "desc",
            episodeNumber = 2,
            seasonNumber = 1,
            stillPath = "/still.jpg",
            airDate = "2024-01-02",
            runtime = 24
        )

        val episode = dto.toDomain()

        assertEquals("https://image.tmdb.org/t/p/w300/still.jpg", episode.stillPath)
        assertEquals(24, episode.runtime)
    }

    @Test
    fun watchCategory_detectsAnimeAndFilms() {
        val movie = MediaDetails(
            id = 1,
            title = "Film",
            overview = "",
            posterPath = null,
            backdropPath = null,
            releaseDate = null,
            voteAverage = 0.0,
            mediaType = MediaType.MOVIE
        )
        val anime = MediaDetails(
            id = 2,
            title = "Anime",
            overview = "",
            posterPath = null,
            backdropPath = null,
            releaseDate = null,
            voteAverage = 0.0,
            mediaType = MediaType.TV,
            genres = listOf("Animation")
        )
        val series = anime.copy(genres = listOf("Drama"))

        assertEquals(WatchCategory.FILMS, movie.watchCategory())
        assertEquals(WatchCategory.ANIME, anime.watchCategory())
        assertEquals(WatchCategory.SERIES, series.watchCategory())
    }

    @Test
    fun watchCategory_defaultStatus_andStatuses_areCorrect() {
        assertEquals(WatchStatus.NOT_WATCHED, WatchCategory.FILMS.defaultStatus())
        assertEquals(WatchStatus.NOT_STARTED, WatchCategory.SERIES.defaultStatus())
        assertEquals(
            listOf(WatchStatus.NOT_WATCHED, WatchStatus.WATCHED),
            WatchCategory.FILMS.statuses()
        )
        assertEquals(
            listOf(
                WatchStatus.NOT_STARTED,
                WatchStatus.IN_PROGRESS,
                WatchStatus.UP_TO_DATE,
                WatchStatus.COMPLETED
            ),
            WatchCategory.ANIME.statuses()
        )
    }

    @Test
    fun tvStatus_fromApiValue_isCaseInsensitive() {
        assertEquals(TvStatus.RETURNING_SERIES, TvStatus.fromApiValue("returning series"))
        assertNull(TvStatus.fromApiValue("unknown"))
    }
}

