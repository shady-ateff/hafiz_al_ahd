import 'package:adhan/adhan.dart';

void main() {
  final params = CalculationMethod.other.getParameters();
  params.fajrAngle = 18.0;
  params.ishaAngle = 17.0;
  params.madhab = Madhab.shafi;
  params.adjustments.fajr = -1;
  params.adjustments.sunrise = -5;
  params.adjustments.dhuhr = 5;
  params.adjustments.asr = 1;
  params.adjustments.maghrib = 6;
  params.adjustments.isha = 0;

  print('adjustments: fajr=${params.adjustments.fajr}, dhuhr=${params.adjustments.dhuhr}, maghrib=${params.adjustments.maghrib}');
}

