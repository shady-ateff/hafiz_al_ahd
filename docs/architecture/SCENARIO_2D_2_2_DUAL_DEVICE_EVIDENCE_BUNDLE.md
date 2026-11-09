# Phase 2D.2 Scenario 2D.2.2: Dual-Device Master Evidence Bundle
## Background Prayer Notification Delivery Verification

**Date:** 2026-11-09  
**Branch:** `feature/p4.1-independent-alarms-adhan`  
**Git Baseline Commit:** `9b016573cac649c421f6414eeba29e720e9d30ef`  
**Production Code Diff (`lib/`, `android/`):** **Strictly 0 diff lines**  
**Scenario Verdict:** **PASS ON BOTH DEVICES** (`SCENARIO_2D_2_2_PASS`)

---

## 1. Executive Summary

Scenario 2D.2.2 evaluates physical delivery of prayer notifications while the application process is alive and placed in the **Background** (`mCurrentFocus / mFocusedApp = LauncherActivity / Launcher`) via Android `KEYCODE_HOME` transition.

The scenario was executed across both physical reference devices:
1. **Primary:** Xiaomi Redmi Note 14 Pro+ 5G (`dfa9f629`, Android 16 / API 36 / HyperOS 2.0).
2. **Secondary:** Samsung Galaxy Tab A7 LTE (`192.168.1.186:45067`, Android 12 / API 31 / One UI 4.1).

Both physical devices passed all 7 multi-tier validation contracts ($C1$ through $C7$):
- **C1 (Tri-State Separation):** Native OS posting (`is_posted_in_os: true`) and Alerting Importance (`importance: 5`) verified via Android `NotificationManagerService`. Shade visibility UI capture executed via `cmd statusbar expand-notifications` + `uiautomator dump` + `screencap -p`.
- **C2 (Process State Preservation):** Application PID was confirmed identical before background transition, after background transition, and after alarm trigger delivery (`pid_preserved_across_trigger: true`), proving the application process remained alive in background without process-death recreation.
- **C3 (Composite Identity):** Exact match across Package (`com.shadyatef.hafiz_alahd`), Target ID (`999902`), Channel ID (`prayer_channel_v10_default`), Unique Title Marker (`[PHASE_2D_2_TEST_...] صلاة الفجر`), and Payload Marker.
- **C4 (AlarmManager Identity):** Exact match in `ScheduledNotificationReceiver` active queue with whole-second epoch alignment and PendingIntent binding while app was in background.
- **C5 (Surgical Cleanup & Sibling Non-Interference):** Target ID `999902` cleanly removed from both NotificationManager and AlarmManager using `cancel(999902)`, while Sibling ID `999903` remained actively queued and intact in AlarmManager (`SURGICAL_CLEANUP_NON_INTERFERENCE_PASS`).
- **C6 (Latency & Early Delivery Handling):** Negative delivery delta resulting from whole-second truncation in FLN/AlarmManager correctly classified as `EARLY_DELIVERY`.
- **C7 (Channel Profile):** Deep channel inspection verified `prayer_channel_v10_default` with `importance: 5`, `sound: true`, and `vibration_enabled: true`.

---

## 2. Dual-Device Side-by-Side Comparison Matrix

