package com.example.achievr_app

import android.app.ActivityManager
import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val deviceMethodChannelName = "achievr/device_runtime_method"
    private val deviceEventChannelName = "achievr/device_runtime_events"
    private val installedAppsChannelName = "achievr/installed_apps"

    private var deviceRuntimeEventSink: EventChannel.EventSink? = null
    private var serviceListener: ((Map<String, Any?>) -> Unit)? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            deviceMethodChannelName
        ).setMethodCallHandler { call, result ->
            handleDeviceRuntimeCall(call, result)
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            deviceEventChannelName
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                deviceRuntimeEventSink = events

                serviceListener = { snapshot ->
                    runOnUiThread {
                        deviceRuntimeEventSink?.success(snapshot)
                    }
                }

                FocusMonitorService.listeners.add(serviceListener!!)
                events?.success(FocusMonitorService.latestSnapshot)
            }

            override fun onCancel(arguments: Any?) {
                serviceListener?.let { FocusMonitorService.listeners.remove(it) }
                serviceListener = null
                deviceRuntimeEventSink = null
            }
        })

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            installedAppsChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getLaunchableApps" -> {
                    try {
                        result.success(getLaunchableApps())
                    } catch (e: Exception) {
                        result.error("APP_QUERY_FAILED", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun handleDeviceRuntimeCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "hasUsageAccess" -> {
                result.success(hasUsageAccess())
            }

            "openUsageAccessSettings" -> {
                startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                result.success(null)
            }

            "isMonitoringActive" -> {
                result.success(FocusMonitorService.monitoringActive || isFocusMonitorServiceRunning())
            }

            "getCurrentSnapshot" -> {
                result.success(FocusMonitorService.latestSnapshot)
            }

            "startMonitoring" -> {
                val allowedApps =
                    call.argument<List<String>>("allowedAppIdentifiers") ?: emptyList()
                val allowScreenOff =
                    call.argument<Boolean>("allowScreenOff") ?: true
                val pollIntervalMs =
                    call.argument<Int>("pollIntervalMs") ?: 1000
                val focusSessionId = call.argument<String>("focusSessionId")
                val habitId = call.argument<String>("habitId")
                val logId = call.argument<String>("logId")
                val graceSeconds = call.argument<Int>("graceSeconds")

                val intent = Intent(this, FocusMonitorService::class.java).apply {
                    action = FocusMonitorService.ACTION_START
                    putStringArrayListExtra(
                        FocusMonitorService.EXTRA_ALLOWED_APPS,
                        ArrayList(allowedApps)
                    )
                    putExtra(FocusMonitorService.EXTRA_ALLOW_SCREEN_OFF, allowScreenOff)
                    putExtra(FocusMonitorService.EXTRA_POLL_INTERVAL_MS, pollIntervalMs.toLong())
                    putExtra(FocusMonitorService.EXTRA_FOCUS_SESSION_ID, focusSessionId)
                    putExtra(FocusMonitorService.EXTRA_HABIT_ID, habitId)
                    putExtra(FocusMonitorService.EXTRA_LOG_ID, logId)
                    if (graceSeconds != null) {
                        putExtra(FocusMonitorService.EXTRA_GRACE_SECONDS, graceSeconds)
                    }
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(intent)
                } else {
                    startService(intent)
                }

                result.success(null)
            }

            "updateMonitoringConfig" -> {
                val allowedApps =
                    call.argument<List<String>>("allowedAppIdentifiers") ?: emptyList()
                val allowScreenOff =
                    call.argument<Boolean>("allowScreenOff") ?: true
                val pollIntervalMs =
                    call.argument<Int>("pollIntervalMs") ?: 1000
                val focusSessionId = call.argument<String>("focusSessionId")
                val habitId = call.argument<String>("habitId")
                val logId = call.argument<String>("logId")
                val graceSeconds = call.argument<Int>("graceSeconds")

                val intent = Intent(this, FocusMonitorService::class.java).apply {
                    action = FocusMonitorService.ACTION_UPDATE
                    putStringArrayListExtra(
                        FocusMonitorService.EXTRA_ALLOWED_APPS,
                        ArrayList(allowedApps)
                    )
                    putExtra(FocusMonitorService.EXTRA_ALLOW_SCREEN_OFF, allowScreenOff)
                    putExtra(FocusMonitorService.EXTRA_POLL_INTERVAL_MS, pollIntervalMs.toLong())
                    putExtra(FocusMonitorService.EXTRA_FOCUS_SESSION_ID, focusSessionId)
                    putExtra(FocusMonitorService.EXTRA_HABIT_ID, habitId)
                    putExtra(FocusMonitorService.EXTRA_LOG_ID, logId)
                    if (graceSeconds != null) {
                        putExtra(FocusMonitorService.EXTRA_GRACE_SECONDS, graceSeconds)
                    }
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(intent)
                } else {
                    startService(intent)
                }

                result.success(null)
            }

            "stopMonitoring" -> {
                val intent = Intent(this, FocusMonitorService::class.java).apply {
                    action = FocusMonitorService.ACTION_STOP
                }
                startService(intent)
                result.success(null)
            }

            else -> result.notImplemented()
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

    private fun isFocusMonitorServiceRunning(): Boolean {
        val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager

        @Suppress("DEPRECATION")
        return manager.getRunningServices(Int.MAX_VALUE).any {
            it.service.className == FocusMonitorService::class.java.name
        }
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