// import 'dart:convert';
// import 'package:http/http.dart' as http;
// import '../config/api_config.dart';

// class ApiService {
//   final http.Client _client = http.Client();
  

//   Future<dynamic> get(String endpoint) async {
//     try {
//       final settings = await ApiConfig.currentSettings;
//       final response = await _client.get(
//         Uri.parse(ApiConfig.baseUrl + endpoint),
//         headers: await ApiConfig.headers,
//       );
//       return _handleResponse(response);
//     } catch (e) {
//       throw Exception('Failed to perform GET request: $e');
//     }
//   }

//   Future<dynamic> post(String endpoint, {dynamic body}) async {
//     try {
//       final response = await _client.post(
//         Uri.parse(ApiConfig.baseUrl + endpoint),
//         headers: ApiConfig.headers,
//         body: json.encode(body),
//       );
//       return _handleResponse(response);
//     } catch (e) {
//       throw Exception('Failed to perform POST request: $e');
//     }
//   }

//   dynamic _handleResponse(http.Response response) {
//     if (response.statusCode >= 200 && response.statusCode < 300) {
//       return json.decode(response.body);
//     } else {
//       throw Exception('HTTP Error: ${response.statusCode}');
//     }
//   }
// }
