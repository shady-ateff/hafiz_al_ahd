# R7 — State Machine
**Document ID:** `FOCUS_MODE_R7`
**Type:** State Machine Specification
**Platform:** Android Only
**Status:** COMPLETE
**Review Date:** 2026-11-21

---

## 1. الحالات الرئيسية (States)

```
DISABLED          → Focus Mode معطَّل بالكامل من الإعدادات
IDLE              → Focus Mode مُفعَّل لكن لا توجد جلسة نشطة
SCHEDULED         → جلسة مجدولة ولم يحن موعدها بعد
STARTING          → جاري تهيئة الجلسة (بدء الـ Service)
ACTIVE            → جلسة نشطة، المستخدم في التطبيق المسموح به
SHIELDING         → جلسة نشطة، المستخدم في تطبيق محظور → Shield ظاهر
COMPLETING        → تم استقبال حدث الاكتمال، جارٍ إنهاء الجلسة
PAUSED            → ⚠️ OPEN QUESTION (تجاوز مؤقت)
ERROR             → خطأ في الخدمة أو الأذونات
```

---

## 2. مخطط الحالات الكامل

```
                     ┌──────────┐
                     │ DISABLED │
                     └────┬─────┘
                          │ User enables Focus Mode
                          ▼
                     ┌──────────┐
              ┌──────│   IDLE   │◄─────────────────────────┐
              │      └────┬─────┘                          │
              │           │ Scheduled time reached          │
              │           │ (AlarmManager fires)            │
              │           ▼                                 │
              │      ┌───────────┐                          │
              │      │ SCHEDULED │                          │
              │      └────┬──────┘                          │
              │           │ Time arrives → start service    │
              │           ▼                                 │
              │      ┌──────────┐                           │
              │      │ STARTING │                           │
              │      └────┬─────┘                           │
              │           │ Service started successfully     │
              │           ▼                                 │
              │      ┌──────────┐    restricted app        │
              │      │  ACTIVE  │──────────────────────────►│SHIELDING│
              │      └────┬─────┘                           └────┬────┘
              │           │                                      │ allowed app
              │           │ completion event                     │ detected
              │           │ OR manual stop                       │
              │           │                                 ┌────▼────┐
              │           ▼                                 │ ACTIVE  │◄─┐
              │      ┌───────────┐                          └─────────┘  │
              │      │COMPLETING │                                        │
              │      └────┬──────┘                                        │
              │           │ cleanup done                                   │
              │           ▼                                                │
              │      ┌──────────┐    completion event from SHIELDING      │
              │      │   IDLE   │                                         │
              │      └──────────┘                                         │
              │                                                           │
              │  User disables                           manual stop      │
              └──────────────────────────────────────────────────────────-┘
```

---

## 3. الانتقالات (Transitions) التفصيلية

### 3.1 DISABLED → IDLE
- **المُشغِّل:** المستخدم يُفعِّل "Enable Focus Mode" في الإعدادات
- **الإجراء:** حفظ الإعداد في SharedPreferences
- **الشرط:** لا شروط

### 3.2 IDLE → IDLE (جدولة)
- **المُشغِّل:** المستخدم يحفظ وقت جلسة جديدة
- **الإجراء:** `AlarmManager.setExactAndAllowWhileIdle()`
- **الحالة الداخلية:** يُحفظ الموعد القادم

### 3.3 IDLE → STARTING
- **المُشغِّل:** `FocusAlarmReceiver.onReceive()` أو المستخدم يبدأ يدوياً
- **الإجراء:** `context.startForegroundService(FocusMonitorService)`
- **الشروط:**
  - Focus Mode مُفعَّل
  - `PACKAGE_USAGE_STATS` ممنوح
  - `SYSTEM_ALERT_WINDOW` ممنوح

### 3.4 STARTING → ACTIVE
- **المُشغِّل:** `FocusMonitorService.onCreate()` يكتمل بنجاح
- **الإجراء:** يبدأ polling loop، يُرسل إشعار Foreground
- **الإشعار:** "🕌 جلسة التركيز نشطة - أذكار الصباح"

### 3.5 STARTING → ERROR
- **المُشغِّل:** فشل بدء الخدمة (لم يُمنح إذن، OEM block)
- **الإجراء:** يُرسل إشعار خطأ، يُرجع إلى IDLE
- **الرسالة:** "تعذّر بدء جلسة التركيز - تحقق من الأذونات"

