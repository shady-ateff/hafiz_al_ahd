import 'package:country_state_city_picker/country_state_city_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/utils/app_colors.dart';
import '../cubit/prayer_times_cubit/prayer_times_cubit.dart';

class ManualLocationDialog extends StatefulWidget {
  const ManualLocationDialog({super.key});

  @override
  State<ManualLocationDialog> createState() => _ManualLocationDialogState();
}

class _ManualLocationDialogState extends State<ManualLocationDialog> {
  String? countryValue;
  String? stateValue;
  String? cityValue;

  bool _isLoading = false;

  Future<void> _handleSelection() async {
    if (countryValue == null || stateValue == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'يرجى اختيار الدولة والمحافظة على الأقل',
            style: GoogleFonts.cairo(),
          ),
          backgroundColor: AppColors.errorColor,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Build address string, preferring city if available, otherwise fallback to state
      String addressQuery = '';
      if (cityValue != null &&
          cityValue!.isNotEmpty &&
          cityValue != 'Choose City') {
        addressQuery = '$cityValue, $stateValue, $countryValue';
      } else {
        addressQuery = '$stateValue, $countryValue';
      }

      // We still need to geocode because the package doesn't return lat/lng directly
      List<Location> locations = await locationFromAddress(addressQuery);

      if (locations.isNotEmpty) {
        Location location = locations.first;

        // Extract Country code from the name (Usually the picker returns something like 'Egypt', we will just pass 'EG' or use the helper later)
        // For simplicity, we just pass the country name and let the helper try its best, or we pass null and it defaults to 3
        if (mounted) {
          Navigator.pop(context);
          // Here we pass the city/state name as the 'city' parameter for the UI
          String displayCity = cityValue != null && cityValue != 'Choose City'
              ? cityValue!
              : stateValue!;

          // A more advanced Country Code extraction would map country Value to ISO code.
          // For now, we pass the raw countryValue. The CalculationMethodHelper might need an update to handle full country names.
          context.read<PrayerTimesCubit>().fetchPrayerTimesManually(
            location.latitude,
            location.longitude,
            displayCity,
            countryValue, // Passing the full name. The helper currently expects 'EG', 'SA' etc. We'll update the helper next!
          );
        }
      } else {
        throw Exception('Location not found');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'حدث خطأ في جلب الإحداثيات، تأكد من اتصالك بالإنترنت لهذه الخطوة فقط أو اختر محافظة رئيسية.',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: AppColors.errorColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.primaryBlack,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: AppColors.secondaryGold.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.location_off_rounded,
                color: AppColors.errorColor,
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                'تعذر تحديد الموقع!',
                style: GoogleFonts.cairo(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'يرجى البحث واختيار مدينتك يدوياً لحساب مواقيت الصلاة بدقة.',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  color: AppColors.silverMarble,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),

              // Customizing the picker to look good on dark theme
              Theme(
                data: Theme.of(context).copyWith(
                  canvasColor: AppColors.primaryBlack, // Dropdown background
                  focusColor: AppColors.secondaryGold,
                ),
                child: SelectState(
                  onCountryChanged: (value) {
                    setState(() {
                      countryValue = value;
                    });
                  },
                  onStateChanged: (value) {
                    setState(() {
                      stateValue = value;
                    });
                  },
                  onCityChanged: (value) {
                    setState(() {
                      cityValue = value;
                    });
                  },
                  style: TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                  dropdownColor: AppColors.primaryBlack,
                ),
              ),

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.secondaryGold,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: _isLoading ? null : _handleSelection,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: AppColors.primaryBlack,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'تأكيد وحساب المواقيت',
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
      ),
    );
  }
}
