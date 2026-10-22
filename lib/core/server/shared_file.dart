import 'dart:math';
import 'package:mime/mime.dart';

class SharedFile {
  final String id;
  final String name;
  final int size;
  final String type;
  final String filePath;
  final DateTime uploadedAt;
  final bool ownedByApp;

  SharedFile({
    required this.id,
    required this.name,
    required this.size,
    required this.type,
    required this.filePath,
    this.ownedByApp = false,
    DateTime? uploadedAt,
  }) : uploadedAt = uploadedAt ?? DateTime.now();

  static String generateId() {
    final random = Random.secure();
    final values = List<int>.generate(16, (_) => random.nextInt(256)); // 16 bytes = 128 bits
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  factory SharedFile.fromPath({
    String? id,
    required String filePath,
    String? customName,
    int? customSize,
    String? customType,
    bool ownedByApp = false,
  }) {
    final name = customName ?? filePath.split('/').last.split('\\').last;
    final mimeType = customType ?? lookupMimeType(filePath) ?? 'application/octet-stream';
    return SharedFile(
      id: id ?? generateId(),
      name: name,
      size: customSize ?? 0,
      type: mimeType,
      filePath: filePath,
      ownedByApp: ownedByApp,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'size': size,
      'type': type,
      'uploadedAt': uploadedAt.toIso8601String(),
      'ownedByApp': ownedByApp,
    };
  }
}
