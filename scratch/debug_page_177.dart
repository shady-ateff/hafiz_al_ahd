import 'dart:convert';
import 'dart:io';

void main() async {
  final file = File('assets/quran/mushaf/quran_lines.json');
  final String jsonData = await file.readAsString();
  final List<dynamic> pages = jsonDecode(jsonData);

  for (var page in pages) {
    if (page['page_number'] == 177) {
      final lines = page['lines'] as List<dynamic>;
      var line9 = lines.firstWhere((l) => l['line_number'] == 9);
      var line10 = lines.firstWhere((l) => l['line_number'] == 10);
      
      String text9 = line9['text'];
      String text10 = line10['text'];

      List<String> words9 = text9.split(' ');
      
      print('Line 9 words count: ${words9.length}');
      for (int i = 0; i < words9.length; i++) {
        String word = words9[i];
        String hexes = word.runes.map((r) => r.toRadixString(16).padLeft(4, '0')).join(' ');
        print('Word $i: $word (Hex: $hexes)');
      }
      
      break;
    }
  }
}
