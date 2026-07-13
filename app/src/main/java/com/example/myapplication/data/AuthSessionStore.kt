package com.example.myapplication.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import java.io.IOException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map

private val Context.authDataStore: DataStore<Preferences> by preferencesDataStore(name = "auth_session")

class AuthSessionStore(private val context: Context) {
    private val preferencesFlow: Flow<Preferences> = context.authDataStore.data
        .catch { exception ->
            if (exception is IOException) {
                emit(emptyPreferences())
            } else {
                throw exception
            }
        }

    val tokenFlow: Flow<String?> = preferencesFlow
        .map { prefs -> prefs[TOKEN_KEY] }

    val refreshTokenFlow: Flow<String?> = preferencesFlow
        .map { prefs -> prefs[REFRESH_TOKEN_KEY] }

    val tokenExpiresAtMillisFlow: Flow<Long?> = preferencesFlow
        .map { prefs -> prefs[TOKEN_EXPIRES_AT_MILLIS_KEY] }

    val retryBlockedUntilMillisFlow: Flow<Long?> = preferencesFlow
        .map { prefs -> prefs[RETRY_BLOCKED_UNTIL_MILLIS_KEY] }

    val usernameFlow: Flow<String?> = preferencesFlow
        .map { prefs -> prefs[USERNAME_KEY] }

    val userIdFlow: Flow<Int?> = preferencesFlow
        .map { prefs -> prefs[USER_ID_KEY]?.toInt() }

    val profileSyncedAtMillisFlow: Flow<Long?> = preferencesFlow
        .map { prefs -> prefs[PROFILE_SYNCED_AT_MILLIS_KEY] }

    suspend fun saveTokens(token: String, refreshToken: String?, expiresInSeconds: Int) {
        val expiresAt = System.currentTimeMillis() + (expiresInSeconds.toLong() * 1000L)
        context.authDataStore.edit { prefs ->
            prefs[TOKEN_KEY] = token
            if (refreshToken.isNullOrBlank()) {
                prefs.remove(REFRESH_TOKEN_KEY)
            } else {
                prefs[REFRESH_TOKEN_KEY] = refreshToken
            }
            prefs[TOKEN_EXPIRES_AT_MILLIS_KEY] = expiresAt
        }
    }

    suspend fun clearTokens() {
        context.authDataStore.edit { prefs ->
            prefs.remove(TOKEN_KEY)
            prefs.remove(REFRESH_TOKEN_KEY)
            prefs.remove(TOKEN_EXPIRES_AT_MILLIS_KEY)
        }
    }

    suspend fun saveUsername(username: String) {
        context.authDataStore.edit { prefs ->
            prefs[USERNAME_KEY] = username
        }
    }

    suspend fun clearUsername() {
        context.authDataStore.edit { prefs ->
            prefs.remove(USERNAME_KEY)
        }
    }

    suspend fun saveUserProfile(email: String, userId: Int) {
        context.authDataStore.edit { prefs ->
            prefs[USERNAME_KEY] = email
            prefs[USER_ID_KEY] = userId.toLong()
            prefs[PROFILE_SYNCED_AT_MILLIS_KEY] = System.currentTimeMillis()
        }
    }

    suspend fun clearUserProfile() {
        context.authDataStore.edit { prefs ->
            prefs.remove(USERNAME_KEY)
            prefs.remove(USER_ID_KEY)
            prefs.remove(PROFILE_SYNCED_AT_MILLIS_KEY)
        }
    }

    suspend fun saveRetryBlockedUntil(untilMillis: Long) {
        context.authDataStore.edit { prefs ->
            prefs[RETRY_BLOCKED_UNTIL_MILLIS_KEY] = untilMillis
        }
    }

    suspend fun clearRetryBlockedUntil() {
        context.authDataStore.edit { prefs ->
            prefs.remove(RETRY_BLOCKED_UNTIL_MILLIS_KEY)
        }
    }

    private companion object {
        val TOKEN_KEY = stringPreferencesKey("backend_auth_token")
        val REFRESH_TOKEN_KEY = stringPreferencesKey("backend_refresh_token")
        val TOKEN_EXPIRES_AT_MILLIS_KEY = longPreferencesKey("backend_token_expires_at_ms")
        val RETRY_BLOCKED_UNTIL_MILLIS_KEY = longPreferencesKey("auth_retry_blocked_until_ms")
        val USERNAME_KEY = stringPreferencesKey("backend_username")
        val USER_ID_KEY = longPreferencesKey("backend_user_id")
        val PROFILE_SYNCED_AT_MILLIS_KEY = longPreferencesKey("backend_profile_synced_at_ms")
    }
}
