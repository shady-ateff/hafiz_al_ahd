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
      
      print('Line 9 Before: ${line9['text']}');
      print('Line 10 Before: ${line10['text']}');

      String text9 = line9['text'];
      String text10 = line10['text'];

      List<String> words9 = text9.split(' ');
      String lastWord = words9.removeLast();
      
      line9['text'] = words9.join(' ');
      line10['text'] = lastWord + ' ' + text10;

      print('Line 9 After: ${line9['text']}');
      print('Line 10 After: ${line10['text']}');
      break;
    }
  }

  await file.writeAsString(jsonEncode(pages));
  print('Done modifying json.');
}
