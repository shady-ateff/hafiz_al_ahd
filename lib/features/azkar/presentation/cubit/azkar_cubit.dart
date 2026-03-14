import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hafiz_al_ahd/features/azkar/domain/usecases/get_azkar_usecase.dart';
import 'package:hafiz_al_ahd/features/azkar/presentation/cubit/azkar_state.dart';

class AzkarCubit extends Cubit<AzkarState> {
  final GetAzkarUseCase getAzkarUseCase;

  AzkarCubit({required this.getAzkarUseCase}) : super(AzkarInitial());

  Future<void> loadAzkar() async {
    emit(AzkarLoading());

    final failureOrAzkar = await getAzkarUseCase.call();

    failureOrAzkar.fold(
      (failureMessage) => emit(AzkarError(failureMessage)),
      (azkarMap) => emit(AzkarLoaded(azkarMap)),
    );
  }
}