| Evaluation Dimension | Xiaomi Redmi Note 14 Pro+ 5G (`dfa9f629`) | Samsung Galaxy Tab A7 LTE (`192.168.1.186:45067`) | Status |
|---|---|---|---|
| **OS & Form Factor** | Android 16 (API 36, HyperOS 2.0) — Primary Phone | Android 12 (API 31, One UI 4.1) — Secondary Tablet | PASS |
| **Transport / Connectivity** | Physical High-Speed USB ADB | Wi-Fi ADB (`192.168.1.186:45067`) | PASS |
| **Preflight State** | Clean (0 active test alarms/notifications) | Clean (0 active test alarms/notifications) | PASS |
| **PID Before Background** | `PID: 19867` | `PID: 14319` | PASS |
| **PID After Background** | `PID: 19867` (Preserved: True) | `PID: 14319` (Preserved: True) | PASS |
| **PID After Alarm Trigger** | `PID: 19867` (Preserved: True) | `PID: 14319` (Preserved: True) | PASS |
| **Background Focus State** | `mCurrentFocus=com.miui.home/com.miui.home.launcher.Launcher`<br>`mFocusedApp=com.miui.home/.launcher.Launcher` | `mCurrentFocus=Window{... NotificationShade}`<br>`mFocusedApp=com.sec.android.app.launcher/...` | PASS |
| **Background Confirmed** | **True** (Focused on System Launcher) | **True** (Focused on System Launcher) | PASS |
| **Target ID & Horizon** | ID: `999902`, Horizon: 15 seconds | ID: `999902`, Horizon: 15 seconds | PASS |
| **Sibling ID & Horizon** | ID: `999903`, Horizon: 180 seconds | ID: `999903`, Horizon: 180 seconds | PASS |
| **Target Scheduled Epoch** | `1794250827728` | `1794251822779` | PASS |
| **Target Title Marker** | `[PHASE_2D_2_TEST_1794250827728] صلاة الفجر` | `[PHASE_2D_2_TEST_1794251822779] صلاة الفجر` | PASS |
| **Channel ID & Importance** | `prayer_channel_v10_default` (Importance: 5) | `prayer_channel_v10_default` (Importance: 5) | PASS |
| **AlarmManager Target Match (C4)** | **Matched: True** (`origWhen: 1794250827000`) | **Matched: True** (`origWhen: 1794251822000`) | PASS |
| **AlarmManager PendingIntent** | `PendingIntentRecord{1398dc3 broadcastIntent}` | `PendingIntentRecord{e976e0a broadcastIntent}` | PASS |
| **AlarmManager Sibling Match** | **Matched: True** (`origWhen: 1794250992000`) | **Matched: True** (`origWhen: 1794251987000`) | PASS |
| **OS Notification Posted (C1)** | **True** (`NotificationRecord` captured) | **True** (`NotificationRecord` captured) | PASS |
| **Alerting Importance (C1)** | **True** (`importance: 5`) | **True** (`importance: 5`) | PASS |
| **Matched Notification Key** | `0\|com.shadyatef.hafiz_alahd\|999902\|null\|10500` | `0\|com.shadyatef.hafiz_alahd\|999902\|null\|10406` | PASS |
| **Matched Notification Title** | `[PHASE_2D_2_TEST_1794250827728] صلاة الفجر` | `[PHASE_2D_2_TEST_1794251822779] صلاة الفجر` | PASS |
| **Matched Notification Text** | `حان الآن موعد صلاة الفجر (Target #999902 marker:...` | `حان الآن موعد صلاة الفجر (Target #999902 marker:...` | PASS |
| **Delivery Timing Delta (C6)** | `-699 ms` (`EARLY_DELIVERY`) | Whole-second aligned | PASS |
| **UI Shade Evidence Captured** | XML Dump + PNG Screenshot captured | XML Dump + PNG Screenshot captured | PASS |
| **Target Absent Post-Cleanup (C5)**| **True** (Notification: Absent, Alarm: Absent) | **True** (Notification: Absent, Alarm: Absent) | PASS |
| **Sibling Intact Post-Cleanup (C5)**| **True** (`sibling_in_alarm_manager: true`) | **True** (`sibling_in_alarm_manager: true`) | PASS |
| **Cleanup Non-Interference Verdict** | **`SURGICAL_CLEANUP_NON_INTERFERENCE_PASS`** | **`SURGICAL_CLEANUP_NON_INTERFERENCE_PASS`** | PASS |
| **Post-Test Teardown Cleanliness** | 0 active alarms, 0 active notifications | 0 active alarms, 0 active notifications | PASS |
| **Production Code Zero-Diff** | `git diff lib/ android/` = 0 lines | `git diff lib/ android/` = 0 lines | PASS |
| **Overall Scenario Verdict** | **`SCENARIO_2D_2_2_PASS`** | **`SCENARIO_2D_2_2_PASS`** | PASS |

---

## 3. Key Technical & Operational Findings

### A. Non-Destructive Background Transition via `KEYCODE_HOME`
In contrast to process-death or swipe-to-dismiss testing, Scenario 2D.2.2 strictly required verifying delivery while the application process remains alive in the background. The orchestrator injected `adb shell input keyevent KEYCODE_HOME`, which:
1. Maintained the process alive with identical PID (`19867` on Xiaomi, `14319` on Samsung).
2. Transferred window focus and top activity to the device launcher (`com.miui.home` / `com.sec.android.app.launcher`).
3. Allowed `AlarmManager` to dispatch the broadcast intent into `ScheduledNotificationReceiver`, which posted to `NotificationManager` while the UI remained in the background.

