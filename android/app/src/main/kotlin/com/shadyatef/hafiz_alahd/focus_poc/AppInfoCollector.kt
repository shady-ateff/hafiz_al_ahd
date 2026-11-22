package com.shadyatef.hafiz_alahd.focus_poc

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.util.Base64
import android.util.Log
import java.io.ByteArrayOutputStream

/**
 * Collects user-facing launchable applications and encodes their metadata and icons.
 */
object AppInfoCollector {
    private const val TAG = "AppInfoCollector"
    private const val ICON_SIZE = 72 // 72x72 px thumbnail

    fun getInstalledLaunchableApps(context: Context): List<Map<String, Any?>> {
        val pm = context.packageManager
        val intent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }

        val resolveInfos = try {
            pm.queryIntentActivities(intent, 0)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to query launcher activities: ${e.message}", e)
            return emptyList()
        }

        val criticalPackages = ExemptionRegistry.getSystemCriticalPackages(context).toSet()
        val appList = mutableListOf<Map<String, Any?>>()
        val seenPackages = mutableSetOf<String>()

        for (resolveInfo in resolveInfos) {
            val activityInfo = resolveInfo.activityInfo ?: continue
            val packageName = activityInfo.packageName

            // Skip duplicates (some apps have multiple launcher activities)
            if (seenPackages.contains(packageName)) continue
            seenPackages.add(packageName)

            val appName = try {
                activityInfo.loadLabel(pm).toString()
            } catch (e: Exception) {
                packageName
            }

            val isSystemApp = try {
                (activityInfo.applicationInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
            } catch (e: Exception) {
                false
            }

            val isCritical = criticalPackages.contains(packageName) || packageName == context.packageName

            val iconBase64 = try {
                val iconDrawable = activityInfo.loadIcon(pm)
                encodeDrawableToBase64(iconDrawable)
            } catch (e: Exception) {
                null
            }

            appList.add(
                mapOf(
                    "packageName" to packageName,
                    "appName" to appName,
                    "isSystemApp" to isSystemApp,
                    "isSystemCritical" to isCritical,
                    "isExempt" to isCritical,
                    "iconBase64" to iconBase64
                )
            )
        }

        // Sort alphabetically by app name
        return appList.sortedBy { (it["appName"] as? String)?.lowercase() ?: "" }
    }

    private fun encodeDrawableToBase64(drawable: Drawable): String? {
        return try {
            val bitmap = Bitmap.createBitmap(ICON_SIZE, ICON_SIZE, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)

            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 85, stream)
            val byteArray = stream.toByteArray()
            Base64.encodeToString(byteArray, Base64.NO_WRAP)
        } catch (e: Exception) {
            null
        }
    }
}
