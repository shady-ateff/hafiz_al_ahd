import 'dart:convert';
import 'dart:io';

void main() async {
  final file = File('assets/quran/mushaf/quran_lines.json');
  final String jsonData = await file.readAsString();
  final List<dynamic> pages = jsonDecode(jsonData);

  for (var page in pages) {
    if (page['page_number'] == 177) {
      final lines = page['lines'] as List<dynamic>;
      for (int i = 9; i <= 15; i++) {
        var line = lines.firstWhere((l) => l['line_number'] == i, orElse: () => null);
        if (line != null) {
          print('Line $i: ${line['text']}');
        }
      }
      break;
    }
  }
}
