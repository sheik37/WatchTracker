package com.example.myapplication.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.example.myapplication.BuildConfig
import com.example.myapplication.R
import kotlinx.coroutines.launch
import retrofit2.HttpException

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileScreen(
    accountEmail: String?,
    displayName: String?,
    userId: Int?,
    settingsVisible: Boolean,
    onDisplayNameChange: (String?) -> Unit,
    onChangePassword: suspend (currentPassword: String, newPassword: String) -> String,
    onPasswordChanged: () -> Unit,
    onCheckForUpdates: suspend () -> String,
    onDeleteAccount: suspend () -> String,
    onSettingsVisibilityChanged: (Boolean) -> Unit,
    onLogout: () -> Unit
) {
    val scope = rememberCoroutineScope()
    var menuExpanded by rememberSaveable { mutableStateOf(false) }
    var showChangePasswordScreen by rememberSaveable { mutableStateOf(false) }
    var showDeleteAccountScreen by rememberSaveable { mutableStateOf(false) }
    var showAboutScreen by rememberSaveable { mutableStateOf(false) }
    var selectedSettingsTab by rememberSaveable { mutableStateOf(0) }
    var showDisplayNameDialog by rememberSaveable { mutableStateOf(false) }
    var showDiscardChangesDialog by rememberSaveable { mutableStateOf(false) }
    var draftDisplayName by rememberSaveable { mutableStateOf("") }
    var pendingDisplayName by rememberSaveable { mutableStateOf("") }
    var currentPassword by rememberSaveable { mutableStateOf("") }
    var newPassword by rememberSaveable { mutableStateOf("") }
    var confirmPassword by rememberSaveable { mutableStateOf("") }
    var changePasswordError by rememberSaveable { mutableStateOf<String?>(null) }
    var changePasswordInProgress by rememberSaveable { mutableStateOf(false) }
    var deleteAccountError by rememberSaveable { mutableStateOf<String?>(null) }
    var deleteAccountInProgress by rememberSaveable { mutableStateOf(false) }
    var updateCheckMessage by rememberSaveable { mutableStateOf<String?>(null) }
    var updateCheckInProgress by rememberSaveable { mutableStateOf(false) }

    val effectiveDisplayName = displayName?.ifBlank { null } ?: userId?.toString() ?: "Non disponible"
    val userIdAsDefaultName = userId?.toString() ?: "Non disponible"
    val hasPendingDisplayNameChanges = pendingDisplayName.trim() != effectiveDisplayName
    val settingsOrSubScreenVisible = settingsVisible || showChangePasswordScreen || showDeleteAccountScreen || showAboutScreen
    val canSubmitPasswordChange =
        currentPassword.isNotBlank() &&
            newPassword.isNotBlank() &&
            confirmPassword.isNotBlank() &&
            !changePasswordInProgress

    LaunchedEffect(displayName, userId) {
        pendingDisplayName = effectiveDisplayName
    }

    LaunchedEffect(settingsVisible, showChangePasswordScreen, showDeleteAccountScreen) {
        if (settingsVisible || showChangePasswordScreen || showDeleteAccountScreen) {
            onSettingsVisibilityChanged(true)
        }
    }

    BackHandler(enabled = settingsOrSubScreenVisible) {
        if (showChangePasswordScreen) {
            showChangePasswordScreen = false
        } else if (showDeleteAccountScreen) {
            showDeleteAccountScreen = false
        } else if (showAboutScreen) {
            showAboutScreen = false
        } else if (selectedSettingsTab == 0 && hasPendingDisplayNameChanges) {
            showDiscardChangesDialog = true
        } else {
            onSettingsVisibilityChanged(false)
        }
    }

    Scaffold(
        topBar = {
            if (settingsOrSubScreenVisible) {
                CenterAlignedTopAppBar(
                    title = {
                        if (showDeleteAccountScreen) {
                            Text("")
                        } else if (showAboutScreen) {
                            Text("À propos")
                        } else {
                            Text(if (showChangePasswordScreen) "Modifier le mot de passe" else "Paramètres")
                        }
                    },
                    navigationIcon = {
                        IconButton(
                            onClick = {
                                if (showChangePasswordScreen) {
                                    showChangePasswordScreen = false
                                } else if (showDeleteAccountScreen) {
                                    showDeleteAccountScreen = false
                                } else if (showAboutScreen) {
                                    showAboutScreen = false
                                } else {
                                    if (selectedSettingsTab == 0 && hasPendingDisplayNameChanges) {
                                        showDiscardChangesDialog = true
                                    } else {
                                        onSettingsVisibilityChanged(false)
                                    }
                                }
                            }
                        ) {
                            Icon(
                                Icons.AutoMirrored.Rounded.ArrowBack,
                                contentDescription = "Retour"
                            )
                        }
                    }
                )
            } else {
                TopAppBar(
                    title = { Text("Profil") },
                    actions = {
                        IconButton(onClick = { menuExpanded = true }) {
                            Icon(Icons.Rounded.MoreVert, contentDescription = "Plus d'options")
                        }
                        DropdownMenu(
                            expanded = menuExpanded,
                            onDismissRequest = { menuExpanded = false }
                        ) {
                            DropdownMenuItem(
                                text = { Text("Paramètres") },
                                leadingIcon = { Icon(Icons.Rounded.Settings, contentDescription = null) },
                                onClick = {
                                    menuExpanded = false
                                    selectedSettingsTab = 0
                                    onSettingsVisibilityChanged(true)
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("À propos") },
                                leadingIcon = { Icon(Icons.Rounded.Info, contentDescription = null) },
                                onClick = {
                                    menuExpanded = false
                                    showAboutScreen = true
                                }
                            )
                        }
                    }
                )
            }
        }
    ) { padding ->
        if (showChangePasswordScreen) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                OutlinedTextField(
                    value = currentPassword,
                    onValueChange = { currentPassword = it },
                    label = { Text("Mot de passe actuel") },
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true,
                    enabled = !changePasswordInProgress,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = newPassword,
                    onValueChange = { newPassword = it },
                    label = { Text("Nouveau mot de passe") },
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true,
                    enabled = !changePasswordInProgress,
                    modifier = Modifier.fillMaxWidth()
                )
                PasswordCriteriaChecklist(password = newPassword)
                OutlinedTextField(
                    value = confirmPassword,
                    onValueChange = { confirmPassword = it },
                    label = { Text("Confirmer le mot de passe") },
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true,
                    enabled = !changePasswordInProgress,
                    modifier = Modifier.fillMaxWidth()
                )
                PasswordCriteriaChecklist(password = confirmPassword)
                if (!changePasswordError.isNullOrBlank()) {
                    Text(
                        text = changePasswordError ?: "",
                        color = androidx.compose.material3.MaterialTheme.colorScheme.error
                    )
                }
                Button(
                    onClick = {
                        changePasswordError = null
                        if (newPassword != confirmPassword) {
                            changePasswordError = "Les mots de passe ne correspondent pas."
                            return@Button
                        }
                        scope.launch {
                            changePasswordInProgress = true
                            runCatching { onChangePassword(currentPassword, newPassword) }
                                .onSuccess {
                                    changePasswordInProgress = false
                                    onPasswordChanged()
                                }
                                .onFailure { error ->
                                    changePasswordInProgress = false
                                    changePasswordError = error.toPasswordChangeMessage()
                                }
                        }
                    },
                    enabled = canSubmitPasswordChange,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Modifier le mot de passe")
                }
            }
        } else if (showDeleteAccountScreen) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Text(
                    "La suppression du compte est définitive. Toutes vos données liées à ce compte " +
                        "(profil, suivi de contenus, progression des épisodes et sessions actives) " +
                        "seront supprimées de manière irréversible."
                )
                Text(
                    "Conformément aux obligations réglementaires, certaines traces techniques " +
                        "strictement nécessaires à la sécurité et à la conformité peuvent être " +
                        "conservées pour une durée limitée."
                )
                if (!deleteAccountError.isNullOrBlank()) {
                    Text(
                        text = deleteAccountError ?: "",
                        color = androidx.compose.material3.MaterialTheme.colorScheme.error
                    )
                }
                Spacer(modifier = Modifier.weight(1f))
                Button(
                    onClick = {
                        deleteAccountError = null
                        scope.launch {
                            deleteAccountInProgress = true
                            runCatching { onDeleteAccount() }
                                .onFailure { error ->
                                    deleteAccountInProgress = false
                                    deleteAccountError = error.toPasswordChangeMessage()
                                }
                        }
                    },
                    enabled = !deleteAccountInProgress,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Supprimer mon compte")
                }
            }
        } else if (showAboutScreen) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(horizontal = 16.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Spacer(modifier = Modifier.size(16.dp))
                Image(
                    painter = painterResource(id = R.drawable.watchtracker_logo),
                    contentDescription = "Logo WatchTracker",
                    modifier = Modifier.size(120.dp)
                )
                Spacer(modifier = Modifier.size(20.dp))
                ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text("Version", style = androidx.compose.material3.MaterialTheme.typography.titleMedium)
                        Text(BuildConfig.VERSION_NAME)
                        HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
                        Text("Mises à jour", style = androidx.compose.material3.MaterialTheme.typography.titleMedium)
                        Button(
                            onClick = {
                                updateCheckMessage = null
                                scope.launch {
                                    updateCheckInProgress = true
                                    runCatching { onCheckForUpdates() }
                                        .onSuccess { message ->
                                            updateCheckMessage = message
                                            updateCheckInProgress = false
                                        }
                                        .onFailure { error ->
                                            updateCheckMessage = error.message ?: "Impossible de vérifier les mises à jour."
                                            updateCheckInProgress = false
                                        }
                                }
                            },
                            enabled = !updateCheckInProgress,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(if (updateCheckInProgress) "Vérification..." else "Vérifier")
                        }
                        if (!updateCheckMessage.isNullOrBlank()) {
                            Text(
                                text = updateCheckMessage ?: "",
                                color = androidx.compose.material3.MaterialTheme.colorScheme.primary
                            )
                        }
                    }
                }
            }
        } else if (settingsVisible) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
            ) {
                TabRow(selectedTabIndex = selectedSettingsTab) {
                    Tab(
                        selected = selectedSettingsTab == 0,
                        onClick = { selectedSettingsTab = 0 },
                        text = { Text("Compte") }
                    )
                    Tab(
                        selected = selectedSettingsTab == 1,
                        onClick = { selectedSettingsTab = 1 },
                        text = { Text("Application") }
                    )
                }

                if (selectedSettingsTab == 0) {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                            Column(modifier = Modifier.padding(vertical = 12.dp)) {
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(horizontal = 16.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Text(
                                        text = "Identification",
                                        style = androidx.compose.material3.MaterialTheme.typography.titleMedium,
                                        color = androidx.compose.material3.MaterialTheme.colorScheme.primary,
                                        modifier = Modifier.weight(1f)
                                    )
                                    TextButton(
                                        enabled = hasPendingDisplayNameChanges,
                                        onClick = {
                                            val normalized = pendingDisplayName.trim()
                                            val valueToSave = if (normalized.isBlank() || normalized == userIdAsDefaultName) {
                                                null
                                            } else {
                                                normalized
                                            }
                                            onDisplayNameChange(valueToSave)
                                        }
                                    ) {
                                        Text("Sauvegarder")
                                    }
                                }
                                HorizontalDivider(modifier = Modifier.padding(top = 8.dp, bottom = 4.dp))
                                AccountField(
                                    label = "Nom d'utilisateur",
                                    value = pendingDisplayName,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clickable {
                                            draftDisplayName = pendingDisplayName
                                            showDisplayNameDialog = true
                                        }
                                        .padding(horizontal = 16.dp, vertical = 8.dp)
                                )
                                HorizontalDivider()
                                AccountField(
                                    label = "Adresse e-mail",
                                    value = accountEmail?.ifBlank { "Non disponible" } ?: "Non disponible",
                                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                                )
                                HorizontalDivider()
                                AccountField(
                                    label = "Identifiant utilisateur",
                                    value = userId?.toString() ?: "Non disponible",
                                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                                )
                                HorizontalDivider()
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clickable {
                                            currentPassword = ""
                                            newPassword = ""
                                            confirmPassword = ""
                                            changePasswordError = null
                                            showChangePasswordScreen = true
                                        }
                                        .padding(horizontal = 16.dp, vertical = 12.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Text(
                                        text = "Modifier le mot de passe",
                                        modifier = Modifier.weight(1f)
                                    )
                                    Text(">")
                                }
                            }
                        }
                        Spacer(modifier = Modifier.weight(1f))
                        Button(
                            onClick = onLogout,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text("Se déconnecter")
                        }
                        Text(
                            text = "Supprimer le compte",
                            color = androidx.compose.material3.MaterialTheme.colorScheme.error,
                            modifier = Modifier
                                .align(Alignment.CenterHorizontally)
                                .clickable {
                                    deleteAccountError = null
                                    deleteAccountInProgress = false
                                    showDeleteAccountScreen = true
                                }
                                .padding(top = 8.dp)
                        )
                    }
                } else {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                            Column(
                                modifier = Modifier.padding(16.dp),
                                verticalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                Text("Application")
                                Text("Configuration de l'application bientôt disponible.")
                            }
                        }
                    }
                }
            }
        } else {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text("Informations du compte")
                        Text("Nom d'utilisateur : $effectiveDisplayName")
                        Text("Adresse e-mail : ${accountEmail?.ifBlank { "Non disponible" } ?: "Non disponible"}")
                        Text("API backend : ${if (BuildConfig.BACKEND_BASE_URL.isBlank()) "Non configurée" else BuildConfig.BACKEND_BASE_URL}")
                        Text("Session : connectée")
                    }
                }
            }
        }
    }

    if (showDisplayNameDialog) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { showDisplayNameDialog = false },
            title = { Text("Modifier le nom d'utilisateur") },
            text = {
                OutlinedTextField(
                    value = draftDisplayName,
                    onValueChange = { draftDisplayName = it },
                    singleLine = true,
                    label = { Text("Nom d'utilisateur") },
                    modifier = Modifier.fillMaxWidth()
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        pendingDisplayName = draftDisplayName.trim().ifBlank { userIdAsDefaultName }
                        showDisplayNameDialog = false
                    }
                ) {
                    Text("Enregistrer")
                }
            },
            dismissButton = {
                TextButton(onClick = { showDisplayNameDialog = false }) {
                    Text("Annuler")
                }
            }
        )
    }

    if (showDiscardChangesDialog) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { showDiscardChangesDialog = false },
            title = { Text("Annuler les modifications ?") },
            text = { Text("Cette page contient des modifications non enregistrées") },
            confirmButton = {
                TextButton(
                    onClick = {
                        showDiscardChangesDialog = false
                        pendingDisplayName = effectiveDisplayName
                        onSettingsVisibilityChanged(false)
                    }
                ) {
                    Text("Confirmer")
                }
            },
            dismissButton = {
                TextButton(onClick = { showDiscardChangesDialog = false }) {
                    Text("Annuler")
                }
            }
        )
    }
}

