import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';

class IncidentScreen extends StatefulWidget {
  final int jornadaId;
  const IncidentScreen({super.key, required this.jornadaId});

  @override
  State<IncidentScreen> createState() => _IncidentScreenState();
}

class _IncidentScreenState extends State<IncidentScreen> {
  final _descController = TextEditingController();
  final ApiService _apiService = ApiService();
  Uint8List? _imageBytes;
  String _imageName = 'evidencia.jpg';
  bool _isSubmitting = false;

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
        maxWidth: 1600,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _imageName = picked.name.isEmpty ? 'evidencia.jpg' : picked.name;
      });
    } catch (e) {
      debugPrint('No se pudo abrir la cámara: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir la cámara del dispositivo.')),
        );
      }
    }
  }

  Future<Position?> _obtenerUbicacion() async {
    try {
      final servicioActivo = await Geolocator.isLocationServiceEnabled();
      if (!servicioActivo) return null;
      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }
      if (permiso == LocationPermission.denied || permiso == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (e) {
      debugPrint('No se pudo obtener la ubicación para la incidencia: $e');
      return null;
    }
  }

  Future<void> _submitIncident() async {
    final descripcion = _descController.text.trim();
    if (descripcion.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Describe brevemente la incidencia encontrada.')),
      );
      return;
    }
    if (_imageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Toma una foto como evidencia para continuar.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final posicion = await _obtenerUbicacion();
    if (!mounted) return;

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiService.baseUrl}/logistica/incidencias/'),
      );

      final token = await _apiService.getToken();
      if (token != null) {
        request.headers['Authorization'] = 'Token $token';
      }

      request.fields['jornada'] = widget.jornadaId.toString();
      request.fields['descripcion'] = descripcion;
      if (posicion != null) {
        request.fields['latitud'] = posicion.latitude.toStringAsFixed(6);
        request.fields['longitud'] = posicion.longitude.toStringAsFixed(6);
      }

      request.files.add(
        http.MultipartFile.fromBytes('foto', _imageBytes!, filename: _imageName),
      );

      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 201) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Incidencia reportada correctamente.'),
            backgroundColor: Color(0xFF16A34A),
          ),
        );
        Navigator.pop(context);
        return;
      }

      var mensaje = 'No se pudo enviar el reporte (${response.statusCode}).';
      try {
        final data = jsonDecode(response.body);
        if (data is Map && data['detail'] != null) {
          mensaje = data['detail'].toString();
        }
      } catch (_) {
        // La respuesta de error no era JSON: se conserva el mensaje genérico.
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mensaje), backgroundColor: Colors.redAccent.shade700),
        );
      }
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El servidor tardó demasiado en responder. Intenta de nuevo.')),
        );
      }
    } catch (e) {
      debugPrint('Error al enviar la incidencia: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al enviar: $e'), backgroundColor: Colors.redAccent.shade700),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportar Incidencia'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Registra la novedad con una fotografía y, si el GPS está disponible, se adjuntará la ubicación exacta.',
              style: TextStyle(fontSize: 13, height: 1.4, color: Colors.white70),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _descController,
              maxLines: 4,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Descripción del problema',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _isSubmitting ? null : _takePhoto,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 220,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                clipBehavior: Clip.antiAlias,
                child: _imageBytes == null
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.camera_alt_outlined, size: 44, color: Color(0xFF10B981)),
                          SizedBox(height: 8),
                          Text(
                            'Toca para tomar la foto de evidencia',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      )
                    : Image.memory(_imageBytes!, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(_imageBytes == null ? 'Tomar Foto' : 'Repetir Foto'),
              onPressed: _isSubmitting ? null : _takePhoto,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                foregroundColor: const Color(0xFF34D399),
                side: const BorderSide(color: Color(0xFF10B981)),
              ),
            ),
            const SizedBox(height: 32),
            _isSubmitting
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
                : ElevatedButton.icon(
                    onPressed: _submitIncident,
                    icon: const Icon(Icons.send),
                    label: const Text('Enviar Reporte', style: TextStyle(fontSize: 17)),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 56),
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
