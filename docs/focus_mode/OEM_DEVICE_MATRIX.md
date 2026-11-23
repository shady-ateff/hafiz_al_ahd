# Focus Mode — OEM Device Matrix & Battery Optimization Reference

**App Name:** حافظ العهد (Hafiz Al-Ahd)  
**Date:** 2026-11-22  
**Feature:** Focus Mode (وضع التركيز وحماية الأوراد)

---

## 1. Background & Problem Statement
Android manufacturers implement non-standard, highly aggressive background process management and task killers (often collectively referred to in the developer community as *Don't Kill My App* behaviors).
These battery managers may kill the `FocusMonitoringService` or suppress exact `AlarmManager` wakeup alarms unless specific manufacturer settings are configured by the user.

This document serves as the architectural reference and user guidance specification for ensuring continuous, reliable session enforcement across all major Android OEMs.

---

## 2. OEM Compatibility Matrix

| Manufacturer / OS | Severity | Primary Risk | Mitigation & Required User Configuration |
|---|---|---|---|
| **Xiaomi / Poco / Redmi**<br>(MIUI 12–14, HyperOS) | 🔴 **High** | Kills background services within 1–3 minutes; drops AlarmManager wakeups. | 1. Enable **Autostart (التشغيل التلقائي)**.<br>2. Set Battery Saver to **"No restrictions" (لا توجد قيود)**.<br>3. Lock the app in the Recent Apps view. |
| **Samsung**<br>(One UI 4.0 – 6.1) | 🟡 **Medium** | Places unused or background apps into "Sleeping" or "Deep Sleeping" lists. | 1. Add Hafiz Al-Ahd to **"Never sleeping apps" (تطبيقات لا تنام أبدًا)**.<br>2. Set App Battery usage to **"Unrestricted" (غير مقيّد)**. |
| **Huawei / Honor**<br>(EMUI 10–13, MagicOS) | 🔴 **High** | Aggressive AI Power Genius stops services upon screen lock. | 1. Battery > **App Launch (تشغيل التطبيقات)**.<br>2. Switch Hafiz Al-Ahd from "Automatic" to **"Manage manually" (إدارة يدوية)**.<br>3. Toggle ON: Auto-launch, Secondary launch, and Run in background. |
| **Oppo / Realme / OnePlus**<br>(ColorOS, Realme UI, OxygenOS 12+) | 🟡 **Medium** | Quick Freezing stops poller thread when app isn't interacted with. | 1. App Info > Battery > Allow **"Background activity"** and **"Auto-launch"**.<br>2. Lock app in Recents. |
| **Vivo / iQOO**<br>(FuntouchOS, OriginOS) | 🟡 **Medium** | Restricts background power consumption. | 1. Battery > Background Power Consumption Management > Allow **"High background power consumption"**.<br>2. Security > Autostart allowed. |
| **Google Pixel / Motorola / Stock Android**<br>(Android 9 – 14+) | 🟢 **Standard** | Standard AOSP Doze Mode. | 1. Request **`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`**.<br>2. Exact alarms via **`SCHEDULE_EXACT_ALARM`** (`setExactAndAllowWhileIdle`). |

---

## 3. Engineering Mitigations Implemented in Code

1. **Doze-Proof Alarm Scheduling (Phase 3):**
   - Utilizes `AlarmManager.setExactAndAllowWhileIdle()` on API 23+.
   - Acquired a 30-second `WakeLock` (`FocusAlarmReceiver.kt`) upon broadcast receipt before starting `FocusMonitoringService` to ensure the CPU does not return to deep sleep prior to service initialization.
2. **Foreground Service with Persistent Notification (Phase 3):**
   - Elevated to high-priority foreground service (`startForeground`) with a visible ongoing notification to signal to the Linux Out-Of-Memory (OOM) killer that the process must not be pruned (`oom_adj` priority).
3. **Boot & Time Event Resilience (Phase 3):**
   - `FocusBootReceiver.kt` listens to `BOOT_COMPLETED`, `TIMEZONE_CHANGED`, `TIME_SET`, and `MY_PACKAGE_REPLACED` to dynamically re-arm alarms after phone reboots or clock adjustments.
4. **Deep Reconciliation upon App Launch (Phase 2 & 6):**
   - Even if an OEM prematurely kills the service, `FocusSessionRecoveryManager` checks native status and persistent SQLite state upon subsequent launch, reconciling any discrepancies without data corruption.
5. **Interactive In-App Guidance (Phase 7):**
   - Integrated `FocusOEMGuideSheet` directly into the Permissions card and Focus Settings screen, delivering manufacturer-specific instructions in clear Arabic.

---

## 4. Verification Checklist for Device Testing

- [x] **Xiaomi HyperOS:** Service survives 10 minutes with screen locked when Autostart & No Restrictions are enabled.
- [x] **Samsung One UI:** Alarm triggers on schedule with device in deep Doze mode overnight.
- [x] **Stock Pixel:** Battery optimization dialog properly removes app from Doze throttling list.
- [x] **App Kill & Reopen:** Active session restores seamlessly without orphaned native alerts.
