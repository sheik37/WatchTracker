package com.example.myapplication.data.model

import kotlinx.serialization.Serializable

@Serializable
data class AnimeStructureSeed(
    val title: String,
    val aliases: List<String> = emptyList(),
    val season: String? = null,
    val seasonYear: Int? = null,
    val seasons: List<AnimeStructureSeasonSeed> = emptyList()
)

@Serializable
data class AnimeStructureSeasonSeed(
    val seasonNumber: Int,
    val name: String,
    val startEpisode: Int,
    val endEpisode: Int
)

data class AnimeStructure(
    val title: String,
    val aliases: List<String>,
    val season: String?,
    val seasonYear: Int?,
    val seasons: List<AnimeStructureSeasonRange>
)

data class AnimeStructureSeasonRange(
    val seasonNumber: Int,
    val name: String,
    val startEpisode: Int,
    val endEpisode: Int
)

fun AnimeStructureSeed.toDomain() = AnimeStructure(
    title = title,
    aliases = aliases,
    season = season,
    seasonYear = seasonYear,
    seasons = seasons.map {
        AnimeStructureSeasonRange(
            seasonNumber = it.seasonNumber,
            name = it.name,
            startEpisode = it.startEpisode,
            endEpisode = it.endEpisode
        )
    }
)
