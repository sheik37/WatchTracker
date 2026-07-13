package com.example.myapplication.ui.navigation

import kotlinx.serialization.Serializable

sealed interface Destination {
    @Serializable
    data object Series : Destination

    @Serializable
    data object Films : Destination

    @Serializable
    data object Anime : Destination

    @Serializable
    data object Search : Destination

    @Serializable
    data object Profile : Destination

    @Serializable
    data class Details(val id: Int, val type: String) : Destination
}
