package com.example.myapplication.ui.screens

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.myapplication.data.local.EpisodeProgressEntity
import com.example.myapplication.data.model.Episode
import com.example.myapplication.data.model.Media
import com.example.myapplication.data.model.MediaDetails
import com.example.myapplication.data.model.MediaType
import com.example.myapplication.data.model.WatchCategory
import com.example.myapplication.data.model.WatchStatus
import com.example.myapplication.data.model.defaultStatus
import com.example.myapplication.data.model.watchCategory
import com.example.myapplication.data.repository.MediaRepository
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.launch

class DetailsViewModel(private val repository: MediaRepository) : ViewModel() {

    private val _details = MutableStateFlow<MediaDetails?>(null)
    val details: StateFlow<MediaDetails?> = _details.asStateFlow()

    private val _isInWatchlist = MutableStateFlow(false)
    val isInWatchlist: StateFlow<Boolean> = _isInWatchlist.asStateFlow()

    private val _watchStatus = MutableStateFlow<WatchStatus?>(null)
    val watchStatus: StateFlow<WatchStatus?> = _watchStatus.asStateFlow()

    private val _watchedEpisodes = MutableStateFlow<Set<String>>(emptySet())
    val watchedEpisodes: StateFlow<Set<String>> = _watchedEpisodes.asStateFlow()

    private val _seasonEpisodesCache = MutableStateFlow<Map<Int, List<Episode>>>(emptyMap())

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private var progressJob: Job? = null

    fun loadDetails(id: Int, type: MediaType) {
        viewModelScope.launch {
            _isLoading.value = true
            _details.value = null
            _watchStatus.value = null
            progressJob?.cancel()
            try {
                val details = if (type == MediaType.MOVIE) {
                    repository.getMovieDetails(id)
                } else {
                    repository.getTvDetails(id)
                }
                val category = details.watchCategory()
                _details.value = details
                _isInWatchlist.value = repository.isInWatchlist(id, type, category)
                _watchStatus.value = if (_isInWatchlist.value) {
                    repository.getWatchStatus(id, type, category)
                } else {
                    null
                }

                if (type == MediaType.TV) {
                    val totalEpisodes = details.seasons
                        .filter { it.seasonNumber != 0 }
                        .sumOf { it.episodeCount }
                    if (_isInWatchlist.value && totalEpisodes > 0) {
                        repository.updateWatchProgressTotal(details.toMedia(), category, totalEpisodes)
                    }
                    _seasonEpisodesCache.value = emptyMap()
                    if (details.seasons.sumOf { it.episodeCount } <= PREFETCH_MAX_EPISODES) {
                        prefetchSeasonEpisodes(details)
                    }
                    progressJob = viewModelScope.launch {
                        repository.getEpisodeProgress(id).collectLatest { progressList ->
                            val watchedSet = progressList.filter { it.isWatched }
                                .map { "${it.seasonNumber}_${it.episodeNumber}" }
                                .toSet()
                            _watchedEpisodes.value = watchedSet
                            if (_isInWatchlist.value) {
                                val totalEpisodes = details.seasons.sumOf { it.episodeCount }
                                val status = when {
                                    watchedSet.isEmpty() -> WatchStatus.NOT_STARTED
                                    totalEpisodes > 0 && watchedSet.size >= totalEpisodes -> {
                                        if (details.tvStatus == com.example.myapplication.data.model.TvStatus.ENDED) {
                                            WatchStatus.COMPLETED
                                        } else {
                                            WatchStatus.UP_TO_DATE
                                        }
                                    }
                                    else -> WatchStatus.IN_PROGRESS
                                }
                                _watchStatus.value = status
                                repository.updateWatchStatus(details.toMedia(), category, status)
                            }
                        }
                    }
                }
            } finally {
                _isLoading.value = false
            }
        }
    }

    private fun prefetchSeasonEpisodes(details: MediaDetails) {
        val seasonsToPrefetch = details.seasons.filter { it.seasonNumber != 0 && it.episodes.isEmpty() }
        if (seasonsToPrefetch.isEmpty()) return
        viewModelScope.launch {
            val fetched = seasonsToPrefetch.map { season ->
                async {
                    season.seasonNumber to try {
                        repository.getSeasonEpisodes(details.id, season.seasonNumber)
                    } catch (e: Exception) {
                        emptyList()
                    }
                }
            }.awaitAll()
            _seasonEpisodesCache.value = _seasonEpisodesCache.value + fetched
        }
    }

    fun toggleWatchlist() {
        val currentDetails = _details.value ?: return
        val category = currentDetails.watchCategory()
        viewModelScope.launch {
            val media = currentDetails.toMedia()
            if (_isInWatchlist.value) {
                repository.removeFromWatchlist(media, category)
                _isInWatchlist.value = false
                _watchStatus.value = null
            } else {
                val status = category.defaultStatus()
                val totalEpisodes = if (media.mediaType == MediaType.TV) {
                    _details.value?.seasons
                        ?.filter { it.seasonNumber != 0 }
                        ?.sumOf { it.episodeCount }
                        ?: 0
                } else {
                    1
                }
                repository.addToWatchlist(media, category, status, totalEpisodes)
                _isInWatchlist.value = true
                _watchStatus.value = status
            }
        }
    }

    fun removeFromWatchlist() {
        val currentDetails = _details.value ?: return
        val category = currentDetails.watchCategory()
        viewModelScope.launch {
            repository.removeFromWatchlist(currentDetails.toMedia(), category)
            _isInWatchlist.value = false
            _watchStatus.value = null
        }
    }

