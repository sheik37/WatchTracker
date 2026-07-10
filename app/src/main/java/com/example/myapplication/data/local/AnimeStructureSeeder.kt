package com.example.myapplication.data.local

import android.content.Context
import androidx.sqlite.db.SupportSQLiteDatabase
import com.example.myapplication.data.model.AnimeStructureSeed
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.util.Locale

class AnimeStructureSeeder(
    private val context: Context
) {
    private val json = Json {
        ignoreUnknownKeys = true
    }

    fun seed(database: SupportSQLiteDatabase) {
        val structures = loadSeeds()
        if (structures.isEmpty()) return

        database.beginTransaction()
        try {
            structures.forEach { seed ->
                val entity = AnimeStructureEntity(
                    normalizedTitle = seed.title.toNormalizedKey(),
                    season = seed.season?.uppercase(Locale.ROOT),
                    seasonYear = seed.seasonYear,
                    payloadJson = json.encodeToString(seed)
                )
                val statement = database.compileStatement(
                    """
                        INSERT OR REPLACE INTO anime_structures (
                            normalizedTitle,
                            season,
                            seasonYear,
                            payloadJson,
                            updatedAt
                        ) VALUES (?, ?, ?, ?, ?)
                    """.trimIndent()
                )
                statement.bindString(1, entity.normalizedTitle)
                if (entity.season == null) {
                    statement.bindNull(2)
                } else {
                    statement.bindString(2, entity.season)
                }
                if (entity.seasonYear == null) {
                    statement.bindNull(3)
                } else {
                    statement.bindLong(3, entity.seasonYear.toLong())
                }
                statement.bindString(4, entity.payloadJson)
                statement.bindLong(5, entity.updatedAt)
                statement.executeInsert()
            }
            database.setTransactionSuccessful()
        } finally {
            database.endTransaction()
        }
    }

    private fun loadSeeds(): List<AnimeStructureSeed> {
        val asset = context.assets.open("anime_structures.json")
            .bufferedReader()
            .use { it.readText() }
        return json.decodeFromString(ListSerializer(AnimeStructureSeed.serializer()), asset)
    }

    private fun String.toNormalizedKey(): String {
        return lowercase(Locale.ROOT)
            .replace(Regex("[^\\p{L}\\p{Nd}]+"), "")
    }
}
