package com.example.myapplication.data

import android.content.Context
import androidx.room.Room
import androidx.room.RoomDatabase
import com.example.myapplication.BuildConfig
import com.example.myapplication.data.api.AniListClient
import com.example.myapplication.data.api.TmdbApiService
import com.example.myapplication.data.local.AnimeStructureSeeder
import com.example.myapplication.data.local.MediaDatabase
import com.example.myapplication.data.repository.MediaRepository
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory
import androidx.sqlite.db.SupportSQLiteDatabase

class DataContainer(context: Context) {
    val authSessionStore = AuthSessionStore(context.applicationContext)
    private val httpLoggingLevel = if (BuildConfig.DEBUG) {
        HttpLoggingInterceptor.Level.BODY
    } else {
        HttpLoggingInterceptor.Level.NONE
    }

    private val tmdbHttpClient = OkHttpClient.Builder()
        .addInterceptor(HttpLoggingInterceptor().apply {
            level = httpLoggingLevel
        })
        .addInterceptor { chain ->
            val original = chain.request()
            val url = original.url.newBuilder()
                .addQueryParameter("api_key", BuildConfig.TMDB_API_KEY)
                .addQueryParameter("language", "fr-FR")
                .build()
            val request = original.newBuilder().url(url).build()
            chain.proceed(request)
        }
        .build()

    private val aniListHttpClient = OkHttpClient.Builder()
        .addInterceptor(HttpLoggingInterceptor().apply {
            level = httpLoggingLevel
        })
        .build()

    private val moshi = Moshi.Builder()
        .add(KotlinJsonAdapterFactory())
        .build()

    private val retrofit = Retrofit.Builder()
        .baseUrl("https://api.themoviedb.org/3/")
        .client(tmdbHttpClient)
        .addConverterFactory(MoshiConverterFactory.create(moshi))
        .build()
    private val apiService = retrofit.create(TmdbApiService::class.java)
    private val aniListClient = AniListClient(aniListHttpClient)

    private val database = Room.databaseBuilder(
        context.applicationContext,
        MediaDatabase::class.java,
        "media_database"
    ).addCallback(object : RoomDatabase.Callback() {
        override fun onCreate(db: SupportSQLiteDatabase) {
            super.onCreate(db)
            AnimeStructureSeeder(context.applicationContext).seed(db)
        }
    }).fallbackToDestructiveMigration()
        .build()

    val repository = MediaRepository(
        apiService,
        aniListClient,
        database.mediaDao(),
        database.animeStructureDao()
    )

    init {
        val initialBackendUrl = BuildConfig.BACKEND_BASE_URL
        if (initialBackendUrl.isNotBlank()) {
            repository.setBackendBaseUrl(initialBackendUrl)
        }
    }
}
