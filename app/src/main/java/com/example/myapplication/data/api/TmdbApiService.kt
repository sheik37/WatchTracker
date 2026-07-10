package com.example.myapplication.data.api

import com.example.myapplication.data.model.MediaResponse
import retrofit2.http.GET
import retrofit2.http.Query

interface TmdbApiService {
    @GET("trending/all/day")
    suspend fun getTrendingMedia(
        @Query("page") page: Int = 1
    ): MediaResponse

    @GET("search/multi")
    suspend fun searchMulti(
        @Query("query") query: String,
        @Query("page") page: Int = 1
    ): MediaResponse

    @GET("movie/upcoming")
    suspend fun getUpcomingMovies(
        @Query("page") page: Int = 1
    ): MediaResponse

    @GET("tv/on_the_air")
    suspend fun getOnTheAirTv(
        @Query("page") page: Int = 1
    ): MediaResponse

    @GET("movie/{movie_id}")
    suspend fun getMovieDetails(
        @retrofit2.http.Path("movie_id") movieId: Int
    ): com.example.myapplication.data.model.MovieDetailsDto

    @GET("tv/{tv_id}")
    suspend fun getTvDetails(
        @retrofit2.http.Path("tv_id") tvId: Int
    ): com.example.myapplication.data.model.TvDetailsDto

    @GET("tv/{tv_id}/season/{season_number}")
    suspend fun getSeasonDetails(
        @retrofit2.http.Path("tv_id") tvId: Int,
        @retrofit2.http.Path("season_number") seasonNumber: Int
    ): com.example.myapplication.data.model.SeasonDetailsDto
}
