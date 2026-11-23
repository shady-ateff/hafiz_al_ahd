package com.shadyatef.hafiz_alahd.focus_poc

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.telecom.TelecomManager
import android.util.Log
import org.json.JSONArray
import java.util.concurrent.ConcurrentHashMap

/**
 * Thread-safe registry for managing exempt application packages.
 * Guarantees system-critical package invariants (Emergency, Dialer, Home Launcher, Hafiz Al-Ahd).
 */
object ExemptionRegistry {
    private const val TAG = "ExemptionRegistry"
    private const val PREFS_NAME = "focus_native_exemptions_prefs"
    private const val KEY_EXEMPT_PACKAGES = "exempt_packages_json"

    private val exemptPackages = ConcurrentHashMap.newKeySet<String>()

    private val KNOWN_EMERGENCY_PACKAGES = setOf(
        "com.android.incallui",
        "com.google.android.dialer",
        "com.samsung.android.incallui",
        "com.android.dialer",
        "com.android.phone"
    )

    fun init(context: Context) {
        ensureSystemCriticals(context)
        loadFromPrefs(context)
    }

    /**
     * Checks if [packageName] is exempted from shielding.
     */
    fun isPackageExempt(context: Context, packageName: String?): Boolean {
        if (packageName.isNullOrBlank()) return true

        // Our app is always exempt
        if (packageName == context.packageName) return true

        // Known emergency packages are always exempt
        if (KNOWN_EMERGENCY_PACKAGES.contains(packageName)) return true

        // System dialer or launcher
        val dialer = getDefaultDialerPackage(context)
        if (dialer != null && dialer == packageName) return true

        val launcher = getDefaultLauncherPackage(context)
        if (launcher != null && launcher == packageName) return true

        // User configured exemptions
        return exemptPackages.contains(packageName)
    }

    /**
     * Updates user-configured exemptions and persists them locally.
     */
    fun setExemptPackages(context: Context, packages: Collection<String>) {
        exemptPackages.clear()
        exemptPackages.addAll(packages)
        ensureSystemCriticals(context)

        saveToPrefs(context)
        Log.i(TAG, "Exemption registry updated with ${exemptPackages.size} packages")
    }

    /**
     * Retrieves all system-critical packages detected on the device.
     */
    fun getSystemCriticalPackages(context: Context): List<String> {
        val criticals = mutableSetOf<String>()
        criticals.add(context.packageName)
        criticals.addAll(KNOWN_EMERGENCY_PACKAGES)

        getDefaultDialerPackage(context)?.let { criticals.add(it) }
        getDefaultLauncherPackage(context)?.let { criticals.add(it) }

        return criticals.toList()
    }

    private fun ensureSystemCriticals(context: Context) {
        exemptPackages.add(context.packageName)
        exemptPackages.addAll(KNOWN_EMERGENCY_PACKAGES)
        getDefaultDialerPackage(context)?.let { exemptPackages.add(it) }
        getDefaultLauncherPackage(context)?.let { exemptPackages.add(it) }
    }

    private fun getDefaultDialerPackage(context: Context): String? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val telecomManager = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
                telecomManager?.defaultDialerPackage
            } else {
                null
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun getDefaultLauncherPackage(context: Context): String? {
        return try {
            val intent = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
            }
            val resolveInfo = context.packageManager.resolveActivity(
                intent,
                PackageManager.MATCH_DEFAULT_ONLY
            )
            resolveInfo?.activityInfo?.packageName
        } catch (e: Exception) {
            null
        }
    }

    private fun saveToPrefs(context: Context) {
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val jsonArray = JSONArray(exemptPackages)
            prefs.edit().putString(KEY_EXEMPT_PACKAGES, jsonArray.toString()).apply()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save exemptions to prefs: ${e.message}")
        }
    }

    private fun loadFromPrefs(context: Context) {
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val jsonStr = prefs.getString(KEY_EXEMPT_PACKAGES, null) ?: return
            val jsonArray = JSONArray(jsonStr)
            for (i in 0 until jsonArray.length()) {
                exemptPackages.add(jsonArray.getString(i))
            }
            ensureSystemCriticals(context)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load exemptions from prefs: ${e.message}")
        }
    }
}
