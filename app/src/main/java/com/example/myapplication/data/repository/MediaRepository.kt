package com.example.myapplication.data.repository

import android.util.Log
import com.example.myapplication.data.api.AniListClient
import com.example.myapplication.data.api.AuthEmailDto
import com.example.myapplication.data.api.AuthChangePasswordDto
import com.example.myapplication.data.api.AuthLogoutDto
import com.example.myapplication.data.api.AuthMeUpdateDto
import com.example.myapplication.data.api.AuthRefreshDto
import com.example.myapplication.data.api.AuthRequestDto
import com.example.myapplication.data.api.AuthResetPasswordDto
import com.example.myapplication.data.api.BackendApiService
import com.example.myapplication.data.api.AuthMeDto
import com.example.myapplication.data.api.BackendAnimeStructureDto
import com.example.myapplication.data.api.BackendAnimeStructureSeasonDto
import com.example.myapplication.data.api.RemoteEpisodeProgressDto
import com.example.myapplication.data.api.RemoteWatchlistItemDto
import com.example.myapplication.data.api.TmdbApiService
import com.example.myapplication.data.api.WatchStatusUpdateDto
import com.example.myapplication.data.api.WatchTotalUpdateDto
import com.example.myapplication.data.api.toBackendDto
import com.example.myapplication.data.local.AnimeStructureDao
import com.example.myapplication.data.local.EpisodeProgressEntity
import com.example.myapplication.data.local.MediaDao
import com.example.myapplication.data.local.WatchlistEntity
import com.example.myapplication.data.model.AnimeStructure
import com.example.myapplication.data.model.AnimeStructureSeed
import com.example.myapplication.data.model.Episode
import com.example.myapplication.data.model.Media
import com.example.myapplication.data.model.MediaDetails
import com.example.myapplication.data.model.MediaType
import com.example.myapplication.data.model.WatchCategory
import com.example.myapplication.data.model.WatchStatus
import com.example.myapplication.data.model.WatchlistItem
import com.example.myapplication.data.model.defaultStatus
import com.example.myapplication.data.model.toDomain
import com.example.myapplication.data.model.watchCategory
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.first
import kotlinx.serialization.json.Json
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import java.util.Locale
import okhttp3.OkHttpClient
import retrofit2.HttpException
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory

