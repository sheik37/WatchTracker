package com.example.myapplication.data.local

import androidx.room.Database
import androidx.room.RoomDatabase

@Database(
    entities = [WatchlistEntity::class, EpisodeProgressEntity::class, AnimeStructureEntity::class],
    version = 7,
    exportSchema = false
)
abstract class MediaDatabase : RoomDatabase() {
    abstract fun mediaDao(): MediaDao
    abstract fun animeStructureDao(): AnimeStructureDao
}