### B. In-Session Surgical Cleanup Under Wi-Fi ADB Latency
On the Samsung tablet communicating via Wi-Fi ADB (`192.168.1.186:45067`), extracting OS state dumps (`dumpsys notification --noredact`, `uiautomator dump`, `screencap -p`, and `adb pull`) requires 40 to 60 seconds of network roundtrip.
- Initial runs revealed that a short teardown delay (32s) caused the test app to execute teardown of Sibling `#999903` before the host-side observer could complete its multi-step verification.
- By calibrating `cleanupDelay = 25s` (for Target `#999902`) and `teardownDelay = 80s` (for Sibling `#999903`), the host successfully captured `sibling_in_alarm_manager: true` during Step 5, proving non-interference conclusively, followed by clean teardown in Step 5b.

---

## 4. Evidence Artifact Manifest

1. **Master Evidence Bundles:**
   - Xiaomi: [`test_evidence/scenario_2d_2_2_master_evidence_dfa9f629_20261109_205926.json`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/test_evidence/scenario_2d_2_2_master_evidence_dfa9f629_20261109_205926.json)
   - Samsung: [`test_evidence/scenario_2d_2_2_master_evidence_192.168.1.186_45067_20261109_211431.json`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/test_evidence/scenario_2d_2_2_master_evidence_192.168.1.186_45067_20261109_211431.json)
2. **Channel & Permissions Profiles:**
   - Xiaomi: [`test_evidence/channel_profile_dfa9f629_20261109_205926.json`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/test_evidence/channel_profile_dfa9f629_20261109_205926.json)
   - Samsung: [`test_evidence/channel_profile_192.168.1.186_45067_20261109_211431.json`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/test_evidence/channel_profile_192.168.1.186_45067_20261109_211431.json)
3. **Mid-Flight AlarmManager Records:**
   - Xiaomi: [`test_evidence/target_notification_alarm_dfa9f629_20261109_210016.json`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/test_evidence/target_notification_alarm_dfa9f629_20261109_210016.json)
   - Samsung: [`test_evidence/target_notification_alarm_192.168.1.186_45067_20261109_211648.json`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/test_evidence/target_notification_alarm_192.168.1.186_45067_20261109_211648.json)
4. **Active NotificationRecords:**
   - Xiaomi: [`test_evidence/target_notification_record_dfa9f629_20261109_210031.json`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/test_evidence/target_notification_record_dfa9f629_20261109_210031.json)
   - Samsung: [`test_evidence/target_notification_record_192.168.1.186_45067_20261109_211711.json`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/test_evidence/target_notification_record_192.168.1.186_45067_20261109_211711.json)
5. **UI Shade Dumps & Screenshots:**
   - Xiaomi XML: [`test_evidence/shade_ui_dfa9f629_20261109_210031.xml`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/test_evidence/shade_ui_dfa9f629_20261109_210031.xml)
   - Xiaomi Screenshot: [`test_evidence/shade_screenshot_dfa9f629_20261109_210031.png`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/test_evidence/shade_screenshot_dfa9f629_20261109_210031.png)
   - Samsung XML: [`test_evidence/shade_ui_192.168.1.186_45067_20261109_211711.xml`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/test_evidence/shade_ui_192.168.1.186_45067_20261109_211711.xml)
   - Samsung Screenshot: [`test_evidence/shade_screenshot_192.168.1.186_45067_20261109_211711.png`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/test_evidence/shade_screenshot_192.168.1.186_45067_20261109_211711.png)
6. **6-Point Surgical Cleanup Records:**
   - Xiaomi: [`test_evidence/notification_cleanup_dfa9f629_20261109_210040.json`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/test_evidence/notification_cleanup_dfa9f629_20261109_210040.json)
   - Samsung: [`test_evidence/notification_cleanup_192.168.1.186_45067_20261109_211753.json`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/test_evidence/notification_cleanup_192.168.1.186_45067_20261109_211753.json)

---

## 5. Next Steps & Stop Gate Recommendation

With Scenario 2D.2.1 (Foreground Delivery) and Scenario 2D.2.2 (Background Delivery) both fully verified and passing on both reference physical devices with zero production diff, the test harness is prepared for the decisive test:

**Scenario 2D.2.3: Process-Death Prayer Notification Delivery**  
- Proving that after the app process is terminated via `SIGKILL` (`kill -9 <PID>`) without package force-stop, `AlarmManager` preserves the pending alarm, Android wakes and dispatches the broadcast intent to `ScheduledNotificationReceiver`, and the native notification is posted to `NotificationManager` during process death.

