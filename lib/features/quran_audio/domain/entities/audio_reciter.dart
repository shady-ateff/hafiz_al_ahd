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
    String? arabicName,
    this.style,
    this.qirat,
    this.description,
    this.provider = 'quran_foundation',
    this.availableFormat = 'mp3',
  }) : arabicName = (name.trim().isEmpty && (arabicName == null || arabicName.trim().isEmpty))
            ? ''
            : _resolveEffectiveArabicName(id, name, arabicName) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Reciter ID cannot be empty');
    }
    if (name.trim().isEmpty && (arabicName == null || arabicName.trim().isEmpty)) {
      throw ArgumentError('Reciter must have at least an English or Arabic name');
    }
  }

  /// Canonical Arabic names map for standard reciters to ensure Arabic presentation.
  static const Map<String, String> kCanonicalArabicNames = {
    '1': 'عبد الباسط عبد الصمد (مجود)',
    '2': 'عبد الباسط عبد الصمد',
    '3': 'عبدالرحمن السديس',
    '4': 'أبو بكر الشاطري',
    '5': 'هاني الرفاعي',
    '6': 'محمود خليل الحصري',
    '7': 'مشاري راشد العفاسي',
    '8': 'علي جابر',
    '9': 'محمد صديق المنشاوي',
    '10': 'سعود الشريم',
    '11': 'محمد محمود الطبلاوي',
    '12': 'محمود خليل الحصري (معلم)',
    '97': 'ياسر الدوسري',
  };

  /// Heuristically resolves canonical Arabic name by English name keywords.
  static String? resolveArabicNameByName(String englishName) {
    final lower = englishName.toLowerCase();
    if (lower.contains('afasy') || lower.contains('afasi')) return 'مشاري راشد العفاسي';
    if (lower.contains('sudais')) return 'عبدالرحمن السديس';
    if (lower.contains('shuraim')) return 'سعود الشريم';
    if (lower.contains('husary') || lower.contains('hussary')) return 'محمود خليل الحصري';
    if (lower.contains('minshawi')) return 'محمد صديق المنشاوي';
    if (lower.contains('baset') || lower.contains('basit')) return 'عبد الباسط عبد الصمد';
    if (lower.contains('dussary') || lower.contains('dosari') || lower.contains('dossari')) return 'ياسر الدوسري';
    if (lower.contains('shatri')) return 'أبو بكر الشاطري';
    if (lower.contains('rifai')) return 'هاني الرفاعي';
    if (lower.contains('tablawi')) return 'محمد محمود الطبلاوي';
    if (lower.contains('jaber')) return 'علي جابر';
    if (lower.contains('ghamadi') || lower.contains('ghamdi')) return 'سعد الغامدي';
    if (lower.contains('muaiqly') || lower.contains('mueaqly') || lower.contains('maher')) return 'ماهر المعيقلي';
    if (lower.contains('ajmy') || lower.contains('ajmi')) return 'أحمد بن علي العجمي';
    if (lower.contains('basfar')) return 'عبدالله بصفر';
    if (lower.contains('qahtani')) return 'خالد القحطاني';
    if (lower.contains('fares') || lower.contains('abbad')) return 'فارس عباد';
    return null;
  }

  static String _resolveEffectiveArabicName(String id, String name, String? arabicName) {
    final trimmed = arabicName?.trim() ?? '';
    // 1. If arabicName contains genuine Arabic characters, honor it
    if (trimmed.isNotEmpty && RegExp(r'[\u0600-\u06FF]').hasMatch(trimmed)) {
      return trimmed;
    }
    // 2. Lookup in canonical map by ID
    final canonicalById = kCanonicalArabicNames[id];
    if (canonicalById != null && canonicalById.isNotEmpty) {
      return canonicalById;
    }
    // 3. Heuristic lookup by English name
    final canonicalByName = resolveArabicNameByName(name);
    if (canonicalByName != null && canonicalByName.isNotEmpty) {
      return canonicalByName;
    }
    // 4. Fallback to trimmed arabicName or name
    return trimmed.isNotEmpty ? trimmed : name.trim();
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
