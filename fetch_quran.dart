import 'dart:convert';
import 'dart:io';

Future<Map<String, dynamic>?> fetchPage(int page) async {
  final url = Uri.parse('https://api.quran.com/api/v4/verses/by_page/$page?words=true&word_fields=code_v2,line_number');
  for (int retry = 0; retry < 3; retry++) {
    try {
      final request = await HttpClient().getUrl(url);
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      final data = jsonDecode(responseBody);
      final verses = data['verses'] as List;

      final Map<int, List<String>> linesMap = {};
      for (var verse in verses) {
        final words = verse['words'] as List;
        for (var word in words) {
          final lineNumber = word['line_number'] as int;
          final codeV2 = word['code_v2'];
          if (codeV2 != null && codeV2.toString().trim().isNotEmpty) {
            linesMap.putIfAbsent(lineNumber, () => []).add(codeV2.toString());
          }
        }
      }

      final List<String> linesList = [];
      final sortedKeys = linesMap.keys.toList()..sort();
      for (var key in sortedKeys) {
        linesList.add(linesMap[key]!.join(' '));
      }

      return {
        'page_number': page,
        'lines': linesList,
      };
    } catch (e) {
      await Future.delayed(Duration(seconds: 1));
    }
  }
  return null;
}

void main() async {
  final file = File('assets/quran/mushaf/quran_lines.json');
  final List<Map<String, dynamic>> allPages = [];

  print('Fetching 604 pages concurrently...');
  
  // Fetch in chunks of 50
  for (int i = 0; i < 604; i += 50) {
    final chunk = <Future<Map<String, dynamic>?>>[];
    for (int j = 1; j <= 50; j++) {
      if (i + j > 604) break;
      chunk.add(fetchPage(i + j));
    }
    
    final results = await Future.wait(chunk);
    for (var res in results) {
      if (res != null) allPages.add(res);
    }
    print('Fetched up to ${i + 50 > 604 ? 604 : i + 50}');
  }

  // Sort by page number just in case
  allPages.sort((a, b) => (a['page_number'] as int).compareTo(b['page_number'] as int));

  await file.writeAsString(jsonEncode(allPages));
  print('Done! Saved to ${file.path}');
}