class MediaRepository(
    private val apiService: TmdbApiService,
    private val aniListClient: AniListClient,
    private val mediaDao: MediaDao,
    private val animeStructureDao: AnimeStructureDao
) {
    data class AuthTokens(
        val accessToken: String,
        val refreshToken: String?,
        val expiresInSeconds: Int
    )

    data class UserProfile(
        val userId: Int,
        val email: String,
        val displayName: String?
    )

    private val structureJson = Json {
        ignoreUnknownKeys = true
    }
    private val backendJson = Moshi.Builder()
        .add(KotlinJsonAdapterFactory())
        .build()

    @Volatile
    private var backendApiService: BackendApiService? = null
    @Volatile
    private var backendBaseUrl: String? = null
    @Volatile
    private var backendAuthToken: String? = null
    @Volatile
    private var lastBackendSyncAtMillis: Long = 0L

    @Synchronized
    fun setBackendBaseUrl(baseUrl: String?) {
        backendBaseUrl = baseUrl
            ?.trim()
            ?.takeIf { it.isNotBlank() }
            ?.let { normalizedUrl ->
                if (normalizedUrl.endsWith("/")) normalizedUrl else "$normalizedUrl/"
            }
        rebuildBackendApiService()
    }

    @Synchronized
    fun setBackendAuthToken(token: String?) {
        backendAuthToken = token?.trim()?.takeIf { it.isNotBlank() }
        rebuildBackendApiService()
    }

    suspend fun register(email: String, password: String): String {
        val backend = backendApiService ?: error("Backend API URL is not configured")
        return backend.register(AuthRequestDto(email = email, password = password)).message
    }

    suspend fun login(email: String, password: String, otpCode: String?): AuthTokens {
        val backend = backendApiService ?: error("Backend API URL is not configured")
        val response = backend.login(
            AuthRequestDto(
                email = email,
                password = password,
                otpCode = otpCode?.trim()?.takeIf { it.isNotBlank() }
            )
        )
        val accessToken = response.accessToken ?: response.token ?: error("Missing access token in login response")
        return AuthTokens(
            accessToken = accessToken,
            refreshToken = response.refreshToken,
            expiresInSeconds = response.expiresInSeconds ?: 3600
        )
    }

    suspend fun refresh(refreshToken: String): AuthTokens {
        val backend = backendApiService ?: error("Backend API URL is not configured")
        val response = backend.refresh(AuthRefreshDto(refreshToken = refreshToken))
        val accessToken = response.accessToken ?: response.token ?: error("Missing access token in refresh response")
        return AuthTokens(
            accessToken = accessToken,
            refreshToken = response.refreshToken,
            expiresInSeconds = response.expiresInSeconds ?: 3600
        )
    }

    suspend fun resendVerification(email: String): String {
        val backend = backendApiService ?: error("Backend API URL is not configured")
        return backend.resendVerification(AuthEmailDto(email = email)).message
    }

    suspend fun forgotPassword(email: String): String {
        val backend = backendApiService ?: error("Backend API URL is not configured")
        return backend.forgotPassword(AuthEmailDto(email = email)).message
    }

    suspend fun resetPassword(token: String, password: String): String {
        val backend = backendApiService ?: error("Backend API URL is not configured")
        return backend.resetPassword(AuthResetPasswordDto(token = token, password = password)).message
    }

    suspend fun changePassword(currentPassword: String, newPassword: String): String {
        val backend = backendApiService ?: error("Backend API URL is not configured")
        return backend.changePassword(
            AuthChangePasswordDto(
                currentPassword = currentPassword,
                newPassword = newPassword
            )
        ).message
    }

    suspend fun logout(refreshToken: String?) {
        backendApiService?.logout(AuthLogoutDto(refreshToken = refreshToken))
    }

    suspend fun getCurrentUserProfile(): UserProfile? {
        val backend = backendApiService ?: return null
        val profile: AuthMeDto = backend.me()
        return UserProfile(
            userId = profile.userId,
            email = profile.email,
            displayName = profile.displayName
        )
    }

    suspend fun updateCurrentUserDisplayName(displayName: String?): UserProfile? {
        val backend = backendApiService ?: return null
        val profile: AuthMeDto = backend.updateMe(AuthMeUpdateDto(displayName = displayName))
        return UserProfile(
            userId = profile.userId,
            email = profile.email,
            displayName = profile.displayName
        )
    }

    @Synchronized
    private fun rebuildBackendApiService() {
        val baseUrl = backendBaseUrl ?: run {
            backendApiService = null
            return
        }
        val authToken = backendAuthToken
        val client = OkHttpClient.Builder()
            .addInterceptor { chain ->
                val requestBuilder = chain.request().newBuilder()
                if (!authToken.isNullOrBlank()) {
                    requestBuilder.header("Authorization", "Bearer $authToken")
                }
                chain.proceed(requestBuilder.build())
            }
            .build()
        backendApiService = Retrofit.Builder()
            .baseUrl(baseUrl)
            .client(client)
            .addConverterFactory(MoshiConverterFactory.create(backendJson))
            .build()
            .create(BackendApiService::class.java)
    }

    suspend fun getTrendingMedia(): List<Media> {
        return apiService.getTrendingMedia().results
            .filter { it.mediaType == "movie" || it.mediaType == "tv" }
            .map { it.toDomain() }
    }

    suspend fun searchMedia(query: String): List<Media> {
        return apiService.searchMulti(query).results
            .filter { it.mediaType == "movie" || it.mediaType == "tv" }
            .map { it.toDomain() }
    }

    suspend fun getDiscoveryMedia(): List<Media> {
        val preferredGenres = buildPreferredGenres()
        val trackedKeys = getTrackedMediaKeys()
        val movies = (1..3).flatMap { page ->
            apiService.getUpcomingMovies(page).results
                .map { it.toDomain(com.example.myapplication.data.model.MediaType.MOVIE) }
        }
        val tv = (1..3).flatMap { page ->
            apiService.getOnTheAirTv(page).results
                .map { it.toDomain(com.example.myapplication.data.model.MediaType.TV) }
        }
        val rankedPool = (movies + tv)
            .distinctBy { "${it.mediaType.value}_${it.id}" }
            .filterNot { media -> "${media.mediaType.value}_${media.id}" in trackedKeys }
            .sortedWith(
                compareByDescending<Media> { it.genreIds.count { genreId -> genreId in preferredGenres } }
                    .thenByDescending { it.voteAverage }
            )
            .take(120)
        return rankedPool.shuffled().take(33)
    }

    suspend fun synchronizeWithBackend() {
        val backend = backendApiService ?: return
        val now = System.currentTimeMillis()
        if ((now - lastBackendSyncAtMillis) < BACKEND_SYNC_MIN_INTERVAL_MILLIS) {
            return
        }
        lastBackendSyncAtMillis = now
        syncWatchlistAndProgress(backend)
    }

    suspend fun clearLocalSessionData() {
        mediaDao.clearWatchlist()
        mediaDao.clearAllEpisodeProgress()
        lastBackendSyncAtMillis = 0L
    }

    fun getWatchlist(category: WatchCategory) = mediaDao.getWatchlist(category.value).map { entities ->
        entities.map { entity ->
            val mediaType = MediaType.fromString(entity.mediaType)
            val totalEpisodes = when {
                mediaType == MediaType.MOVIE -> 1
                entity.totalEpisodes > 0 -> entity.totalEpisodes
                else -> 0
            }
            val watchedEpisodes = when {
                mediaType == MediaType.MOVIE && WatchStatus.fromString(entity.contentStatus) == WatchStatus.WATCHED -> 1
                mediaType == MediaType.MOVIE -> 0
                else -> entity.watchedEpisodes
            }
            WatchlistItem(
                media = Media(
                    id = entity.id,
                    title = entity.title,
                    posterPath = entity.posterPath,
                    backdropPath = null,
                    overview = "",
                    releaseDate = null,
                    voteAverage = 0.0,
                    mediaType = mediaType
                ),
                status = WatchStatus.fromString(entity.contentStatus),
                watchedEpisodes = watchedEpisodes,
                totalEpisodes = totalEpisodes,
                lastWatchedAt = entity.lastWatchedAt
            )
        }
    }

    suspend fun addToWatchlist(
        media: Media,
        category: WatchCategory,
        status: WatchStatus = category.defaultStatus(),
        totalEpisodes: Int = 0
    ) {
        mediaDao.addToWatchlist(
            WatchlistEntity(
                id = media.id,
                title = media.title,
                posterPath = media.posterPath,
                mediaType = media.mediaType.value,
                contentCategory = category.value,
                contentStatus = status.value,
                totalEpisodes = totalEpisodes
            )
        )
        syncWatchlistItemToBackend(media, category, status, totalEpisodes)
    }

    suspend fun removeFromWatchlist(media: Media, category: WatchCategory) {
        mediaDao.removeFromWatchlist(
            WatchlistEntity(
                id = media.id,
                title = media.title,
                posterPath = media.posterPath,
                mediaType = media.mediaType.value,
                contentCategory = category.value,
                contentStatus = category.defaultStatus().value
            )
        )
        runBackendSync("removeFromWatchlist") {
            backendApiService?.deleteWatchlist(media.id, media.mediaType.value, category.value)
        }
    }

    suspend fun updateWatchStatus(media: Media, category: WatchCategory, status: WatchStatus) {
        mediaDao.updateWatchStatus(media.id, media.mediaType.value, category.value, status.value)
        runBackendSync("updateWatchStatus") {
            backendApiService?.updateWatchStatus(
                media.id,
                media.mediaType.value,
                category.value,
                WatchStatusUpdateDto(status.value)
            )
        }
    }

    suspend fun updateWatchProgressTotal(media: Media, category: WatchCategory, totalEpisodes: Int) {
        mediaDao.updateWatchProgressTotal(media.id, media.mediaType.value, category.value, totalEpisodes)
        runBackendSync("updateWatchProgressTotal") {
            backendApiService?.updateWatchTotal(
                media.id,
                media.mediaType.value,
                category.value,
                WatchTotalUpdateDto(totalEpisodes)
            )
        }
    }

    suspend fun isInWatchlist(id: Int, type: MediaType, category: WatchCategory) =
        mediaDao.isInWatchlist(id, type.value, category.value)

    suspend fun getTrackedMediaKeys(): Set<String> {
        return mediaDao.getAllWatchlist()
            .map { "${it.mediaType}_${it.id}" }
            .toSet()
    }

    suspend fun getWatchStatus(id: Int, type: MediaType, category: WatchCategory): WatchStatus? {
        val status = mediaDao.getWatchStatus(id, type.value, category.value) ?: return null
        return WatchStatus.fromString(status)
    }

    suspend fun getMovieDetails(id: Int): MediaDetails {
        return apiService.getMovieDetails(id).toDomain()
    }

    suspend fun getTvDetailsFast(id: Int): MediaDetails {
        return apiService.getTvDetails(id).toDomain()
    }

    suspend fun getTvDetails(id: Int): MediaDetails {
        val details = getTvDetailsFast(id)
        if (details.seasons.isEmpty()) {
            return details
        }

        if (details.watchCategory() == WatchCategory.ANIME) {
            val manualStructure = loadManualAnimeStructure(details)
            ensureAnimeStructureOnBackend(details, manualStructure)
            manualStructure?.let { structure ->
                val regularEpisodes = fetchAllRegularSeasonEpisodes(id)
                if (regularEpisodes.isNotEmpty()) {
                    val specialSeasons = details.seasons.filter { it.seasonNumber == 0 }
                    val rebuiltSeasons = buildCustomAnimeSeasons(structure, regularEpisodes)
                    if (rebuiltSeasons.isNotEmpty()) {
                        return details.copy(seasons = rebuiltSeasons + specialSeasons)
                    }
                }
            }

            val animeSplit = runCatching { aniListClient.getAnimeSeasons(details.title) }.getOrDefault(emptyList())
            if (animeSplit.size > 1) {
                val regularEpisodes = fetchAllRegularSeasonEpisodes(id)
                if (regularEpisodes.isNotEmpty()) {
                    val specialSeasons = details.seasons.filter { it.seasonNumber == 0 }
                    val rebuiltSeasons = buildAnimeSeasons(animeSplit, regularEpisodes)
                    if (rebuiltSeasons.isNotEmpty()) {
                        return details.copy(seasons = rebuiltSeasons + specialSeasons)
                    }
                }
            }
        }

        val specialSeasons = details.seasons.filter { it.seasonNumber == 0 }
        val regularSeasons = details.seasons.filter { it.seasonNumber != 0 }

        if (regularSeasons.isEmpty()) {
            return details
        }

        if (regularSeasons.size > 1) {
            return details
        }

        val firstSeason = regularSeasons.first()
        if (firstSeason.seasonNumber != 1) {
            return details
        }

        val episodes = apiService.getSeasonDetails(id, 1).episodes.map { it.toDomain() }
        if (episodes.isEmpty()) {
            return details
        }

        val splitSeasons = splitSeasonByAirDate(episodes)
        val populatedSeasons = if (splitSeasons.size > 1) {
            splitSeasons
        } else {
            listOf(
                firstSeason.copy(
                    episodeCount = episodes.size,
                    episodes = episodes.mapIndexed { index, episode ->
                        episode.copy(
                            seasonNumber = 1,
                            episodeNumber = index + 1
                        )
                    }
                )
            )
        }

        return details.copy(seasons = populatedSeasons + specialSeasons)
    }

    suspend fun getSeasonEpisodes(tvId: Int, seasonNumber: Int): List<Episode> {
        return apiService.getSeasonDetails(tvId, seasonNumber).episodes.map { it.toDomain() }
    }

    fun getEpisodeProgress(mediaId: Int) = mediaDao.getEpisodeProgress(mediaId)

    suspend fun updateEpisodeProgress(mediaId: Int, seasonNumber: Int, episodeNumber: Int, isWatched: Boolean) {
        mediaDao.updateEpisodeProgress(
            EpisodeProgressEntity(
                mediaId = mediaId,
                seasonNumber = seasonNumber,
                episodeNumber = episodeNumber,
                isWatched = isWatched
            )
        )
        syncEpisodeProgressToBackend(mediaId)
    }

    suspend fun updateEpisodeProgress(entities: List<EpisodeProgressEntity>) {
        if (entities.isEmpty()) return
        mediaDao.updateEpisodeProgress(entities)
        syncEpisodeProgressToBackend(entities.first().mediaId)
    }

    private fun splitSeasonByAirDate(episodes: List<Episode>): List<com.example.myapplication.data.model.Season> {
        val orderedEpisodes = episodes
            .sortedWith(
                compareBy<Episode> { parseAirDate(it.airDate) ?: LocalDate.MAX }
                    .thenBy { it.episodeNumber }
            )

        if (orderedEpisodes.size < 2) {
            return emptyList()
        }

        val groups = mutableListOf<MutableList<Episode>>()
        var currentGroup = mutableListOf<Episode>()
        var previousDate: LocalDate? = null

        orderedEpisodes.forEach { episode ->
            val currentDate = parseAirDate(episode.airDate)
            val shouldSplit = previousDate != null &&
                currentDate != null &&
                ChronoUnit.DAYS.between(previousDate, currentDate) > SEASON_SPLIT_DAYS

            if (shouldSplit && currentGroup.isNotEmpty()) {
                groups += currentGroup
                currentGroup = mutableListOf()
            }

            currentGroup += episode
            previousDate = currentDate ?: previousDate
        }

        if (currentGroup.isNotEmpty()) {
            groups += currentGroup
        }

        if (groups.size <= 1) {
            return emptyList()
        }

        return groups.mapIndexed { index, group ->
            val seasonNumber = index + 1
            com.example.myapplication.data.model.Season(
                id = group.first().id,
                name = "Saison $seasonNumber",
                seasonNumber = seasonNumber,
                episodeCount = group.size,
                episodes = group.mapIndexed { episodeIndex, episode ->
                    episode.copy(
                        seasonNumber = seasonNumber,
                        episodeNumber = episodeIndex + 1
                    )
                }
            )
        }
    }

    private fun parseAirDate(value: String?): LocalDate? {
        if (value.isNullOrBlank()) return null
        return runCatching { LocalDate.parse(value) }.getOrNull()
    }

    private suspend fun fetchAllRegularSeasonEpisodes(tvId: Int): List<Episode> = coroutineScope {
        val seasons = apiService.getTvDetails(tvId).seasons.filter { it.seasonNumber != 0 }
        if (seasons.isEmpty()) return@coroutineScope emptyList()
        seasons.map { season ->
            async {
                runCatching { apiService.getSeasonDetails(tvId, season.seasonNumber).episodes.map { it.toDomain() } }
                    .getOrDefault(emptyList())
            }
        }.map { it.await() }.flatten()
    }

    private suspend fun loadManualAnimeStructure(details: MediaDetails): AnimeStructure? {
        val normalizedTitle = details.title.toNormalizedTitle()
        val releaseYear = details.releaseDate?.take(4)?.toIntOrNull()
        val releaseSeason = details.releaseDate.toSeasonLabel()

        return animeStructureDao.getAll()
            .map { entity ->
                structureJson.decodeFromString(AnimeStructureSeed.serializer(), entity.payloadJson).toDomain()
            }
            .firstOrNull { structure ->
                val titleMatches = structure.matchesTitle(normalizedTitle)
                val yearMatches = structure.seasonYear == null || structure.seasonYear == releaseYear
                val seasonMatches = structure.season == null || structure.season.equals(releaseSeason, ignoreCase = true)
                titleMatches && yearMatches && seasonMatches
            }
    }

    private fun buildCustomAnimeSeasons(
        structure: AnimeStructure,
        episodes: List<Episode>
    ): List<com.example.myapplication.data.model.Season> {
        val orderedEpisodes = episodes.sortedWith(
            compareBy<Episode> { parseAirDate(it.airDate) ?: LocalDate.MAX }
                .thenBy { it.episodeNumber }
        )

        return structure.seasons.mapNotNull { season ->
            val seasonEpisodes = orderedEpisodes.filter { episode ->
                episode.episodeNumber in season.startEpisode..season.endEpisode
            }
            if (seasonEpisodes.isEmpty()) return@mapNotNull null

            com.example.myapplication.data.model.Season(
                id = seasonEpisodes.first().id,
                name = season.name,
                seasonNumber = season.seasonNumber,
                episodeCount = seasonEpisodes.size,
                episodes = seasonEpisodes.mapIndexed { index, episode ->
                    episode.copy(
                        seasonNumber = season.seasonNumber,
                        episodeNumber = index + 1
                    )
                }
            )
        }
    }

    private fun buildAnimeSeasons(animeSplit: List<com.example.myapplication.data.model.Season>, episodes: List<Episode>): List<com.example.myapplication.data.model.Season> {
        if (animeSplit.isEmpty() || episodes.isEmpty()) return emptyList()

        val orderedEpisodes = episodes.sortedWith(
            compareBy<Episode> { parseAirDate(it.airDate) ?: LocalDate.MAX }
                .thenBy { it.episodeNumber }
        )

        if (orderedEpisodes.isEmpty()) return emptyList()

        var cursor = 0
        return animeSplit.mapIndexed { index, season ->
            val remainingSeasons = animeSplit.size - index
            val remainingEpisodes = orderedEpisodes.size - cursor
            val wanted = season.episodeCount.coerceAtLeast(1)
            val takeCount = if (remainingSeasons == 1) {
                remainingEpisodes
            } else {
                (remainingEpisodes - (remainingSeasons - 1)).coerceAtLeast(1).coerceAtMost(wanted)
            }

            val chunk = orderedEpisodes.subList(cursor, cursor + takeCount.coerceAtMost(remainingEpisodes))
            cursor += chunk.size

            season.copy(
                episodeCount = chunk.size,
                episodes = chunk.mapIndexed { episodeIndex, episode ->
                    episode.copy(
                        seasonNumber = index + 1,
                        episodeNumber = episodeIndex + 1
                    )
                }
            )
        }.filter { it.episodeCount > 0 }
    }

    private suspend fun buildPreferredGenres(): Set<Int> = coroutineScope {
        val watchlist = mediaDao.getAllWatchlist()
        if (watchlist.isEmpty()) return@coroutineScope emptySet()

        val genreLists = watchlist.map { entity ->
            async {
                when (MediaType.fromString(entity.mediaType)) {
                    MediaType.MOVIE -> runCatching { apiService.getMovieDetails(entity.id).genres.map { it.id } }.getOrDefault(emptyList())
                    MediaType.TV -> runCatching { apiService.getTvDetails(entity.id).genres.map { it.id } }.getOrDefault(emptyList())
                }
            }
        }.map { it.await() }

        genreLists.flatten().toSet()
    }

    private suspend fun ensureAnimeStructureOnBackend(details: MediaDetails, localStructure: AnimeStructure?) {
        val backend = backendApiService ?: return
        val title = details.title.trim()
        if (title.isBlank()) return
        val existsOnBackend = runCatching {
            backend.getAnimeStructure(title)
            true
        }.getOrElse { error ->
            if (error is HttpException && error.code() == 404) {
                false
            } else {
                Log.w(TAG, "Failed to check anime structure on backend", error)
                return
            }
        }
        if (existsOnBackend) return

        val structure = localStructure ?: return
        runBackendSync("ensureAnimeStructureOnBackend") {
            backend.upsertAnimeStructure(structure.toBackendDto())
        }
    }

    private suspend fun syncWatchlistAndProgress(backend: BackendApiService) {
        val snapshot = runCatching { backend.getSyncSnapshot() }.getOrElse {
            Log.w(TAG, "Failed to fetch remote snapshot", it)
            return
        }
        val remoteWatchlist = snapshot.watchlist
        val remoteWatchlistByKey = remoteWatchlist.associateBy {
            WatchlistItemKey(
                id = it.id,
                mediaType = it.mediaType,
                contentCategory = it.contentCategory
            )
        }
        val remoteProgressByMediaId = snapshot.episodeProgress
            .mapNotNull { item ->
                val mediaId = item.mediaId ?: return@mapNotNull null
                mediaId to item
            }
            .groupBy({ it.first }, { it.second })
        val localWatchlist = mediaDao.getAllWatchlist()
        val localProgressByMediaId = mediaDao.getAllEpisodeProgress().groupBy { it.mediaId }

        val mergedProgressByMediaId = mergeEpisodeProgressByMediaId(
            localProgressByMediaId = localProgressByMediaId,
            remoteProgressByMediaId = remoteProgressByMediaId
        )

        val mergedWatchlist = mergeWatchlistEntities(
            localWatchlist = localWatchlist,
            remoteWatchlist = remoteWatchlist,
            mergedProgressByMediaId = mergedProgressByMediaId
        )

        mediaDao.clearWatchlist()
        mediaDao.clearAllEpisodeProgress()

        mergedWatchlist.forEach { entity ->
            mediaDao.addToWatchlist(entity)
        }
        mergedProgressByMediaId.values.flatten().let { mergedProgress ->
            if (mergedProgress.isNotEmpty()) {
                mediaDao.updateEpisodeProgress(mergedProgress)
            }
        }

        mergedWatchlist
            .map { it.toRemoteDto() }
            .filter { localItem ->
                val key = WatchlistItemKey(
                    id = localItem.id,
                    mediaType = localItem.mediaType,
                    contentCategory = localItem.contentCategory
                )
                val remoteItem = remoteWatchlistByKey[key]
                remoteItem == null || !remoteItem.matches(localItem)
            }
            .forEach { changedItem ->
                runBackendSync("syncWatchlistAndProgress") {
                    backend.upsertWatchlist(changedItem)
                }
            }

        mergedProgressByMediaId.forEach { (mediaId, progressEntities) ->
            val remoteProgress = remoteProgressByMediaId[mediaId].orEmpty()
            if (progressEntities.matchesRemote(remoteProgress)) {
                return@forEach
            }
            runBackendSync("syncWatchlistAndProgress") {
                backend.replaceEpisodeProgress(
                    mediaId,
                    progressEntities.map { item ->
                        RemoteEpisodeProgressDto(
                            seasonNumber = item.seasonNumber,
                            episodeNumber = item.episodeNumber,
                            isWatched = item.isWatched
                        )
                    }
                )
            }
        }
    }

    private suspend fun syncWatchlistItemToBackend(
        media: Media,
        category: WatchCategory,
        status: WatchStatus,
        totalEpisodes: Int
    ) {
        runBackendSync("syncWatchlistItemToBackend") {
            backendApiService?.upsertWatchlist(
                RemoteWatchlistItemDto(
                    id = media.id,
                    title = media.title,
                    posterPath = media.posterPath,
                    mediaType = media.mediaType.value,
                    contentCategory = category.value,
                    contentStatus = status.value,
                    totalEpisodes = totalEpisodes
                )
            )
        }
    }

    private suspend fun syncEpisodeProgressToBackend(mediaId: Int) {
        val backend = backendApiService ?: return
        val progress = mediaDao.getEpisodeProgress(mediaId).first().map { item ->
            RemoteEpisodeProgressDto(
                seasonNumber = item.seasonNumber,
                episodeNumber = item.episodeNumber,
                isWatched = item.isWatched
            )
        }
        runBackendSync("syncEpisodeProgressToBackend") {
            backend.replaceEpisodeProgress(mediaId, progress)
        }
    }

    private fun RemoteWatchlistItemDto.toEntity(): WatchlistEntity {
        return WatchlistEntity(
            id = id,
            title = title,
            posterPath = posterPath,
            mediaType = mediaType,
            contentCategory = contentCategory,
            contentStatus = contentStatus,
            totalEpisodes = totalEpisodes
        )
    }

    private fun RemoteEpisodeProgressDto.toEntity(mediaId: Int): EpisodeProgressEntity {
        return EpisodeProgressEntity(
            mediaId = mediaId,
            seasonNumber = seasonNumber,
            episodeNumber = episodeNumber,
            isWatched = isWatched
        )
    }

    private fun WatchlistEntity.toRemoteDto(): RemoteWatchlistItemDto {
        return RemoteWatchlistItemDto(
            id = id,
            title = title,
            posterPath = posterPath,
            mediaType = mediaType,
            contentCategory = contentCategory,
            contentStatus = contentStatus,
            totalEpisodes = totalEpisodes
        )
    }

    private fun AnimeStructure.toBackendDto(): BackendAnimeStructureDto {
        return BackendAnimeStructureDto(
            title = title,
            aliases = aliases,
            season = season,
            seasonYear = seasonYear,
            seasons = seasons.map { seasonRange ->
                BackendAnimeStructureSeasonDto(
                    seasonNumber = seasonRange.seasonNumber,
                    name = seasonRange.name,
                    startEpisode = seasonRange.startEpisode,
                    endEpisode = seasonRange.endEpisode
                )
            }
        )
    }

    private fun RemoteWatchlistItemDto.matches(other: RemoteWatchlistItemDto): Boolean {
        return id == other.id &&
            title == other.title &&
            posterPath == other.posterPath &&
            mediaType == other.mediaType &&
            contentCategory == other.contentCategory &&
            contentStatus == other.contentStatus &&
            totalEpisodes == other.totalEpisodes
    }

    private fun List<EpisodeProgressEntity>.matchesRemote(remote: List<RemoteEpisodeProgressDto>): Boolean {
        val localSet = map { Triple(it.seasonNumber, it.episodeNumber, it.isWatched) }.toSet()
        val remoteSet = remote.map { Triple(it.seasonNumber, it.episodeNumber, it.isWatched) }.toSet()
        return localSet == remoteSet
    }

    private suspend fun runBackendSync(operation: String, block: suspend () -> Unit) {
        if (backendApiService == null) return
        try {
            block()
        } catch (e: Exception) {
            Log.w(TAG, "Backend sync failed for $operation", e)
        }
    }

    private fun AnimeStructure.matchesTitle(normalizedTitle: String): Boolean {
        return listOf(title, *aliases.toTypedArray())
            .map { it.toNormalizedTitle() }
            .any { it == normalizedTitle }
    }

    private fun String?.toSeasonLabel(): String? {
        val month = this?.takeIf { it.length >= 7 }?.substring(5, 7)?.toIntOrNull() ?: return null
        return when (month) {
            12, 1, 2 -> "WINTER"
            3, 4, 5 -> "SPRING"
            6, 7, 8 -> "SUMMER"
            9, 10, 11 -> "FALL"
            else -> null
        }
    }

    private fun String.toNormalizedTitle(): String {
        return lowercase(Locale.ROOT)
            .replace(Regex("[^\\p{L}\\p{Nd}]+"), "")
    }

    private companion object {
        const val SEASON_SPLIT_DAYS = 70L
        const val BACKEND_SYNC_MIN_INTERVAL_MILLIS = 60_000L
        const val TAG = "MediaRepository"
    }
}

