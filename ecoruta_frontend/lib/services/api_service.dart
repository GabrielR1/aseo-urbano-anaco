import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ApiService {
  static const String defaultProductionUrl = 'https://aseo-urbano-anaco.onrender.com/api';
  static const String defaultLocalUrl = 'http://127.0.0.1:8000/api';

  static String customUrl = '';
  // Timeout amplio (55s) para tolerar el arranque en frío del plan gratuito de Render.
  static const Duration _timeout = Duration(seconds: 55);
  static const Duration _telemetryTimeout = Duration(seconds: 20);

  String? lastError;
  bool sessionExpired = false;

  static String _normalizeUrl(String raw) {
    var clean = raw.trim();
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    if (clean.isNotEmpty && !RegExp(r'^https?://', caseSensitive: false).hasMatch(clean)) {
      clean = 'https://$clean';
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
    return defaultProductionUrl;
  }

  static String get serverLabel {
    final url = baseUrl.toLowerCase();
    if (url.contains('onrender.com')) return 'Nube (Render)';
    if (url.contains('127.0.0.1') || url.contains('localhost')) return 'Local (PC)';
    return url.replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'/api$'), '');
  }

  final storage = const FlutterSecureStorage();

  Future<void> initServerUrl() async {
    try {
      final saved = await storage.read(key: 'custom_server_url');
      if (saved != null && saved.trim().isNotEmpty) {
        customUrl = _normalizeUrl(saved);
      }
    } catch (e) {
      debugPrint('No se pudo recuperar la URL del servidor: $e');
    }
  }

  Future<void> saveServerUrl(String newUrl) async {
    customUrl = _normalizeUrl(newUrl);
    await storage.write(key: 'custom_server_url', value: customUrl);
  }

  Future<void> resetServerUrl() async {
    customUrl = '';
    try {
      await storage.delete(key: 'custom_server_url');
    } catch (e) {
      debugPrint('No se pudo restablecer la URL del servidor: $e');
    }
  }

  Future<String?> getToken() async {
    try {
      return await storage.read(key: 'auth_token');
    } catch (e) {
      debugPrint('No se pudo leer el token: $e');
      return null;
    }
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
    lastError = null;
    sessionExpired = false;
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/login/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data is Map ? data['token'] : null;
        if (token is String && token.isNotEmpty) {
          await storage.write(key: 'auth_token', value: token);
          return true;
        }
        lastError = 'El servidor no devolvió un token válido.';
        return false;
      }
      if (response.statusCode == 400 || response.statusCode == 401) {
        lastError = 'Usuario o contraseña incorrectos.';
      } else {
        lastError = 'El servidor respondió con un error (${response.statusCode}).';
      }
      return false;
    } on TimeoutException {
      lastError = 'El servidor tardó demasiado en responder. Intenta de nuevo en unos segundos.';
      return false;
    } catch (e) {
      debugPrint('Error during login: $e');
      lastError = 'No se pudo conectar con el servidor. Revisa tu conexión a internet.';
      return false;
    }
  }

  Future<bool> requestPasswordReset(String email) async {
    lastError = null;
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/password-reset/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email.trim().toLowerCase()}),
          )
          .timeout(_timeout);
      if (response.statusCode == 200) {
        return true;
      }
      try {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is Map && data['detail'] != null) {
          lastError = data['detail'].toString();
          return false;
        }
      } catch (_) {}
      lastError = 'No se pudo enviar el correo de recuperación.';
      return false;
    } on TimeoutException {
      lastError = 'El servidor tardó demasiado en responder. Intenta nuevamente.';
      return false;
    } catch (e) {
      debugPrint('Error solicitando recuperación de contraseña: $e');
      lastError = 'No se pudo conectar con el servidor. Revisa tu conexión.';
      return false;
    }
  }

  Future<void> logout() async {
    sessionExpired = false;
    try {
      await storage.delete(key: 'auth_token');
    } catch (e) {
      debugPrint('No se pudo cerrar la sesión local: $e');
    }
  }

  Future<List<dynamic>> getMisJornadas() async {
    sessionExpired = false;
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/logistica/mis_jornadas/'),
            headers: await getHeaders(),
          )
          .timeout(_timeout);
      if (response.statusCode == 401) {
        sessionExpired = true;
        return [];
      }
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data is Map ? (data['jornadas'] ?? []) : [];
      }
      return [];
    } catch (e) {
      debugPrint('Error obteniendo jornadas: $e');
      return [];
    }
  }

  Future<bool> iniciarJornada(int jornadaId) async {
    sessionExpired = false;
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/logistica/jornadas/$jornadaId/iniciar/'),
            headers: await getHeaders(),
          )
          .timeout(_timeout);
      if (response.statusCode == 401) {
        sessionExpired = true;
        return false;
      }
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error iniciando jornada: $e');
      return false;
    }
  }

  Future<bool> finalizarJornada(int jornadaId, {double? toneladas}) async {
    lastError = null;
    sessionExpired = false;
    try {
      final payload = <String, dynamic>{};
      if (toneladas != null) {
        payload['toneladas_recolectadas'] = toneladas;
      }
      final response = await http
          .post(
            Uri.parse('$baseUrl/logistica/jornadas/$jornadaId/finalizar/'),
            headers: await getHeaders(),
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
      if (response.statusCode == 401) {
        sessionExpired = true;
        lastError = 'Tu sesión venció. Inicia sesión nuevamente.';
        return false;
      }
      if (response.statusCode == 200) {
        return true;
      }
      try {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is Map && data['detail'] != null) {
          final detail = data['detail'].toString();
          if (response.statusCode == 400 && detail.toLowerCase().contains('finalizada')) {
            return true;
          }
          lastError = detail;
          return false;
        }
      } catch (_) {}
      lastError = 'No se pudo finalizar la ruta (código ${response.statusCode}).';
      return false;
    } on TimeoutException {
      lastError = 'El servidor tardó demasiado en responder. Intenta nuevamente.';
      return false;
    } catch (e) {
      debugPrint('Error finalizando jornada: $e');
      lastError = 'No se pudo conectar con el servidor. Revisa tu conexión.';
      return false;
    }
  }

  /// Obtiene el trazado real calle por calle (OSRM gratuito, sin API key) para los waypoints de la ruta.
  Future<List<List<double>>> getStreetRoute(List<List<double>> waypoints) async {
    if (waypoints.length < 2) return const [];
    try {
      final coords = waypoints.take(25).map((p) => '${p[1]},${p[0]}').join(';');
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/$coords?overview=full&geometries=geojson',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return const [];
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map || data['code'] != 'Ok') return const [];
      final routes = data['routes'];
      if (routes is! List || routes.isEmpty) return const [];
      final geometry = routes.first['geometry'];
      final rawCoords = geometry is Map ? geometry['coordinates'] : null;
      if (rawCoords is! List) return const [];
      final out = <List<double>>[];
      for (final c in rawCoords) {
        if (c is List && c.length >= 2 && c[0] is num && c[1] is num) {
          out.add([(c[1] as num).toDouble(), (c[0] as num).toDouble()]);
        }
      }
      return out;
    } catch (e) {
      debugPrint('No se pudo calcular trazado por calles OSRM: $e');
      return const [];
    }
  }

  Future<bool> sendLocation(
    int jornadaId,
    double lat,
    double lng, {
    double? speedKmh,
    double? accuracy,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/logistica/puntos/'),
            headers: await getHeaders(),
            body: jsonEncode({
              'jornada': jornadaId,
              'latitud': lat.toStringAsFixed(6),
              'longitud': lng.toStringAsFixed(6),
              'velocidad_kmh': double.parse((speedKmh ?? 0.0).toStringAsFixed(1)),
              'precision_metros': double.parse((accuracy ?? 5.0).toStringAsFixed(1)),
            }),
          )
          .timeout(_telemetryTimeout);
      if (response.statusCode == 401) {
        sessionExpired = true;
        return false;
      }
      return response.statusCode == 201;
    } catch (e) {
      debugPrint('Error sending location: $e');
      return false;
    }
  }

  Future<bool> sincronizarLote(List<Map<String, dynamic>> puntos) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/logistica/coordenadas/sincronizar_lote/'),
            headers: await getHeaders(),
            body: jsonEncode({'puntos': puntos}),
          )
          .timeout(_timeout);
      if (response.statusCode == 401) {
        sessionExpired = true;
        return false;
      }
      return response.statusCode == 201;
    } catch (e) {
      debugPrint('Error sincronizando lote offline: $e');
      return false;
    }
  }

  /// Cola de puntos GPS pendientes de sincronizar, persistida en el dispositivo.
  Future<List<Map<String, dynamic>>> loadOfflineQueue() async {
    try {
      final raw = await storage.read(key: 'offline_gps_queue');
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (e) {
      debugPrint('No se pudo recuperar la cola offline: $e');
      return [];
    }
  }

  Future<void> saveOfflineQueue(List<Map<String, dynamic>> queue) async {
    try {
      if (queue.isEmpty) {
        await storage.delete(key: 'offline_gps_queue');
        return;
      }
      final recortada = queue.length > 2000 ? queue.sublist(queue.length - 2000) : queue;
      await storage.write(key: 'offline_gps_queue', value: jsonEncode(recortada));
    } catch (e) {
      debugPrint('No se pudo persistir la cola offline: $e');
    }
  }

  Future<Map<String, dynamic>?> getGamificacion() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/logistica/chofer/gamificacion/'),
            headers: await getHeaders(),
          )
          .timeout(_timeout);
      if (response.statusCode == 401) {
        sessionExpired = true;
        return null;
      }
      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      }
      return null;
    } catch (e) {
      debugPrint('Error al obtener gamificacion: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getVehiculosCombustible() async {
    sessionExpired = false;
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/logistica/combustible/'),
            headers: await getHeaders(),
          )
          .timeout(_timeout);
      if (response.statusCode == 401) {
        sessionExpired = true;
        return [];
      }
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final raw = data is Map ? (data['vehiculos'] as List? ?? []) : [];
        return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error obteniendo vehículos para combustible: $e');
      return [];
    }
  }

  Future<bool> registrarCombustible({
    required int vehiculoId,
    required double litros,
    double costoTotal = 0.0,
    int kilometrajeActual = 0,
    Uint8List? comprobanteBytes,
    String comprobanteName = 'comprobante.jpg',
  }) async {
    lastError = null;
    sessionExpired = false;
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/logistica/combustible/'),
      );
      final token = await getToken();
      if (token != null) {
        request.headers['Authorization'] = 'Token $token';
      }
      request.fields['vehiculo'] = vehiculoId.toString();
      request.fields['litros'] = litros.toStringAsFixed(2);
      request.fields['costo_total'] = costoTotal.toStringAsFixed(2);
      request.fields['kilometraje_actual'] = kilometrajeActual.toString();
      if (comprobanteBytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes('comprobante', comprobanteBytes, filename: comprobanteName),
        );
      }

      final streamed = await request.send().timeout(_timeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 401) {
        sessionExpired = true;
        return false;
      }
      if (response.statusCode == 201) {
        return true;
      }
      try {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is Map && data['detail'] != null) {
          lastError = data['detail'].toString();
        }
      } catch (_) {}
      lastError ??= 'No se pudo registrar el combustible (${response.statusCode}).';
      return false;
    } on TimeoutException {
      lastError = 'El servidor tardó en responder. Intenta de nuevo.';
      return false;
    } catch (e) {
      debugPrint('Error registrando combustible: $e');
      lastError = 'Sin conexión con el servidor. Intenta de nuevo.';
      return false;
    }
  }
}
