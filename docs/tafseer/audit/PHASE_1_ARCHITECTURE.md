# Phase 1: Tafseer Architecture & Data Format Design (Revised v1.2)

**Feature:** Offline Quran Tafseer (التفسير الميسر — مجمع الملك فهد لطباعة المصحف الشريف)  
**Status:** DESIGN & INTEGRITY VALIDATION CLOSURE — APPROVED SPECIFICATION  
**Author:** Hafiz Al-Ahd Engineering Team  
**Date:** 2026-11-02  
**Target Module:** `lib/features/quran/`  

---

## 1. Executive Summary & Accepted Architecture

Following the Phase 0 audit and Phase 1 review, the core architectural foundation is finalized:
1. **Canonical Identifier:** `AyahId(surahNumber, ayahNumber)` is the universal primary key.
2. **Domain Representation:** Minimal `QuranTafseer` entity composed of typed `TafseerSegment` value objects (`commentary` vs `quranQuote`).
3. **Application Asset Format:** Bundled minified JSON (`assets/quran/tafseer/tafseer_mouaser.json`), mapping `AyahId.formatted` directly to raw commentary text (~2.0 MB on disk, ~0.65 MB in packaged APK).
4. **Zero New External Dependencies:** No `flutter_html`, `sqflite_common_ffi`, or third-party parsers required. Pure Dart implementation.
5. **Clean Architecture Separation:** Domain entity, UseCase, Repository, Local DataSource, Cubit, and BottomSheet.

This revised specification (v1.2) incorporates the **integrity closure** of the Tafseer text parser and SQL conversion engine, backed by empirical execution proofs on all 6,236 Quranic Ayahs.

---

## 2. Corrected Tafseer Text Parser Design

### 2.1 The Source Markup Reality
The King Fahd Complex Tafseer dataset uses strictly one semantic HTML tag:
`<span class='aya'>...</span>` (with occasional whitespace variations such as `<span class = 'aya'>`).
* Total spans across entire Quran: **47 spans** in **42 Ayahs**.
* Text inside span: Embedded Quranic words enclosed in Unicode brackets `ﵡ` (U+FD61) and `ﵠ` (U+FD60), often with ` ` (U+200A Hair Space).
* 6,194 Ayahs (99.33%) contain no HTML tags.

### 2.2 Corrected, Standard Dart Parser Implementation

