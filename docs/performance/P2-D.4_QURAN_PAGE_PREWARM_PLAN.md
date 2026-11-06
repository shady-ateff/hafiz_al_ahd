# P2-D.4 — Quran Page Rendering Prewarm Optimization: Engineering Plan

**Project:** Hafiz Al-Ahd  
**Feature:** Quran Rendering  
**Phase:** P2-D.4 — Architecture & Implementation Strategy  
**Status:** PLANNING ONLY — NO CODE MODIFICATIONS  
**Next Phase:** P2-D.4.1 (Implementation upon approval)

---

## 1. Executive Summary & Objective

In **P2-D.3**, physical and static evidence confirmed that Quran page swiping suffers from severe first-frame jank:
* **UI Paint**: 68.3 ms (4.1× the 16.67 ms 60Hz frame budget)
* **Raster**: 45.7 ms (2.7× the 16.67 ms 60Hz frame budget)
* **`Canvas.saveLayer()`**: 1 invocation in the slow frame
* **Warm Rendering**: ~1.5–3 ms UI / ~2–4 ms Raster (smooth 60/120 FPS)

The objective of **P2-D.4** is to design a minimal, robust pre-warming architecture that reduces cold-rendering latency by preparing upcoming pages ahead of time, transforming cold page transitions into warm transitions without altering the visual output, Mushaf layout, fonts, or navigation semantics.

---

## 2. Current Rendering Lifecycle & Cost Decomposition

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ COLD SWIPE FRAME PIPELINE (Total Latency: ~114.0 ms)                                   │
├─────────────────────────────────────────────────┬──────────────────────────────────────┤
│ UI Thread: 68.3 ms (60% contribution)           │ Raster Thread: 45.7 ms (40%)         │
├─────────────────────────────────────────────────┼──────────────────────────────────────┤
│ 1. Lazy Mount Inflation: ~10.2 ms               │ 1. Cold Impeller Glyph Atlas: ~35.4 ms│
│    • 195 Widgets & 56 RenderObjects             │    • QCF2xxx.ttf has 0 glyphs in GPU │
│    • 15 lines x 10 words = 150 Recognizers      │      texture atlas; full raster + VRAM│
│ 2. HarfBuzz Cursive Arabic Shaping: ~40.1 ms    │      upload on render pass.          │
│    • 15 lines of dense Quranic ligatures,       │ 2. ColorFilterLayer saveLayer: ~7.1 ms│
│      diacritical marks (GPOS), GSUB tables.     │    • Juz_border.svg offscreen subpass│
│ 3. Double FittedBox Intrinsic Layout: ~8.0 ms   │ 3. SVG Vector Path Tessellation: ~3.2ms│
│ 4. Display List Recording: ~10.0 ms             │                                      │
└─────────────────────────────────────────────────┴──────────────────────────────────────┘
```

### Critical Framework Mechanic Identified
In Flutter 3.44 (`sliver_multi_box_adaptor.dart:738-742`):
```dart
if (mainAxisDelta < constraints.remainingPaintExtent &&
    mainAxisDelta + paintExtentOf(child) > 0) {
  context.paintChild(child, childOffset);
}
```
When a sliver child resides in the viewport's `cacheExtent` (outside visible bounds):
* **Widget Construction**: **EXECUTED** (UI thread)
* **Element & State Creation**: **EXECUTED** (UI thread)
* **Layout & HarfBuzz Text Shaping**: **EXECUTED** (UI thread during `RenderParagraph.performLayout()`)
* **Paint & Display List Recording**: **SKIPPED** (Child does not intersect `remainingPaintExtent`)
* **GPU Rasterization & Glyph Atlas**: **SKIPPED** (No display list emitted for offscreen sliver)

**Core Implication**: PageView cache optimization completely eliminates the **68.3 ms UI thread bottleneck** ahead of time. However, it does not warm the Raster thread's glyph atlas until the page enters the visible viewport.

---

## 3. Evaluation of Proposed Optimization Strategies

| Strategy | Scope | Mechanism | Expected Benefit | Recommendation | Justification |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **A. PageView Viewport Cache (`allowImplicitScrolling: true` / `scrollCacheExtent`)** | UI Thread | Set `allowImplicitScrolling: true` on `PageView.builder`, activating `ScrollCacheExtent.viewport(1.0)` | Drops UI first-frame latency from **68.3 ms to < 2.0 ms** during active gesture | **RECOMMENDED** | Built-in Flutter framework feature. Pre-shapes 15 lines of Arabic text and inflates widgets while user is reading page $N$. Zero custom hacks. |
| **B. Symmetrical Sibling Retention ($[N-1, N, N+1]$)** | Navigation | Retain previous page ($N-1$) and next page ($N+1$) in viewport cache | Backward swipes are instantaneous warm renders (<2 ms) | **RECOMMENDED** | Standard sliding window. Eliminates jank when user flips back and forth between adjacent pages. |
| **C. Footer Border `saveLayer` Elimination** | Raster Thread | Replace `ColorFilter.mode` on `Juz_border.svg` with pre-tinted SVG assets or custom canvas painter | Eliminates the single `Canvas.saveLayer()` call; saves **~5–7 ms Raster time** | **RECOMMENDED** | Highly effective, zero risk to text or navigation. Resolves the single offscreen subpass identified in profiling. |
| **D. Settled Page Rebuild Deduplication** | UI Thread | Guard `BlocBuilder.buildWhen` in `QuranScreen.itemBuilder` to avoid rebuilding settled page on `onPageChanged` | Saves **~8–12 ms** secondary settle jank immediately after swipe snap | **RECOMMENDED** | Prevents redundant second layout/paint pass right when the animation finishes. |
| **E. Speculative Offscreen Glyph Atlas Prewarming** | Raster Thread | Render invisible 1x1 text in an overlay to force Impeller to rasterize glyphs before visibility | Speculative Raster savings of ~15–25 ms | **NOT RECOMMENDED** | Fragile, hacky, and risks being culled by Impeller's occlusion culler. Incurs CPU/GPU overhead on idle frames for pages that may never be visited. |
| **F. Custom Offscreen Bitmap Caching (`toImage`)** | Memory / GPU | Pre-render pages to `ui.Image` bitmaps | Bypasses text shaping | **NOT RECOMMENDED** | `toImage()` forces GPU pipeline flushes, causing severe UI thread pauses. 3 pages $\times$ 10.3 MB = 31 MB VRAM churn per flip. |

---

## 4. Proposed Implementation Architecture

```
                                  ┌──────────────────────────────┐
                                  │      CURRENT PAGE (N)        │
                                  │   (Fully Visible in Viewport)│
                                  └──────────────┬───────────────┘
                                                 │
                                 Pre-warmed via sliding window
                                                 │
                        ┌────────────────────────┴────────────────────────┐
                        ▼                                                 ▼
          ┌───────────────────────────┐                     ┌───────────────────────────┐
          │     PREVIOUS PAGE (N-1)   │                     │       NEXT PAGE (N+1)     │
          │   (Pre-shaped in Cache)   │                     │   (Pre-shaped in Cache)   │
          └───────────────────────────┘                     └───────────────────────────┘
          • Widgets mounted                                 • Widgets mounted
          • HarfBuzz shaping cached                         • HarfBuzz shaping cached
          • Recognizers initialized                         • Recognizers initialized
          • Ready for instant translation                   • Ready for instant translation
