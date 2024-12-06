import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:http_parser/http_parser.dart';
import 'package:logging/logging.dart';
import '../config/api_config.dart';
import './api_service.dart';
import '../../features/chat/models/uploaded_file.dart';

class FileUploadService {
  static final _log = Logger('FileUploadService');
  final _api = ApiService();

  Future<UploadedFile> uploadFile(File file) async {
    _log.info('开始上传文件: ${file.path}');
    final mimeType = lookupMimeType(file.path);
    final sendFile = await http.MultipartFile.fromPath(
      'file',
      file.path,
      contentType: mimeType != null ? MediaType.parse(mimeType) : null,
    );

    final response = await _api.streamRequest(
        'POST', ApiConfig.fileUpload, files: sendFile);
    final responseBody = await response.stream.bytesToString();
    final data = json.decode(responseBody);
    _log.info('上传响应: $data');
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
  }
}
