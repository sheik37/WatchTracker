package com.example.myapplication.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp

@Composable
fun AuthScreen(
    isLoading: Boolean,
    errorMessage: String?,
    retryAfterSeconds: Int?,
    attemptsRemaining: Int?,
    onLogin: (username: String, password: String) -> Unit,
    onRegister: (username: String, password: String) -> Unit
) {
    var isRegisterMode by remember { mutableStateOf(false) }
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }

    val isRateLimited = (retryAfterSeconds ?: 0) > 0
    val canSubmit = username.isNotBlank() && password.length >= 8 && !isLoading && !isRateLimited
    val submitLabel = if (isRegisterMode) "Créer un compte" else "Se connecter"
    val modeTitle = if (isRegisterMode) "Inscription" else "Connexion"
    val modeSubtitle = if (isRegisterMode) {
        "Crée un compte personnel pour ta propre liste."
    } else {
        "Connecte-toi pour charger ta liste personnelle."
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = "WatchTracker",
            style = MaterialTheme.typography.headlineMedium
        )
        Text(
            text = modeTitle,
            style = MaterialTheme.typography.titleLarge,
            modifier = Modifier.padding(top = 8.dp)
        )
        Text(
            text = modeSubtitle,
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.padding(top = 8.dp, bottom = 24.dp)
        )

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            if (!isRegisterMode) {
                Button(
                    onClick = { isRegisterMode = false },
                    enabled = !isLoading,
                    modifier = Modifier.weight(1f)
                ) {
                    Text("Connexion")
                }
            } else {
                OutlinedButton(
                    onClick = { isRegisterMode = false },
                    enabled = !isLoading,
                    modifier = Modifier.weight(1f)
                ) {
                    Text("Connexion")
                }
            }

            if (isRegisterMode) {
                Button(
                    onClick = { isRegisterMode = true },
                    enabled = !isLoading,
                    modifier = Modifier.weight(1f)
                ) {
                    Text("Inscription")
                }
            } else {
                OutlinedButton(
                    onClick = { isRegisterMode = true },
                    enabled = !isLoading,
                    modifier = Modifier.weight(1f)
                ) {
                    Text("Inscription")
                }
            }
        }

        OutlinedTextField(
            value = username,
            onValueChange = { username = it },
            label = { Text("Nom d'utilisateur") },
            enabled = !isLoading,
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )

        OutlinedTextField(
            value = password,
            onValueChange = { password = it },
            label = { Text("Mot de passe (min 8 caractères)") },
            enabled = !isLoading,
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 12.dp)
        )

        if (!errorMessage.isNullOrBlank()) {
            Text(
                text = errorMessage,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 12.dp)
            )
        }

        if (isRateLimited) {
            Text(
                text = "Trop de tentatives. Réessaie dans ${retryAfterSeconds}s.",
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp)
            )
        } else if (attemptsRemaining != null) {
            Text(
                text = "Tentatives restantes avant blocage : $attemptsRemaining",
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp)
            )
        }

        Button(
            onClick = {
                val cleanUsername = username.trim()
                if (isRegisterMode) {
                    onRegister(cleanUsername, password)
                } else {
                    onLogin(cleanUsername, password)
                }
            },
            enabled = canSubmit,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 20.dp)
        ) {
            if (isLoading) {
                CircularProgressIndicator(
                    modifier = Modifier.padding(2.dp),
                    strokeWidth = 2.dp
                )
            } else {
                Text(submitLabel)
            }
        }

    }
}
