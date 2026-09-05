import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('assets/quran/mushaf/quran_lines.json');
  final data = json.decode(file.readAsStringSync()) as List;
  
  for (var page in data) {
    if (page['page_number'] == 583) {
      print('Page 583 lines:');
      for (var line in page['lines']) {
        print('Line ${line['line_number']}: Surah ${line['surah_number']} - ${line['text']}');
      }
      break;
    }
  }
}
