package com.example.myapplication

data class UpdateCheckResult(
    val message: String,
    val updateAvailable: Boolean,
    val versionName: String? = null,
    val downloadUrl: String? = null,
    val expectedSha256: String? = null,
    val releaseNotes: String? = null
)
