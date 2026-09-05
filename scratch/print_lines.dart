import 'dart:convert';
import 'dart:io';

void main() async {
  final file = File('assets/quran/mushaf/quran_lines.json');
  final String jsonData = await file.readAsString();
  final List<dynamic> pages = jsonDecode(jsonData);

  for (var page in pages) {
    if (page['page_number'] == 177) {
      final lines = page['lines'] as List<dynamic>;
      var line8 = lines.firstWhere((l) => l['line_number'] == 8);
      var line9 = lines.firstWhere((l) => l['line_number'] == 9);
      var line10 = lines.firstWhere((l) => l['line_number'] == 10);
      
      print('Line 8: ${line8['text']}');
      print('Line 9: ${line9['text']}');
      print('Line 10: ${line10['text']}');
      break;
    }
  }
}
