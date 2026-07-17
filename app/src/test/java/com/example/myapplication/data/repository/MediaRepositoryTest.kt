package com.example.myapplication.data.repository

import com.example.myapplication.data.api.AniListClient
import com.example.myapplication.data.api.TmdbApiService
import com.example.myapplication.data.local.AnimeStructureDao
import com.example.myapplication.data.local.AnimeStructureEntity
import com.example.myapplication.data.local.EpisodeProgressEntity
import com.example.myapplication.data.local.MediaDao
import com.example.myapplication.data.local.WatchlistEntity
import com.example.myapplication.data.local.WatchlistProgressRow
import com.example.myapplication.data.model.GenreDto
import com.example.myapplication.data.model.Media
import com.example.myapplication.data.model.MediaDetails
import com.example.myapplication.data.model.MediaDto
import com.example.myapplication.data.model.MediaResponse
import com.example.myapplication.data.model.MediaType
import com.example.myapplication.data.model.MovieDetailsDto
import com.example.myapplication.data.model.SeasonDetailsDto
import com.example.myapplication.data.model.TvDetailsDto
import com.example.myapplication.data.model.WatchCategory
import com.example.myapplication.data.model.WatchStatus
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class MediaRepositoryTest {

    @Test
    fun getDiscoveryMedia_prioritizesPreferredGenresThenVoteAverage() = runTest {
        val dao = FakeMediaDao().apply {
            addToWatchlist(
                WatchlistEntity(
                    id = 100,
                    title = "Existing",
                    posterPath = null,
                    mediaType = MediaType.MOVIE.value,
                    contentCategory = WatchCategory.FILMS.value,
                    contentStatus = WatchStatus.NOT_WATCHED.value
                )
            )
        }
        val tmdb = FakeTmdbApiService().apply {
            movieDetailsById[100] = MovieDetailsDto(
                id = 100,
                title = "Existing",
                posterPath = null,
                backdropPath = null,
                overview = "",
                releaseDate = "2020-01-01",
                voteAverage = 1.0,
                runtime = 100,
                genres = listOf(GenreDto(1, "Animation"))
            )
            upcoming = mediaResponse(
                MediaDto(id = 1, title = "A", name = null, posterPath = null, backdropPath = null, overview = "", releaseDate = null, firstAirDate = null, voteAverage = 5.0, genreIds = listOf(1), mediaType = "movie"),
                MediaDto(id = 2, title = "B", name = null, posterPath = null, backdropPath = null, overview = "", releaseDate = null, firstAirDate = null, voteAverage = 9.0, genreIds = listOf(2), mediaType = "movie")
            )
            onTheAir = mediaResponse(
                MediaDto(id = 3, title = null, name = "C", posterPath = null, backdropPath = null, overview = "", releaseDate = null, firstAirDate = null, voteAverage = 8.0, genreIds = listOf(1, 2), mediaType = "tv")
            )
        }
        val repository = createRepository(tmdb = tmdb, mediaDao = dao)

        val discovery = repository.getDiscoveryMedia()

        assertEquals(listOf(3, 1, 2), discovery.map { it.id })
    }

    @Test
    fun addToWatchlist_persistsEntity() = runTest {
        val dao = FakeMediaDao()
        val repository = createRepository(mediaDao = dao)
        val media = Media(
            id = 5,
            title = "Film X",
            posterPath = "/x.jpg",
            backdropPath = null,
            overview = "",
            releaseDate = null,
            voteAverage = 6.0,
            mediaType = MediaType.MOVIE
        )

        repository.addToWatchlist(
            media = media,
            category = WatchCategory.FILMS,
            status = WatchStatus.WATCHED,
            totalEpisodes = 1
        )

        val stored = dao.getAllWatchlist().single()
        assertEquals(5, stored.id)
        assertEquals("films", stored.contentCategory)
        assertEquals("watched", stored.contentStatus)
        assertEquals(1, stored.totalEpisodes)
    }

    @Test
    fun getWatchlist_mapsMovieProgressFromStatus() = runTest {
        val dao = FakeMediaDao().apply {
            addToWatchlist(
                WatchlistEntity(
                    id = 9,
                    title = "Film Y",
                    posterPath = null,
                    mediaType = MediaType.MOVIE.value,
                    contentCategory = WatchCategory.FILMS.value,
                    contentStatus = WatchStatus.WATCHED.value,
                    totalEpisodes = 0
                )
            )
        }
        val repository = createRepository(mediaDao = dao)

        val watchlist = repository.getWatchlist(WatchCategory.FILMS).first()

        assertEquals(1, watchlist.size)
        assertEquals(1, watchlist.first().watchedEpisodes)
        assertEquals(1, watchlist.first().totalEpisodes)
    }

    @Test
    fun register_withoutBackendUrl_throwsError() = runTest {
        val repository = createRepository()

        try {
            repository.register("user", "pass")
            fail("Expected IllegalStateException")
        } catch (e: IllegalStateException) {
            assertTrue(e.message?.contains("not configured") == true)
        }
    }

    private fun createRepository(
        tmdb: FakeTmdbApiService = FakeTmdbApiService(),
        mediaDao: FakeMediaDao = FakeMediaDao(),
        animeDao: FakeAnimeStructureDao = FakeAnimeStructureDao()
    ): MediaRepository {
        return MediaRepository(
            apiService = tmdb,
            aniListClient = AniListClient(OkHttpClient()),
            mediaDao = mediaDao,
            animeStructureDao = animeDao
        )
    }

    private fun mediaResponse(vararg items: MediaDto): MediaResponse {
        return MediaResponse(
            page = 1,
            results = items.toList(),
            totalPages = 1,
            totalResults = items.size
        )
    }
}

