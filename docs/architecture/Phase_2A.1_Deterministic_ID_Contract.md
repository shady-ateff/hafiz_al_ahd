# P4.1-B.3 Phase 2A.1 — Deterministic ID Contract
**Project:** Hafiz Al-Ahd (حافظ العهد)  
**Branch:** `feature/p4.1-independent-alarms-adhan`  
**Phase:** P4.1-B.3 — Phase 2A.1  
**Document ID:** Deliverable E (`Phase_2A.1_Deterministic_ID_Contract.md`)  
**Status:** Frozen Contract — Architectural Specification  

---

## 1. Frozen Deterministic ID Formula (E1)

The calendar-deterministic ID formula is frozen without modification:

$$\mathbf{ID} = (\text{year} \pmod{100}) \times 1,000,000 + (\text{month} \times 10,000) + (\text{day} \times 100) + (\text{prayerIndex} \times 10) + \text{typeOffset}$$

### Positional Bit/Digit Decomposition:
- **Digits 7–6 (`[24..99]`):** Year modulo 100 ($2024 \to 24, \; 2099 \to 99$).
- **Digits 5–4 (`[01..12]`):** Calendar month.
- **Digits 3–2 (`[01..31]`):** Calendar day of month.
- **Digit 1 (`[0..4]`):** Prayer index (`0`=Fajr, `1`=Dhuhr, `2`=Asr, `3`=Maghrib, `4`=Isha).
- **Digit 0 (`[0..9]`):** Event type offset.

Because the maximum month contribution ($12 \times 10,000 = 120,000$) plus maximum day, prayer, and offset ($3,100 + 40 + 9 = 3,149$) totals $123,149$, it **never exceeds or overflows into the $1,000,000$ multiplier**. Digits remain strictly orthogonal.

---

## 2. Supported Year Range & Boundary Safeguards (E2)

### 2.1. Supported Operational Range:
- **Minimum Supported Year:** `2024`
- **Maximum Supported Year:** `2099`

### 2.2. Boundary ID Values:
- **Absolute Minimum ID (2024-01-01, Fajr, Adhan Alarm):**
  $$24 \times 1,000,000 + 10,000 + 100 + 0 + 0 = \mathbf{24,010,100}$$
- **Absolute Maximum ID (2099-12-31, Isha, Reserved Offset 9):**
  $$99 \times 1,000,000 + 120,000 + 3,100 + 40 + 9 = \mathbf{99,123,149}$$

### 2.3. Platform Safety:
- Maximum ID ($99,123,149$) is strictly less than the Android 32-bit signed integer limit ($2,147,483,647$).
- Capacity utilization: $\frac{99,123,149}{2,147,483,647} \approx 4.615\%$.
- Negative IDs and 32-bit overflow are mathematically impossible within the supported range.

### 2.4. Input Validation Contract:
Any invocation with:
- `year < 2024 || year > 2099`
- `month < 1 || month > 12`
- `day < 1 || day > 31`
- `prayerIndex < 0 || prayerIndex > 4`
- `typeOffset < 0 || typeOffset > 9`

**Must immediately throw an `ArgumentError`** to prevent corrupt or ambiguous IDs.

---

## 3. Comprehensive Event Identity Map (E3)

