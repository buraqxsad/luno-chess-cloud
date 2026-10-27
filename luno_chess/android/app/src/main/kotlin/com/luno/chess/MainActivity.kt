package com.luno.chess

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var legalChannel: MethodChannel? = null
    private var releaseIdentityChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        releaseIdentityChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.luno.chess/release_identity").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method != "getReleaseIdentity") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    @Suppress("DEPRECATION")
                    val info = packageManager.getPackageInfo(packageName, 0)
                    @Suppress("DEPRECATION")
                    val buildNumber = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode else info.versionCode.toLong()
                    result.success(mapOf("versionName" to info.versionName, "buildNumber" to buildNumber))
                } catch (_: PackageManager.NameNotFoundException) {
                    result.error("release-identity-unavailable", "Installed package metadata is unavailable.", null)
                }
            }
        }
        legalChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.luno.chess/legal").also { channel ->
            channel.setMethodCallHandler { call, result ->
                val url = when (call.method) {
                    "openPlaySubscriptions" -> "https://play.google.com/store/account/subscriptions"
                    "openLegalUrl" -> {
                        val url = (call.arguments as? Map<*, *>)?.get("url") as? String
                        if (url == null || url !in setOf(
                        "https://luno-legal-site.vercel.app/",
                        "https://luno-legal-site.vercel.app/terms.html"
                        )) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        url
                    }
                    else -> {
                        result.notImplemented()
                        return@setMethodCallHandler
                    }
                }
                try {
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addCategory(Intent.CATEGORY_BROWSABLE))
                    result.success(true)
                } catch (_: ActivityNotFoundException) {
                    result.success(false)
                } catch (_: SecurityException) {
                    result.success(false)
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        releaseIdentityChannel?.setMethodCallHandler(null)
        releaseIdentityChannel = null
        legalChannel?.setMethodCallHandler(null)
        legalChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
