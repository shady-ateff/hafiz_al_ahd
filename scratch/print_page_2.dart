import 'dart:convert';
import 'dart:io';

void main() async {
  final file = File('assets/quran/mushaf/quran_lines.json');
  final String jsonData = await file.readAsString();
  final List<dynamic> pages = jsonDecode(jsonData);

  for (var page in pages) {
    if (page['page_number'] == 2) {
      final lines = page['lines'] as List<dynamic>;
      for (var line in lines) {
        print('Line ${line['line_number']}: ${line['text']}');
      }
      break;
    }
  }
}
