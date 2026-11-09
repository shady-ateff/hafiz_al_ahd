# Phase 2D — Physical Android Verification
## Real-Device Delivery, Audio, Lifecycle & Power-Management Validation

**Project:** Hafiz Al-Ahd (حافظ العهد)  
**Branch:** `feature/p4.1-independent-alarms-adhan`  
**Previous Phase:** Phase 2C.4.2.4 — CLOSED (Commit: `9b016573cac649c421f6414eeba29e720e9d30ef`)  
**Authorization:** Phase 2D Planning & Verification Only  
**Status:** PLAN — NOT AUTHORIZED FOR PRODUCTION IMPLEMENTATION

---

# 1. Objective

التحقق من سلوك نظام Prayer Alarms على أجهزة Android فعلية، وإثبات صحة دورة حياة الأحداث من لحظة الجدولة وحتى التسليم الفعلي.

التحقق يشمل:
1. Prayer Alarm delivery باستخدام `package:alarm`.
2. Prayer Notification delivery باستخدام `flutter_local_notifications`.
3. Adhan audio playback.
4. Vibration behavior.
5. Behavior أثناء إغلاق التطبيق أو انتقاله للخلفية.
6. Doze Mode وBattery Optimization.
7. OEM-specific background restrictions.
8. Reboot behavior إذا كان مدعومًا ضمن التصميم الحالي.
9. عدم فقدان أو تكرار الأحداث أثناء إعادة الجدولة.

**المبدأ الأساسي:**
$$\text{Plugin Registry} \ne \text{Android OS Delivery}$$
وجود Alarm في `Alarm.getAlarm()` أو Notification داخل `pendingNotificationRequests()` لا يثبت أن Android سلّم الحدث فعليًا.

---

# 2. Scope & Non-Goals

## In Scope
- Physical Android verification.
- Controlled scheduling scenarios.
- Actual notification delivery.
- Actual alarm screen/audio behavior.
- Background and foreground lifecycle.
- Doze and battery restrictions.
- Reconciliation after app restart.
- Evidence collection and failure classification.

## Explicitly Out of Scope
- UI settings implementation.
- Adhan voice catalog.
- User-uploaded Adhan audio.
- Fajr challenge.
- New alarm customization features.
- Changes to deterministic ID contract.
- Changes to reconciliation architecture without a reproduced defect.
- Production release or deployment.

أي defect يتم اكتشافه يُسجل أولًا، ولا يتم تعديل النظام أثناء تنفيذ تجربة التحقق نفسها.

---

# 3. Device Matrix

| Device | Role | Platform / Hardware |
|---|---|---|
| **Xiaomi Redmi Note 14 Pro+ 5G** (`25098RA98G` / `kunzite`) | Primary device | Android 16 / API 36 |
| **Samsung Galaxy Tab A7 LTE** (`SM-T505N`) | Secondary device | Android version/API يتم تسجيلهما قبل الاختبار |

قبل أي تجربة، سجل:
- Device model.
- Android version / API level.
- Manufacturer build number.
- Battery optimization state.
- App battery restriction state.
- Notification permission state.
- Exact app build / Git commit.
- Plugin versions.
- Device time and timezone.
- Whether the device is charging.

لا نفترض أن نتيجة جهاز واحد قابلة للتعميم على جميع أجهزة Android.

---

# 4. Phase 2D.0 — Baseline & Test Harness Preparation

## Objective
إنشاء بيئة اختبار قابلة للتكرار دون إدخال Production UI.

## Tasks
### 4.1 Freeze Baseline
- تأكيد وجود Commit الخاص بـ Phase 2C.4.2.4 (`9b016573cac649c421f6414eeba29e720e9d30ef`).
- تسجيل commit hash.
- عدم تعديل scheduler أو repositories أثناء baseline collection.
- تسجيل Flutter/Dart versions.
- تسجيل dependency versions المتعلقة بالـ Alarm و Notifications (`alarm`, `flutter_local_notifications`, `crypto`).

### 4.2 Diagnostic Harness
إنشاء وسيلة اختبار داخلية مؤقتة تسمح بتنفيذ السيناريوهات دون الحاجة إلى UI نهائية (عبر `integration_test/` أو debug test runner).