private fun Throwable.toPasswordChangeMessage(): String {
    return when (this) {
        is HttpException -> {
            val detail = response()?.errorBody()?.string()?.let { raw ->
                Regex("\"detail\"\\s*:\\s*\"([^\"]+)\"").find(raw)?.groupValues?.getOrNull(1)
            }
            when (detail) {
                "Current password is invalid" -> "Le mot de passe actuel est incorrect."
                "Password must contain at least 10 characters" -> "Le mot de passe doit contenir au moins 10 caractères."
                "Password must include lower, upper, digit, and symbol" -> "Le mot de passe doit inclure une minuscule, une majuscule, un chiffre et un symbole."
                "New password must be different from current password" -> "Le nouveau mot de passe doit être différent du mot de passe actuel."
                "Password was already used recently" -> "Ce mot de passe a déjà été utilisé récemment."
                else -> "Erreur serveur (${code()})."
            }
        }
        else -> message ?: "Une erreur est survenue."
    }
}

@Composable
private fun PasswordCriteriaChecklist(password: String) {
    val checks = listOf(
        "10 caractères minimum" to (password.length >= 10),
        "au moins une minuscule" to password.any { it.isLowerCase() },
        "au moins une majuscule" to password.any { it.isUpperCase() },
        "au moins un chiffre" to password.any { it.isDigit() },
        "au moins un symbole" to password.any { !it.isLetterOrDigit() }
    )
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 2.dp)
    ) {
        checks.forEach { (label, isValid) ->
            val prefix = if (isValid) "• ✓ " else "• ✗ "
            val color = if (isValid) Color(0xFF2E7D32) else androidx.compose.material3.MaterialTheme.colorScheme.error
            Text(
                text = prefix + label,
                color = color,
                style = androidx.compose.material3.MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(top = 2.dp)
            )
        }
    }
}

@Composable
private fun AccountField(
    label: String,
    value: String,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier) {
        Text(
            text = label,
            style = androidx.compose.material3.MaterialTheme.typography.labelMedium,
            color = androidx.compose.material3.MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = value,
            style = androidx.compose.material3.MaterialTheme.typography.bodyLarge
        )
    }
}
