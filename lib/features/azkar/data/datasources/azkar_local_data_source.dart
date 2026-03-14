import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:hafiz_al_ahd/features/azkar/data/models/azkar_item_model.dart';
import 'package:hafiz_al_ahd/core/error/exceptions.dart'; // assuming exists, otherwise create or use just Exception

abstract class AzkarLocalDataSource {
  Future<Map<String, List<AzkarItemModel>>> getAzkar();
}

class AzkarLocalDataSourceImpl implements AzkarLocalDataSource {
  @override
  Future<Map<String, List<AzkarItemModel>>> getAzkar() async {
    try {
      final String jsonString = await rootBundle.loadString(
        'assets/azkar.json',
      );
      final Map<String, dynamic> jsonMap = json.decode(jsonString);

      Map<String, List<AzkarItemModel>> parsedData = {};

      jsonMap.forEach((category, azkarList) {
        if (azkarList is List) {
          parsedData[category] = azkarList
              .map((e) => AzkarItemModel.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      });

      return parsedData;
    } catch (e) {
      throw ServerException(); // Or CacheException depending on your core exceptions
    }
  }
}
