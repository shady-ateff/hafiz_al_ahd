import 'package:country_state_city_picker/country_state_city_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/utils/app_colors.dart';
import '../../../../core/utils/calculation_method_helper.dart';
import '../cubit/prayer_times_cubit/prayer_times_cubit.dart';

class ManualLocationDialog extends StatefulWidget {
  final bool isFromSettings;
  const ManualLocationDialog({super.key, this.isFromSettings = false});

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

      List<Location> locations = await locationFromAddress(addressQuery);

      if (locations.isNotEmpty) {
        Location location = locations.first;

        if (mounted) {
          Navigator.pop(context, true);
          String displayCity = cityValue != null && cityValue != 'Choose City'
              ? cityValue!
              : stateValue!;

          // تطبيع كود الدولة
          final String resolvedCountry =
              CalculationMethodHelper.normalizeToIsoCountryCode(countryValue) ??
              countryValue ??
              '';

          context.read<PrayerTimesCubit>().fetchPrayerTimesManually(
            location.latitude,
            location.longitude,
            displayCity,
            resolvedCountry,
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
                widget.isFromSettings
                    ? Icons.location_on_rounded
                    : Icons.location_off_rounded,
                color: widget.isFromSettings
                    ? AppColors.secondaryGold
                    : AppColors.errorColor,
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                widget.isFromSettings
                    ? 'تحديد الموقع يدويًا'
                    : 'تعذر تحديد الموقع!',
                style: GoogleFonts.cairo(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.isFromSettings
                    ? 'اختر الدولة والمحافظة/المدينة لحساب مواقيت الصلاة بدقة.'
                    : 'يرجى البحث واختيار مدينتك يدوياً لحساب مواقيت الصلاة بدقة.',
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
                  style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                  dropdownColor: AppColors.primaryBlack,
                ),
              ),

              const SizedBox(height: 16),

              // صندوق التحذير والتنبيه
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withOpacity(0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.amber,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تنبيه: اختيار الموقع يدويًا يثبت حساب المواقيت على هذه المدينة. في حال السفر أو الانتقال لبلد آخر، يجب تحديث الموقع يدويًا أو تفعيل التحديد التلقائي.',
                        style: GoogleFonts.cairo(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
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
