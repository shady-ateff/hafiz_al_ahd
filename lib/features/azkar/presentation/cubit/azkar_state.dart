import 'package:hafiz_al_ahd/features/azkar/domain/entities/azkar_item.dart';

abstract class AzkarState {
  const AzkarState();
}

class AzkarInitial extends AzkarState {}

class AzkarLoading extends AzkarState {}

class AzkarLoaded extends AzkarState {
  final Map<String, List<AzkarItem>> azkarMap;

  const AzkarLoaded(this.azkarMap);
}

class AzkarError extends AzkarState {
  final String message;

  const AzkarError(this.message);
}
