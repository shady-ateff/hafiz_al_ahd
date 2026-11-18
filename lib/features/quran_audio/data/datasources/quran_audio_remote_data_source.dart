import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/audio_reciter_model.dart';
import '../models/surah_audio_model.dart';

abstract class BaseQuranAudioRemoteDataSource {
  Future<List<AudioReciterModel>> getChapterReciters();
  Future<SurahAudioModel> getSurahAudio({
    required int surahNumber,
    required String reciterId,
  });
  Future<int?> getRemoteAudioContentLength(String audioUrl);
}

class QuranAudioRemoteDataSourceImpl implements BaseQuranAudioRemoteDataSource {
  static const String kDefaultBaseUrl = 'https://api.qurancdn.com/api/qdc';
  static const Duration kDefaultTimeout = Duration(seconds: 20);

  final http.Client client;
  final String baseUrl;

  QuranAudioRemoteDataSourceImpl({
    required this.client,
    this.baseUrl = kDefaultBaseUrl,
  });

  @override
  Future<List<AudioReciterModel>> getChapterReciters() async {
    final uri = Uri.parse('$baseUrl/audio/reciters?locale=ar');
    final response = await client.get(uri).timeout(kDefaultTimeout);

    if (response.statusCode != 200) {
      throw http.ClientException('HTTP ${response.statusCode}: Failed to fetch reciters');
    }

    final decoded = jsonDecode(response.body);
    final List<AudioReciterModel> reciters = [];

    if (decoded is Map && decoded['reciters'] is List) {
      for (final item in decoded['reciters']) {
        if (item is Map<String, dynamic>) {
          reciters.add(AudioReciterModel.fromJson(item));
        } else if (item is Map) {
          reciters.add(AudioReciterModel.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    return reciters;
  }

  @override
  Future<SurahAudioModel> getSurahAudio({
    required int surahNumber,
    required String reciterId,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/audio/reciters/$reciterId/audio_files?chapter=$surahNumber&segments=true',
    );
    final response = await client.get(uri).timeout(kDefaultTimeout);

    if (response.statusCode == 404) {
      throw http.ClientException('Surah audio not found (404)');
    }
    if (response.statusCode != 200) {
      throw http.ClientException('HTTP ${response.statusCode}: Failed to fetch surah audio');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map && decoded['audio_files'] is List && (decoded['audio_files'] as List).isNotEmpty) {
      final first = (decoded['audio_files'] as List).first;
      final map = first is Map<String, dynamic> ? first : Map<String, dynamic>.from(first as Map);
      return SurahAudioModel.fromJson(
        map,
        fallbackSurahNumber: surahNumber,
        fallbackReciterId: reciterId,
      );
    }

    throw http.ClientException('Malformed audio files response');
  }

  @override
  Future<int?> getRemoteAudioContentLength(String audioUrl) async {
    try {
      final response = await client.head(Uri.parse(audioUrl)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200 || response.statusCode == 206) {
        final cl = response.headers['content-length'];
        if (cl != null) {
          return int.tryParse(cl);
        }
      }
    } catch (_) {}
    return null;
  }
}
