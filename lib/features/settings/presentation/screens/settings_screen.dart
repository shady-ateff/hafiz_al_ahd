import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/features/settings/domain/usecases/get_iqama_delays_usecase.dart';
import 'package:hafiz_al_ahd/features/settings/domain/usecases/save_iqama_delays_usecase.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final Map<String, int> _delays = {
    'fajr': 25,
    'dhuhr': 15,
    'asr': 15,
    'maghrib': 10,
    'isha': 15,
  };

  final Map<String, String> _prayerNames = {
    'fajr': 'الفجر',
    'dhuhr': 'الظهر',
    'asr': 'العصر',
    'maghrib': 'المغرب',
    'isha': 'العشاء',
  };

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final getUseCase = GetIqamaDelaysUseCase();
    final savedDelays = await getUseCase.execute();
    setState(() {
      _delays.addAll(savedDelays);
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    final saveUseCase = SaveIqamaDelaysUseCase();
    await saveUseCase.execute(_delays);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم حفظ الإعدادات وسيتم إعادة جدولة الإشعارات!',
            style: GoogleFonts.cairo(),
          ),
          backgroundColor: Colors.green,
        ),
      );
      // Re-fetch to reschedule notifications with new delays
      context.read<PrayerTimesCubit>().fetchPrayerTimesByLocation();
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'الإعدادات',
          style: GoogleFonts.cairo(
            color: AppColors.secondaryGold,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.secondaryGold),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.secondaryGold),
            )
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'إعدادات تأخير الإقامة (بالدقائق)',
                    style: GoogleFonts.cairo(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryBlack,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _prayerNames.length,
                      separatorBuilder: (context, index) => const Divider(),
                      itemBuilder: (context, index) {
                        String key = _prayerNames.keys.elementAt(index);
                        String name = _prayerNames[key]!;
                        return ListTile(
                          title: Text(
                            name,
                            style: GoogleFonts.cairo(fontSize: 16),
                          ),
                          trailing: DropdownButton<int>(
                            value: _delays[key],
                            items: [5, 10, 15, 20, 25, 30].map((int value) {
                              return DropdownMenuItem<int>(
                                value: value,
                                child: Text(
                                  '$value دقيقة',
                                  style: GoogleFonts.cairo(),
                                ),
                              );
                            }).toList(),
                            onChanged: (int? newValue) {
                              if (newValue != null) {
                                setState(() {
                                  _delays[key] = newValue;
                                });
                              }
                            },
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.secondaryGold,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: _saveSettings,
                      child: Text(
                        'حفظ الإعدادات',
                        style: GoogleFonts.cairo(
                          color: AppColors.primaryBlack,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
