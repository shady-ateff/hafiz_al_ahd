import 'dart:io';
import 'dart:convert';

class TraceSlice {
  final String name;
  final String cat;
  final int tid;
  final int startTs;
  final int endTs;
  final double durMs;
  final Map<String, dynamic>? args;

  TraceSlice({
    required this.name,
    required this.cat,
    required this.tid,
    required this.startTs,
    required this.endTs,
    required this.durMs,
    this.args,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'cat': cat,
    'tid': tid,
    'startTs': startTs,
    'endTs': endTs,
    'durMs': durMs,
    'args': args,
  };
}

class TraceAnalyzer {
  static List<TraceSlice> parseSlices(List<Map<String, dynamic>> events) {
    final List<TraceSlice> completedSlices = [];

    // Separate by thread for sync events (ph: B / E)
    final Map<int, List<Map<String, dynamic>>> syncStacks = {};

    // For async / ID-based events (ph: b / e)
    final Map<String, Map<String, dynamic>> asyncOpen = {};

    for (final e in events) {
      final ph = e['ph'] as String?;
      final name = e['name'] as String? ?? '';
      final cat = e['cat'] as String? ?? '';
      final tid = e['tid'] as int? ?? 0;
      final ts = e['ts'] as int? ?? 0;
      final id = e['id']?.toString();
      final args = e['args'] as Map<String, dynamic>?;

      if (ph == 'B') {
        syncStacks.putIfAbsent(tid, () => []).add(e);
      } else if (ph == 'E') {
        final stack = syncStacks[tid];
        if (stack != null && stack.isNotEmpty) {
          // Look from the top of the stack for matching name
          int matchIdx = -1;
          for (int i = stack.length - 1; i >= 0; i--) {
            if (stack[i]['name'] == name) {
              matchIdx = i;
              break;
            }
          }
          if (matchIdx != -1) {
            final begin = stack.removeAt(matchIdx);
            final startTs = begin['ts'] as int;
            final durUs = ts - startTs;
            completedSlices.add(TraceSlice(
              name: name,
              cat: cat,
              tid: tid,
              startTs: startTs,
              endTs: ts,
              durMs: durUs / 1000.0,
              args: begin['args'] ?? args,
            ));
          }
        }
      } else if (ph == 'b') {
        final key = '${name}_${id ?? tid}';
        asyncOpen[key] = e;
      } else if (ph == 'e') {
        final key = '${name}_${id ?? tid}';
        final begin = asyncOpen.remove(key);
        if (begin != null) {
          final startTs = begin['ts'] as int;
          final durUs = ts - startTs;
          completedSlices.add(TraceSlice(
            name: name,
            cat: cat,
            tid: tid,
            startTs: startTs,
            endTs: ts,
            durMs: durUs / 1000.0,
            args: begin['args'] ?? args,
          ));
        }
      } else if (ph == 'X') {
        // Complete event with 'dur'
        final durUs = e['dur'] as num? ?? 0;
        completedSlices.add(TraceSlice(
          name: name,
          cat: cat,
          tid: tid,
          startTs: ts,
          endTs: ts + durUs.toInt(),
          durMs: durUs / 1000.0,
          args: args,
        ));
      }
    }

    return completedSlices;
  }
}

void main() async {
  // Test parser on existing file if present
  final rawPath = 'scratch/inspect_raw.json';
  if (File(rawPath).existsSync()) {
    final raw = jsonDecode(File(rawPath).readAsStringSync()) as Map<String, dynamic>;
    final events = (raw['traceEvents'] as List).cast<Map<String, dynamic>>();
    final slices = TraceAnalyzer.parseSlices(events);
    print('Parsed ${slices.length} completed slices from raw trace.');
  }
}