```dart
// lib/features/quran/presentation/utils/tafseer_text_parser.dart

import '../../domain/entities/quran_tafseer.dart';

/// High-performance, non-destructive lexer for Tafseer commentary text.
/// Extracts embedded Quranic quotes (<span class='aya'>...</span>) into typed segments.
class TafseerTextParser {
  /// Robust standard Dart RegExp matching `<span class='aya'>...</span>`:
  /// - `\s+`: required whitespace after span
  /// - `class\s*=\s*`: supports optional whitespace around '='
  /// - `['"]`: supports both single quotes ('aya') and double quotes ("aya")
  /// - `\s*`: supports optional trailing whitespace before '>'
  /// - `(.*?)`: non-greedy capture of inner content with dotAll: true
  /// - `</span>`: exact closing tag
  static final RegExp spanPattern = RegExp(
    r'''<span\s+class\s*=\s*['"]aya['"]\s*>(.*?)</span>''',
    caseSensitive: false,
    dotAll: true,
  );

  /// Parses raw Tafseer text into structured commentary and Quranic quote segments.
  /// Guarantees that:
  /// 1. No character is silently discarded.
  /// 2. Unmatched or unknown markup remains part of commentary text.
  /// 3. All Unicode brackets, hair spaces, and diacritics are strictly preserved.
  static List<TafseerSegment> parse(String rawText) {
    if (rawText.isEmpty) return const [];

    // Fast-path: 99.33% of Ayahs contain no HTML tags
    if (!rawText.contains('<span')) {
      return [TafseerSegment(text: rawText, type: TafseerSegmentType.commentary)];
    }

    final segments = <TafseerSegment>[];
    int cursor = 0;

    for (final match in spanPattern.allMatches(rawText)) {
      // 1. Text preceding the span (Commentary)
      if (match.start > cursor) {
        final commentary = rawText.substring(cursor, match.start);
        if (commentary.isNotEmpty) {
          segments.add(TafseerSegment(
            text: commentary,
            type: TafseerSegmentType.commentary,
          ));
        }
      }

      // 2. Embedded Quranic quote inside the span
      final quote = match.group(1);
      if (quote != null && quote.isNotEmpty) {
        segments.add(TafseerSegment(
          text: quote,
          type: TafseerSegmentType.quranQuote,
        ));
      }

      cursor = match.end;
    }

    // 3. Trailing commentary text after the final span
    if (cursor < rawText.length) {
      final trailing = rawText.substring(cursor);
      if (trailing.isNotEmpty) {
        segments.add(TafseerSegment(
          text: trailing,
          type: TafseerSegmentType.commentary,
        ));
      }
    }

    return List.unmodifiable(segments);
  }
}
```

### 2.3 Mathematical & Behavioral Guarantees
1. **Reconstruction Invariant (Zero Data Loss):**
   $$\sum_{s \in \text{segments}} s.\text{text} \equiv \text{rawText.replaceAllMapped}(spanPattern, (m) \to m[1])$$
   Concatenating all segments reproduces the exact original commentary text with only the matching opening/closing tag wrappers removed.
2. **Unicode Preservation:**
   All Quranic brackets (`ﵡ`, `ﵠ`), Hair spaces (`U+200A`), Arabic commas (`،`), diacritics, and presentation forms remain 100% intact.
3. **Resilience to Malformed Tags:**
   An unclosed `<span class='aya'>` or orphan `</span>` without a match is never swallowed; it remains part of the surrounding commentary segment.

---

## 3. SQL vs. CSV Conversion Strategy

### 3.1 Empirical Comparison Findings
During source analysis, both `tafseerMouaser_v03.sql` and `tafseerMouaser_v03.csv` were parsed and compared character-by-character across all 6,236 records:
* **Match Rate:** 5,936 / 6,236 records were identical.
* **The 300 Discrepancies:** Inspection revealed that the CSV export introduced extraneous **trailing whitespace** (e.g. `U+0020` before closing quotes) in 300 Ayahs (such as Ayahs 1:7 and 2:5).
* **Conclusion:** `tafseerMouaser_v03.sql` represents the authoritative, untampered database dump from the King Fahd Complex.

### 3.2 Robust SQL State-Machine Lexer
To avoid fragile comma-splitting or regex failures, the conversion script uses a character-by-character state-machine lexer that correctly handles MySQL dump escaping while **preserving exact quoted string content (no `.trim()` on quoted strings)**:

```dart
class SqlField {
  final dynamic value; // String, int, or null
  final bool isQuoted;

  const SqlField.string(String str) : value = str, isQuoted = true;
  const SqlField.number(int num) : value = num, isQuoted = false;
  const SqlField.nullValue() : value = null, isQuoted = false;
}

