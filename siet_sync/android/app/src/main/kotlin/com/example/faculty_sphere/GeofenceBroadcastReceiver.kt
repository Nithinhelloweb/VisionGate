package com.example.faculty_sphere

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.*

class GeofenceBroadcastReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "GeofenceReceiver"
        private const val CHANNEL_ID = "attenda_warning_channel"
        private const val NOTIFICATION_ID = 1001
    }

    private fun shouldTrack(context: Context): Boolean {
        val prefs = context.getSharedPreferences("AttendanceNativePrefs", Context.MODE_PRIVATE)
        val token = prefs.getString("token", "") ?: ""
        val startDay = prefs.getString("startDay", "") ?: ""
        
        if (token.isEmpty() || startDay.isEmpty()) return false

        val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
        sdf.timeZone = TimeZone.getTimeZone("GMT+5:30")
        val today = sdf.format(Date())
        
        return today == startDay
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "Geofence event received.")
        if (!shouldTrack(context)) {
            Log.d(TAG, "Geofence event ignored: user is not checked-in or has checked-out today.")
            return
        }
        val geofencingEvent = GeofencingEvent.fromIntent(intent)
        if (geofencingEvent == null) {
            Log.e(TAG, "GeofencingEvent is null")
            return
        }
        if (geofencingEvent.hasError()) {
            Log.e(TAG, "GeofencingEvent error: ${geofencingEvent.errorCode}")
            return
        }

        val geofenceTransition = geofencingEvent.geofenceTransition

        if (geofenceTransition == Geofence.GEOFENCE_TRANSITION_ENTER ||
            geofenceTransition == Geofence.GEOFENCE_TRANSITION_EXIT) {

            val triggeringLocation = geofencingEvent.triggeringLocation
            val transitionType = if (geofenceTransition == Geofence.GEOFENCE_TRANSITION_ENTER) "ENTER" else "EXIT"
            Log.i(TAG, "Geofence transition detected: $transitionType")

            // Send notification about geofence breach
            val message = if (geofenceTransition == Geofence.GEOFENCE_TRANSITION_ENTER) {
                "Welcome to campus! Automatic attendance location sharing is active."
            } else {
                "⚠ You have moved outside the campus boundary. Please remain on campus during attendance hours."
            }
            
            showNotification(context, message)

            // Trigger action inside the service (e.g. stop location updates when exited)
            val serviceIntent = Intent(context, AttendanceForegroundService::class.java).apply {
                action = AttendanceForegroundService.ACTION_START
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }

            if (triggeringLocation != null) {
                CoroutineScope(Dispatchers.IO).launch {
                    sendTransitionToBackend(context, transitionType, triggeringLocation)
                }
            }
        } else {
            Log.e(TAG, "Unknown geofence transition type: $geofenceTransition")
        }
    }

    private fun showNotification(context: Context, message: String) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Attenda Warnings",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Alerts and rule violation warnings"
            }
            notificationManager.createNotificationChannel(channel)
        }

        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val pendingIntent = PendingIntent.getActivity(
            context, 0, launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle("Attenda Geofence Alert")
            .setContentText(message)
            .setStyle(NotificationCompat.BigTextStyle().bigText(message))
            .setSmallIcon(context.resources.getIdentifier("ic_launcher", "mipmap", context.packageName))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()

        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    private suspend fun sendTransitionToBackend(context: Context, transition: String, location: android.location.Location) {
        try {
            val nativePrefs = context.getSharedPreferences("AttendanceNativePrefs", Context.MODE_PRIVATE)
            val baseUrl = nativePrefs.getString("baseUrl", "https://attenda.srishakthicgpa.in") ?: return

            val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val sessionStr = flutterPrefs.getString("flutter.user_session", null) ?: return
            
            val session = JSONObject(sessionStr)
            val token = session.optString("token", null) ?: return
            val user = session.optJSONObject("user") ?: return
            val deviceSessionId = session.optString("deviceSessionId", "")
            val regNo = user.optString("regNo", user.optString("reg_no", ""))

            val sdf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.getDefault())
            sdf.timeZone = TimeZone.getTimeZone("GMT+5:30")
            val capturedAtIST = sdf.format(Date(location.time)) + "+05:30"

            val payload = JSONObject().apply {
                put("latitude", location.latitude)
                put("longitude", location.longitude)
                put("accuracy_meters", location.accuracy)
                put("speed_mps", location.speed)
                put("heading_deg", location.bearing)
                put("altitude_m", location.altitude)
                put("is_mocked", location.isFromMockProvider)
                put("source", "geofence_transition_$transition")
                put("app_state", "background")
                put("captured_at", capturedAtIST)
                put("device_id", if (deviceSessionId.isNotEmpty()) deviceSessionId else "app_$regNo")
            }

            val conn = URL("$baseUrl/location/update").openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("Authorization", "Bearer $token")
            conn.doOutput = true

            OutputStreamWriter(conn.outputStream).use { writer ->
                writer.write(payload.toString())
                writer.flush()
            }

            val responseCode = conn.responseCode
            Log.d(TAG, "Send geofence transition response code: $responseCode")
            conn.disconnect()
        } catch (e: Exception) {
            Log.e(TAG, "Error sending geofence transition to backend: ${e.message}")
        }
    }
}
