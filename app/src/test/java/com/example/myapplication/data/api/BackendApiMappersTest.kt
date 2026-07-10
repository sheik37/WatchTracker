package com.example.myapplication.data.api

import com.example.myapplication.data.model.AnimeStructureSeasonSeed
import com.example.myapplication.data.model.AnimeStructureSeed
import com.example.myapplication.data.model.toDomain
import org.junit.Assert.assertEquals
import org.junit.Test

class BackendApiMappersTest {

    @Test
    fun animeStructureSeed_toDomain_mapsSeasonRanges() {
        val seed = AnimeStructureSeed(
            title = "My Hero Academia",
            aliases = listOf("Boku no Hero Academia"),
            season = "SPRING",
            seasonYear = 2016,
            seasons = listOf(
                AnimeStructureSeasonSeed(1, "Saison 1", 1, 13),
                AnimeStructureSeasonSeed(2, "Saison 2", 14, 38)
            )
        )

        val domain = seed.toDomain()

        assertEquals("My Hero Academia", domain.title)
        assertEquals("Boku no Hero Academia", domain.aliases.first())
        assertEquals(2, domain.seasons.size)
        assertEquals(14, domain.seasons[1].startEpisode)
    }

    @Test
    fun animeStructureSeed_toBackendDto_mapsAllFields() {
        val seed = AnimeStructureSeed(
            title = "Jujutsu Kaisen",
            aliases = listOf("Sorcery Fight"),
            season = "FALL",
            seasonYear = 2020,
            seasons = listOf(
                AnimeStructureSeasonSeed(
                    seasonNumber = 1,
                    name = "Saison 1",
                    startEpisode = 1,
                    endEpisode = 24
                )
            )
        )

        val dto = seed.toBackendDto()

        assertEquals("Jujutsu Kaisen", dto.title)
        assertEquals("Sorcery Fight", dto.aliases.first())
        assertEquals("FALL", dto.season)
        assertEquals(2020, dto.seasonYear)
        assertEquals(1, dto.seasons.single().seasonNumber)
        assertEquals(24, dto.seasons.single().endEpisode)
    }
}

