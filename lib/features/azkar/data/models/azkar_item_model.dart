import 'package:hafiz_al_ahd/features/azkar/domain/entities/azkar_item.dart';

class AzkarItemModel extends AzkarItem {
  const AzkarItemModel({
    required super.category,
    required super.text,
    required super.description,
    required super.reference,
    required super.count,
  });

  factory AzkarItemModel.fromJson(Map<String, dynamic> json) {
    return AzkarItemModel(
      category: json['category']?.toString() ?? '',
      text: json['content']?.toString() ?? '', // أحياناً ملفات الـ JSON بتسميها text أو content
      description: json['description']?.toString() ?? '',
      reference: json['reference']?.toString() ?? '',
      count: _parseCount(json['count']),
    );
  }

  // 👈 الصنفرة هنا: أمان 100% ضد أي داتا بايظة في الـ JSON
  static int _parseCount(dynamic countStr) {
    if (countStr == null) return 1;
    if (countStr is int) return countStr;
    
    final parsed = int.tryParse(countStr.toString().trim());
    return (parsed != null && parsed > 0) ? parsed : 1;
  }

  Map<String, dynamic> toJson() {
    return {
      'category': category,
      'content': text,
      'description': description,
      'reference': reference,
      'count': count.toString(),
    };
  }
}