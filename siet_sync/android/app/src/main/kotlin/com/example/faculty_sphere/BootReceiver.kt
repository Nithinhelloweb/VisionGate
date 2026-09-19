package com.example.faculty_sphere

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import java.text.SimpleDateFormat
import java.util.*

/**
 * Restarts the AttendanceForegroundService after:
 *  • device boot / reboot
 *  • app update (MY_PACKAGE_REPLACED)
 *  • HTC/some-OEM quickboot (QUICKBOOT_POWERON)
 *
 * Only restarts if the saved token is non-empty AND startDay matches today's IST date,
 * meaning the user was actively tracked before the device shut down.
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "AttendanceBootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val allowedActions = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON"
        )
        if (intent.action !in allowedActions) return

        val prefs = context.getSharedPreferences("AttendanceNativePrefs", Context.MODE_PRIVATE)
        val token = prefs.getString("token", "") ?: ""
        if (token.isEmpty()) {
            Log.d(TAG, "No saved token — skipping service restart after boot.")
            return
        }

        val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
        sdf.timeZone = TimeZone.getTimeZone("GMT+5:30")
        val today = sdf.format(Date())
        prefs.edit().putString("startDay", today).apply()

        Log.d(TAG, "Boot detected. Restarting AttendanceForegroundService for day=$today.")
        val serviceIntent = Intent(context, AttendanceForegroundService::class.java).apply {
            action = AttendanceForegroundService.ACTION_START
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }
}
