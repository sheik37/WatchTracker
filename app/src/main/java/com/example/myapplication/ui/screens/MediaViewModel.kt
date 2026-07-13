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
    private var hasLoadedDiscoveryThisSession: Boolean = false

    init {
        loadDiscovery()
        refreshTrackedMedia()
    }

    fun loadDiscovery(force: Boolean = false) {
        if (hasLoadedDiscoveryThisSession && !force) return
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
                val trackedKeys = repository.getTrackedMediaKeys()
                _trackedMediaKeys.value = trackedKeys
                if (_discoveryHiddenKeys.value.isEmpty()) {
                    _discoveryHiddenKeys.value = trackedKeys
                }
                hasLoadedDiscoveryThisSession = true
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
                refreshTrackedMedia()
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

    fun refreshTrackedMedia() {
        viewModelScope.launch {
            val trackedKeys = repository.getTrackedMediaKeys()
            _trackedMediaKeys.value = trackedKeys
            if (_discoveryHiddenKeys.value.isEmpty()) {
                _discoveryHiddenKeys.value = trackedKeys
            }
        }
    }

    fun followMedia(media: Media) {
        toggleFollowMedia(media, isTracked = false)
    }

    fun toggleFollowMedia(media: Media, isTracked: Boolean) {
        viewModelScope.launch {
            val key = mediaKey(media)
            if (isTracked) {
                _trackedMediaKeys.update { current -> current - key }
                try {
                    removeMediaFromWatchlist(media)
                } catch (e: Exception) {
                    _trackedMediaKeys.update { current -> current + key }
                    _errorMessage.value = "Échec de la mise à jour : ${e.message}"
                }
            } else {
                _trackedMediaKeys.update { current -> current + key }
                try {
                    addMediaToWatchlist(media)
                } catch (e: Exception) {
                    _trackedMediaKeys.update { current -> current - key }
                    _errorMessage.value = "Échec de la mise à jour : ${e.message}"
                }
            }
        }
    }

    private suspend fun addMediaToWatchlist(media: Media) {
        val category = when (media.mediaType) {
            MediaType.MOVIE -> WatchCategory.FILMS
            MediaType.TV -> repository.getTvDetailsFast(media.id).watchCategory()
        }
        repository.addToWatchlist(media, category, category.defaultStatus(), if (media.mediaType == MediaType.MOVIE) 1 else 0)
    }

    private suspend fun removeMediaFromWatchlist(media: Media) {
        val category = when (media.mediaType) {
            MediaType.MOVIE -> WatchCategory.FILMS
            MediaType.TV -> repository.getTvDetailsFast(media.id).watchCategory()
        }
        repository.removeFromWatchlist(media, category)
    }

    private fun mediaKey(media: Media): String = "${media.mediaType.value}_${media.id}"
}
