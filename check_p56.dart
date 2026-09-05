import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('assets/quran/mushaf/quran_lines.json');
  final data = jsonDecode(file.readAsStringSync()) as List;
  final p1 = data.firstWhere((e) => e['page_number'] == 1, orElse: () => null);
  print(p1);
}