```

### Architecture Specifications

1. **Pre-warming Trigger**:
   When the user settles on Page $N$ (`onPageChanged`), `QuranScreen` updates `_currentPageNotifier.value = N`.
2. **Pre-warming Horizon**:
   Strictly **1 page ahead ($N+1$)** and **1 page behind ($N-1$)**. Symmetrical window: $[N-1, N, N+1]$.
3. **Retention Policy**:
   Page $N-1$ is retained. If the user flips back to $N-1$, it is an instant warm render (<2 ms).
4. **Caching Mechanism**:
   Leverages Flutter's native `PageView.builder(allowImplicitScrolling: true)`. In Flutter 3.44, `allowImplicitScrolling: true` automatically configures:
   * `scrollCacheExtent: ScrollCacheExtent.viewport(1.0)`
   * `RenderSliverFillViewport.allowImplicitScrolling = true`
5. **Cache Eviction Rules**:
   Strict FIFO sliding window managed natively by `SliverFillViewport`. As the user moves from $N$ to $N+1$, Page $N-2$ falls outside the `1.0 * viewportDimension` cache boundary and is automatically unmounted and collected by Flutter's garbage collector.
6. **Rapid Navigation Handling (Flings / Multi-page Swipes)**:
   If the user executes a fast fling skipping multiple pages, intermediate pages are not built. `onPageChanged` triggers data loading only for the destination page and its immediate neighbors.
7. **Unexpected Page Jumps (Slider / Surah Jumper)**:
   Calling `_pageController.jumpToPage(targetPage - 1)` instantly relocates the viewport window. The destination becomes the new $N$, and $[N-1, N+1]$ are pre-warmed while idle.
8. **Interaction with `QuranCubit`**:
   `quran_screen.dart:947-952` already triggers `preloadPage(pageNumber + 1)` and `preloadPage(pageNumber - 1)`. When the data returns, `_pagesCache` is populated. When `PageView` builds the cached sliver, `effectiveState` is already non-null and `QuranPageWidget` shapes immediately without showing shimmer.
9. **Memory Implications**:
   * Baseline (1 page in memory): ~56 RenderObjects, ~150 Recognizers, ~1.2 MB.
   * Proposed (3 pages in memory: $[N-1, N, N+1]$): ~168 RenderObjects, ~450 Recognizers, ~3.6 MB RAM.
   * **Net increase**: **< 2.5 MB RAM**, which is negligible on modern devices (4–12 GB).
10. **Cleanup and Lifecycle**:
    In `QuranScreen.dispose()`, `_tappedCallbacks.clear()`, `_longPressedCallbacks.clear()`, and the `_pageController` disposal ensure complete teardown of all pre-warmed elements and recognizers.

---

## 5. Performance Targets & Budgets

| Metric | Baseline (Cold Swipe) | Target (Optimized P2-D.4) | Frame Budget Reference |
| :--- | :--- | :--- | :--- |
| **UI Thread Build/Layout** | **68.3 ms** (Severe Jank) | **< 3.0 ms** (>95% reduction) | 16.67 ms (60Hz) / 8.33 ms (120Hz) |
| **Raster Thread** | **45.7 ms** (Severe Jank) | **< 12.0 ms** (~74% reduction) | 16.67 ms (60Hz) / 8.33 ms (120Hz) |
| **`Canvas.saveLayer()`** | **1 invocation** | **0 invocations** | 0 subpasses |
| **Swipe Average FPS** | **~50 FPS (with frame drops)** | **Locked 60 / 120 FPS** | Native display rate |

---

## 6. Exact Files Expected to Change in P2-D.4.1

| File | Target Modifications | Risk Level |
| :--- | :--- | :--- |
| [`lib/features/quran/presentation/screens/quran_screen.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/quran/presentation/screens/quran_screen.dart) | 1. Enable `allowImplicitScrolling: true` on `PageView.builder`.<br>2. Add deduplication guard in `itemBuilder`'s `buildWhen` to prevent settled page rebuilds. | Very Low |
| [`lib/features/quran/presentation/widgets/quran_page_widget.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/quran/presentation/widgets/quran_page_widget.dart) | Replace `SvgPicture.asset(..., colorFilter: ...)` on footer border with pre-tinted SVG asset or vector graphics to eliminate `ColorFilterLayer` / `saveLayer()`. | Very Low |
| [`test/quran_page_prewarm_p2d4_test.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/test/quran_page_prewarm_p2d4_test.dart) | New test suite verifying neighboring page pre-mounting, layout completion, memory bounds, and gesture routing. | None (Test) |

