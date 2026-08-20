package com.example.watchtracker.flutter_app

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.webkit.URLUtil
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "watchtracker/system")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openUrl" -> {
                        val url = call.argument<String>("url").orEmpty().trim()
                        val mode = call.argument<String>("mode").orEmpty().trim()
                        if (url.isEmpty()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        when (mode) {
                            "download" -> result.success(startDownload(url))
                            else -> result.success(openExternalUrl(url))
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun openExternalUrl(url: String): Boolean {
        return runCatching {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        }.isSuccess
    }

    private fun startDownload(url: String): Boolean {
        val uri = Uri.parse(url)
        val scheme = uri.scheme?.lowercase()
        if (scheme != "http" && scheme != "https") {
            return false
        }
        return runCatching {
            val request = DownloadManager.Request(uri).apply {
                val fileName = URLUtil.guessFileName(
                    url,
                    null,
                    "application/vnd.android.package-archive"
                )
                setTitle(fileName)
                setDescription("Téléchargement de la mise à jour")
                setMimeType("application/vnd.android.package-archive")
                setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                setAllowedOverMetered(true)
                setAllowedOverRoaming(true)
            }
            val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            manager.enqueue(request)
        }.isSuccess
    }
}