internal data class WatchlistItemKey(
    val id: Int,
    val mediaType: String,
    val contentCategory: String
)

internal fun mergeEpisodeProgressByMediaId(
    localProgressByMediaId: Map<Int, List<EpisodeProgressEntity>>,
    remoteProgressByMediaId: Map<Int, List<RemoteEpisodeProgressDto>>
): Map<Int, List<EpisodeProgressEntity>> {
    val allMediaIds = localProgressByMediaId.keys + remoteProgressByMediaId.keys
    return allMediaIds.associateWith { mediaId ->
        val localByKey = localProgressByMediaId[mediaId].orEmpty().associateBy {
            it.seasonNumber to it.episodeNumber
        }
        val remoteByKey = remoteProgressByMediaId[mediaId].orEmpty().associateBy {
            it.seasonNumber to it.episodeNumber
        }
        (localByKey.keys + remoteByKey.keys).map { key ->
            val local = localByKey[key]
            val remote = remoteByKey[key]
            EpisodeProgressEntity(
                mediaId = mediaId,
                seasonNumber = key.first,
                episodeNumber = key.second,
                isWatched = (local?.isWatched == true) || (remote?.isWatched == true),
                updatedAt = local?.updatedAt ?: System.currentTimeMillis()
            )
        }
    }
}