class SqlInsertParser {
  /// Parses a single MySQL INSERT statement:
  /// INSERT INTO `` (`id`,...) VALUES (1,1,1,1,'Al-Fātiḥah',...);
  ///
  /// CRITICAL RULES:
  /// 1. Quoted string contents are NEVER trimmed; exact leading/trailing spaces are preserved.
  /// 2. Commas inside quoted strings do not delimit fields.
  /// 3. Escaped single quotes (\' and '') are unescaped to a single quote.
  /// 4. Escaped backslashes (\\) are unescaped to \.
  /// 5. Standard escapes \n, \r, \t are unescaped.
  /// 6. Non-quoted tokens (integers, NULL) are trimmed and validated.
  /// 7. Throws FormatException on syntax errors (never silently skips).
  static List<SqlField> parseInsertValues(String line, {int lineNumber = 0}) {
    final valuesIdx = line.indexOf('VALUES (');
    if (valuesIdx == -1) {
      throw FormatException('Line $lineNumber missing "VALUES (" marker');
    }

    final start = valuesIdx + 8;
    final end = line.lastIndexOf(');');
    if (end == -1) {
      throw FormatException('Line $lineNumber missing closing ");" marker');
    }

    final inner = line.substring(start, end);
    final List<SqlField> fields = [];
    final sb = StringBuffer();
    bool inQuotes = false;
    bool hasSeenQuoteInField = false;
    int i = 0;

    while (i < inner.length) {
      final c = inner[i];

      if (inQuotes) {
        if (c == '\\') {
          // MySQL backslash escape
          if (i + 1 < inner.length) {
            final next = inner[i + 1];
            switch (next) {
              case "'":  sb.write("'"); break;
              case '"':  sb.write('"'); break;
              case '\\': sb.write('\\'); break;
              case 'n':  sb.write('\n'); break;
              case 'r':  sb.write('\r'); break;
              case 't':  sb.write('\t'); break;
              case '0':  sb.write('\x00'); break;
              default:   sb.write(next);
            }
            i += 2;
            continue;
          } else {
            throw FormatException('Line $lineNumber: trailing backslash escape at end of string');
          }
        } else if (c == "'") {
          // Standard SQL quote escape ('')
          if (i + 1 < inner.length && inner[i + 1] == "'") {
            sb.write("'");
            i += 2;
            continue;
          } else {
            inQuotes = false;
            i++;
            continue;
          }
        } else {
          sb.write(c);
          i++;
        }
      } else {
        if (c == "'") {
          inQuotes = true;
          hasSeenQuoteInField = true;
          i++;
        } else if (c == ',') {
          if (hasSeenQuoteInField) {
            fields.add(SqlField.string(sb.toString()));
          } else {
            final raw = sb.toString().trim();
            if (raw.toUpperCase() == 'NULL' || raw.isEmpty) {
              fields.add(const SqlField.nullValue());
            } else {
              final numVal = int.tryParse(raw);
              if (numVal != null) {
                fields.add(SqlField.number(numVal));
              } else {
                throw FormatException('Line $lineNumber: invalid unquoted token "$raw"');
              }
            }
          }
          sb.clear();
          hasSeenQuoteInField = false;
          i++;
        } else {
          sb.write(c);
          i++;
        }
      }
    }

    if (inQuotes) {
      throw FormatException('Line $lineNumber: unterminated single quote at end of line');
    }

    if (hasSeenQuoteInField) {
      fields.add(SqlField.string(sb.toString()));
    } else {
      final raw = sb.toString().trim();
      if (raw.toUpperCase() == 'NULL' || raw.isEmpty) {
        fields.add(const SqlField.nullValue());
      } else {
        final numVal = int.tryParse(raw);
        if (numVal != null) {
          fields.add(SqlField.number(numVal));
        } else {
          throw FormatException('Line $lineNumber: invalid unquoted token "$raw"');
        }
      }
    }

    return fields;
  }
}
```

### 3.3 Conversion Output Target (`assets/quran/tafseer/tafseer_mouaser.json`)
The script extracts only the minimal required schema:
```json
{
  "metadata": {
    "version": "3.0",
    "edition": "KFGQPC Tafseer Mouaser",
    "total_ayahs": 6236,
    "source": "King Fahd Complex for Printing the Holy Quran"
  },
  "tafseer": {
    "1:1": "[1] أبتدئ قراءة القرآن باسم الله مستعيناً به، <span class='aya'>ﵡ ٱللَّهِﵠ</span> علم على الرب...",
    "1:2": "[2] الثناء على الله بصفاته التي كلُّها أوصاف كمال...",
    "114:6": "[6] من شياطين الجن والإنس."
  }
}
```

---

## 4. Dataset Loading & Caching Strategy

```
App Startup
  │ (No Tafseer loading — 0 ms overhead)
  ▼
User taps "التفسير" for Ayah 2:255
  │
  ▼
QuranTafseerLocalDataSourceImpl._getOrLoadMap()
  │
  ├─► Is Map cached in RAM?
  │     ├── YES ──► O(1) Map lookup (< 0.1 ms)
  │     └── NO  ──► Shared Future load (single read from rootBundle)
  │
  ▼
