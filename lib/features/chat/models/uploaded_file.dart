import 'dart:io';

class UploadedFile {
  final String id;
  final String name;
  final int size;
  final String extension;
  final String mimeType;
  final String createdBy;
  final int createdAt;
  final File? file;

  UploadedFile({
    required this.id,
    required this.name,
    required this.size,
    required this.extension,
    required this.mimeType,
    required this.createdBy,
    required this.createdAt,
    this.file,
  });

  Map<String, dynamic> toJson() {
    return {
      'transfer_method': 'local_file',
      'upload_file_id': id,
      'type': getFileType()
    };
  }

  factory UploadedFile.fromJson(Map<String, dynamic> json) {
    return UploadedFile(
      id: json['id'] as String,
      name: json['name'] as String,
      size: json['size'] as int,
      extension: json['extension'] as String,
      mimeType: json['mimeType'] as String,
      createdBy: json['createdBy'] as String,
      createdAt: json['createdAt'] as int,
    );
  }

  String getFileType() {
    final ext = extension.toLowerCase();
    if (_imageExtensions.contains(ext)) return 'image';
    if (_documentExtensions.contains(ext)) return 'document';
    if (_audioExtensions.contains(ext)) return 'audio';
    if (_videoExtensions.contains(ext)) return 'video';
    return 'custom';
  }

  static const _imageExtensions = {
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'svg',
  };

  static const _documentExtensions = {
    'txt', 'md', 'markdown', 'pdf', 'doc', 'docx',
    'xls', 'xlsx', 'ppt', 'pptx', 'html', 'htm',
  };

  static const _audioExtensions = {
    'mp3', 'wav', 'ogg', 'm4a', 'aac',
  };

  static const _videoExtensions = {
    'mp4', 'mov', 'avi', 'mkv', 'wmv',
  };
}
