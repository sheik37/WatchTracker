package com.example.watchtracker.flutter_app

import android.content.Intent
import android.net.Uri
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
                        if (url.isEmpty()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        runCatching {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                        }.onSuccess {
                            result.success(true)
                        }.onFailure {
                            result.success(false)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
