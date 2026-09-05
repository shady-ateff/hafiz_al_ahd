import 'dart:convert';
import 'dart:io';

void main() async {
  final file = File('assets/quran/mushaf/quran_lines.json');
  final String jsonData = await file.readAsString();
  final List<dynamic> pages = jsonDecode(jsonData);

  for (var page in pages) {
    if (page['page_number'] == 177) {
      final lines = page['lines'] as List<dynamic>;
      
      // We will shift exactly 1 word (the last word) from each line down to the next, starting from line 9 up to line 14.
      // Line 9 ends with "وهم" (which is one word/character in QCF).
      // We will pop the last word of line 9, unshift it to line 10, then pop the last word of line 10...
      
      String carryWord = "";
      
      for (int i = 9; i <= 15; i++) {
        var line = lines.firstWhere((l) => l['line_number'] == i, orElse: () => null);
        if (line != null) {
          String text = line['text'];
          List<String> words = text.split(' ').where((w) => w.isNotEmpty).toList();
          
          if (carryWord.isNotEmpty) {
            // Add the carry word to the BEGINNING (logical right) of the line
            words.insert(0, carryWord);
          }
          
          if (i < 15) {
            // Pop the last word to carry to the next line
            carryWord = words.removeLast();
          } else {
            // Line 15 absorbs the word, no carry
            carryWord = "";
          }
          
          line['text'] = words.join(' ');
        }
      }
      
      print('Done cascading page 177.');
      break;
    }
  }

  await file.writeAsString(jsonEncode(pages));
}
