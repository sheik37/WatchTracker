package com.example.myapplication.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "anime_structures")
data class AnimeStructureEntity(
    @PrimaryKey val normalizedTitle: String,
    val season: String? = null,
    val seasonYear: Int? = null,
    val payloadJson: String,
    val updatedAt: Long = System.currentTimeMillis()
)
