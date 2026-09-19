package com.example.faculty_sphere

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.location.Location
import android.os.Build
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.work.*
import com.google.android.gms.location.*
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.TimeUnit

class AttendanceForegroundService : Service() {

    companion object {
        private const val TAG = "AttendanceService"
        private const val CHANNEL_ID = "background_location_channel"
        private const val NOTIFICATION_ID = 888

        // Wakelock max single hold: 10 minutes — rolling re-acquire on each location fix
        private const val WAKELOCK_TIMEOUT_MS = 10 * 60 * 1000L

        // Control actions
        const val ACTION_START = "ACTION_START"
        const val ACTION_STOP = "ACTION_STOP"
        const val ACTION_UPDATE_GEOFENCE = "ACTION_UPDATE_GEOFENCE"

        // Keys for Intent extras
        const val EXTRA_BASE_URL = "EXTRA_BASE_URL"
        const val EXTRA_GEOFENCE_LAT = "EXTRA_GEOFENCE_LAT"
        const val EXTRA_GEOFENCE_LNG = "EXTRA_GEOFENCE_LNG"
        const val EXTRA_GEOFENCE_RADIUS = "EXTRA_GEOFENCE_RADIUS"
        const val EXTRA_TOKEN = "EXTRA_TOKEN"
        const val EXTRA_REG_NO = "EXTRA_REG_NO"
        const val EXTRA_DEVICE_SESSION_ID = "EXTRA_DEVICE_SESSION_ID"

        // Native offline queue key (separate from Flutter SharedPreferences)
        private const val NATIVE_OFFLINE_QUEUE_KEY = "native_offline_queue"
        private const val MAX_OFFLINE_QUEUE_SIZE = 500

        @Volatile
        var isRunning: Boolean = false

        @Volatile
        var lastHeartbeatMs: Long = 0L
    }

    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private lateinit var geofencingClient: GeofencingClient
    private var locationCallback: LocationCallback? = null
    private val serviceJob = SupervisorJob()
    private val serviceScope = CoroutineScope(Dispatchers.IO + serviceJob)

    private var baseUrl: String = "https://attenda.srishakthicgpa.in"
    private var geofenceLat: Double = 11.0396
    private var geofenceLng: Double = 77.0747
    private var geofenceRadius: Float = 250f
    private var wakeLock: android.os.PowerManager.WakeLock? = null

    private var token: String = ""
    private var regNo: String = ""
    private var deviceSessionId: String = ""
    private var startDay: String = ""

    // ────────────────────────────────────────────────────────────────
    // Lifecycle
    // ────────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        lastHeartbeatMs = System.currentTimeMillis()
        try {
            getSharedPreferences("AttendanceNativePrefs", Context.MODE_PRIVATE).edit()
                .putBoolean("service_running", true)
                .putLong("last_heartbeat_ms", lastHeartbeatMs)
                .apply()
        } catch (_: Exception) {}
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        geofencingClient = LocationServices.getGeofencingClient(this)
        createNotificationChannel()
        acquireWakeLock()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START
        Log.d(TAG, "onStartCommand action=$action")

        isRunning = true
        lastHeartbeatMs = System.currentTimeMillis()

        val prefs = getSharedPreferences("AttendanceNativePrefs", Context.MODE_PRIVATE)
        prefs.edit()
            .putBoolean("service_running", true)
            .putLong("last_heartbeat_ms", lastHeartbeatMs)
            .apply()

