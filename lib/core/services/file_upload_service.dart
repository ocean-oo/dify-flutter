import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'dart:convert';
import 'package:logging/logging.dart';

class UploadedFile {
  final String id;
  final String name;
  final int size;
  final String extension;
  final String mimeType;
  final String createdBy;
  final int createdAt;

  static const _documentExtensions = {
    'TXT',
    'MD',
    'MARKDOWN',
    'PDF',
    'HTML',
    'XLSX',
    'XLS',
    'DOCX',
    'CSV',
    'EML',
    'MSG',
    'PPTX',
    'PPT',
    'XML',
    'EPUB'
  };
  static const _imageExtensions = {'JPG', 'JPEG', 'PNG', 'GIF', 'WEBP', 'SVG'};
  static const _audioExtensions = {'MP3', 'M4A', 'WAV', 'WEBM', 'AMR'};
  static const _videoExtensions = {'MP4', 'MOV', 'MPEG', 'MPGA'};

  UploadedFile({
    required this.size,
    required this.extension,
    required this.mimeType,
    required this.createdBy,
    required this.createdAt,
    required this.id,
    required this.name,
  });

  String getFileType() {
    final ext = extension.toUpperCase();
    if (_documentExtensions.contains(ext)) return 'document';
    if (_imageExtensions.contains(ext)) return 'image';
    if (_audioExtensions.contains(ext)) return 'audio';
    if (_videoExtensions.contains(ext)) return 'video';
    return 'custom';
  }

  Map<String, dynamic> toJson() {
    return {
      'transfer_method': 'local_file',
      'upload_file_id': id,
      'type': getFileType()
    };
  }
}

class FileUploadService {
  static final _log = Logger('FileUploadService');
  final _client = http.Client();

  Future<UploadedFile> uploadFile(File file) async {
    _log.info('开始上传文件: ${file.path}');

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/files/upload'),
      );

      request.headers['Authorization'] = ApiConfig.headers['Authorization']!;

      request.files.add(await http.MultipartFile.fromPath(
        'file',
        file.path,
      ));

      request.fields['user'] = ApiConfig.defaultUserId;

      final response = await _client.send(request);
      final responseBody = await response.stream.bytesToString();
      _log.info('上传响应: $responseBody');

      if (response.statusCode == 201) {
        final data = json.decode(responseBody);
        return UploadedFile(
          id: data['id'],
          name: data['name'],
          size: data['size'],
          extension: data['extension'],
          mimeType: data['mime_type'],
          createdBy: data['created_by'],
          createdAt: data['created_at'],
        );
      } else {
        throw Exception('Failed to upload file: ${response.statusCode}');
      }
    } catch (e, stack) {
      _log.severe('文件上传失败', e, stack);
      rethrow;
    }
  }
}