### 3.6 ACTIVE → SHIELDING
- **المُشغِّل:** `UsageStatsHelper.getForegroundApp()` يُرجع package محظور
- **الإجراء:** `FocusShieldOverlayService.show()`
- **الكمون:** 3-5 ثوانٍ (بحسب polling interval)

### 3.7 SHIELDING → ACTIVE
- **المُشغِّل:** `UsageStatsHelper.getForegroundApp()` يُرجع:
  - package التطبيق نفسه (Hafiz Al-Ahd)
  - package تطبيق مسموح به
  - `null`
- **الإجراء:** `FocusShieldOverlayService.hide()`

### 3.8 ACTIVE/SHIELDING → COMPLETING
- **المُشغِّل:** `AzkarCompletionPort` يُصدر `AzkarSessionResult(isFullyCompleted: true)` لنوع الورد الحالي
- **الإجراء:**
  1. `FocusShieldOverlayService.hide()`
  2. إشعار "🎉 أحسنت! أكملت وردك"
  3. `FocusMonitorService.stopSelf()`

### 3.9 ACTIVE/SHIELDING → COMPLETING (manual stop)
- **المُشغِّل:** المستخدم يضغط "إيقاف التركيز" في الإشعار
- **الإجراء:** نفس 3.8 بدون إشعار التهنئة

### 3.10 COMPLETING → IDLE
- **المُشغِّل:** انتهاء عملية التنظيف
- **الإجراء:** إعادة جدولة الجلسة القادمة إن وُجدت

---

## 4. حالات الحافة (Edge Cases)

### 4.1 Reboot أثناء ACTIVE
```
ACTIVE → [DEVICE REBOOTS] → IDLE
  → BOOT_COMPLETED receiver يُعيد جدولة المنبهات
  → لا تُبدأ جلسة جديدة تلقائياً (قد انتهى وقت الورد)
  → إشعار: "انتهت جلسة التركيز بسبب إعادة التشغيل"
```

### 4.2 PACKAGE_USAGE_STATS يُسحب أثناء ACTIVE
```
ACTIVE → ERROR
  → Service يكتشف عودة list فارغة من UsageStats
  → يُوقف نفسه
  → إشعار: "تعذّر متابعة جلسة التركيز - الإذن لم يعد متاحاً"
```

### 4.3 اتصال هاتفي وارد
```
ACTIVE/SHIELDING → تطبيق الهاتف يصبح Foreground
  → الهاتف مستثنى دائماً → لا يظهر Shield
  → بعد انتهاء المكالمة → يُعود للحالة السابقة
```

### 4.4 شاشة القفل
```
الجهاز يُقفل → الشاشة تُطفأ
  → polling يتوقف مؤقتاً (Doze)
  → Service يستمر بفضل WAKE_LOCK
  → عند فتح الشاشة → polling يُستأنف
```

### 4.5 OEM يوقف الـ Service قسراً
```
ACTIVE → [OEM kills service] → ضياع الجلسة
  → لا يوجد حل مضمون
  → ⚠️ UNVERIFIED: هل flutter_background_service لديه آلية restart؟
  → يُوثَّق في R8 كـ known limitation على هذه الأجهزة
```

---

## 5. حالة ماكينة Foreground Service

```
Service State:
  NOT_CREATED → onCreate() → CREATED
  CREATED → onStartCommand() → RUNNING (Foreground)
  RUNNING → polling loop → RUNNING
  RUNNING → stopSelf() / stopService() → DESTROYED
  DESTROYED → NOT_CREATED
```

---

## 6. ملخص الحالات والإشعارات

| الحالة | نوع الإشعار | نص الإشعار |
|---|---|---|
| ACTIVE | Ongoing (Low Priority) | 🕌 جلسة التركيز نشطة - أذكار الصباح |
| SHIELDING | — | يظهر Overlay بدلاً من إشعار |
| COMPLETING (success) | One-shot | 🎉 أحسنت! أكملت وردك بنجاح |
| COMPLETING (manual) | — | لا إشعار |
| ERROR | One-shot | ⚠️ تعذّر جلسة التركيز - تحقق من الأذونات |

---

*Review Date: 2026-11-21 | Phase: Research Only*
