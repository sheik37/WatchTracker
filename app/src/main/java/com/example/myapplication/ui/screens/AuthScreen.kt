package com.example.myapplication.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp

@Composable
fun AuthScreen(
    isLoading: Boolean,
    errorMessage: String?,
    infoMessage: String?,
    retryAfterSeconds: Int?,
    attemptsRemaining: Int?,
    showResendVerification: Boolean,
    admin2faEmail: String?,
    showOtpCodeField: Boolean,
    resendCooldownSeconds: Int?,
    forgotPasswordCooldownSeconds: Int?,
    onLogin: (email: String, password: String, otpCode: String?) -> Unit,
    onRegister: (email: String, password: String) -> Unit,
    onResendVerification: (email: String) -> Unit,
    onForgotPassword: (email: String) -> Unit
) {
    var isRegisterMode by remember { mutableStateOf(false) }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var otpCode by remember { mutableStateOf("") }

    val isRateLimited = (retryAfterSeconds ?: 0) > 0
    val isAdminLoginTarget = admin2faEmail
        ?.takeIf { it.isNotBlank() }
        ?.equals(email.trim(), ignoreCase = true) == true
    val shouldShowOtpField = !isRegisterMode && (showOtpCodeField || isAdminLoginTarget)
    val hasMinLength = password.length >= 10
    val hasLower = password.any { it.isLowerCase() }
    val hasUpper = password.any { it.isUpperCase() }
    val hasDigit = password.any { it.isDigit() }
    val hasSymbol = password.any { !it.isLetterOrDigit() }
    val registerPasswordValid = hasMinLength && hasLower && hasUpper && hasDigit && hasSymbol
    val canSubmit = if (isRegisterMode) {
        email.contains("@") && registerPasswordValid && !isLoading && !isRateLimited
    } else {
        email.contains("@") &&
            password.isNotBlank() &&
            (!shouldShowOtpField || otpCode.length >= 6) &&
            !isLoading &&
            !isRateLimited
    }
    val resendCooldown = resendCooldownSeconds ?: 0
    val forgotCooldown = forgotPasswordCooldownSeconds ?: 0
    val canResendVerification = isRegisterMode &&
        showResendVerification &&
        email.contains("@") &&
        !isLoading &&
        !isRateLimited &&
        resendCooldown <= 0
    val canForgotPassword = !isRegisterMode &&
        email.contains("@") &&
        !isLoading &&
        !isRateLimited &&
        forgotCooldown <= 0
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
            value = email,
            onValueChange = { email = it },
            label = { Text("Adresse mail") },
            enabled = !isLoading,
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )

        OutlinedTextField(
            value = password,
            onValueChange = { password = it },
            label = {
                if (isRegisterMode) {
                    Text("Mot de passe (10+, min/maj/chiffre/symbole)")
                } else {
                    Text("Mot de passe")
                }
            },
            enabled = !isLoading,
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 12.dp)
        )

        if (shouldShowOtpField) {
            OutlinedTextField(
                value = otpCode,
                onValueChange = { value ->
                    otpCode = value.filter { it.isDigit() }.take(8)
                },
                label = { Text("Code 2FA (admin)") },
                enabled = !isLoading,
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 12.dp)
            )
        }

        if (isRegisterMode) {
            val checks = listOf(
                "10 caractères minimum" to hasMinLength,
                "au moins une minuscule" to hasLower,
                "au moins une majuscule" to hasUpper,
                "au moins un chiffre" to hasDigit,
                "au moins un symbole" to hasSymbol
            )
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp)
            ) {
                checks.forEach { (label, isValid) ->
                    val prefix = if (isValid) "• ✓ " else "• ✗ "
                    val color = if (isValid) {
                        Color(0xFF2E7D32)
                    } else {
                        MaterialTheme.colorScheme.error
                    }
                    Text(
                        text = prefix + label,
                        color = color,
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.padding(top = 2.dp)
                    )
                }
            }
        }

        if (!errorMessage.isNullOrBlank()) {
            Text(
                text = errorMessage,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 12.dp)
            )
        }

        if (!infoMessage.isNullOrBlank()) {
            Text(
                text = infoMessage,
                color = MaterialTheme.colorScheme.primary,
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
                val cleanEmail = email.trim()
                if (isRegisterMode) {
                    onRegister(cleanEmail, password)
                } else {
                    onLogin(cleanEmail, password, if (shouldShowOtpField) otpCode else null)
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

        if (!isRegisterMode) {
            OutlinedButton(
                onClick = { onForgotPassword(email.trim()) },
                enabled = canForgotPassword,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 10.dp)
            ) {
                if (forgotCooldown > 0) {
                    Text("Mot de passe oublié (${forgotCooldown}s)")
                } else {
                    Text("Mot de passe oublié")
                }
            }
        }

        if (isRegisterMode && showResendVerification) {
            OutlinedButton(
                onClick = { onResendVerification(email.trim()) },
                enabled = canResendVerification,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 10.dp)
            ) {
                if (resendCooldown > 0) {
                    Text("Renvoyer l'email (${resendCooldown}s)")
                } else {
                    Text("Renvoyer l'email de vérification")
                }
            }
        }

    }
}