يجب أن تدعم:
1. Schedule Prayer Alarm بعد مدة قصيرة محددة (Short horizon: e.g. 15s, 30s, 60s).
2. Schedule Prayer Notification بعد مدة قصيرة محددة.
3. Schedule أكثر من حدث بمعرفات مختلفة.
4. تشغيل scheduler reconciliation.
5. قراءة plugin-level state.
6. قراءة persistent fingerprint state.
7. تسجيل lifecycle events.
8. تسجيل actual delivery callbacks أو native events المتاحة.

**Constraint:** لا تضف Debug UI إلى Production، ولا تجعل أداة الاختبار تعتمد على تعديل بيانات المستخدم الفعلية.

### 4.3 Evidence Logger
كل تجربة تسجل:
- Scenario ID.
- Device ID.
- Commit hash.
- Event ID.
- Expected delivery time.
- Scheduling timestamp.
- Plugin verification result.
- App lifecycle state.
- Actual delivery timestamp.
- Audio start/end timestamps إن أمكن.
- Observed result.
- Failure classification.

### Exit Criteria
- Test harness يعمل على الجهازين.
- يمكن جدولة حدث قصير المدى بصورة متكررة.
- يمكن تمييز plugin-level verification عن actual OS delivery.
- لا توجد تغييرات في Production scheduling behavior.

**STOP GATE 2D.0:** اعتماد Test Harness و Baseline قبل اختبارات التسليم.

---

# 5. Phase 2D.1 — Prayer Alarm Physical Delivery

## Objective
إثبات أن `package:alarm` ينتج Alarm فعليًا على الجهاز.

## Scenarios
### A. Foreground
- التطبيق مفتوح.
- جدولة Alarm بعد مدة قصيرة.
- انتظار موعد الحدث.
- التحقق من ظهور شاشة المنبه.
- التحقق من تشغيل الصوت.
- التحقق من الاهتزاز.

### B. Background
- جدولة Alarm.
- نقل التطبيق إلى الخلفية.
- انتظار موعد الحدث.
- تسجيل هل تم التسليم أم لا.

### C. App Process Death
- جدولة Alarm.
- التأكد من تسجيله داخل Plugin.
- إنهاء عملية التطبيق بالطريقة المحددة في السيناريو.
- انتظار موعد الحدث.
- تسجيل النتيجة.

يجب التفريق بين:
- App moved to background.
- App process killed.
- Force Stop من Android Settings.

هذه حالات مختلفة، ولا يجوز دمج نتائجها.

### D. Active Alarm Protection
- تشغيل Alarm.
- محاولة تشغيل reconciliation أثناء الرنين.
- التأكد أن منطق الحماية لا يلغي الحدث النشط.

### E. Timing Accuracy
اختبار عدة مدد زمنية قصيرة ومتوسطة.
تسجيل:
$$\text{Delivery Delta} = \text{Actual Delivery Time} - \text{Expected Delivery Time}$$
لا يتم اعتماد دقة التسليم من تجربة واحدة.

## Evidence
- فيديو أو تسجيل شاشة عند الحاجة.
- Logcat.
- Harness logs.
- Expected vs actual timestamps.
- Plugin state before/after delivery.

## Exit Criteria
- توثيق نتائج foreground/background/process death كل حالة على حدة.
- لا توجد ادعاءات بتسليم ناجح بدون دليل فعلي.
- أي تأخير أو فقدان موثق مع ظروف إعادة إنتاجه.

**STOP GATE 2D.1:** CLOSED & APPROVED (Dual-Device Certified: Xiaomi HyperOS Android 16 & Samsung One UI Android 12). Full Evidence in `docs/architecture/PHASE_2D_1_DUAL_DEVICE_FINAL_EVIDENCE_BUNDLE.md`.

---

# 6. Phase 2D.2 — Prayer Notification Physical Delivery

## Objective
إثبات تسليم FLN Notifications فعليًا.

## Scenarios
1. التطبيق مفتوح.
2. التطبيق في الخلفية.
3. عملية التطبيق منتهية.
4. Notification Channel enabled.
5. Notification permission denied.
6. Notification permission granted.
7. Multiple notifications with different IDs.
8. Notification arrives while another notification is visible.

## Verification
لكل حدث:
- التأكد من أن الحدث تم جدولته.
- تسجيل pending request قبل الموعد.
- انتظار الموعد الفعلي.
- التحقق من ظهور Notification داخل Android Notification Shade.
- تسجيل وقت التسليم.
- التحقق من عدم ظهور Notification مكرر.
- التأكد من أن أحداثًا أخرى غير مملوكة للنظام لم تتأثر.

