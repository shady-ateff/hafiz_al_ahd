import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/quran_bookmark_model.dart';

abstract class BaseQuranBookmarkLocalDataSource {
  Future<List<QuranBookmarkModel>> getBookmarks();
  Future<void> saveBookmarks(List<QuranBookmarkModel> bookmarks);
}

typedef QuranBookmarkLocalDataSource = BaseQuranBookmarkLocalDataSource;

class QuranBookmarkLocalDataSourceImpl implements BaseQuranBookmarkLocalDataSource {
  static const String kQuranBookmarksKey = 'quran_saved_bookmarks';

  final SharedPreferences sharedPreferences;

  QuranBookmarkLocalDataSourceImpl({required this.sharedPreferences});

  @override
  Future<List<QuranBookmarkModel>> getBookmarks() async {
    final jsonString = sharedPreferences.getString(kQuranBookmarksKey);
    if (jsonString == null || jsonString.trim().isEmpty) {
      return [];
    }

    try {
      final dynamic decoded = jsonDecode(jsonString);
      if (decoded is! List) {
        debugPrint('[QuranBookmarkLocalDataSource] Stored JSON root is not a list. Resetting gracefully.');
        return [];
      }

      final List<QuranBookmarkModel> validBookmarks = [];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          try {
            validBookmarks.add(QuranBookmarkModel.fromJson(item));
          } catch (e) {
            debugPrint('[QuranBookmarkLocalDataSource] Skipping corrupt bookmark item: $e');
          }
        } else if (item is Map) {
          try {
            validBookmarks.add(QuranBookmarkModel.fromJson(Map<String, dynamic>.from(item)));
          } catch (e) {
            debugPrint('[QuranBookmarkLocalDataSource] Skipping corrupt bookmark item: $e');
          }
        }
      }
      return validBookmarks;
    } catch (e) {
      debugPrint('[QuranBookmarkLocalDataSource] Malformed bookmarks JSON, recovering gracefully: $e');
      return [];
    }
  }

  @override
  Future<void> saveBookmarks(List<QuranBookmarkModel> bookmarks) async {
    final list = bookmarks.map((b) => b.toJson()).toList();
    final jsonString = jsonEncode(list);
    await sharedPreferences.setString(kQuranBookmarksKey, jsonString);
  }
}

