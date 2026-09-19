package com.example.faculty_sphere

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "attendance"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {

                // ── Start the foreground location service ──────────────────────
                "startService" -> {
                    val baseUrl = call.argument<String>("baseUrl") ?: "https://attenda.srishakthicgpa.in"
                    val lat = call.argument<Double>("geofenceLat") ?: 11.0396
                    val lng = call.argument<Double>("geofenceLng") ?: 77.0747
                    val radius = call.argument<Double>("geofenceRadius")?.toFloat() ?: 250f
                    val token = call.argument<String>("token") ?: ""
                    val regNo = call.argument<String>("regNo") ?: ""
                    val deviceSessionId = call.argument<String>("deviceSessionId") ?: ""

                    val serviceIntent = Intent(this, AttendanceForegroundService::class.java).apply {
                        action = AttendanceForegroundService.ACTION_START
                        putExtra(AttendanceForegroundService.EXTRA_BASE_URL, baseUrl)
                        putExtra(AttendanceForegroundService.EXTRA_GEOFENCE_LAT, lat)
                        putExtra(AttendanceForegroundService.EXTRA_GEOFENCE_LNG, lng)
                        putExtra(AttendanceForegroundService.EXTRA_GEOFENCE_RADIUS, radius)
                        putExtra(AttendanceForegroundService.EXTRA_TOKEN, token)
                        putExtra(AttendanceForegroundService.EXTRA_REG_NO, regNo)
                        putExtra(AttendanceForegroundService.EXTRA_DEVICE_SESSION_ID, deviceSessionId)
                    }

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(serviceIntent)
                    } else {
                        startService(serviceIntent)
                    }
                    result.success(true)
                }

                // ── Stop the foreground location service ───────────────────────
                "stopService" -> {
                    val serviceIntent = Intent(this, AttendanceForegroundService::class.java).apply {
                        action = AttendanceForegroundService.ACTION_STOP
                    }
                    startService(serviceIntent)
                    result.success(true)
                }

                // ── Query whether battery optimisation is exempted ─────────────
                "isIgnoringBatteryOptimisations" -> {
                    val pm = getSystemService(POWER_SERVICE) as PowerManager
                    result.success(pm.isIgnoringBatteryOptimizations(packageName))
                }

                // ── Open the system dialog to request battery exemption ─────────
                // Must be called from a user-initiated action (settings button tap).
                "requestBatteryOptimisationExemption" -> {
                    try {
                        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                            data = Uri.parse("package:$packageName")
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        // Fallback: open general battery optimisation settings
                        try {
                            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                            result.success(true)
                        } catch (ex: Exception) {
                            result.error("BATTERY_SETTINGS_UNAVAILABLE", ex.message, null)
                        }
                    }
                }

                // ── Check if service process is running ────────────────────────
                "getServiceStatus" -> {
                    val pm = getSystemService(POWER_SERVICE) as PowerManager
                    val batteryExempt = pm.isIgnoringBatteryOptimizations(packageName)

                    val prefs = getSharedPreferences("AttendanceNativePrefs", Context.MODE_PRIVATE)
                    val prefsRunning = prefs.getBoolean("service_running", false)
                    val lastHeartbeat = prefs.getLong("last_heartbeat_ms", 0L)
                    val isHeartbeatFresh = (System.currentTimeMillis() - lastHeartbeat) < (5 * 60 * 1000L)

                    var legacyRunning = false
                    try {
                        @Suppress("DEPRECATION")
                        val activityManager = getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager
                        @Suppress("DEPRECATION")
                        legacyRunning = activityManager.getRunningServices(50).any {
                            it.service.className == AttendanceForegroundService::class.java.name
                        }
                    } catch (_: Exception) {}

                    val running = AttendanceForegroundService.isRunning || (prefsRunning && isHeartbeatFresh) || legacyRunning

                    result.success(mapOf(
                        "running" to running,
                        "batteryExempt" to batteryExempt
                    ))
                }

                // ── Restart the foreground location service ─────────────────────
                "restartService" -> {
                    val prefs = getSharedPreferences("AttendanceNativePrefs", Context.MODE_PRIVATE)
                    val token = prefs.getString("token", "") ?: ""
                    if (token.isNotEmpty()) {
                        val serviceIntent = Intent(this, AttendanceForegroundService::class.java).apply {
                            action = AttendanceForegroundService.ACTION_START
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(serviceIntent)
                        } else {
                            startService(serviceIntent)
                        }
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }

                // ── OEM battery / autostart deeplink ──────────────────────────
                "launchOemBatterySettings" -> {
                    val launched = OemAutostartLauncher.launch(this)
                    result.success(launched)
                }

                else -> result.notImplemented()
            }
        }
    }
}