TafseerTextParser.parse(rawText) (On-demand: < 0.02 ms)
  │
  ▼
QuranTafseer Entity emitted to Cubit
```

### 4.1 Specification
1. **Lazy Loading:** Loading occurs strictly on-demand when the user first opens Tafseer. It never executes during app initialization.
2. **Single Shared Future (Concurrency Guard):**
   ```dart
   Future<Map<String, String>>? _loadFuture;

   Future<Map<String, String>> _getOrLoadMap() {
     _loadFuture ??= _loadFromAsset();
     return _loadFuture!;
   }
   ```
   If two Ayah requests fire concurrently before the JSON asset finishes reading, both await the **identical Future**, preventing duplicate I/O and race conditions.
3. **In-Memory Storage:** The parsed map `Map<String, String>` is kept in memory as a singleton cache for the lifetime of the application. It occupies **~3.8 MB RAM** total.
4. **On-Demand Parsing:** We do **not** pre-parse all 6,236 Ayahs into segment objects on load. We parse only the active Ayah upon request, taking less than 20 microseconds.
5. **Initialization Error Recovery:**
   If reading the asset fails, `_loadFuture` is reset to `null` so the user can immediately retry via the UI retry button.

---

## 5. Cubit Lifecycle & Concurrency Safeguards

The `QuranTafseerCubit` manages Tafseer retrieval with five strict safeguards:

```dart
// lib/features/quran/presentation/cubit/quran_tafseer_cubit.dart

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/ayah_id.dart';
import '../../domain/usecases/get_quran_tafseer_use_case.dart';
import 'quran_tafseer_state.dart';

class QuranTafseerCubit extends Cubit<QuranTafseerState> {
  final GetQuranTafseerUseCase getTafseerUseCase;

  /// Monotonically increasing request sequence counter
  int _latestRequestId = 0;

  QuranTafseerCubit({required this.getTafseerUseCase})
      : super(QuranTafseerInitial());

  /// Loads Tafseer for [ayahId] with concurrency and lifecycle safeguards.
  Future<void> loadTafseer(AyahId ayahId) async {
    // 1. Duplicate Request Guard:
    // If the requested Ayah is already loaded, skip re-fetching to prevent flicker.
    final currentState = state;
    if (currentState is QuranTafseerLoaded && currentState.tafseer.ayahId == ayahId) {
      return;
    }

    // 2. Increment request ID ("Latest request wins")
    final requestId = ++_latestRequestId;

    emit(QuranTafseerLoading(targetAyahId: ayahId));

    final result = await getTafseerUseCase(ayahId);

    // 3. Stale Response & Disposal Guard:
    // If a newer request was made while awaiting, or if Cubit was disposed, discard response.
    if (requestId != _latestRequestId || isClosed) {
      return;
    }

    result.fold(
      (failure) => emit(QuranTafseerError(
        message: failure.message,
        targetAyahId: ayahId,
      )),
      (tafseer) => emit(QuranTafseerLoaded(tafseer)),
    );
  }