يجب عدم اعتبار اختفاء pending request وحده دليلًا كافيًا على التسليم؛ يلزم إثبات ظهور الحدث أو تسجيل native delivery evidence مناسب.

## Exit Criteria
- نتائج فعلية لكل حالة.
- فصل مشاكل الإذن والقنوات عن مشاكل الجدولة والتسليم.
- إثبات عدم وجود blanket cancellation أو تداخل بين الأحداث.

**STOP GATE 2D.2:** CLOSED & APPROVED (Dual-Device Certified: Xiaomi HyperOS Android 16 & Samsung One UI Android 12). Full Evidence in `docs/architecture/PHASE_2D_2_DUAL_DEVICE_FINAL_EVIDENCE_BUNDLE.md`.

---

# 7. Phase 2D.3 — Adhan Audio & Vibration

## Objective
التحقق من تجربة التنبيه الفعلية، وليس مجرد نجاح استدعاء تشغيل الصوت.

## Scenarios
### Audio
- Alarm starts with expected Adhan asset.
- Audio continues for expected duration.
- Audio stops when the alarm is dismissed.
- Audio behavior when another notification arrives.
- Audio behavior when the app is backgrounded.
- Audio behavior when device volume is low or muted.

### Audio Interruption
اختبر:
- Incoming phone call.
- Another media playback session.
- Audio focus interruption.
- Device DND state.

يجب تسجيل السلوك المتوقع والسلوك الفعلي لكل حالة.

### Vibration
- Vibration enabled.
- Vibration disabled.
- Repeated alarm behavior.
- Interaction with device vibration settings.

لا نعتبر تشغيل الصوت ناجحًا لمجرد عدم ظهور Exception.

## Exit Criteria
- إثبات بداية الصوت ونهايته.
- إثبات اختيار الـ asset الصحيح.
- إثبات سلوك الاهتزاز.
- توثيق أي اختلاف بين الأجهزة.

**STOP GATE 2D.3:** اعتماد Audio/Vibration behavior.

---

# 8. Phase 2D.4 — Doze & Battery Restrictions

## Objective
تحديد مدى موثوقية التسليم تحت قيود الطاقة الحقيقية.

## Test Conditions
اختبر كل حالة بصورة مستقلة:
1. Screen on / device active.
2. Screen off.
3. Device idle.
4. Doze Mode.
5. App battery optimization enabled.
6. App battery optimization disabled.
7. OEM background restrictions enabled.
8. OEM background restrictions disabled.

## Android Test Procedure
استخدم Android debugging tools لتفعيل ومراقبة حالات Doze و Idle، مع تسجيل الأوامر والنتائج الفعلية (`adb shell dumpsys deviceidle`).

يجب أن تكون التجارب Controlled:
- لا تغير أكثر من متغير واحد في كل تجربة.
- سجل حالة الجهاز قبل وبعد الاختبار.
- أعد الجهاز إلى baseline بين التجارب.

## Important Distinction
عدم وصول Alarm تحت بعض القيود لا يعني تلقائيًا وجود defect في scheduler.
يجب تصنيف المشكلة إلى:
- Scheduling defect.
- Plugin limitation.
- Android OS restriction.
- OEM power management.
- Permission/configuration issue.
- Audio execution issue.

## Exit Criteria
- نتائج Doze موثقة.
- نتائج battery optimization موثقة.
- نتائج OEM restrictions موثقة لكل جهاز.
- لا توجد استنتاجات معممة من جهاز واحد.

**STOP GATE 2D.4:** اعتماد Power Management Findings.

---

# 9. Phase 2D.5 — Reboot & Recovery

## Objective
التحقق من استمرارية الأحداث واستعادة الجدولة بعد إعادة تشغيل الجهاز.

## Scenarios
1. Schedule events.
2. Reboot device before delivery.
3. Verify whether events remain scheduled.
4. Open app after reboot.
5. Execute reconciliation.
6. Verify that missing events are restored.
7. Verify that existing events are not duplicated.
8. Verify horizon advancement only after successful reconciliation.

يجب تحديد ما إذا كان النظام الحالي يتوقع تسليم الأحداث بعد reboot مباشرة أم يتطلب تشغيل التطبيق وإعادة reconciliation.

