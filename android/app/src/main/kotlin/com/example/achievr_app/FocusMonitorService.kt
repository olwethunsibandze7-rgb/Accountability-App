package com.example.achievr_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat

class FocusMonitorService : Service() {

    companion object {
        const val CHANNEL_ID = "focus_monitor_channel"
        const val CHANNEL_NAME = "Focus Monitor"
        const val NOTIFICATION_ID = 4401

        const val ACTION_START = "achievr.action.START_MONITORING"
        const val ACTION_STOP = "achievr.action.STOP_MONITORING"
        const val ACTION_UPDATE = "achievr.action.UPDATE_MONITORING"

        const val EXTRA_ALLOWED_APPS = "allowedAppIdentifiers"
        const val EXTRA_ALLOW_SCREEN_OFF = "allowScreenOff"
        const val EXTRA_POLL_INTERVAL_MS = "pollIntervalMs"
        const val EXTRA_FOCUS_SESSION_ID = "focusSessionId"
        const val EXTRA_HABIT_ID = "habitId"
        const val EXTRA_LOG_ID = "logId"
        const val EXTRA_GRACE_SECONDS = "graceSeconds"

        @Volatile
        var latestSnapshot: Map<String, Any?> = mapOf(
            "foregroundAppIdentifier" to null,
            "isScreenOff" to false,
            "monitoringActive" to false,
            "timestampMillis" to System.currentTimeMillis(),
        )

        @Volatile
        var monitoringActive: Boolean = false

        val listeners = mutableSetOf<(Map<String, Any?>) -> Unit>()

        fun emitSnapshot(snapshot: Map<String, Any?>) {
            latestSnapshot = snapshot
            listeners.toList().forEach { listener ->
                listener(snapshot)
            }
        }
    }

    private val handler = Handler(Looper.getMainLooper())

    private var pollIntervalMs: Long = 1000L
    private var allowScreenOff: Boolean = true
    private var allowedApps: Set<String> = emptySet()

    private var focusSessionId: String? = null
    private var habitId: String? = null
    private var logId: String? = null
    private var graceSeconds: Int? = null

    @Volatile
    private var latestForegroundApp: String? = null

    @Volatile
    private var latestScreenOff: Boolean = false

    private val pollRunnable = object : Runnable {
        override fun run() {
            if (!monitoringActive) return

            latestForegroundApp = getCurrentForegroundApp()
            val snapshot = buildSnapshot()
            emitSnapshot(snapshot)
            updateOngoingNotification()

            handler.postDelayed(this, pollIntervalMs)
        }
    }

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_OFF -> {
                    latestScreenOff = true
                    emitSnapshot(buildSnapshot())
                    updateOngoingNotification()
                }

                Intent.ACTION_SCREEN_ON,
                Intent.ACTION_USER_PRESENT -> {
                    latestScreenOff = false
                    emitSnapshot(buildSnapshot())
                    updateOngoingNotification()
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        registerScreenReceiver()
    }

    override fun onDestroy() {
        stopPolling()
        unregisterReceiverSafely()
        monitoringActive = false
        emitSnapshot(buildSnapshot(monitoring = false))
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                applyIntentConfig(intent)
                startAsForegroundService()
                startMonitoringLoop()
            }

            ACTION_UPDATE -> {
                applyIntentConfig(intent)
                updateOngoingNotification()
                emitSnapshot(buildSnapshot())
            }

            ACTION_STOP -> {
                stopSelfSafely()
            }

            else -> {
                if (!monitoringActive) {
                    startAsForegroundService()
                    startMonitoringLoop()
                }
            }
        }

        return START_STICKY
    }

    private fun startAsForegroundService() {
        val notification = buildOngoingNotification()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun applyIntentConfig(intent: Intent) {
        val apps = intent.getStringArrayListExtra(EXTRA_ALLOWED_APPS) ?: arrayListOf()
        allowedApps = apps.map { it.trim() }.filter { it.isNotEmpty() }.toSet()

        allowScreenOff = intent.getBooleanExtra(EXTRA_ALLOW_SCREEN_OFF, true)
        pollIntervalMs = intent.getLongExtra(EXTRA_POLL_INTERVAL_MS, 1000L).coerceAtLeast(500L)

        focusSessionId = intent.getStringExtra(EXTRA_FOCUS_SESSION_ID)
        habitId = intent.getStringExtra(EXTRA_HABIT_ID)
        logId = intent.getStringExtra(EXTRA_LOG_ID)
        graceSeconds = if (intent.hasExtra(EXTRA_GRACE_SECONDS)) {
            intent.getIntExtra(EXTRA_GRACE_SECONDS, 0)
        } else {
            null
        }
    }

    private fun startMonitoringLoop() {
        monitoringActive = true
        handler.removeCallbacks(pollRunnable)
        handler.post(pollRunnable)
    }

    private fun stopPolling() {
        handler.removeCallbacks(pollRunnable)
    }

    private fun stopSelfSafely() {
        stopPolling()
        monitoringActive = false
        emitSnapshot(buildSnapshot(monitoring = false))
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun buildSnapshot(monitoring: Boolean = monitoringActive): Map<String, Any?> {
        return mapOf(
            "foregroundAppIdentifier" to latestForegroundApp,
            "isScreenOff" to latestScreenOff,
            "monitoringActive" to monitoring,
            "timestampMillis" to System.currentTimeMillis(),
            "allowScreenOff" to allowScreenOff,
            "allowedAppIdentifiers" to allowedApps.toList(),
            "focusSessionId" to focusSessionId,
            "habitId" to habitId,
            "logId" to logId,
            "graceSeconds" to graceSeconds,
        )
    }

    private fun registerScreenReceiver() {
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        registerReceiver(screenReceiver, filter)
    }

    private fun unregisterReceiverSafely() {
        try {
            unregisterReceiver(screenReceiver)
        } catch (_: Exception) {
        }
    }

    private fun getCurrentForegroundApp(): String? {
        val usageStatsManager =
            getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
                ?: return null

        val end = System.currentTimeMillis()
        val begin = end - 15_000L
        val events = usageStatsManager.queryEvents(begin, end)
        val event = UsageEvents.Event()

        var lastPackage: String? = null
        var lastTimestamp = 0L

        while (events.hasNextEvent()) {
            events.getNextEvent(event)

            val isForegroundEvent =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    event.eventType == UsageEvents.Event.ACTIVITY_RESUMED
                } else {
                    event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND
                }

            if (!isForegroundEvent) continue

            val packageName = event.packageName ?: continue
            if (event.timeStamp >= lastTimestamp) {
                lastTimestamp = event.timeStamp
                lastPackage = packageName
            }
        }

        return lastPackage
    }

    private fun buildOngoingNotification(
        title: String = "Achievr Focus Mode",
        body: String = notificationBody(),
    ): Notification {
        val launchIntent = packageManager
            .getLaunchIntentForPackage(packageName)
            ?.apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }

        val pendingIntent = PendingIntent.getActivity(
            this,
            1001,
            launchIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun notificationBody(): String {
        val fg = latestForegroundApp ?: "unknown"
        return buildString {
            append("Monitoring focus")
            append(" • ")
            append(fg)
            if (latestScreenOff) {
                append(" • screen off")
            }
        }
    }

    private fun updateOngoingNotification() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(
            NOTIFICATION_ID,
            buildOngoingNotification()
        )
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Shows active focus monitoring status."
            setShowBadge(false)
        }

        manager.createNotificationChannel(channel)
    }
}