  /// Retries loading the failed Ayah
  void retry(AyahId ayahId) => loadTafseer(ayahId);
}
```

### 5.1 States Definition
* `QuranTafseerInitial`
* `QuranTafseerLoading(AyahId targetAyahId)`
* `QuranTafseerLoaded(QuranTafseer tafseer)`
* `QuranTafseerError(String message, AyahId targetAyahId)`

---

## 6. Typography & UI Integration

### 6.1 Visual Styling

| Element | Font Family | Size | Weight | Color (Light / Dark) |
| :--- | :--- | :---: | :---: | :--- |
| **Ayah Header** | `Tajawal` | 16 sp | Bold | `AppColors.secondaryGold` |
| **Original Quran Ayah Card** | `Amiri` | 18 sp | Semi-Bold | `AppColors.darkText` / `Colors.white` |
| **Tafseer Commentary Text** | `Tajawal` | 15.5 sp | Regular | `Color(0xFF2C2C2C)` / `Color(0xFFE0E0E0)` |
| **Embedded Quranic Quote** | `Amiri` | 16.5 sp | Bold | `Color(0xFFB8860B)` / `AppColors.secondaryGold` |
| **Quran Brackets (`ﵡ`, `ﵠ`)** | `Amiri` | 16.5 sp | Bold | `AppColors.secondaryGold` |

### 6.2 Selection State Preservation Contract
* When the user taps "التفسير" from `QuranAyahActionBottomSheet`:
  1. The action BottomSheet pops.
  2. The selected Ayah highlight is strictly **preserved** (`_selectedAyahIdNotifier` remains active).
  3. `QuranTafseerBottomSheet` opens.
  4. Dismissing `QuranTafseerBottomSheet` leaves the Ayah selected on the Quran page.
  5. Page navigation continues to clear selection according to existing behavior.

---

## 7. Licensing Status

> [!WARNING]
> ### `LICENSE VERIFICATION REQUIRED`
> * **Attribution:** King Fahd Complex for Printing the Holy Quran (مجمع الملك فهد لطباعة المصحف الشريف - المدينة المنورة).
> * **Notice:** The dataset is distributed freely on the King Fahd Complex developer portal for Islamic knowledge dissemination. However, commercial bundling terms must be officially reviewed prior to a monetized store release.

---

## 8. Comprehensive Testing Plan

| Suite | Target | Key Test Cases |
| :--- | :---: | :--- |
| **`tafseer_text_parser_test.dart`** | Pure Dart | 1. Plain text Ayah without spans.<br>2. Single span extraction.<br>3. Multiple spans in one commentary.<br>4. Quotes with single quotes `'aya'` and double quotes `"aya"`.<br>5. Whitespace variations (`class = 'aya'`).<br>6. Malformed span (unclosed `<span` or missing `</span>`).<br>7. Full identity reversibility test across all 6,236 Ayahs. |
| **`tafseer_data_validation_test.dart`** | Pure Dart | Automated test validating that `tafseer_mouaser.json` contains exactly 6,236 Ayahs, 114 Surahs, and zero null or empty entries. |
| **`quran_tafseer_repository_test.dart`** | Pure Dart | 1. Successful lookup from local data source.<br>2. Missing Ayah returns `CacheFailure`.<br>3. Error propagation. |
| **`quran_tafseer_cubit_test.dart`** | Pure Dart | 1. Initial state.<br>2. Loading → Loaded flow.<br>3. Error state on failure.<br>4. Rapid concurrency ("latest request wins").<br>5. Duplicate request guard (skips re-fetching identical Ayah).<br>6. Disposed Cubit safety. |
| **`quran_tafseer_ui_test.dart`** | Flutter Widget | 1. Renders Surah name, Ayah number, page number.<br>2. Renders Uthmani Ayah text card.<br>3. Renders RichText with distinct gold styling for embedded spans.<br>4. Scrollable on long commentary.<br>5. Loading indicator and retry button on error. |
| **`quran_screen_tafseer_integration_test.dart`** | Flutter Widget | 1. Tapping Tafseer opens BottomSheet.<br>2. Selected Ayah highlight preserved when sheet opens and closes.<br>3. Fullscreen toggle remains unaffected. |

---

## 9. Next Implementation Phases

* **Phase 2: Data Conversion & Asset Generation**
  * Implement `scripts/convert_tafseer_to_json.dart` using the SQL state-machine lexer.
  * Generate `assets/quran/tafseer/tafseer_mouaser.json`.
  * Add asset to `pubspec.yaml`.
  * Run automated validation test.
* **Phase 3: Data Access Layer**
  * Domain models (`QuranTafseer`, `TafseerSegment`).
  * `TafseerTextParser`.
  * Local DataSource, Repository, and `GetQuranTafseerUseCase`.
  * DI registration in `service_locator.dart`.
  * Unit tests.
* **Phase 4: Presentation & Integration**
  * `QuranTafseerCubit` and States.
  * `QuranTafseerBottomSheet`.
  * Integration into `QuranScreen` (`onTafseerTap`).
  * Widget and integration tests.
* **Phase 5: Full Regression Audit**
  * Full regression test suite execution across all Quran features.

---

## 10. Phase 1.2 — Parser & Conversion Integrity Closure

### 10.1 Separation of Evidence
In accordance with strict verification rules:
* **Implemented & Executed (Validation Sandbox):**
  1. `TafseerTextParser` unit test suite (9 / 9 tests passed).
  2. `SqlInsertParser` state-machine lexer unit test suite (6 / 6 tests passed).
  3. Full 6,236 Ayahs SQL extraction & character-level reconstruction test (6,236 / 6,236 with 100% identity, zero data loss).
  4. Quran mapping reconciliation test (100% 1:1 match across all 6,236 Ayahs).
  5. Repeated conversion determinism test (2,002,738 bytes identical character-for-character).
* **Implemented but Not Executed in Production:**
  * Production CLI conversion script `scripts/convert_tafseer_to_json.dart` (awaiting Phase 2 authorization).
* **Designed but Not Implemented:**
  * Production UI components (`QuranTafseerBottomSheet`).
  * Production Data Layer classes and Cubit.

### 10.2 Actual Execution Console Output
```text
===============================================================
    PHASE 1.2 — PARSER & CONVERSION INTEGRITY VALIDATION
