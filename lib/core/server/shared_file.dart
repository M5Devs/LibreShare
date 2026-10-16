import 'package:mime/mime.dart';

class SharedFile {
  final String id;
  final String name;
  final int size;
  final String type;
  final String filePath;
  final DateTime uploadedAt;

  SharedFile({
    required this.id,
    required this.name,
    required this.size,
    required this.type,
    required this.filePath,
    DateTime? uploadedAt,
  }) : uploadedAt = uploadedAt ?? DateTime.now();

  factory SharedFile.fromPath({
    required String id,
    required String filePath,
    String? customName,
    int? customSize,
    String? customType,
  }) {
    final name = customName ?? filePath.split('/').last.split('\\').last;
    final mimeType = customType ?? lookupMimeType(filePath) ?? 'application/octet-stream';
    return SharedFile(
      id: id,
      name: name,
      size: customSize ?? 0,
      type: mimeType,
      filePath: filePath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'size': size,
      'type': type,
      'uploadedAt': uploadedAt.toIso8601String(),
    };
  }
}
