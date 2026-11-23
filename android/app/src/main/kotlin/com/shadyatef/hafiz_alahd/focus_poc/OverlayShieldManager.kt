package com.shadyatef.hafiz_alahd.focus_poc

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.PorterDuff
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

class OverlayShieldManager(private val context: Context) {
    private val TAG = "OverlayShieldManager"
    private val mainHandler = Handler(Looper.getMainLooper())
    private var windowManager: WindowManager? = null
    private var shieldView: View? = null
    private var isShieldAttached = false

    var onSnoozeListener: (() -> Unit)? = null

    fun hasOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(context)
        } else {
            true
        }
    }

    /**
     * Shows the Focus Shield overlay. Must be called or dispatched to Main Thread.
     */
    fun show(wardTitle: String, remainingSnoozeCount: Int = 2) {
        if (!hasOverlayPermission()) {
            Log.w(TAG, "Cannot show overlay: Permission not granted")
            return
        }

        mainHandler.post {
            if (isShieldAttached && shieldView != null) {
                // Already showing
                return@post
            }

            try {
                if (windowManager == null) {
                    windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
                }

                val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                } else {
                    @Suppress("DEPRECATION")
                    WindowManager.LayoutParams.TYPE_PHONE
                }

                val params = WindowManager.LayoutParams(
                    WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.MATCH_PARENT,
                    layoutType,
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                    PixelFormat.TRANSLUCENT
                ).apply {
                    gravity = Gravity.CENTER
                }

                shieldView = createShieldLayout(wardTitle, remainingSnoozeCount)
                windowManager?.addView(shieldView, params)
                isShieldAttached = true
                Log.i(TAG, "Focus Shield successfully shown for ward: $wardTitle (Remaining snoozes: $remainingSnoozeCount)")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to show Focus Shield overlay: ${e.message}", e)
                isShieldAttached = false
                shieldView = null
            }
        }
    }

    /**
     * Hides and removes the Focus Shield overlay.
     */
    fun hide() {
        mainHandler.post {
            if (isShieldAttached && shieldView != null) {
                try {
                    windowManager?.removeView(shieldView)
                    Log.i(TAG, "Focus Shield hidden successfully")
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to remove Focus Shield view: ${e.message}", e)
                } finally {
                    isShieldAttached = false
                    shieldView = null
                }
            }
        }
    }

    fun isShowing(): Boolean = isShieldAttached

    private fun createShieldLayout(wardTitle: String, remainingSnoozeCount: Int): View {
        val rootLayout = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            // Deep background with soft opacity
            setBackgroundColor(Color.parseColor("#F20F1216"))
            setPadding(40, 40, 40, 40)
            isClickable = true
            isFocusable = true
        }

        // Card Container with Gold Border and Luxury Background
        val card = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(40, 44, 40, 44)
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#181D24"))
                cornerRadius = 40f
                setStroke(3, Color.parseColor("#BC8C15")) // AppColors.secondaryGold
            }
        }

        // 1. App Logo Container (Circular with gold halo)
        val logoContainer = LinearLayout(context).apply {
            gravity = Gravity.CENTER
            val paddingPx = 28
            setPadding(paddingPx, paddingPx, paddingPx, paddingPx)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#15BC8C15"))
                setStroke(2, Color.parseColor("#66BC8C15"))
            }
        }
        val logoView = ImageView(context).apply {
            val resId = context.resources.getIdentifier("ic_hafiz_logo", "drawable", context.packageName)
            if (resId != 0) {
                setImageResource(resId)
            } else {
                setImageResource(android.R.drawable.ic_lock_idle_alarm)
            }
            // Tint with app gold
            setColorFilter(Color.parseColor("#BC8C15"), PorterDuff.Mode.SRC_IN)
        }
        val logoSize = 160
        logoContainer.addView(logoView, LinearLayout.LayoutParams(110, 110))
        val containerParams = LinearLayout.LayoutParams(logoSize, logoSize).apply {
            setMargins(0, 0, 0, 20)
        }
        card.addView(logoContainer, containerParams)

        // 2. Title with Light Gold
        val titleText = TextView(context).apply {
            text = "حافظ على عهدك مع الله"
            textSize = 22f
            setTextColor(Color.parseColor("#F9D406")) // AppColors.lightGold
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
        }
        card.addView(titleText)

        // 3. Ward Name Subtitle
        val wardText = TextView(context).apply {
            text = "جلسة تركيز: $wardTitle"
            textSize = 18f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(0, 10, 0, 6)
        }
        card.addView(wardText)

        // 4. Reminder Body (Silver Marble Text)
        val bodyText = TextView(context).apply {
            text = "أنت الآن في وقت عبادتك، حافظ على عهدك واختم وردك قبل الانتقال لتطبيقات أخرى."
            textSize = 14f
            setTextColor(Color.parseColor("#D1D5DB"))
            gravity = Gravity.CENTER
            setLineSpacing(8f, 1.2f)
            setPadding(0, 10, 0, 26)
        }
        card.addView(bodyText)

        val btnParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            setMargins(0, 6, 0, 14)
        }

        // 5. Primary Action: Return to App with Authentic Gold Gradient (#F9D406 -> #BC8C15)
        val returnButton = Button(context).apply {
            text = "العودة للورد الآن"
            textSize = 16f
            setTextColor(Color.parseColor("#121212")) // Crisp dark contrast on gold
            typeface = Typeface.DEFAULT_BOLD
            background = GradientDrawable(
                GradientDrawable.Orientation.LEFT_RIGHT,
                intArrayOf(
                    Color.parseColor("#F9D406"), // lightGold
                    Color.parseColor("#BC8C15")  // secondaryGold
                )
            ).apply {
                cornerRadius = 28f
            }
            setPadding(32, 20, 32, 20)
            setOnClickListener {
                launchHafizApp(wardTitle)
            }
        }
        card.addView(returnButton, btnParams)

        // 6. Secondary Action: Snooze 5 Minutes (Max 2 times)
        val snoozeButton = Button(context).apply {
            if (remainingSnoozeCount > 0) {
                text = "⏳ غفوة 5 دقائق (متبقي $remainingSnoozeCount من 2)"
                textSize = 14f
                setTextColor(Color.parseColor("#F9D406")) // lightGold text
                background = GradientDrawable().apply {
                    setColor(Color.parseColor("#241D12"))
                    cornerRadius = 28f
                    setStroke(2, Color.parseColor("#BC8C15")) // secondaryGold border
                }
                setOnClickListener {
                    hide()
                    onSnoozeListener?.invoke()
                }
            } else {
                text = "استنفدت مرات الغفوة المتاحة (2/2)"
                textSize = 13f
                setTextColor(Color.parseColor("#6B7280")) // Muted Gray
                background = GradientDrawable().apply {
                    setColor(Color.parseColor("#191C22"))
                    cornerRadius = 28f
                    setStroke(1, Color.parseColor("#374151"))
                }
                isEnabled = false
            }
            setPadding(24, 16, 24, 16)
        }
        card.addView(snoozeButton, btnParams)

        // 7. Cancel Explanation Note
        val cancelNote = TextView(context).apply {
            text = "⚠️ لإلغاء جلسة اليوم، يرجى فتح التطبيق والإلغاء من الداخل."
            textSize = 11f
            setTextColor(Color.parseColor("#9CA3AF"))
            gravity = Gravity.CENTER
            setPadding(0, 6, 0, 0)
        }
        card.addView(cancelNote)

        rootLayout.addView(card)
        return rootLayout
    }

    private fun launchHafizApp(wardTitle: String) {
        try {
            hide()
            FocusPoCChannelHandler.pendingWardIntent = wardTitle
            FocusPoCChannelHandler.notifyEvent("onNavigateToWard", mapOf("wardTitle" to wardTitle))
            val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                putExtra("focus_ward_target", wardTitle)
            }
            if (intent != null) {
                context.startActivity(intent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to bring app to front: ${e.message}", e)
        }
    }
}
