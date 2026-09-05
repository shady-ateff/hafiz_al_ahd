import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('assets/quran/mushaf/quran_lines.json');
  final data = jsonDecode(file.readAsStringSync()) as List;
  print('Total pages: ${data.length}');
  
  final pages = data.map((e) => e['page_number'] as int).toList();
  for (int i = 1; i <= 604; i++) {
    if (!pages.contains(i)) {
      print('Missing page: $i');
    }
  }
}