    fun toggleMovieWatched() {
        val currentDetails = _details.value ?: return
        if (currentDetails.mediaType != MediaType.MOVIE) return
        val category = currentDetails.watchCategory()
        val nextStatus = if (_watchStatus.value == WatchStatus.WATCHED) {
            WatchStatus.NOT_WATCHED
        } else {
            WatchStatus.WATCHED
        }
        viewModelScope.launch {
            if (_isInWatchlist.value) {
                repository.updateWatchStatus(currentDetails.toMedia(), category, nextStatus)
                _watchStatus.value = nextStatus
            }
        }
    }

    fun setEpisodeWatched(episode: Episode, watched: Boolean) {
        val mediaId = _details.value?.id ?: return
        viewModelScope.launch {
            repository.updateEpisodeProgress(
                mediaId = mediaId,
                seasonNumber = episode.seasonNumber,
                episodeNumber = episode.episodeNumber,
                isWatched = watched
            )
        }
    }

    suspend fun getEpisodesForSeason(seasonNumber: Int): List<Episode> {
        val details = _details.value ?: return emptyList()
        _seasonEpisodesCache.value[seasonNumber]?.let { return it }
        details.seasons.firstOrNull { it.seasonNumber == seasonNumber && it.episodes.isNotEmpty() }?.let {
            _seasonEpisodesCache.value = _seasonEpisodesCache.value + (seasonNumber to it.episodes)
            return it.episodes
        }
        return try {
            val episodes = repository.getSeasonEpisodes(details.id, seasonNumber)
            _seasonEpisodesCache.value = _seasonEpisodesCache.value + (seasonNumber to episodes)
            episodes
        } catch (e: Exception) {
            emptyList()
        }
    }

    fun markSeasonWatched(seasonNumber: Int, watched: Boolean) {
        val mediaId = _details.value?.id ?: return
        val details = _details.value ?: return
        val seasons = details.seasons
            .sortedBy { it.seasonNumber }
        val targetSeason = seasons.firstOrNull { it.seasonNumber == seasonNumber } ?: return
        viewModelScope.launch {
            val updates = if (seasonNumber == 0) {
                (1..targetSeason.episodeCount).map { episodeNumber ->
                    EpisodeProgressEntity(
                        mediaId = mediaId,
                        seasonNumber = seasonNumber,
                        episodeNumber = episodeNumber,
                        isWatched = watched
                    )
                }
            } else if (watched) {
                seasons
                    .filter { it.seasonNumber <= seasonNumber && it.seasonNumber != 0 }
                    .flatMap { season ->
                        val maxEpisode = if (season.seasonNumber == seasonNumber) targetSeason.episodeCount else season.episodeCount
                        (1..maxEpisode).map { episodeNumber ->
                            EpisodeProgressEntity(
                                mediaId = mediaId,
                                seasonNumber = season.seasonNumber,
                                episodeNumber = episodeNumber,
                                isWatched = true
                            )
                        }
                    }
            } else {
                (1..targetSeason.episodeCount).map { episodeNumber ->
                    EpisodeProgressEntity(
                        mediaId = mediaId,
                        seasonNumber = seasonNumber,
                        episodeNumber = episodeNumber,
                        isWatched = false
                    )
                }
            }
            repository.updateEpisodeProgress(updates)
        }
    }

    fun markEpisodeUpTo(seasonNumber: Int, episodeNumber: Int, watched: Boolean) {
        val mediaId = _details.value?.id ?: return
        val details = _details.value ?: return
        val seasons = details.seasons
            .filter { it.seasonNumber != 0 }
            .sortedBy { it.seasonNumber }
        val targetSeason = seasons.firstOrNull { it.seasonNumber == seasonNumber } ?: return
        viewModelScope.launch {
            val updates = if (watched) {
                seasons
                    .filter { it.seasonNumber < seasonNumber }
                    .flatMap { season ->
                        (1..season.episodeCount).map { previousEpisodeNumber ->
                            EpisodeProgressEntity(
                                mediaId = mediaId,
                                seasonNumber = season.seasonNumber,
                                episodeNumber = previousEpisodeNumber,
                                isWatched = true
                            )
                        }
                    } + (1..episodeNumber.coerceAtMost(targetSeason.episodeCount)).map { currentEpisodeNumber ->
                        EpisodeProgressEntity(
                            mediaId = mediaId,
                            seasonNumber = seasonNumber,
                            episodeNumber = currentEpisodeNumber,
                            isWatched = true
                        )
                    }
            } else {
                listOf(
                    EpisodeProgressEntity(
                        mediaId = mediaId,
                        seasonNumber = seasonNumber,
                        episodeNumber = episodeNumber.coerceAtMost(targetSeason.episodeCount),
                        isWatched = false
                    )
                )
            }
            repository.updateEpisodeProgress(updates)
        }
    }

    fun markEpisodesWatched(episodes: List<Episode>, watched: Boolean) {
        val mediaId = _details.value?.id ?: return
        viewModelScope.launch {
            repository.updateEpisodeProgress(
            episodes.map { episode ->
                    EpisodeProgressEntity(
                        mediaId = mediaId,
                        seasonNumber = episode.seasonNumber,
                        episodeNumber = episode.episodeNumber,
                        isWatched = watched
                    )
                }
            )
        }
    }

    private fun MediaDetails.toMedia() = Media(
        id = id,
        title = title,
        posterPath = posterPath,
        backdropPath = backdropPath,
        overview = overview,
        releaseDate = releaseDate,
        voteAverage = voteAverage,
        mediaType = mediaType
    )

    private companion object {
        const val PREFETCH_MAX_EPISODES = 50
    }
}
