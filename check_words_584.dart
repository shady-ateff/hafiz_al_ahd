import 'dart:convert';
import 'dart:io';

void main() async {
  final url = Uri.parse('https://api.quran.com/api/v4/verses/by_page/584?words=true&word_fields=code_v2,line_number');
  final request = await HttpClient().getUrl(url);
  final response = await request.close();
  final responseBody = await response.transform(utf8.decoder).join();
  final data = json.decode(responseBody);
  
  for (var verse in data['verses']) {
    final v = verse['verse_key'];
    final words = verse['words'] as List;
    for (var w in words) {
      if (w['char_type_name'] == 'word' || w['char_type_name'] == 'end') {
        print('$v word: ${w['code_v2']} line: ${w['line_number']}');
      }
    }
  }
}
