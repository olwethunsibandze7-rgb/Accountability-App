package com.example.achievr_app

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val deviceMethodChannelName = "achievr/device_runtime_methods"
    private val deviceEventChannelName = "achievr/device_runtime_events"
    private val installedAppsChannelName = "achievr/installed_apps"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Existing device runtime methods
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            deviceMethodChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasUsageAccess" -> {
                    result.success(hasUsageAccess())
                }

                "openUsageAccessSettings" -> {
                    startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                    result.success(null)
                }

                "startMonitoring" -> {
                    val allowedApps =
                        call.argument<List<String>>("allowedAppIdentifiers") ?: emptyList()
                    val allowScreenOff =
                        call.argument<Boolean>("allowScreenOff") ?: true
                    val pollIntervalMs =
                        call.argument<Int>("pollIntervalMs") ?: 1000

                    val intent = Intent(this, FocusMonitorService::class.java).apply {
                        putStringArrayListExtra("allowedApps", ArrayList(allowedApps))
                        putExtra("allowScreenOff", allowScreenOff)
                        putExtra("pollIntervalMs", pollIntervalMs.toLong())
                    }

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }

                    result.success(null)
                }

                "stopMonitoring" -> {
                    stopService(Intent(this, FocusMonitorService::class.java))
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        // Existing device runtime event stream
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            deviceEventChannelName
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                FocusMonitorService.listener = { snapshot ->
                    runOnUiThread {
                        events?.success(snapshot)
                    }
                }
            }

            override fun onCancel(arguments: Any?) {
                FocusMonitorService.listener = null
            }
        })

        // New installed apps picker channel
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            installedAppsChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getLaunchableApps" -> {
                    try {
                        result.success(getLaunchableApps())
                    } catch (e: Exception) {
                        result.error(
                            "APP_QUERY_FAILED",
                            e.message,
                            null
                        )
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun hasUsageAccess(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                "android:get_usage_stats",
                android.os.Process.myUid(),
                packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                "android:get_usage_stats",
                android.os.Process.myUid(),
                packageName
            )
        }

        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun getLaunchableApps(): List<Map<String, String>> {
        val pm = applicationContext.packageManager

        val intent = Intent(Intent.ACTION_MAIN, null).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }

        val resolvedApps = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.queryIntentActivities(
                intent,
                PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_ALL.toLong())
            )
        } else {
            @Suppress("DEPRECATION")
            pm.queryIntentActivities(intent, PackageManager.MATCH_ALL)
        }

        return resolvedApps
            .mapNotNull { resolveInfo ->
                val activityInfo = resolveInfo.activityInfo ?: return@mapNotNull null
                val packageName = activityInfo.packageName ?: return@mapNotNull null

                // Hide this app itself from the picker
                if (packageName == applicationContext.packageName) {
                    return@mapNotNull null
                }

                val label = resolveInfo.loadLabel(pm)?.toString()?.trim().orEmpty()
                if (label.isEmpty()) {
                    return@mapNotNull null
                }

                mapOf(
                    "app_label" to label,
                    "package_name" to packageName
                )
            }
            .distinctBy { it["package_name"] }
            .sortedBy { it["app_label"]?.lowercase() ?: "" }
    }
}