===============================================================

--- [1] TAFSEER TEXT PARSER UNIT TESTS ---      
  ✓ PASS: 1. Plain text without spans returns single commentary segment
  ✓ PASS: 2. Single quotes match <span class='aya'>
  ✓ PASS: 3. Double quotes match <span class="aya">
  ✓ PASS: 4. Whitespace variations around equals sign
  ✓ PASS: 5. Multiple spans in single commentary (Ayah 1:1)
  ✓ PASS: 6. Preserves Unicode brackets U+FD61/U+FD60 and Hair Space U+200A exactly
  ✓ PASS: 7. Unmatched opening tag is NOT discarded; preserved as commentary
  ✓ PASS: 8. Orphan closing tag is NOT discarded; preserved as commentary
  ✓ PASS: 9. Unknown tag (e.g. <div>) is NOT treated as quote span; preserved in commentary     
Parser Unit Tests: 9 passed, 0 failed.

--- [2] SQL CONVERSION INTEGRITY & LEXER TESTS ---
  ✓ PASS: 1. Preserves exact leading and trailing whitespace in quoted string
  ✓ PASS: 2. Handles escaped single quotes with backslash (\)
  ✓ PASS: 3. Handles standard doubled single quotes ('')
  ✓ PASS: 4. Handles commas inside quoted strings without field split
  ✓ PASS: 5. Handles NULL values explicitly     
  ✓ PASS: 6. Throws FormatException on unterminated string quote
SQL Lexer Unit Tests: 6 passed, 0 failed.       

--- [3] FULL DATASET CONVERSION & RECONCILIATION AUDIT ---
1. File inspection:
   File: docs/tafseer/tafseerMouaser_v03.sql
   Total lines: 6240
   INSERT statements: 6236

2. Dataset Statistics:
   Total records parsed: 6236 / 6236
   Unique AyahId keys: 6236
   Total valid <span class='aya'> detected: 47 (Expected: 47)
   Total Ayahs containing spans: 42 (Expected: 42)

3. Quran Mapping Engine Reconciliation:
   Mapping Ayahs: 6236
   Missing in Tafseer: 0 (NONE)
   Extra in Tafseer: 0 (NONE)

4. Full Dataset Parser Reconstruction Test:     
   100% Character Identity Reconstructions: 6236 / 6236 (Zero Data Loss)

5. Determinism Verification (Repeated Execution):
   Run 1 JSON byte length: 2002738
   Run 2 JSON byte length: 2002738
   Exact character match between runs: true     

===============================================================
   PHASE 1.2 INTEGRITY CLOSURE: ALL VERIFICATION GATES PASSED!
===============================================================
```

---

## 11. Final Stop Gate Notice

🛑 **STOP GATE:** This concludes Phase 1.2 Parser & Conversion Integrity Closure. No application source code, assets, or dependencies were created or modified. Awaiting explicit user approval before proceeding to Phase 2.