internal fun mergeWatchlistEntities(
    localWatchlist: List<WatchlistEntity>,
    remoteWatchlist: List<RemoteWatchlistItemDto>,
    mergedProgressByMediaId: Map<Int, List<EpisodeProgressEntity>>
): List<WatchlistEntity> {
    val localByKey = localWatchlist.associateBy {
        WatchlistItemKey(
            id = it.id,
            mediaType = it.mediaType,
            contentCategory = it.contentCategory
        )
    }
    val remoteByKey = remoteWatchlist.associateBy {
        WatchlistItemKey(
            id = it.id,
            mediaType = it.mediaType,
            contentCategory = it.contentCategory
        )
    }
    val keys = localByKey.keys + remoteByKey.keys

    return keys.map { key ->
        val local = localByKey[key]
        val remote = remoteByKey[key]
        val mergedTotalEpisodes = maxOf(
            local?.totalEpisodes ?: 0,
            remote?.totalEpisodes ?: 0
        )
        val mergedStatus = resolveMergedStatus(
            mediaType = key.mediaType,
            category = key.contentCategory,
            localStatusRaw = local?.contentStatus,
            remoteStatusRaw = remote?.contentStatus,
            watchedEpisodes = mergedProgressByMediaId[key.id].orEmpty().count { it.isWatched },
            totalEpisodes = mergedTotalEpisodes
        )
        WatchlistEntity(
            id = key.id,
            title = local?.title ?: remote?.title.orEmpty(),
            posterPath = local?.posterPath ?: remote?.posterPath,
            mediaType = key.mediaType,
            contentCategory = key.contentCategory,
            contentStatus = mergedStatus.value,
            totalEpisodes = mergedTotalEpisodes,
            addedAt = local?.addedAt ?: System.currentTimeMillis()
        )
    }
}