        if (intent == null) {
            // System restarted service (START_STICKY) — restore from SharedPreferences
            baseUrl = prefs.getString("baseUrl", baseUrl) ?: baseUrl
            geofenceLat = prefs.getFloat("geofenceLat", geofenceLat.toFloat()).toDouble()
            geofenceLng = prefs.getFloat("geofenceLng", geofenceLng.toFloat()).toDouble()
            geofenceRadius = prefs.getFloat("geofenceRadius", geofenceRadius)
            token = prefs.getString("token", "") ?: ""
            regNo = prefs.getString("regNo", "") ?: ""
            deviceSessionId = prefs.getString("deviceSessionId", "") ?: ""
            startDay = prefs.getString("startDay", "") ?: ""
            Log.d(TAG, "Restored from prefs: baseUrl=$baseUrl regNo=$regNo startDay=$startDay")
        } else {
            intent.getStringExtra(EXTRA_BASE_URL)?.let { baseUrl = it }
            if (intent.hasExtra(EXTRA_GEOFENCE_LAT)) {
                geofenceLat = intent.getDoubleExtra(EXTRA_GEOFENCE_LAT, geofenceLat)
                geofenceLng = intent.getDoubleExtra(EXTRA_GEOFENCE_LNG, geofenceLng)
                geofenceRadius = intent.getFloatExtra(EXTRA_GEOFENCE_RADIUS, geofenceRadius)
            }
            intent.getStringExtra(EXTRA_TOKEN)?.let { token = it }
            intent.getStringExtra(EXTRA_REG_NO)?.let { regNo = it }
            intent.getStringExtra(EXTRA_DEVICE_SESSION_ID)?.let { deviceSessionId = it }

            val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
            sdf.timeZone = TimeZone.getTimeZone("GMT+5:30")
            startDay = sdf.format(Date())

            prefs.edit().apply {
                putString("baseUrl", baseUrl)
                putFloat("geofenceLat", geofenceLat.toFloat())
                putFloat("geofenceLng", geofenceLng.toFloat())
                putFloat("geofenceRadius", geofenceRadius)
                putString("token", token)
                putString("regNo", regNo)
                putString("deviceSessionId", deviceSessionId)
                putString("startDay", startDay)
                apply()
            }
        }

        when (action) {
            ACTION_START -> {
                startForegroundCompat()
                setupGeofence()
                startLocationUpdates()
                // Flush any locations queued while service was dead
                serviceScope.launch { flushNativeOfflineQueue() }
            }
            ACTION_STOP -> {
                cancelWorkManagerRestart()
                stopLocationUpdates()
                removeGeofence()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
            ACTION_UPDATE_GEOFENCE -> setupGeofence()
        }

        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.d(TAG, "App swiped — scheduling WorkManager restart.")
        // Cancel any stale restart job first, then enqueue a fresh one
        val workRequest = OneTimeWorkRequestBuilder<ServiceRestartWorker>()
            .setInitialDelay(3, TimeUnit.SECONDS)
            .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            .build()

        WorkManager.getInstance(applicationContext).enqueueUniqueWork(
            ServiceRestartWorker.WORK_NAME,
            ExistingWorkPolicy.REPLACE,
            workRequest
        )
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        super.onDestroy()
        isRunning = false
        try {
            getSharedPreferences("AttendanceNativePrefs", Context.MODE_PRIVATE).edit()
                .putBoolean("service_running", false)
                .apply()
        } catch (_: Exception) {}
        releaseWakeLock()
        serviceJob.cancel()
        Log.d(TAG, "Service destroyed")
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ────────────────────────────────────────────────────────────────
    // Foreground notification (API-34 compatible)
    // ────────────────────────────────────────────────────────────────

    private fun startForegroundCompat() {
        val notification = createNotification("VisionGate — Location Sync", "Background location tracking is active.")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // API 29+: declare foreground service type explicitly
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun updateNotification(title: String, content: String) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, createNotification(title, content))
    }

