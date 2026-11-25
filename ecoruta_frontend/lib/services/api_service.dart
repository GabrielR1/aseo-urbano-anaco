import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  static String customUrl = '';

  static String _normalizeUrl(String raw) {
    var clean = raw.trim();
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    if (clean.isNotEmpty && !clean.endsWith('/api')) {
      clean = '$clean/api';
    }
    return clean;
  }

  static String get baseUrl {
    if (customUrl.isNotEmpty) {
      return _normalizeUrl(customUrl);
    }
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.windows) {
      return 'http://127.0.0.1:8000/api';
    }
    // Configura la URL HTTPS de tu servidor en Render desde el ícono de ajustes en el Login
    return 'http://192.168.1.112:8000/api';
  }

  final storage = const FlutterSecureStorage();

  Future<void> initServerUrl() async {
    final saved = await storage.read(key: 'custom_server_url');
    if (saved != null && saved.trim().isNotEmpty) {
      customUrl = _normalizeUrl(saved);
    }
  }

  Future<void> saveServerUrl(String newUrl) async {
    customUrl = _normalizeUrl(newUrl);
    await storage.write(key: 'custom_server_url', value: customUrl);
  }

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

  Future<List<dynamic>> getMisJornadas() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/logistica/mis_jornadas/'),
        headers: await getHeaders(),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['jornadas'] ?? [];
      }
      return [];
    } catch (e) {
      debugPrint('Error obteniendo jornadas: $e');
      return [];
    }
  }

  Future<bool> iniciarJornada(int jornadaId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/logistica/jornadas/$jornadaId/iniciar/'),
        headers: await getHeaders(),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error iniciando jornada: $e');
      return false;
    }
  }

  Future<bool> finalizarJornada(int jornadaId, {double? toneladas}) async {
    try {
      final payload = <String, dynamic>{};
      if (toneladas != null) {
        payload['toneladas_recolectadas'] = toneladas;
      }
      final response = await http.post(
        Uri.parse('$baseUrl/logistica/jornadas/$jornadaId/finalizar/'),
        headers: await getHeaders(),
        body: jsonEncode(payload),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error finalizando jornada: $e');
      return false;
    }
  }

  Future<bool> sendLocation(int jornadaId, double lat, double lng, {double? speedKmh, double? accuracy}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/logistica/puntos/'),
        headers: await getHeaders(),
        body: jsonEncode({
          'jornada': jornadaId,
          'latitud': lat.toStringAsFixed(6),
          'longitud': lng.toStringAsFixed(6),
          'velocidad_kmh': double.parse((speedKmh ?? 0.0).toStringAsFixed(1)),
          'precision_metros': double.parse((accuracy ?? 5.0).toStringAsFixed(1)),
        }),
      );
      return response.statusCode == 201;
    } catch (e) {
      debugPrint('Error sending location: $e');
      return false;
    }
  }

  Future<bool> sincronizarLote(List<Map<String, dynamic>> puntos) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/logistica/coordenadas/sincronizar_lote/'),
        headers: await getHeaders(),
        body: jsonEncode({'puntos': puntos}),
      );
      return response.statusCode == 201;
    } catch (e) {
      debugPrint('Error sincronizando lote offline: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getGamificacion() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/logistica/chofer/gamificacion/'),
        headers: await getHeaders(),
      );
      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      }
      return null;
    } catch (e) {
      debugPrint('Error al obtener gamificacion: $e');
      return null;
    }
  }

  Future<List<dynamic>> getNotificaciones() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/logistica/notificaciones/'),
        headers: await getHeaders(),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['notificaciones'] ?? [];
      }
      return [];
    } catch (e) {
      debugPrint('Error al obtener notificaciones: $e');
      return [];
    }
  }
}
