import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'trace_analyzer.dart';

class VmClient {
  final WebSocket ws;
  int _nextId = 1;
  final Map<int, Completer<dynamic>> _pending = {};

  VmClient(this.ws) {
    ws.listen((data) {
      final msg = jsonDecode(data as String) as Map<String, dynamic>;
      final id = msg['id'] as int?;
      if (id != null && _pending.containsKey(id)) {
        if (msg.containsKey('error')) {
          _pending.remove(id)!.completeError(msg['error']);
        } else {
          _pending.remove(id)!.complete(msg['result']);
        }
      }
    });
  }

  Future<dynamic> call(String method, [Map<String, dynamic>? params]) {
    final id = _nextId++;
    final completer = Completer<dynamic>();
    _pending[id] = completer;
    ws.add(jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    }));
    return completer.future;
  }
}

class ValidationHarness {
  final VmClient client;
  final String deviceId;

  ValidationHarness(this.client, this.deviceId);

  void swipeForward() {
    Process.runSync('adb', ['-s', deviceId, 'shell', 'input', 'swipe', '200', '1200', '900', '1200', '300']);
  }

  void swipeBackward() {
    Process.runSync('adb', ['-s', deviceId, 'shell', 'input', 'swipe', '900', '1200', '200', '1200', '300']);
  }

  void tap(int x, int y) {
    Process.runSync('adb', ['-s', deviceId, 'shell', 'input', 'tap', x.toString(), y.toString()]);
  }

  void longPress(int x, int y) {
    Process.runSync('adb', ['-s', deviceId, 'shell', 'input', 'swipe', x.toString(), y.toString(), x.toString(), y.toString(), '600']);
  }

  void keyBack() {
    Process.runSync('adb', ['-s', deviceId, 'shell', 'input', 'keyevent', '4']);
  }

  void jumpToPage(int page) {
    print('Navigating to page $page...');
    // 1. Open overlay
    Process.runSync('adb', ['-s', deviceId, 'shell', 'input', 'tap', '540', '1200']);
    sleep(const Duration(milliseconds: 700));
    // 2. Open jump dialog
    Process.runSync('adb', ['-s', deviceId, 'shell', 'input', 'tap', '820', '2220']);
    sleep(const Duration(milliseconds: 700));
    // 3. Enter page number
    Process.runSync('adb', ['-s', deviceId, 'shell', 'input', 'text', page.toString()]);
    sleep(const Duration(milliseconds: 300));
    // 4. Submit
    Process.runSync('adb', ['-s', deviceId, 'shell', 'input', 'keyevent', '66']);
    sleep(const Duration(milliseconds: 1500));
    // 5. Dismiss overlay
    Process.runSync('adb', ['-s', deviceId, 'shell', 'input', 'tap', '540', '1200']);
    // 6. Wait for settle and idle prewarming of upcoming page
    sleep(const Duration(milliseconds: 2500));
  }

  Map<String, double> getMemoryStats() {
    final result = Process.runSync('adb', ['-s', deviceId, 'shell', 'dumpsys', 'meminfo', 'com.shadyatef.hafiz_alahd']);
    final out = result.stdout as String;

    double pss = 0.0;
    double egl = 0.0;
    double gfx = 0.0;

    for (final line in out.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('TOTAL PSS:')) {
        final parts = trimmed.split(RegExp(r'\s+'));
        if (parts.length >= 3) {
          pss = (double.tryParse(parts[2]) ?? 0.0) / 1024.0;
        }
      } else if (trimmed.startsWith('TOTAL:')) {
        final parts = trimmed.split(RegExp(r'\s+'));
        if (parts.length >= 2) {
          pss = (double.tryParse(parts[1]) ?? 0.0) / 1024.0;
        }
      } else if (trimmed.startsWith('EGL mtrack')) {
        final parts = trimmed.split(RegExp(r'\s+'));
        if (parts.length >= 3) {
          egl = (double.tryParse(parts[2]) ?? 0.0) / 1024.0;
        }
      } else if (trimmed.startsWith('GL mtrack') || trimmed.startsWith('Gfx dev')) {
        final parts = trimmed.split(RegExp(r'\s+'));
        if (parts.length >= 3) {
          gfx = (double.tryParse(parts[2]) ?? 0.0) / 1024.0;
        }
      }
    }