private fun resolveMergedStatus(
    mediaType: String,
    category: String,
    localStatusRaw: String?,
    remoteStatusRaw: String?,
    watchedEpisodes: Int,
    totalEpisodes: Int
): WatchStatus {
    val mediaTypeValue = MediaType.fromString(mediaType)
    val categoryValue = WatchCategory.fromString(category)
    val localStatus = WatchStatus.fromString(localStatusRaw)
    val remoteStatus = WatchStatus.fromString(remoteStatusRaw)
    val statusFromProgress = when (mediaTypeValue) {
        MediaType.MOVIE -> if (watchedEpisodes > 0) WatchStatus.WATCHED else WatchStatus.NOT_WATCHED
        MediaType.TV -> when {
            watchedEpisodes <= 0 -> WatchStatus.NOT_STARTED
            totalEpisodes > 0 && watchedEpisodes >= totalEpisodes -> WatchStatus.COMPLETED
            else -> WatchStatus.IN_PROGRESS
        }
    }

    val priorityOrder = when (categoryValue) {
        WatchCategory.FILMS -> listOf(WatchStatus.NOT_WATCHED, WatchStatus.WATCHED)
        WatchCategory.SERIES, WatchCategory.ANIME -> listOf(
            WatchStatus.NOT_STARTED,
            WatchStatus.IN_PROGRESS,
            WatchStatus.UP_TO_DATE,
            WatchStatus.COMPLETED
        )
    }

    return listOf(localStatus, remoteStatus, statusFromProgress)
        .maxBy { status -> priorityOrder.indexOf(status).coerceAtLeast(0) }
}
