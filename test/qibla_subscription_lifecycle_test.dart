import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/qibla/presentation/screens/qibla_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QiblaScreen Lifecycle & Active State Tests', () {
    test('QiblaScreen defaults to isActive == true', () {
      const qiblaScreen = QiblaScreen();
      expect(qiblaScreen.isActive, isTrue);
    });

    test('QiblaScreen can be instantiated with isActive == false', () {
      const qiblaScreen = QiblaScreen(isActive: false);
      expect(qiblaScreen.isActive, isFalse);
    });

    test('QiblaScreen can toggle isActive parameter', () {
      var screen = const QiblaScreen(isActive: false);
      expect(screen.isActive, isFalse);

      screen = const QiblaScreen(isActive: true);
      expect(screen.isActive, isTrue);
    });
  });
}