private class FakeTmdbApiService : TmdbApiService {
    var search: MediaResponse = MediaResponse(1, emptyList(), 1, 0)
    var upcoming: MediaResponse = MediaResponse(1, emptyList(), 1, 0)
    var onTheAir: MediaResponse = MediaResponse(1, emptyList(), 1, 0)
    val movieDetailsById: MutableMap<Int, MovieDetailsDto> = mutableMapOf()
    val tvDetailsById: MutableMap<Int, TvDetailsDto> = mutableMapOf()
    val seasonDetailsByKey: MutableMap<Pair<Int, Int>, SeasonDetailsDto> = mutableMapOf()

    override suspend fun searchMulti(query: String, page: Int): MediaResponse = search

    override suspend fun getUpcomingMovies(page: Int): MediaResponse = upcoming

    override suspend fun getOnTheAirTv(page: Int): MediaResponse = onTheAir

    override suspend fun getMovieDetails(movieId: Int): MovieDetailsDto {
        return movieDetailsById[movieId]
            ?: MovieDetailsDto(movieId, "Movie $movieId", null, null, "", null, 0.0, null)
    }

    override suspend fun getTvDetails(tvId: Int): TvDetailsDto {
        return tvDetailsById[tvId]
            ?: TvDetailsDto(tvId, "TV $tvId", null, null, "", null, 0.0, null, emptyList())
    }

    override suspend fun getSeasonDetails(tvId: Int, seasonNumber: Int): SeasonDetailsDto {
        return seasonDetailsByKey[tvId to seasonNumber]
            ?: SeasonDetailsDto(id = tvId, seasonNumber = seasonNumber, episodes = emptyList())
    }
}

private class FakeMediaDao : MediaDao {
    private val watchlistState = MutableStateFlow<List<WatchlistEntity>>(emptyList())
    private val episodeProgressState = MutableStateFlow<List<EpisodeProgressEntity>>(emptyList())

