package com.example.myapplication.ui.screens

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.myapplication.data.model.Media
import com.example.myapplication.data.model.MediaType
import com.example.myapplication.data.model.WatchCategory
import com.example.myapplication.data.model.defaultStatus
import com.example.myapplication.data.model.watchCategory
import com.example.myapplication.data.repository.MediaRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class MediaViewModel(private val repository: MediaRepository) : ViewModel() {

    private val _discoveryState = MutableStateFlow<List<Media>>(emptyList())
    val discoveryState: StateFlow<List<Media>> = _discoveryState.asStateFlow()

    private val _searchState = MutableStateFlow<List<Media>>(emptyList())
    val searchState: StateFlow<List<Media>> = _searchState.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    private val _selectedMedia = MutableStateFlow<Media?>(null)
    val selectedMedia: StateFlow<Media?> = _selectedMedia.asStateFlow()

    private val _trackedMediaKeys = MutableStateFlow<Set<String>>(emptySet())
    val trackedMediaKeys: StateFlow<Set<String>> = _trackedMediaKeys.asStateFlow()

    private val _discoveryHiddenKeys = MutableStateFlow<Set<String>>(emptySet())
    val discoveryHiddenKeys: StateFlow<Set<String>> = _discoveryHiddenKeys.asStateFlow()

    init {
        loadDiscovery()
    }

    fun loadDiscovery() {
        if (com.example.myapplication.BuildConfig.TMDB_API_KEY.isBlank()) {
            _errorMessage.value = "La clé API TMDB est manquante. Veuillez l'ajouter au fichier local.properties."
            return
        }
        viewModelScope.launch {
            _isLoading.value = true
            _errorMessage.value = null
            try {
                val discovery = repository.getDiscoveryMedia()
                _discoveryState.value = discovery
                _discoveryHiddenKeys.value = discovery.mapNotNull { media ->
                    if (isTracked(media)) mediaKey(media) else null
                }.toSet()
            } catch (e: Exception) {
                _errorMessage.value = "Échec du chargement des découvertes : ${e.message}"
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun search(query: String) {
        if (query.isBlank()) {
            _searchState.value = emptyList()
            _errorMessage.value = null
            return
        }
        if (com.example.myapplication.BuildConfig.TMDB_API_KEY.isBlank()) {
            _errorMessage.value = "La clé API TMDB est manquante. Veuillez l'ajouter au fichier local.properties."
            return
        }
        viewModelScope.launch {
            _isLoading.value = true
            _errorMessage.value = null
            try {
                _searchState.value = repository.searchMedia(query)
            } catch (e: Exception) {
                _errorMessage.value = "La recherche a échoué : ${e.message}"
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun selectMedia(media: Media?) {
        _selectedMedia.value = media
    }

    fun refreshTrackedMedia(mediaList: List<Media>) {
        viewModelScope.launch {
            _trackedMediaKeys.value = mediaList.mapNotNull { media ->
                if (isTracked(media)) mediaKey(media) else null
            }.toSet()
        }
    }

    fun followMedia(media: Media) {
        viewModelScope.launch {
            addMediaToWatchlist(media)
        }
    }

    fun toggleFollowMedia(media: Media, isTracked: Boolean) {
        viewModelScope.launch {
            if (isTracked) {
                removeMediaFromWatchlist(media)
                _trackedMediaKeys.update { current -> current - mediaKey(media) }
            } else {
                addMediaToWatchlist(media)
            }
        }
    }

    private suspend fun addMediaToWatchlist(media: Media) {
        val category = when (media.mediaType) {
            MediaType.MOVIE -> WatchCategory.FILMS
            MediaType.TV -> repository.getTvDetails(media.id).watchCategory()
        }
        repository.addToWatchlist(media, category, category.defaultStatus(), if (media.mediaType == MediaType.MOVIE) 1 else 0)
        _trackedMediaKeys.update { current -> current + mediaKey(media) }
    }

    private suspend fun removeMediaFromWatchlist(media: Media) {
        val category = when (media.mediaType) {
            MediaType.MOVIE -> WatchCategory.FILMS
            MediaType.TV -> repository.getTvDetails(media.id).watchCategory()
        }
        repository.removeFromWatchlist(media, category)
    }

    private suspend fun isTracked(media: Media): Boolean {
        return when (media.mediaType) {
            MediaType.MOVIE -> repository.isInWatchlist(media.id, media.mediaType, WatchCategory.FILMS)
            MediaType.TV -> {
                repository.isInWatchlist(media.id, media.mediaType, WatchCategory.SERIES) ||
                    repository.isInWatchlist(media.id, media.mediaType, WatchCategory.ANIME)
            }
        }
    }

    private fun mediaKey(media: Media): String = "${media.mediaType.value}_${media.id}"
}
