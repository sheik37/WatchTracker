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

    val retryBlockedUntilMillisFlow: Flow<Long?> = preferencesFlow
        .map { prefs -> prefs[RETRY_BLOCKED_UNTIL_MILLIS_KEY] }

    suspend fun saveToken(token: String) {
        context.authDataStore.edit { prefs ->
            prefs[TOKEN_KEY] = token
        }
    }

    suspend fun clearToken() {
        context.authDataStore.edit { prefs ->
            prefs.remove(TOKEN_KEY)
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
        val RETRY_BLOCKED_UNTIL_MILLIS_KEY = longPreferencesKey("auth_retry_blocked_until_ms")
    }
}
