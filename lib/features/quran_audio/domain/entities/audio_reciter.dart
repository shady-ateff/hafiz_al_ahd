import 'package:equatable/equatable.dart';

/// Represents a Quran recitation reciter (Qari) supported by the Quran Audio subsystem.
class AudioReciter extends Equatable {
  /// Unique identifier (e.g., "7" for Mishari Alafasy, "6" for Al-Husary).
  final String id;

  /// English / international display name.
  final String name;

  /// Arabic display name when available.
  final String arabicName;

  /// Recitation style (e.g. "Murattal", "Mujawwad", "Muallim").
  final String? style;

  /// Qirat / Riwayah (e.g. "Hafs").
  final String? qirat;

  /// Optional biographical or descriptive note.
  final String? description;

  /// Originating provider identifier (e.g., "quran_foundation").
  final String provider;

  /// Available audio format (typically "mp3").
  final String availableFormat;

  AudioReciter({
    required this.id,
    required this.name,
    required this.arabicName,
    this.style,
    this.qirat,
    this.description,
    this.provider = 'quran_foundation',
    this.availableFormat = 'mp3',
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Reciter ID cannot be empty');
    }
    if (name.trim().isEmpty && arabicName.trim().isEmpty) {
      throw ArgumentError('Reciter must have at least an English or Arabic name');
    }
  }

  /// Preferred display name in Arabic if available, falling back to English.
  String get displayName => arabicName.trim().isNotEmpty ? arabicName : name;

  /// Default canonical reciters list ensuring immediate offline and fallback availability.
  static final List<AudioReciter> kDefaultReciters = [
    AudioReciter(
      id: '7',
      name: 'Mishari Rashid al-`Afasy',
      arabicName: 'مشاري راشد العفاسي',
      style: 'Murattal',
      qirat: 'Hafs',
    ),
    AudioReciter(
      id: '2',
      name: 'AbdulBaset AbdulSamad',
      arabicName: 'عبد الباسط عبد الصمد',
      style: 'Murattal',
      qirat: 'Hafs',
    ),
    AudioReciter(
      id: '6',
      name: 'Mahmoud Khalil Al-Husary',
      arabicName: 'محمود خليل الحصري',
      style: 'Murattal',
      qirat: 'Hafs',
    ),
    AudioReciter(
      id: '9',
      name: 'Mohamed Siddiq al-Minshawi',
      arabicName: 'محمد صديق المنشاوي',
      style: 'Murattal',
      qirat: 'Hafs',
    ),
    AudioReciter(
      id: '97',
      name: 'Yasser Ad Dussary',
      arabicName: 'ياسر الدوسري',
      style: 'Murattal',
      qirat: 'Hafs',
    ),
    AudioReciter(
      id: '10',
      name: "Sa'ud ash-Shuraim",
      arabicName: 'سعود الشريم',
      style: 'Murattal',
      qirat: 'Hafs',
    ),
    AudioReciter(
      id: '3',
      name: 'Abdur-Rahman as-Sudais',
      arabicName: 'عبدالرحمن السديس',
      style: 'Murattal',
      qirat: 'Hafs',
    ),
    AudioReciter(
      id: '4',
      name: 'Abu Bakr al-Shatri',
      arabicName: 'أبو بكر الشاطري',
      style: 'Murattal',
      qirat: 'Hafs',
    ),
    AudioReciter(
      id: '5',
      name: 'Hani ar-Rifai',
      arabicName: 'هاني الرفاعي',
      style: 'Murattal',
      qirat: 'Hafs',
    ),
  ];

  static final AudioReciter kDefaultReciter = kDefaultReciters.first;

  @override
  List<Object?> get props => [
        id,
        name,
        arabicName,
        style,
        qirat,
        description,
        provider,
        availableFormat,
      ];
}
