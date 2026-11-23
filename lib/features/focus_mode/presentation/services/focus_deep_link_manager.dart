import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hafiz_al_ahd/main.dart'; // For navigatorKey
import 'package:hafiz_al_ahd/features/azkar/data/datasources/azkar_local_data_source.dart';
import 'package:hafiz_al_ahd/features/azkar/data/repositories/azkar_repository_impl.dart';
import 'package:hafiz_al_ahd/features/azkar/domain/entities/azkar_item.dart';
import 'package:hafiz_al_ahd/features/azkar/domain/usecases/get_azkar_usecase.dart';
import 'package:hafiz_al_ahd/features/azkar/presentation/screens/misbaha_screen.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/screens/quran_screen.dart';

/// Centralized deep-link navigator for Focus Mode wards.
/// Routes incoming ward intents directly to the target destination screen
/// (e.g. Misbaha with morning/evening Azkar, or QuranScreen).
class FocusDeepLinkManager {
  static bool _isNavigating = false;

  /// Routes to the matching ward screen based on [wardTitle].
  static Future<void> navigateToWard(String wardTitle) async {
    if (_isNavigating) return;
    _isNavigating = true;

    try {
      final navState = navigatorKey.currentState;
      if (navState == null) return;

      final normalized = wardTitle.trim().toLowerCase();

      // 1. Quran reading ward routing
      if (normalized.contains('قرآن') ||
          normalized.contains('مصحف') ||
          normalized.contains('quran')) {
        await navState.push(
          MaterialPageRoute(builder: (_) => const QuranScreen()),
        );
        return;
      }

      // 2. Azkar / Misbaha ward routing
      String? matchedCategory;
      if (normalized.contains('صباح')) {
        matchedCategory = 'أذكار الصباح';
      } else if (normalized.contains('مساء')) {
        matchedCategory = 'أذكار المساء';
      } else if (normalized.contains('صلاة')) {
        matchedCategory = 'أذكار بعد السلام من الصلاة المفروضة';
      } else if (normalized.contains('نوم')) {
        matchedCategory = 'أذكار النوم';
      } else if (normalized.contains('استيقاظ')) {
        matchedCategory = 'أذكار الاستيقاظ';
      } else if (normalized.contains('تسابيح') || normalized.contains('تسبيح')) {
        matchedCategory = 'تسابيح';
      }

      final azkarList = await _loadAzkarForCategory(matchedCategory ?? wardTitle);

      if (azkarList != null && azkarList.isNotEmpty) {
        await navState.push(
          MaterialPageRoute(
            builder: (_) => MisbahaScreen(dynamicAzkarList: azkarList),
          ),
        );
      } else {
        // Fallback to default Misbaha
        await navState.push(
          MaterialPageRoute(builder: (_) => const MisbahaScreen()),
        );
      }
    } catch (_) {
      // Prevent unhandled navigation exceptions
    } finally {
      Future.delayed(const Duration(milliseconds: 1000), () {
        _isNavigating = false;
      });
    }
  }

  static Future<List<AzkarItem>?> _loadAzkarForCategory(String targetCategory) async {
    try {
      final useCase = GetAzkarUseCase(
        AzkarRepositoryImpl(localDataSource: AzkarLocalDataSourceImpl()),
      );
      final result = await useCase();
      return result.fold(
        (_) => null,
        (azkarMap) {
          // Exact match first
          if (azkarMap.containsKey(targetCategory)) {
            return azkarMap[targetCategory];
          }
          // Partial search match
          for (final entry in azkarMap.entries) {
            if (entry.key.contains(targetCategory) ||
                targetCategory.contains(entry.key)) {
              return entry.value;
            }
          }
          return null;
        },
      );
    } catch (_) {
      return null;
    }
  }
}