    return {'pss': pss, 'egl': egl, 'gfx': gfx};
  }

  double getBatteryTemp() {
    final result = Process.runSync('adb', ['-s', deviceId, 'shell', 'dumpsys', 'battery']);
    final out = result.stdout as String;
    for (final line in out.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('temperature:')) {
        final parts = trimmed.split(RegExp(r'\s+'));
        if (parts.length >= 2) {
          return (double.tryParse(parts[1]) ?? 0.0) / 10.0;
        }
      }
    }
    return 0.0;
  }

  Future<Map<String, dynamic>> benchmarkScenario({
    required String name,
    required String description,
    required Future<void> Function() action,
    int waitAfterMs = 1500,
  }) async {
    print('\n========================================');
    print('Executing Scenario: $name ($description)');
    print('========================================');

    await client.call('clearVMTimeline');

    final memBefore = getMemoryStats();
    final sw = Stopwatch()..start();

    await action();

    await Future.delayed(Duration(milliseconds: waitAfterMs));
    sw.stop();

    final memAfter = getMemoryStats();

    print('Fetching timeline events for $name...');
    final result = await client.call('getVMTimeline') as Map<String, dynamic>;
    final events = (result['traceEvents'] as List).cast<Map<String, dynamic>>();

    final rawFile = 'scratch/p36b_${name}_raw.json';
    File(rawFile).writeAsStringSync(jsonEncode(result));
    print('Saved raw trace (${events.length} events) to $rawFile');

    final slices = TraceAnalyzer.parseSlices(events);

    // Identify threads
    final threads = <int, String>{};
    for (final e in events) {
      if (e['ph'] == 'M' && e['name'] == 'thread_name') {
        threads[e['tid'] as int] = e['args']['name'] as String;
      }
    }

    int? uiTid;
    int? rasterTid;
    threads.forEach((tid, tName) {
      if (tName.contains('.ui')) uiTid = tid;
      if (tName.contains('.raster')) rasterTid = tid;
    });

    // UI Frames
    final uiFrames = slices.where((s) => s.name == 'Animator::BeginFrame' || s.name == 'Frame').toList();
    final uiCount = uiFrames.length;
    final uiAvg = uiCount == 0 ? 0.0 : uiFrames.map((s) => s.durMs).reduce((a, b) => a + b) / uiCount;
    final uiMax = uiCount == 0 ? 0.0 : uiFrames.map((s) => s.durMs).reduce((a, b) => a > b ? a : b);
    final uiOver16 = uiFrames.where((s) => s.durMs > 16.67).length;
    final uiJank = uiCount == 0 ? 0.0 : (uiOver16 / uiCount) * 100.0;

    // Frame Pacing (Intervals between frame starts)
    uiFrames.sort((a, b) => a.startTs.compareTo(b.startTs));
    final intervals = <double>[];
    for (int i = 0; i < uiFrames.length - 1; i++) {
      intervals.add((uiFrames[i + 1].startTs - uiFrames[i].startTs) / 1000.0);
    }
    final int pacingOver16 = intervals.where((v) => v > 16.67).length;
    final int pacingOver33 = intervals.where((v) => v > 33.33).length;
    final double maxInterval = intervals.isEmpty ? 0.0 : intervals.reduce(max);
    final double medianInterval = intervals.isEmpty ? 0.0 : _percentile(intervals, 50);

    // Raster Frames
    final rasterFrames = slices.where((s) => s.name == 'GPURasterizer::Draw').toList();
    final rCount = rasterFrames.length;
    final rAvg = rCount == 0 ? 0.0 : rasterFrames.map((s) => s.durMs).reduce((a, b) => a + b) / rCount;
    final rMax = rCount == 0 ? 0.0 : rasterFrames.map((s) => s.durMs).reduce((a, b) => a > b ? a : b);
    final rOver16 = rasterFrames.where((s) => s.durMs > 16.67).length;
    final rJank = rCount == 0 ? 0.0 : (rOver16 / rCount) * 100.0;

    // Glyph Atlas
    final glyphAtlas = slices.where((s) => s.name == 'CreateGlyphAtlas').toList();
    final gaCount = glyphAtlas.length;
    final gaAvg = gaCount == 0 ? 0.0 : glyphAtlas.map((s) => s.durMs).reduce((a, b) => a + b) / gaCount;
    final gaMax = gaCount == 0 ? 0.0 : glyphAtlas.map((s) => s.durMs).reduce((a, b) => a > b ? a : b);

    // UpdateAtlasBitmap
    final updateBitmap = slices.where((s) => s.name == 'UpdateAtlasBitmap' || s.name == 'BulkUpdateAtlasBitmap').toList();
    final ubCount = updateBitmap.length;
    final ubAvg = ubCount == 0 ? 0.0 : updateBitmap.map((s) => s.durMs).reduce((a, b) => a + b) / ubCount;
    final ubMax = ubCount == 0 ? 0.0 : updateBitmap.map((s) => s.durMs).reduce((a, b) => a > b ? a : b);

    final summary = {
      'name': name,
      'description': description,
      'ui': {
        'frameCount': uiCount,
        'avgMs': double.parse(uiAvg.toStringAsFixed(2)),
        'maxMs': double.parse(uiMax.toStringAsFixed(2)),
        'over16ms': uiOver16,
        'jankPercent': double.parse(uiJank.toStringAsFixed(2)),
      },
      'pacing': {
        'totalIntervals': intervals.length,
        'over16ms': pacingOver16,
        'over33ms': pacingOver33,
        'medianMs': double.parse(medianInterval.toStringAsFixed(2)),
        'maxIntervalMs': double.parse(maxInterval.toStringAsFixed(2)),
      },
      'raster': {
        'frameCount': rCount,
        'avgMs': double.parse(rAvg.toStringAsFixed(2)),
        'maxMs': double.parse(rMax.toStringAsFixed(2)),
        'over16ms': rOver16,
        'jankPercent': double.parse(rJank.toStringAsFixed(2)),
        'glyphAtlas': {
          'count': gaCount,
          'avgMs': double.parse(gaAvg.toStringAsFixed(2)),
          'maxMs': double.parse(gaMax.toStringAsFixed(2)),
        },
        'updateBitmap': {
          'count': ubCount,
          'avgMs': double.parse(ubAvg.toStringAsFixed(2)),
          'maxMs': double.parse(ubMax.toStringAsFixed(2)),
        },
      },
      'memory': {
        'pssBefore': memBefore['pss'],
        'pssAfter': memAfter['pss'],
        'eglBefore': memBefore['egl'],
        'eglAfter': memAfter['egl'],
        'gfxBefore': memBefore['gfx'],
        'gfxAfter': memAfter['gfx'],
      },
    };

    print('--> UI Frame Max: ${uiMax.toStringAsFixed(2)}ms (Avg: ${uiAvg.toStringAsFixed(2)}ms), >16ms: $uiOver16/$uiCount');
    print('--> Pacing Gap Max: ${maxInterval.toStringAsFixed(2)}ms, >16ms: $pacingOver16, >33ms: $pacingOver33');
    print('--> Raster Frame Max: ${rMax.toStringAsFixed(2)}ms (Avg: ${rAvg.toStringAsFixed(2)}ms)');
    print('--> CreateGlyphAtlas: count=$gaCount, Max: ${gaMax.toStringAsFixed(2)}ms, Avg: ${gaAvg.toStringAsFixed(2)}ms');
    print('--> Memory: PSS=${memAfter['pss']?.toStringAsFixed(1)}MB, EGL=${memAfter['egl']?.toStringAsFixed(1)}MB');

    return summary;
  }

  static double _percentile(List<double> values, double p) {
    if (values.isEmpty) return 0.0;
    final sorted = List<double>.from(values)..sort();
    final idx = ((p / 100.0) * (sorted.length - 1)).round();
    return sorted[idx.clamp(0, sorted.length - 1)];
  }
}