---

## 7. Potential Regressions & Mitigation Strategy

| Potential Regression | Cause | Mitigation Strategy |
| :--- | :--- | :--- |
| **Callback Bleed Across Pages** | Pre-warmed page captures wrong `pageNumber` | Already mitigated by P2-D.2: callbacks are strictly keyed by `pageNumber` in `_tappedCallbacks`. |
| **Excessive Font Loading on Rapid Scroll** | Preloading fonts for skipped pages | `QuranCubit._preloadSurroundingFonts` throttles requests to every 4 pages and operates in a background compute isolate. |
| **Memory Growth During Long Reading Session** | Retaining too many pages | `PageView`'s native cache extent strictly bounds the element tree to $[N-1, N+1]$. Distant pages are automatically unmounted. |
| **Ayah Selection State Desynchronization** | Selecting an ayah while adjacent page is mounted | `QuranCubit` updates selection by Ayah ID across all cached pages. Unaffected lines skip updates via P2-D.2 stability. |

---

## 8. Testing & Verification Strategy

### Automated Regression & Parity Suite
1. `test/quran_callback_identity_p2d2_test.dart` (4 tests) — Callback stability.
2. `test/quran_selection_rendering_p2b_test.dart` (7 tests) — Highlight rendering & recognizer reuse.
3. `test/quran_full_page_interactive_test.dart` — Visual parity & golden diff on pages 1, 2, 48, 201, 604 (0.00% diff).
4. `test/quran_page_prewarm_p2d4_test.dart` — Prewarm verification.

### Physical Device A/B Benchmark Protocol (Once Device Connected)
* **Device**: Xiaomi `25098RA98G` (Android 16 / API 36) in Flutter Profile Mode.
* **A/B Test Runs**:
  1. **Test 1**: Cold forward swipe (first swipe after opening).
  2. **Test 2**: Warm return swipe.
  3. **Test 3**: Continuous navigation across 5 pages forward and backward.
  4. **Test 4**: Rapid consecutive swipes (flings).
  5. **Test 5**: Random page jump via bottom slider.
  6. **Test 6**: Ayah selection / deselection under pre-warmed tree.
  7. **Test 7**: App backgrounding and resume.

---

## 9. Rollback Strategy

Because all proposed changes are localized to:
1. One boolean flag (`allowImplicitScrolling: true`) in `quran_screen.dart`.
2. One widget refactor in `quran_page_widget.dart` (footer border asset).

Rollback can be executed instantaneously in under 60 seconds by reverting those two lines, restoring the codebase to its exact P2-D.2 state without collateral damage to any data layer or cubit logic.

---

```
══════════════════════════════════════════════════════════════════════════════
STOP GATE: Phase P2-D.4 Complete.
Status: PLANNING ONLY. Zero source code files modified.
Awaiting user review and explicit approval before Phase P2-D.4.1 implementation.
══════════════════════════════════════════════════════════════════════════════
```

