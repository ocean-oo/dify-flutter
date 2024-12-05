import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:http_parser/http_parser.dart';
import 'package:logging/logging.dart';
import '../config/api_config.dart';
import '../../features/chat/models/uploaded_file.dart';

class FileUploadService {
  static final _log = Logger('FileUploadService');
  final _client = http.Client();

  Future<UploadedFile> uploadFile(File file) async {
    _log.info('开始上传文件: ${file.path}');

    try {
      final settings = await ApiConfig.currentSettings;
      final baseUrl = settings['baseUrl'];
      final defaultUserId = settings['defaultUserId'];
      final headers = await ApiConfig.headers;

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/files/upload'),
      );

      request.headers.addAll(headers);

      final mimeType = lookupMimeType(file.path);

      request.files.add(await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: mimeType != null ? MediaType.parse(mimeType) : null,
      ));

      request.fields['user'] = defaultUserId!;

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
          filePath: file.path,
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
