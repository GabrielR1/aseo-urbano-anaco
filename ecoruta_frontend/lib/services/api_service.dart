import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  // Use 10.0.2.2 for Android Emulator, or your local network IP (e.g., 192.168.x.x) for physical device
  static const String baseUrl = 'http://10.0.2.2:8000/api';
  final storage = const FlutterSecureStorage();

  Future<String?> getToken() async {
    return await storage.read(key: 'auth_token');
  }

  Future<Map<String, String>> getHeaders() async {
    final token = await getToken();
    if (token != null) {
      return {
        'Content-Type': 'application/json',
        'Authorization': 'Token $token',
      };
    }
    return {'Content-Type': 'application/json'};
  }

  Future<bool> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await storage.write(key: 'auth_token', value: data['token']);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error during login: $e');
      return false;
    }
  }

  Future<void> logout() async {
    await storage.delete(key: 'auth_token');
  }

  Future<bool> sendLocation(int jornadaId, double lat, double lng) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/logistica/puntos/'),
        headers: await getHeaders(),
        body: jsonEncode({
          'jornada': jornadaId,
          'latitud': lat.toString(),
          'longitud': lng.toString()
        }),
      );
      return response.statusCode == 201;
    } catch (e) {
      debugPrint('Error sending location: $e');
      return false;
    }
  }
}
