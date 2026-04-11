package com.example.achievr_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import java.time.Instant
import java.util.Timer
import java.util.TimerTask

class FocusMonitorService : Service() {

    companion object {
        const val CHANNEL_ID = "focus_monitor_channel"
        const val NOTIFICATION_ID = 4401

        var latestForegroundApp: String? = null
        var latestScreenOff: Boolean = false
        var latestTimestamp: String = ""
        var listener: ((Map<String, Any?>) -> Unit)? = null
    }

    private var timer: Timer? = null
    private var allowScreenOff: Boolean = true
    private var pollIntervalMs: Long = 1000L
    private var allowedApps: Set<String> = emptySet()

    private val screenReceiver = ScreenStateReceiver(
        onScreenOff = {
            latestScreenOff = true
            emitSnapshot()
        },
        onScreenOn = {
            latestScreenOff = false
            emitSnapshot()
        }
    )

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        registerReceiver(
            screenReceiver,
            IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(Intent.ACTION_SCREEN_ON)
            }
        )
    }

    override fun onDestroy() {
        timer?.cancel()
        unregisterReceiver(screenReceiver)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val apps = intent?.getStringArrayListExtra("allowedApps") ?: arrayListOf()
        allowedApps = apps.toSet()
        allowScreenOff = intent?.getBooleanExtra("allowScreenOff", true) ?: true
        pollIntervalMs = intent?.getLongExtra("pollIntervalMs", 1000L) ?: 1000L

        startForeground(NOTIFICATION_ID, buildNotification())
        startPolling()

        return START_STICKY
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Achievr Focus Mode")
            .setContentText("Monitoring focus session")
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setOngoing(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Focus Monitor",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun startPolling() {
        timer?.cancel()
        timer = Timer()

        timer?.scheduleAtFixedRate(object : TimerTask() {
            override fun run() {
                latestForegroundApp = getCurrentForegroundApp()
                latestTimestamp = Instant.now().toString()
                emitSnapshot()
            }
        }, 0L, pollIntervalMs)
    }

    private fun emitSnapshot() {
        listener?.invoke(
            mapOf(
                "foregroundAppIdentifier" to latestForegroundApp,
                "isScreenOff" to latestScreenOff,
                "timestamp" to latestTimestamp
            )
        )
    }

    private fun getCurrentForegroundApp(): String? {
        val usageStatsManager =
            getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager

        val end = System.currentTimeMillis()
        val begin = end - 10_000L

        val events = usageStatsManager.queryEvents(begin, end)
        val event = android.app.usage.UsageEvents.Event()

        var lastPackage: String? = null

        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            if (event.eventType == android.app.usage.UsageEvents.Event.MOVE_TO_FOREGROUND) {
                lastPackage = event.packageName
            }
        }

        return lastPackage
    }
}