لا نضيف Boot Receiver أو نغير native architecture قبل إثبات أن السلوك المطلوب غير مدعوم حاليًا.

## Exit Criteria
- توثيق السلوك قبل وبعد reboot.
- التحقق من عدم وجود duplicate scheduling.
- إثبات recovery behavior.
- تسجيل أي متطلبات Android native غير متوفرة.

**STOP GATE 2D.5:** اعتماد Recovery Findings.

---

# 10. Phase 2D.6 — Cross-Device Regression

بعد اكتمال المراحل السابقة، شغّل مجموعة Regression موحدة على الجهازين.

| Category | Primary Device | Secondary Device |
|---|---|---|
| Alarm foreground | Required | Required |
| Alarm background | Required | Required |
| Alarm process death | Required | Required |
| Notification delivery | Required | Required |
| Audio playback | Required | Required |
| Vibration | Required | Required |
| Doze | Required | Required |
| Battery restrictions | Required | Required |
| Reboot recovery | Required | Required |
| Reconciliation | Required | Required |

كل نتيجة يجب أن تكون واحدة من:
- **PASS** — verified physically.
- **FAIL** — reproducible failure.
- **BLOCKED** — environment/permission prevents execution.
- **INCONCLUSIVE** — insufficient evidence.

ممنوع تحويل BLOCKED أو INCONCLUSIVE إلى PASS.

---

# 11. Defect Handling Protocol

عند اكتشاف أي مشكلة:
1. أوقف السيناريو الحالي.
2. احتفظ بالـ logs والـ timestamps.
3. حاول إعادة إنتاج المشكلة.
4. حدد هل المشكلة في scheduler أم plugin أم Android OS أم OEM.
5. أنشئ Defect Report منفصل.
6. اقترح إصلاحًا محدود النطاق.
7. لا تعدل أكثر من طبقة دون دليل يثبت الحاجة.
8. أعد تشغيل السيناريو المتأثر.
9. أعد تشغيل Regression Tests الخاصة بالمرحلة.

أي تعديل في Production code يفتح مراجعة جديدة قبل اعتماده.

---

# 12. Final Acceptance Criteria

لا تعتبر Phase 2D مكتملة إلا عند توفر:
- Physical delivery evidence للـ Prayer Alarm.
- Physical delivery evidence للـ Prayer Notification.
- Audio/Vibration verification.
- Background/process lifecycle results.
- Doze and battery restrictions results.
- Reboot/recovery results أو توثيق واضح لحدود الدعم الحالي.
- Cross-device regression report.
- Defect list مع حالة كل مشكلة.
- Final test matrix.
- No unresolved critical delivery failures.

**مهم:** نجاح الاختبارات على جهازين لا يثبت ضمان التسليم على كل أجهزة Android؛ التقرير النهائي يجب أن يحدد الأجهزة والإصدارات والظروف التي تم اختبارها فقط.

---

# 13. Final STOP GATE

بعد اكتمال Phase 2D:
**STOP GATE 2D — Physical Verification Closure**

القرارات الممكنة:
- **APPROVED:** physical verification passed ضمن الأجهزة والظروف المختبرة.
- **CONDITIONALLY APPROVED:** قيود معروفة ومقبولة وموثقة.
- **REJECTED:** فشل أساسي في التسليم أو الصوت أو الاستعادة.

إغلاق هذا الـ Gate لا يمنح تلقائيًا تصريح Release أو Deploy.
أي Release يحتاج Gate مستقل ومراجعة مستقلة.

---

# 14. Execution Order

التنفيذ الإلزامي:
1. Phase 2D.0 — Baseline & Harness.
2. Phase 2D.1 — Prayer Alarm Delivery.
3. Phase 2D.2 — Notification Delivery.
4. Phase 2D.3 — Audio & Vibration.
5. Phase 2D.4 — Doze & Battery Restrictions.
6. Phase 2D.5 — Reboot & Recovery.
7. Phase 2D.6 — Cross-Device Regression.
8. Final STOP GATE 2D.

**Current Authorization:**
مسموح بالبدء في Phase 2D.0 فقط بعد اعتماد الخطة.
- لا تبدأ Phase 2D.1 قبل إغلاق Gate 2D.0.
- لا تبدأ إصلاحات Production أثناء جمع Baseline evidence.
- لا يوجد تصريح UI أو Release أو Deploy ضمن هذه الخطة.

