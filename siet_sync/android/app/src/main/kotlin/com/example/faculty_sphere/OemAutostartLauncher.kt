package com.example.faculty_sphere

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.net.Uri
import android.util.Log

/**
 * Launches the OEM-specific battery manager / auto-start settings screen.
 *
 * Many Chinese OEMs ship proprietary battery killers that terminate services
 * even when the standard Android battery-optimisation exemption is granted.
 * This object holds the known intent package/class pairs for the most common
 * OEMs and tries them in order until one succeeds.
 */
object OemAutostartLauncher {
    private const val TAG = "OemAutostartLauncher"

    private data class OemIntent(val pkg: String, val cls: String)

    private val OEM_INTENTS = listOf(
        // Xiaomi / MIUI
        OemIntent("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"),
        OemIntent("com.miui.securitycenter", "com.miui.powercenter.PowerSettings"),
        // Samsung (One UI 4+)
        OemIntent("com.samsung.android.lool", "com.samsung.android.sm.ui.battery.BatteryActivity"),
        // OnePlus / OxygenOS
        OemIntent("com.oneplus.security", "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"),
        // Oppo / ColorOS
        OemIntent("com.coloros.oppoguardelf", "com.coloros.powermanager.fuelgaue.PowerUsageModelActivity"),
        OemIntent("com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity"),
        // Vivo / FunTouch
        OemIntent("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"),
        // Huawei / EMUI
        OemIntent("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
        OemIntent("com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity"),
        // Asus
        OemIntent("com.asus.mobilemanager", "com.asus.mobilemanager.powersaver.PowerSaverSettings"),
        OemIntent("com.asus.mobilemanager", "com.asus.mobilemanager.autostart.AutostartSettings"),
        // Letv / LeEco
        OemIntent("com.letv.android.letvsafe", "com.letv.android.letvsafe.AutobootManageActivity"),
    )

    /**
     * Tries each known OEM intent. Returns `true` if one was launched.
     * Falls back to the standard battery-optimisation settings if no OEM screen found.
     */
    fun launch(context: Context): Boolean {
        for (oemIntent in OEM_INTENTS) {
            try {
                val intent = Intent().apply {
                    component = ComponentName(oemIntent.pkg, oemIntent.cls)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                if (context.packageManager.resolveActivity(intent, 0) != null) {
                    context.startActivity(intent)
                    Log.d(TAG, "Launched OEM settings: ${oemIntent.pkg}/${oemIntent.cls}")
                    return true
                }
            } catch (e: Exception) {
                Log.d(TAG, "OEM intent failed (${oemIntent.pkg}): ${e.message}")
            }
        }

        // Standard fallback: Android battery optimisation settings
        return try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:${context.packageName}")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
            Log.d(TAG, "Launched standard battery optimisation settings.")
            true
        } catch (e: Exception) {
            Log.e(TAG, "All OEM + standard intents failed: ${e.message}")
            false
        }
    }
}
