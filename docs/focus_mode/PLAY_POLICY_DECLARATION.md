# Focus Mode — Google Play Store Policy & Compliance Declaration

**App Name:** حافظ العهد (Hafiz Al-Ahd)  
**Package:** `com.shadyatef.hafiz_alahd`  
**Target Feature:** Focus Mode (وضع التركيز وحماية الأوراد)  
**Date:** 2026-11-22  
**Target API:** Android 14 (API 34) / Minimum SDK: Android 8.0 (API 26)

---

## 1. Feature Description & Category
Focus Mode in «حافظ العهد» is a **Digital Wellbeing & Spiritual Habit Management** feature. It empowers Muslims to dedicate uninterrupted time to daily Quran reading and remembrance (Azkar) by shielding them from distracting social media, games, and entertainment apps during scheduled worship intervals.

---

## 2. Sensitive Permissions Declarations

### A. `android.permission.PACKAGE_USAGE_STATS` (Usage Access)
- **Play Console Core Functionality Declaration:**
  - Selected Category: **Digital Wellbeing / Habit Tracking**.
  - Purpose: To detect the package name of the currently visible foreground application during an **actively running** focus session.
- **Prominent In-App Disclosure (Compliant with Google Play User Data Policy):**
  - Before the user is redirected to `Settings.ACTION_USAGE_ACCESS_SETTINGS`, the app displays `FocusProminentDisclosureDialog`.
  - The dialog explicitly informs the user that usage access is needed solely to identify non-exempt apps while a focus session is active and show the protective shield.
- **Privacy & Data Minimization Guarantees:**
  - **100% On-Device Processing:** Polling is executed strictly in local RAM (`UsageStatsPoller.kt`).
  - **Zero Telemetry / Off-Device Transmission:** No package names, timestamps, app history, or device identifiers are recorded to remote servers or third-party analytics.
  - **Zero Content Inspection:** The app only inspects the active package identifier; it never reads app content, notifications, or user messages.
  - **Dismissibility:** The user retains full control to cancel or snooze the session at any time from within Hafiz Al-Ahd.

### B. `android.permission.SYSTEM_ALERT_WINDOW` (Display Over Other Apps)
- **Purpose:** To render the Focus Mode barrier screen when an unexempt app is launched during a scheduled ward session.
- **Deceptive Design & Security Protections:**
  - **Permanent System-Critical Exemption:** The system dialer (`ACTION_DIAL`), default home launcher (`CATEGORY_HOME`), emergency call receivers, and Hafiz Al-Ahd itself are **permanently unshielded** and cannot be blocked under any circumstances.
  - **Non-Obstruction:** The overlay does not mimic system security prompts, lockscreens, or system updates.
  - **Dismissibility:** Provides unambiguous buttons to snooze (up to 2 times, 5 minutes each) or return to Hafiz Al-Ahd to finish the ward.

### C. `android.permission.SCHEDULE_EXACT_ALARM` & `USE_EXACT_ALARM`
- **Play Console Declaration:**
  - Selected Core Use Case: **Time-sensitive alarms & spiritual habit schedules**.
  - Rationale: Morning Azkar (after Fajr/sunrise) and Evening Azkar (before Maghrib/Asr) are tied to exact solar prayer schedules and user-set prayer offsets. Imprecise alarms (inexact alarms) result in the session firing hours late or while the user is asleep, failing the core utility of timely worship.

### D. `android.permission.FOREGROUND_SERVICE_SPECIAL_USE` (Android 14+)
- **Manifest Definition:**
  ```xml
  <service
      android:name=".focus_poc.FocusPoCService"
      android:foregroundServiceType="specialUse"
      android:exported="false">
      <property
          android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
          android:value="Focus mode monitoring to prevent digital distractions during daily Quran and Azkar worship sessions" />
  </service>
  ```
- **FGS Justification for Reviewers:**
  - A persistent, user-visible notification is displayed whenever monitoring is active.
  - The service is transient: it only runs during the duration of the scheduled ward session and immediately stops itself upon ward completion.

### E. Package Visibility (`<queries>`)
- To list launchable apps for user customization in the App Exemption manager, the app declares:
  ```xml
  <queries>
      <intent>
          <action android:name="android.intent.action.MAIN" />
          <category android:name="android.intent.category.LAUNCHER" />
      </intent>
  </queries>
  ```
- **Policy Compliance:** Hafiz Al-Ahd **does NOT** declare `QUERY_ALL_PACKAGES`, ensuring 100% adherence to Google Play's high-risk permission restrictions.

---

## 3. Data Safety Section Responses

| Play Console Field | Answer | Justification |
|---|---|---|
| **Data Collection** | **No** | Hafiz Al-Ahd does not collect any user data via Focus Mode. |
| **Data Sharing** | **No** | No data is shared with third parties. |
| **Data Processing** | **Ephemeral (In-Memory)** | Foreground app checks are evaluated instantly in memory and discarded. |
| **Security Practices** | **No Data Transmitted** | All state resides in local SQLite database (`focus_mode.db`). |

---

## 4. Video Demonstration Script for Play Store Review Team
1. User enters **Settings** -> **وضع التركيز (حماية الأوراد)**.
2. User taps **تفعيل** for Usage Access: Prominent disclosure dialog appears and clearly details local processing. User accepts and is routed to system settings.
3. User enables a scheduled ward (e.g., Morning Azkar at current time + 1 min).
4. Alarm triggers; persistent notification appears stating "جلسة التركيز نشطة - أذكار الصباح".
5. User attempts to open a distracting app (e.g., YouTube); Hafiz Al-Ahd barrier appears encouraging the user to return to their ward.
6. User taps "العودة للورد" and completes the Azkar.
7. Barrier dismantles immediately and notification disappears.
