import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('assets/quran/mushaf/quran_lines.json');
  final data = jsonDecode(file.readAsStringSync()) as List;
  for(var p in data) {
    if(p['lines'].length < 15) {
      print('Page ${p["page_number"]}: ${p["lines"].length} lines');
    }
  }
}
