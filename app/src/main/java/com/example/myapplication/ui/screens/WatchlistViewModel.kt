package com.example.myapplication.ui.screens

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.myapplication.data.model.Media
import com.example.myapplication.data.model.WatchCategory
import com.example.myapplication.data.model.WatchStatus
import com.example.myapplication.data.model.WatchlistItem
import com.example.myapplication.data.repository.MediaRepository
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class WatchlistViewModel(private val repository: MediaRepository) : ViewModel() {

    private val seriesWatchlist: StateFlow<List<WatchlistItem>> = repository.getWatchlist(WatchCategory.SERIES)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    private val filmsWatchlist: StateFlow<List<WatchlistItem>> = repository.getWatchlist(WatchCategory.FILMS)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    private val animeWatchlist: StateFlow<List<WatchlistItem>> = repository.getWatchlist(WatchCategory.ANIME)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    fun watchlist(category: WatchCategory): StateFlow<List<WatchlistItem>> = when (category) {
        WatchCategory.SERIES -> seriesWatchlist
        WatchCategory.FILMS -> filmsWatchlist
        WatchCategory.ANIME -> animeWatchlist
    }

    fun removeFromWatchlist(media: Media, category: WatchCategory) {
        viewModelScope.launch {
            repository.removeFromWatchlist(media, category)
        }
    }

    fun updateStatus(media: Media, category: WatchCategory, status: WatchStatus) {
        viewModelScope.launch {
            repository.updateWatchStatus(media, category, status)
        }
    }
}
