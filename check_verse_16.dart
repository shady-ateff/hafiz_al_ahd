import 'dart:convert';
import 'dart:io';

void main() async {
  final url = Uri.parse('https://api.quran.com/api/v4/verses/by_key/79:16?words=true&word_fields=code_v2,line_number,v2_page');
  final request = await HttpClient().getUrl(url);
  final response = await request.close();
  final responseBody = await response.transform(utf8.decoder).join();
  print(responseBody);
}
