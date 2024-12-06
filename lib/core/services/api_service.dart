import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import '../config/api_config.dart';

class ApiService {
  final http.Client _client = http.Client();
  static final _log = Logger('ApiService');

  Future<dynamic> request(
    String method,
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParams,
  }) async {
    try {
      final settings = await ApiConfig.currentSettings;
      final baseUrl = settings['baseUrl'];
      final defaultUserId = settings['defaultUserId'];

      var uri = Uri.parse('$baseUrl$endpoint');
      if (queryParams != null) {
        uri = uri
            .replace(queryParameters: {...queryParams, 'user': defaultUserId});
      }

      _log.info('Request to: $uri');
      late final http.Response response;

      switch (method) {
        case 'GET':
          response = await _client.get(
            uri,
            headers: await ApiConfig.headers,
          );
          break;
        case 'POST':
          final queryBody = {...?body, 'user': defaultUserId};
          _log.info('Request Body: $queryBody');
          response = await _client.post(
            uri,
            headers: await ApiConfig.headers,
            body: json.encode(queryBody),
          );
          break;
        case 'DELETE':
          final queryBody = {...?body, 'user': defaultUserId};
          _log.info('Request Body: $queryBody');
          response = await _client.delete(
            uri,
            headers: await ApiConfig.headers,
            body: json.encode(queryBody),
          );
          break;
        default:
          throw Exception('Unsupported HTTP method: $method');
      }

      return _handleResponse(response);
    } catch (e) {
      throw Exception('Failed to perform $method request: $e');
    }
  }

  Future<http.StreamedResponse> streamRequest(
    String method,
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParams,
    http.MultipartFile? files,
  }) async {
    try {
      final settings = await ApiConfig.currentSettings;
      final baseUrl = settings['baseUrl'];
      final defaultUserId = settings['defaultUserId'];

      var uri = Uri.parse('$baseUrl$endpoint');
      if (queryParams != null) {
        uri = uri
            .replace(queryParameters: {...queryParams, 'user': defaultUserId});
      }

      var request; // ignore: prefer_typing_uninitialized_variables
      if (files != null) {
        request = http.MultipartRequest(method, uri);
        request.files.add(files);
        request.fields['user'] = defaultUserId!;
      } else {
        request = http.Request(method, uri);
      }
      request.headers.addAll(await ApiConfig.headers);
      _log.info('Streaming request to: ${request.url}');
      if (body != null) {
        final queryBody = {...body, 'user': defaultUserId};
        request.body = json.encode(queryBody);
        _log.info('Request Body: ${request.body}');
      }

      final response = await _client.send(request);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      } else {
        final errorBody = await response.stream.transform(utf8.decoder).join();
        throw Exception('HTTP Error: $errorBody');
      }
    } catch (e) {
      throw Exception('Failed to perform streaming request: $e');
    }
  }

  dynamic _handleResponse(http.Response response) {
    _log.info('响应状态码: ${response.statusCode}');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = json.decode(response.body);
      _log.info('响应数据: $data');
      return data;
    } else {
      throw Exception('HTTP Error: ${response.body}');
    }
  }
}
