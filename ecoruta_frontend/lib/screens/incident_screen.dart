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
  static const List<String> _motivosRapidos = [
    'Vía obstruida o cerrada',
    'Falla mecánica en la unidad',
    'Contenedor lleno o desbordado',
    'Tráfico o desvío en el sector',
  ];

  final _descController = TextEditingController();
  final ApiService _apiService = ApiService();
  String? _motivoSeleccionado;
  Uint8List? _imageBytes;
  String _imageName = 'evidencia.jpg';
  bool _isSubmitting = false;

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
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
      debugPrint('No se pudo obtener la foto: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir la cámara o galería.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _mostrarOpcionesFoto() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded, color: Color(0xFF10B981)),
                title: const Text('Tomar foto con la cámara', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickPhoto(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: Color(0xFF60A5FA)),
                title: const Text('Elegir de la galería', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickPhoto(ImageSource.gallery);
                },
              ),
              if (_imageBytes != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Color(0xFFFCA5A5)),
                  title: const Text('Quitar foto', style: TextStyle(color: Color(0xFFFCA5A5))),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _imageBytes = null);
                  },
                ),
            ],
          ),
        ),
      ),
    );
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
        const SnackBar(
          content: Text('Elige un motivo rápido o escribe qué ocurrió.'),
          behavior: SnackBarBehavior.floating,
        ),
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

      if (_imageBytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes('foto', _imageBytes!, filename: _imageName),
        );
      }

      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 201) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Novedad enviada al centro de control.'),
            backgroundColor: Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
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
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(mensaje),
            backgroundColor: Colors.redAccent.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El servidor tardó en responder. Intenta de nuevo.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error al enviar la incidencia: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Sin conexión con el servidor. Intenta de nuevo.'),
            backgroundColor: Colors.redAccent.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        title: const Text('Reportar novedad', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '¿Qué ocurrió en la ruta?',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _motivosRapidos.map((motivo) {
                final selected = _motivoSeleccionado == motivo;
                return ChoiceChip(
                  label: Text(motivo),
                  selected: selected,
                  selectedColor: const Color(0x33EF4444),
                  backgroundColor: const Color(0xFF1E293B),
                  side: BorderSide(color: selected ? const Color(0xFFEF4444) : const Color(0xFF334155)),
                  labelStyle: TextStyle(
                    color: selected ? const Color(0xFFFECACA) : Colors.white70,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  onSelected: _isSubmitting
                      ? null
                      : (_) {
                          setState(() {
                            _motivoSeleccionado = motivo;
                            _descController.text = motivo;
                          });
                        },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descController,
              maxLines: 3,
              maxLength: 500,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Detalle (puedes editarlo)',
                labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                filled: true,
                fillColor: const Color(0xFF111827),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            // Único control para la foto (sin botón duplicado)
            InkWell(
              onTap: _isSubmitting ? null : _mostrarOpcionesFoto,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 190,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                ),
                clipBehavior: Clip.antiAlias,
                child: _imageBytes == null
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo_rounded, size: 40, color: Color(0xFF10B981)),
                          SizedBox(height: 10),
                          Text(
                            'Agregar foto (opcional)',
                            style: TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Toca para usar cámara o galería',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                          ),
                        ],
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(_imageBytes!, fit: BoxFit.cover),
                          Positioned(
                            right: 10,
                            bottom: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.edit, size: 14, color: Colors.white),
                                  SizedBox(width: 5),
                                  Text('Cambiar foto', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submitIncident,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(
                  _isSubmitting ? 'Enviando...' : 'Enviar reporte',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
