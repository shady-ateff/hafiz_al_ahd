import 'dart:convert';
import 'dart:io';

Future<Map<String, dynamic>?> fetchPage(int page) async {
  final url = Uri.parse('https://api.quran.com/api/v4/verses/by_page/$page?words=true&word_fields=code_v2,line_number');
  for (int retry = 0; retry < 3; retry++) {
    try {
      final request = await HttpClient().getUrl(url).timeout(Duration(seconds: 10));
      final response = await request.close().timeout(Duration(seconds: 10));
      final responseBody = await response.transform(utf8.decoder).join();
      final data = jsonDecode(responseBody);
      final verses = data['verses'] as List;

      // Map of lineNumber -> Map with 'text' (List of words) and 'surah'
      final Map<int, Map<String, dynamic>> linesMap = {};
      
      for (var verse in verses) {
        final surahNumber = int.parse(verse['verse_key'].toString().split(':')[0]);
        final words = verse['words'] as List;
        for (var word in words) {
          final lineNumber = word['line_number'] as int;
          final codeV2 = word['code_v2'];
          if (codeV2 != null && codeV2.toString().trim().isNotEmpty) {
            if (!linesMap.containsKey(lineNumber)) {
              linesMap[lineNumber] = {
                'words': <String>[],
                'surah': surahNumber,
              };
            }
            (linesMap[lineNumber]!['words'] as List<String>).add(codeV2.toString());
          }
        }
      }

      final List<Map<String, dynamic>> linesList = [];
      final sortedKeys = linesMap.keys.toList()..sort();
      for (var key in sortedKeys) {
        linesList.add({
          'line_number': key,
          'surah_number': linesMap[key]!['surah'],
          'text': (linesMap[key]!['words'] as List<String>).join(' '),
        });
      }

      return {
        'page_number': page,
        'lines': linesList,
      };
    } catch (e) {
      print('Retry page $page due to error: $e');
      await Future.delayed(Duration(seconds: 2));
    }
  }
  return null;
}

void main() async {
  final file = File('assets/quran/mushaf/quran_lines.json');
  final List<Map<String, dynamic>> allPages = [];

  print('Fetching 604 pages concurrently...');
  
  // Fetch in chunks of 10 to avoid API blocks
  for (int i = 0; i < 604; i += 10) {
    final chunk = <Future<Map<String, dynamic>?>>[];
    for (int j = 1; j <= 10; j++) {
      if (i + j > 604) break;
      chunk.add(fetchPage(i + j));
    }
    
    final results = await Future.wait(chunk);
    for (var res in results) {
      if (res != null) allPages.add(res);
    }
    print('Fetched up to ${i + 10 > 604 ? 604 : i + 10}');
    await Future.delayed(Duration(milliseconds: 500)); // Be nice to the API
  }

  // Sort by page number just in case
  allPages.sort((a, b) => (a['page_number'] as int).compareTo(b['page_number'] as int));

  await file.writeAsString(jsonEncode(allPages));
  print('Done! Saved to ${file.path}');
}
