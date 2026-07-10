package com.example.myapplication.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

@Dao
interface AnimeStructureDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(entities: List<AnimeStructureEntity>)

    @Query("SELECT * FROM anime_structures")
    suspend fun getAll(): List<AnimeStructureEntity>

    @Query("SELECT COUNT(*) FROM anime_structures")
    suspend fun count(): Int

    @Query("DELETE FROM anime_structures")
    suspend fun clear()
}