void main() async {
  const deviceId = 'dfa9f629';
  const wsUrl = 'ws://127.0.0.1:56799/fYS7fco8ybo=/ws';
  print('Connecting to VM Service: $wsUrl ...');
  final ws = await WebSocket.connect(wsUrl);
  final client = VmClient(ws);

  await client.call('setVMTimelineFlags', {'recordedStreams': ['Embedder', 'GC', 'VM']});

  final harness = ValidationHarness(client, deviceId);
  final allResults = <String, dynamic>{};

  // 1. Cold ordinary page (Page 64 -> 65)
  harness.jumpToPage(63);
  harness.jumpToPage(64);
  allResults['1_cold_ordinary_p65'] = await harness.benchmarkScenario(
    name: '1_cold_ordinary_p65',
    description: '1. Cold ordinary page swipe (Page 64 -> 65)',
    action: () async => harness.swipeForward(),
  );

  // 2. Cold dense page (Page 67 -> 68)
  harness.jumpToPage(67);
  allResults['2_cold_dense_p68'] = await harness.benchmarkScenario(
    name: '2_cold_dense_p68',
    description: '2. Cold dense page swipe (Page 67 -> 68)',
    action: () async => harness.swipeForward(),
  );

  // 3. Cold Surah-header page (Page 76 -> 77)
  harness.jumpToPage(76);
  allResults['3_cold_header_p77'] = await harness.benchmarkScenario(
    name: '3_cold_header_p77',
    description: '3. Cold Surah-header page swipe (Page 76 -> 77)',
    action: () async => harness.swipeForward(),
  );

  // 4. Warm revisit (Page 76 -> 77 revisit)
  harness.swipeBackward();
  sleep(const Duration(milliseconds: 1500));
  allResults['4_warm_revisit_p77'] = await harness.benchmarkScenario(
    name: '4_warm_revisit_p77',
    description: '4. Warm revisit swipe (Page 76 -> 77)',
    action: () async => harness.swipeForward(),
  );

  // 5. Rapid forward fling (5 rapid swipes without pause: 77 -> 82)
  allResults['5_rapid_fling'] = await harness.benchmarkScenario(
    name: '5_rapid_fling',
    description: '5. Rapid forward fling across 5 pages',
    action: () async {
      for (int i = 0; i < 5; i++) {
        harness.swipeForward();
        sleep(const Duration(milliseconds: 120));
      }
    },
    waitAfterMs: 3000,
  );

  // 6. Reverse navigation (swiping backward 82 -> 81)
  allResults['6_reverse_navigation'] = await harness.benchmarkScenario(
    name: '6_reverse_navigation',
    description: '6. Reverse navigation swipe (Page 82 -> 81)',
    action: () async => harness.swipeBackward(),
  );

  // 7. Touch during scheduled prewarm
  harness.jumpToPage(90);
  allResults['7_touch_interruption'] = await harness.benchmarkScenario(
    name: '7_touch_interruption',
    description: '7. Touch interruption immediately during scheduled prewarm',
    action: () async {
      harness.swipeForward();
      sleep(const Duration(milliseconds: 80));
      harness.tap(500, 1000);
    },
  );
  // Ensure any sheet or dialog from tap is dismissed
  harness.keyBack();
  sleep(const Duration(milliseconds: 800));

  // 8. Quran route covered and restored (Bottom Sheet / Dialog)
  allResults['8_route_covered_restored'] = await harness.benchmarkScenario(
    name: '8_route_covered_restored',
    description: '8. Quran route covered by bottom sheet and restored',
    action: () async {
      harness.longPress(540, 1000);
      sleep(const Duration(milliseconds: 1500));
      harness.keyBack();
      sleep(const Duration(milliseconds: 1000));
    },
  );
  // Ensure clean state
  harness.tap(540, 300);
  sleep(const Duration(milliseconds: 800));

  // 9. 100-page continuous reading benchmark
  print('\n=== Running Scenario 9: 100-Page Continuous Reading Benchmark ===');
  harness.jumpToPage(100);
  final startMem = harness.getMemoryStats();
  final startTemp = harness.getBatteryTemp();

  final memCheckpoints = <String, Map<String, double>>{};
  memCheckpoints['100'] = startMem;

  for (int p = 101; p <= 200; p++) {
    harness.swipeForward();
    sleep(const Duration(milliseconds: 400));
    if (p % 25 == 0) {
      memCheckpoints[p.toString()] = harness.getMemoryStats();
      print('Page $p/200: PSS=${memCheckpoints[p.toString()]!['pss']?.toStringAsFixed(1)}MB, EGL=${memCheckpoints[p.toString()]!['egl']?.toStringAsFixed(1)}MB');
    }
  }

  final endMem = harness.getMemoryStats();
  final endTemp = harness.getBatteryTemp();

  allResults['9_continuous_100_pages'] = {
    'startPage': 100,
    'endPage': 200,
    'totalPages': 100,
    'startMem': startMem,
    'endMem': endMem,
    'pssDelta': double.parse((endMem['pss']! - startMem['pss']!).toStringAsFixed(2)),
    'eglDelta': double.parse((endMem['egl']! - startMem['egl']!).toStringAsFixed(2)),
    'gfxDelta': double.parse((endMem['gfx']! - startMem['gfx']!).toStringAsFixed(2)),
    'startTempC': startTemp,
    'endTempC': endTemp,
    'tempDeltaC': double.parse((endTemp - startTemp).toStringAsFixed(1)),
    'checkpoints': memCheckpoints,
  };

  print('\n=== 100-Page Continuous Reading Results ===');
  print('PSS Delta: ${allResults['9_continuous_100_pages']['pssDelta']} MB');
  print('EGL mtrack Delta: ${allResults['9_continuous_100_pages']['eglDelta']} MB');
  print('Gfx Dev Delta: ${allResults['9_continuous_100_pages']['gfxDelta']} MB');
  print('Battery Temp: $startTemp C -> $endTemp C (delta: ${allResults['9_continuous_100_pages']['tempDeltaC']} C)');

  File('scratch/p36b_validation_summary.json').writeAsStringSync(jsonEncode(allResults));
  print('\n=== All 9 Physical Validation Scenarios Completed! Saved to scratch/p36b_validation_summary.json ===');

  await ws.close();
}