    override fun getWatchlist(category: String): Flow<List<WatchlistProgressRow>> {
        return combine(watchlistState, episodeProgressState) { watchlist, progress ->
            watchlist
                .filter { it.contentCategory == category }
                .sortedByDescending { it.addedAt }
                .map { item ->
                    val itemProgress = progress.filter { it.mediaId == item.id }
                    WatchlistProgressRow(
                        id = item.id,
                        title = item.title,
                        posterPath = item.posterPath,
                        mediaType = item.mediaType,
                        contentCategory = item.contentCategory,
                        contentStatus = item.contentStatus,
                        totalEpisodes = item.totalEpisodes,
                        watchedEpisodes = itemProgress.count { it.isWatched },
                        lastWatchedAt = itemProgress.filter { it.isWatched }.maxOfOrNull { it.updatedAt }
                    )
                }
        }
    }

    override suspend fun getAllWatchlist(): List<WatchlistEntity> = watchlistState.value

    override suspend fun clearWatchlist() {
        watchlistState.value = emptyList()
    }

    override suspend fun addToWatchlist(entity: WatchlistEntity) {
        watchlistState.value = watchlistState.value
            .filterNot { it.id == entity.id && it.mediaType == entity.mediaType }
            .plus(entity)
    }

    override suspend fun removeFromWatchlist(entity: WatchlistEntity) {
        watchlistState.value = watchlistState.value
            .filterNot {
                it.id == entity.id &&
                    it.mediaType == entity.mediaType &&
                    it.contentCategory == entity.contentCategory
            }
    }

    override suspend fun updateWatchStatus(id: Int, type: String, category: String, status: String) {
        watchlistState.value = watchlistState.value.map { item ->
            if (item.id == id && item.mediaType == type && item.contentCategory == category) {
                item.copy(contentStatus = status)
            } else {
                item
            }
        }
    }

    override suspend fun updateWatchProgressTotal(id: Int, type: String, category: String, totalEpisodes: Int) {
        watchlistState.value = watchlistState.value.map { item ->
            if (item.id == id && item.mediaType == type && item.contentCategory == category) {
                item.copy(totalEpisodes = totalEpisodes)
            } else {
                item
            }
        }
    }

    override suspend fun isInWatchlist(id: Int, type: String, category: String): Boolean {
        return watchlistState.value.any { item ->
            item.id == id && item.mediaType == type && item.contentCategory == category
        }
    }

    override suspend fun getWatchStatus(id: Int, type: String, category: String): String? {
        return watchlistState.value.firstOrNull { item ->
            item.id == id && item.mediaType == type && item.contentCategory == category
        }?.contentStatus
    }

    override fun getEpisodeProgress(mediaId: Int): Flow<List<EpisodeProgressEntity>> {
        return episodeProgressState.map { list -> list.filter { it.mediaId == mediaId } }
    }

    override suspend fun getAllEpisodeProgress(): List<EpisodeProgressEntity> = episodeProgressState.value

    override suspend fun clearAllEpisodeProgress() {
        episodeProgressState.value = emptyList()
    }

    override suspend fun clearEpisodeProgress(mediaId: Int) {
        episodeProgressState.value = episodeProgressState.value.filterNot { it.mediaId == mediaId }
    }

    override suspend fun updateEpisodeProgress(entity: EpisodeProgressEntity) {
        updateEpisodeProgress(listOf(entity))
    }

    override suspend fun updateEpisodeProgress(entities: List<EpisodeProgressEntity>) {
        val keys = entities.map { Triple(it.mediaId, it.seasonNumber, it.episodeNumber) }.toSet()
        episodeProgressState.value = episodeProgressState.value
            .filterNot { existing ->
                Triple(existing.mediaId, existing.seasonNumber, existing.episodeNumber) in keys
            }
            .plus(entities)
    }
}

private class FakeAnimeStructureDao : AnimeStructureDao {
    private val data = mutableListOf<AnimeStructureEntity>()

    override suspend fun upsertAll(entities: List<AnimeStructureEntity>) {
        data.clear()
        data.addAll(entities)
    }

    override suspend fun getAll(): List<AnimeStructureEntity> = data.toList()

    override suspend fun count(): Int = data.size

    override suspend fun clear() {
        data.clear()
    }
}
