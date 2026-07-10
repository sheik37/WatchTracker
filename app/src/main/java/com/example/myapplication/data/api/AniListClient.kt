package com.example.myapplication.data.api

import com.example.myapplication.data.model.Season
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject

class AniListClient(
    private val client: OkHttpClient
) {
    suspend fun getAnimeSeasons(query: String): List<Season> = withContext(Dispatchers.IO) {
        val candidates = searchAnime(query)
        val chain = buildSeasonChain(candidates)
        if (chain.size <= 1) return@withContext emptyList()
        chain.sortedBy { it.sortKey() }.mapIndexed { index, item ->
            Season(
                id = item.id,
                name = item.displaySeasonName(),
                seasonNumber = index + 1,
                episodeCount = item.episodes,
                episodes = emptyList()
            )
        }
    }

    private fun searchAnime(query: String): List<AniListMedia> {
        val payload = graphqlPayload(
            query = """
                query (${'$'}search: String) {
                  Page(page: 1, perPage: 10) {
                    media(search: ${'$'}search, type: ANIME, sort: SEARCH_MATCH) {
                      id
                      episodes
                      season
                      seasonYear
                      format
                      title {
                        romaji
                        english
                        native
                      }
                      relations {
                        edges {
                          relationType
                          node {
                            id
                            episodes
                            seasonYear
                            format
                            title {
                              romaji
                              english
                              native
                            }
                          }
                        }
                      }
                    }
                  }
                }
            """.trimIndent(),
            variables = JSONObject().put("search", query)
        )
        val response = executeQuery(payload)
        val mediaArray = response
            .optJSONObject("data")
            ?.optJSONObject("Page")
            ?.optJSONArray("media")
            ?: return emptyList()
        return mediaArray.toAnimeMediaList()
    }

    private fun fetchAnimeById(id: Int): AniListMedia? {
        val payload = graphqlPayload(
            query = """
                query (${'$'}id: Int) {
                  Media(id: ${'$'}id, type: ANIME) {
                    id
                    episodes
                    season
                    seasonYear
                    format
                    title {
                      romaji
                      english
                      native
                    }
                    relations {
                      edges {
                        relationType
                        node {
                          id
                          episodes
                          seasonYear
                          format
                          title {
                            romaji
                            english
                            native
                          }
                        }
                      }
                    }
                  }
                }
            """.trimIndent(),
            variables = JSONObject().put("id", id)
        )
        val response = executeQuery(payload)
        return response
            .optJSONObject("data")
            ?.optJSONObject("Media")
            ?.toAnimeMedia()
    }

    private fun buildSeasonChain(candidates: List<AniListMedia>): List<AniListMedia> {
        if (candidates.isEmpty()) return emptyList()

        val allNodes = mutableMapOf<Int, AniListMedia>()
        val queue = candidates.toMutableList()

        while (queue.isNotEmpty()) {
            val current = queue.removeAt(0)
            if (allNodes.containsKey(current.id)) continue
            allNodes[current.id] = current

            current.previousSeasonId()?.let { previousId ->
                if (!allNodes.containsKey(previousId)) {
                    fetchAnimeById(previousId)?.let(queue::add)
                }
            }
            current.nextSeasonId()?.let { nextId ->
                if (!allNodes.containsKey(nextId)) {
                    fetchAnimeById(nextId)?.let(queue::add)
                }
            }
        }

        return allNodes.values
            .filter { it.isSeasonCandidate() }
            .distinctBy { it.id }
    }

    private fun AniListMedia.previousSeasonId(): Int? {
        return relations.firstOrNull { it.relationType == "PREQUEL" }?.node?.id
    }

    private fun AniListMedia.nextSeasonId(): Int? {
        return relations.firstOrNull { it.relationType == "SEQUEL" }?.node?.id
    }

    private fun AniListMedia.isSeasonCandidate(): Boolean {
        return episodes > 0 && format in setOf("TV", "TV_SHORT", "ONA")
    }

    private fun AniListMedia.displaySeasonName(): String {
        val seasonLabel = season?.toFrenchLabel().orEmpty()
        val yearLabel = seasonYear?.toString().orEmpty()
        return listOf(seasonLabel, yearLabel)
            .filter { it.isNotBlank() }
            .joinToString(" ")
            .ifBlank { displayTitle }
    }

    private fun AniListMedia.sortKey(): Int {
        val year = seasonYear ?: Int.MAX_VALUE
        val seasonOrder = when (season?.uppercase()) {
            "WINTER" -> 0
            "SPRING" -> 1
            "SUMMER" -> 2
            "FALL" -> 3
            else -> 4
        }
        return year * 10 + seasonOrder
    }

    private fun JSONObject.toAnimeMedia(): AniListMedia {
        val title = optJSONObject("title") ?: JSONObject()
        return AniListMedia(
            id = optInt("id"),
            episodes = optInt("episodes"),
            season = if (has("season") && !isNull("season")) optString("season") else null,
            seasonYear = if (has("seasonYear") && !isNull("seasonYear")) optInt("seasonYear") else null,
            format = optString("format"),
            displayTitle = title.optString("romaji")
                .ifBlank { title.optString("english") }
                .ifBlank { title.optString("native") }
                .ifBlank { "Anime" },
            relations = optJSONObject("relations")
                ?.optJSONArray("edges")
                .toRelationList()
        )
    }

    private fun JSONArray?.toAnimeMediaList(): List<AniListMedia> {
        if (this == null) return emptyList()
        val items = mutableListOf<AniListMedia>()
        for (index in 0 until length()) {
            getJSONObject(index).toAnimeMedia().also { items += it }
        }
        return items
    }

    private fun JSONArray?.toRelationList(): List<AniListRelation> {
        if (this == null) return emptyList()
        val items = mutableListOf<AniListRelation>()
        for (index in 0 until length()) {
            val edge = getJSONObject(index)
            val node = edge.optJSONObject("node") ?: continue
            items += AniListRelation(
                relationType = edge.optString("relationType"),
                node = AniListNode(
                    id = node.optInt("id"),
                    episodes = node.optInt("episodes"),
                    season = if (node.has("season") && !node.isNull("season")) node.optString("season") else null,
                    seasonYear = if (node.has("seasonYear") && !node.isNull("seasonYear")) node.optInt("seasonYear") else null,
                    format = node.optString("format"),
                    displayTitle = node.optJSONObject("title")
                        ?.optString("romaji")
                        .orEmpty()
                        .ifBlank { node.optJSONObject("title")?.optString("english").orEmpty() }
                        .ifBlank { node.optJSONObject("title")?.optString("native").orEmpty() }
                )
            )
        }
        return items
    }

    private fun executeQuery(payload: JSONObject): JSONObject {
        val request = Request.Builder()
            .url("https://graphql.anilist.co")
            .post(payload.toString().toRequestBody("application/json".toMediaType()))
            .build()

        client.newCall(request).execute().use { response ->
            val body = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                throw IllegalStateException("AniList HTTP ${response.code}: $body")
            }
            return JSONObject(body)
        }
    }

    private fun graphqlPayload(query: String, variables: JSONObject): JSONObject {
        return JSONObject()
            .put("query", query)
            .put("variables", variables)
    }

    private fun String.toFrenchLabel(): String = when (uppercase()) {
        "SPRING" -> "Printemps"
        "SUMMER" -> "Été"
        "FALL" -> "Automne"
        "WINTER" -> "Hiver"
        else -> this
    }

    private data class AniListMedia(
        val id: Int,
        val episodes: Int,
        val season: String?,
        val seasonYear: Int?,
        val format: String,
        val displayTitle: String,
        val relations: List<AniListRelation>
    )

    private data class AniListRelation(
        val relationType: String,
        val node: AniListNode
    )

    private data class AniListNode(
        val id: Int,
        val episodes: Int,
        val season: String?,
        val seasonYear: Int?,
        val format: String,
        val displayTitle: String
    )
}
