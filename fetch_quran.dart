import 'dart:convert';
import 'dart:io';

Future<List<Map<String, dynamic>>> fetchAllQuran() async {
  final Map<int, Map<int, Map<String, dynamic>>> globalPages = {};

  final futures = <Future<void>>[];
  for (int i = 1; i <= 604; i++) {
    futures.add(() async {
      final url = Uri.parse('https://api.quran.com/api/v4/verses/by_page/$i?words=true&word_fields=code_v2,line_number,v2_page');
      for (int retry = 0; retry < 3; retry++) {
        try {
          final request = await HttpClient().getUrl(url).timeout(Duration(seconds: 15));
          final response = await request.close().timeout(Duration(seconds: 15));
          final responseBody = await response.transform(utf8.decoder).join();
          final data = jsonDecode(responseBody);
          final verses = data['verses'] as List;

          for (var verse in verses) {
            final surahNumber = int.parse(verse['verse_key'].toString().split(':')[0]);
            final words = verse['words'] as List;
            for (var word in words) {
              final codeV2 = word['code_v2'];
              if (codeV2 == null || codeV2.toString().trim().isEmpty) continue;

              final v2Page = word['v2_page'] ?? i;
              final lineNumber = word['line_number'] as int;
              final wordId = word['id'] as int;

              if (!globalPages.containsKey(v2Page)) {
                globalPages[v2Page as int] = {};
              }

              if (!globalPages[v2Page]!.containsKey(lineNumber)) {
                globalPages[v2Page]![lineNumber] = {
                  'words': <Map<String, dynamic>>[],
                  'surah': surahNumber,
                };
              }
              (globalPages[v2Page]![lineNumber]!['words'] as List<Map<String, dynamic>>).add({
                'code': codeV2.toString(),
                'id': wordId,
              });
            }
          }
          break;
        } catch (e) {
          if (retry == 2) {
            print('Failed to fetch page $i after 3 retries: $e');
          }
        }
      }
    }());

    if (i % 50 == 0 || i == 604) {
      await Future.wait(futures);
      futures.clear();
      print('Fetched up to page $i');
    }
  }

  final List<Map<String, dynamic>> finalPagesList = [];
  final sortedPages = globalPages.keys.toList()..sort();
  
  for (var pageNum in sortedPages) {
    final linesMap = globalPages[pageNum]!;
    final List<Map<String, dynamic>> linesList = [];
    final sortedLines = linesMap.keys.toList()..sort();
    
    for (var lineNum in sortedLines) {
      final wordsList = linesMap[lineNum]!['words'] as List<Map<String, dynamic>>;
      // Sort words by their exact ID to ensure correct Quranic order regardless of fetch concurrency
      wordsList.sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
      
      linesList.add({
        'line_number': lineNum,
        'surah_number': linesMap[lineNum]!['surah'],
        'text': wordsList.map((w) => w['code'] as String).join(' '),
      });
    }

    finalPagesList.add({
      'page_number': pageNum,
      'lines': linesList,
    });
  }

  return finalPagesList;
}

void main() async {
  print('Fetching all Quran data and grouping by v2_page (sorted by word ID)...');
  final allPages = await fetchAllQuran();
  
  final file = File('assets/quran/mushaf/quran_lines.json');
  file.writeAsStringSync(jsonEncode(allPages));
  print('Successfully wrote ${allPages.length} pages to quran_lines.json');
}