| Event Name | Prayer Name | Prayer Index | Type Offset | Backend | Example ID (2026-11-08) | Notes |
|---|---|:---:|:---:|---|:---:|---|
| **Fajr Adhan Alarm** | الفجر | 0 | 0 | `package:alarm` | `26110800` | Fullscreen / audio |
| **Fajr Adhan Notification** | الفجر | 0 | 1 | FLN | `26110801` | Silent / chime alert |
| **Fajr Iqama** | الفجر | 0 | 2 | FLN | `26110802` | Iqama delay |
| **Fajr Post-Prayer Azkar** | الفجر | 0 | 3 | FLN | `26110803` | After prayer azkar |
| **Morning Azkar** | الفجر (Exclusive) | **0** | **4** | FLN | `26110804` | **Explicitly bound to Fajr** |
| **Dhuhr Adhan Alarm** | الظهر | 1 | 0 | `package:alarm` | `26110810` | Fullscreen / audio |
| **Dhuhr Adhan Notification** | الظهر | 1 | 1 | FLN | `26110811` | Silent alert |
| **Dhuhr Iqama** | الظهر | 1 | 2 | FLN | `26110812` | Iqama delay |
| **Dhuhr Post-Prayer Azkar** | الظهر | 1 | 3 | FLN | `26110813` | After prayer azkar |
| **Asr Adhan Alarm** | العصر | 2 | 0 | `package:alarm` | `26110820` | Fullscreen / audio |
| **Asr Adhan Notification** | العصر | 2 | 1 | FLN | `26110821` | Silent alert |
| **Asr Iqama** | العصر | 2 | 2 | FLN | `26110822` | Iqama delay |
| **Asr Post-Prayer Azkar** | العصر | 2 | 3 | FLN | `26110823` | After prayer azkar |
| **Evening Azkar** | العصر (Exclusive) | **2** | **5** | FLN | `26110825` | **Explicitly bound to Asr** |
| **Maghrib Adhan Alarm** | المغرب | 3 | 0 | `package:alarm` | `26110830` | Fullscreen / audio |
| **Maghrib Adhan Notification** | المغرب | 3 | 1 | FLN | `26110831` | Silent alert |
| **Maghrib Iqama** | المغرب | 3 | 2 | FLN | `26110832` | Iqama delay |
| **Maghrib Post-Prayer Azkar** | المغرب | 3 | 3 | FLN | `26110833` | After prayer azkar |
| **Isha Adhan Alarm** | العشاء | 4 | 0 | `package:alarm` | `26110840` | Fullscreen / audio |
| **Isha Adhan Notification** | العشاء | 4 | 1 | FLN | `26110841` | Silent alert |
| **Isha Iqama** | العشاء | 4 | 2 | FLN | `26110842` | Iqama delay |
| **Isha Post-Prayer Azkar** | العشاء | 4 | 3 | FLN | `26110843` | After prayer azkar |
| **Reserved Future Slots** | Any (0..4) | 0..4 | 6..9 | Reserved | `...06` .. `...49` | Reserved for P4.2 / P4.3 |

---

## 4. Collision-Proof Requirements for Phase 2B (E4)

The test suite must enforce the following non-collision properties:

1. **Type Disjointness:** For any given date and prayer, no two event types share the same ID ($\text{offset}_a \ne \text{offset}_b \implies \text{ID}_a \ne \text{ID}_b$).
2. **Prayer Disjointness:** For any given date and type, no two prayers share the same ID ($\text{prayer}_a \ne \text{prayer}_b \implies \text{ID}_a \ne \text{ID}_b$).
3. **Date Disjointness:** For all valid dates $(D_1, D_2)$ where $D_1 \ne D_2$, their generated sets of IDs are completely disjoint.
4. **Explicit Azkar Independence:**
   - Morning Azkar ID ($P=0, \text{offset}=4$) never collides with Fajr Adhan, Iqama, or Post-Prayer Azkar.
   - Evening Azkar ID ($P=2, \text{offset}=5$) never collides with Asr Adhan, Iqama, or Post-Prayer Azkar.
5. **Signed 32-Bit Range Guard:** All generated IDs across the entire span $2024..2099$ must be $> 0$ and $\le 2,147,483,647$.
6. **Input Validation Enforcement:** Any out-of-bounds input throws `ArgumentError`.
7. **Reserved ID Isolation:** Every generated deterministic ID is $> 24,000,000$, establishing zero overlap with:
   - `888` (Test Alarm)
   - `999` (Home Widget Update)
   - `8888` (Foreground Service Notification)
   - Legacy sequential range `1..100`.