    private fun createNotification(title: String, content: String): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(content)
            .setSmallIcon(resources.getIdentifier("ic_launcher", "mipmap", packageName))
            .setContentIntent(pendingIntent)
            // ONGOING + NO_CLEAR: locks the notification in the shade
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            // PRIORITY_DEFAULT (not LOW) — LOW notifications can be auto-suppressed by the OS
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            // Show immediately when service starts (API 31+)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            // Show on lock-screen so user knows tracking is active
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)

        val notification = builder.build()
        notification.flags = notification.flags or
                Notification.FLAG_ONGOING_EVENT or
                Notification.FLAG_NO_CLEAR
        return notification
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "VisionGate Location Sync",
                // IMPORTANCE_DEFAULT so Android does not silently suppress the channel
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Running in the background to verify location attendance."
                // No sound/vibration for an ongoing service notification
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    // ────────────────────────────────────────────────────────────────
    // WakeLock — rolling 10-min acquire to avoid infinite hold
    // ────────────────────────────────────────────────────────────────

    private fun acquireWakeLock() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
            wakeLock?.let { if (it.isHeld) it.release() }
            wakeLock = powerManager.newWakeLock(
                android.os.PowerManager.PARTIAL_WAKE_LOCK,
                "VisionGate::AttendanceWakeLock"
            ).apply { acquire(WAKELOCK_TIMEOUT_MS) }
            Log.d(TAG, "WakeLock acquired (10 min timeout).")
        } catch (e: Exception) {
            Log.e(TAG, "WakeLock acquire failed: ${e.message}")
        }
    }

    private fun releaseWakeLock() {
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
            wakeLock = null
            Log.d(TAG, "WakeLock released.")
        } catch (e: Exception) {
            Log.e(TAG, "WakeLock release error: ${e.message}")
        }
    }

    // ────────────────────────────────────────────────────────────────
    // Location updates
    // ────────────────────────────────────────────────────────────────

    private fun startLocationUpdates() {
        if (locationCallback != null) return

        val locationRequest = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 120_000L).apply {
            setMinUpdateIntervalMillis(120_000L)
            setWaitForAccurateLocation(true)
        }.build()

        locationCallback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                // Re-acquire WakeLock on every fix so it never lapses mid-session
                acquireWakeLock()
                for (location in result.locations) {
                    onLocationChanged(location)
                }
            }
        }

        try {
            fusedLocationClient.requestLocationUpdates(
                locationRequest,
                locationCallback!!,
                Looper.getMainLooper()
            )
            Log.d(TAG, "Location updates started (2-min interval).")
        } catch (e: SecurityException) {
            Log.e(TAG, "Missing location permission: ${e.message}")
        }
    }

    private fun stopLocationUpdates() {
        locationCallback?.let {
            fusedLocationClient.removeLocationUpdates(it)
            locationCallback = null
            Log.d(TAG, "Location updates stopped.")
        }
    }

    // ────────────────────────────────────────────────────────────────
    // Geofence
    // ────────────────────────────────────────────────────────────────

    private fun setupGeofence() {
        val geofence = Geofence.Builder()
            .setRequestId("college_geofence")
            .setCircularRegion(geofenceLat, geofenceLng, geofenceRadius)
            .setExpirationDuration(Geofence.NEVER_EXPIRE)
            .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT)
            .build()

        val request = GeofencingRequest.Builder()
            .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
            .addGeofence(geofence)
            .build()

        val intent = Intent(this, GeofenceBroadcastReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            this, 0, intent,
            PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        try {
            geofencingClient.addGeofences(request, pendingIntent)
                .addOnSuccessListener { Log.d(TAG, "Geofence added at ($geofenceLat, $geofenceLng) r=$geofenceRadius") }
                .addOnFailureListener { Log.e(TAG, "Geofence add failed: ${it.message}") }
        } catch (e: SecurityException) {
            Log.e(TAG, "Missing permission for geofence: ${e.message}")
        }
    }

    private fun removeGeofence() {
        val intent = Intent(this, GeofenceBroadcastReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            this, 0, intent,
            PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        geofencingClient.removeGeofences(pendingIntent)
            .addOnSuccessListener { Log.d(TAG, "Geofences removed.") }
            .addOnFailureListener { Log.e(TAG, "Geofence remove failed: ${it.message}") }
    }

    // ────────────────────────────────────────────────────────────────
    // Tracking guard
    // ────────────────────────────────────────────────────────────────

    private fun shouldTrack(): Boolean {
        if (token.isEmpty() || regNo.isEmpty()) return false

        val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
        sdf.timeZone = TimeZone.getTimeZone("GMT+5:30")
        val today = sdf.format(Date())

        if (today != startDay) {
            Log.d(TAG, "Day rolled over ($startDay → $today). Updating startDay and continuing sync.")
            startDay = today
            try {
                getSharedPreferences("AttendanceNativePrefs", Context.MODE_PRIVATE).edit()
                    .putString("startDay", startDay)
                    .apply()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to persist new startDay: ${e.message}")
            }
        }
        return true
    }

    // ────────────────────────────────────────────────────────────────
    // Location dispatch
    // ────────────────────────────────────────────────────────────────

    private fun onLocationChanged(location: Location) {
        if (!shouldTrack()) return
        lastHeartbeatMs = System.currentTimeMillis()
        try {
            getSharedPreferences("AttendanceNativePrefs", Context.MODE_PRIVATE).edit()
                .putLong("last_heartbeat_ms", lastHeartbeatMs)
                .apply()
        } catch (_: Exception) {}
        Log.d(TAG, "Location fix: ${location.latitude}, ${location.longitude} acc=${location.accuracy}m")
        serviceScope.launch { sendLocationToBackend(location) }
    }

    private suspend fun sendLocationToBackend(location: Location) {
        if (token.isEmpty() || regNo.isEmpty()) return

        val sdf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.getDefault())
        sdf.timeZone = TimeZone.getTimeZone("GMT+5:30")
        val capturedAtIST = sdf.format(Date(location.time)) + "+05:30"
        val deviceId = if (deviceSessionId.isNotEmpty()) deviceSessionId else "app_$regNo"

        val payload = JSONObject().apply {
            put("latitude", location.latitude)
            put("longitude", location.longitude)
            put("accuracy_meters", location.accuracy)
            put("speed_mps", location.speed)
            put("heading_deg", location.bearing)
            put("altitude_m", location.altitude)
            put("is_mocked", location.isFromMockProvider)
            put("source", "native_background_service")
            put("app_state", "background")
            put("captured_at", capturedAtIST)
            put("device_id", deviceId)
        }

        try {
            val conn = URL("$baseUrl/location/update").openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("Authorization", "Bearer $token")
            conn.connectTimeout = 10_000
            conn.readTimeout = 10_000
            conn.doOutput = true

            OutputStreamWriter(conn.outputStream).use { it.write(payload.toString()); it.flush() }

            val code = conn.responseCode
            Log.d(TAG, "POST /location/update → $code")

            if (code in 200..299) {
                val body = conn.inputStream.bufferedReader().use { it.readText() }
                val json = JSONObject(body)
                if (json.optBoolean("boundary_warning", false)) {
                    updateNotification("⚠ Boundary Breach", json.optString("warning", "You have left the campus boundary."))
                } else {
                    updateNotification("VisionGate — Location Sync", "Location synced successfully.")
                }
                // Flush offline queue now that we have connectivity
                flushNativeOfflineQueue()
            } else {
                // Non-2xx: queue locally and retry on next fix
                enqueueNativeOffline(payload)
            }
            conn.disconnect()
        } catch (e: Exception) {
            Log.e(TAG, "Network error — queuing location locally: ${e.message}")
            enqueueNativeOffline(payload)
        }
    }

    // ────────────────────────────────────────────────────────────────
    // Native offline queue (survives Flutter isolate being dead)
    // ────────────────────────────────────────────────────────────────

    private fun enqueueNativeOffline(payload: JSONObject) {
        try {
            val prefs = getSharedPreferences("AttendanceNativePrefs", Context.MODE_PRIVATE)
            val existing = prefs.getString(NATIVE_OFFLINE_QUEUE_KEY, "[]") ?: "[]"
            val arr = JSONArray(existing)
            if (arr.length() >= MAX_OFFLINE_QUEUE_SIZE) arr.remove(0)
            arr.put(payload)
            prefs.edit().putString(NATIVE_OFFLINE_QUEUE_KEY, arr.toString()).apply()
            Log.d(TAG, "Queued location offline. Queue size=${arr.length()}")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to queue offline: ${e.message}")
        }
    }

    private suspend fun flushNativeOfflineQueue() {
        if (token.isEmpty()) return
        try {
            val prefs = getSharedPreferences("AttendanceNativePrefs", Context.MODE_PRIVATE)
            val raw = prefs.getString(NATIVE_OFFLINE_QUEUE_KEY, "[]") ?: "[]"
            val arr = JSONArray(raw)
            if (arr.length() == 0) return

            Log.d(TAG, "Flushing ${arr.length()} offline native location(s).")

            val logs = JSONArray()
            for (i in 0 until arr.length()) logs.put(arr.getJSONObject(i))

            val deviceId = if (deviceSessionId.isNotEmpty()) deviceSessionId else "app_$regNo"
            val body = JSONObject().apply {
                put("device_id", deviceId)
                put("logs", logs)
            }

            val conn = URL("$baseUrl/location/sync_offline").openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("Authorization", "Bearer $token")
            conn.connectTimeout = 15_000
            conn.readTimeout = 15_000
            conn.doOutput = true

            OutputStreamWriter(conn.outputStream).use { it.write(body.toString()); it.flush() }
            val code = conn.responseCode
            conn.disconnect()

            if (code in 200..299) {
                prefs.edit().putString(NATIVE_OFFLINE_QUEUE_KEY, "[]").apply()
                Log.d(TAG, "Native offline queue flushed successfully.")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Flush native offline failed: ${e.message}")
        }
    }

    // ────────────────────────────────────────────────────────────────
    // WorkManager helpers
    // ────────────────────────────────────────────────────────────────

    private fun cancelWorkManagerRestart() {
        WorkManager.getInstance(applicationContext)
            .cancelUniqueWork(ServiceRestartWorker.WORK_NAME)
    }
}
