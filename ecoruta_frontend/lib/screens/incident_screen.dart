import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
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
    final colors = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
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
                leading: Icon(Icons.camera_alt_rounded, color: colors.primary),
                title: const Text('Tomar foto con la cámara'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickPhoto(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_library_rounded, color: colors.secondary),
                title: const Text('Elegir de la galería'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickPhoto(ImageSource.gallery);
                },
              ),
              if (_imageBytes != null)
                ListTile(
                  leading: Icon(Icons.delete_outline, color: colors.error),
                  title: Text('Quitar foto', style: TextStyle(color: colors.error)),
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

      final streamed = await request.send().timeout(const Duration(seconds: 45));
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 401 && mounted) {
        await context.read<AuthProvider>().logout(
              notice: 'Tu sesión venció. Inicia sesión nuevamente.',
            );
        if (mounted) Navigator.popUntil(context, (route) => route.isFirst);
        return;
      }

      if (response.statusCode == 201) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Novedad enviada al centro de control.'),
            backgroundColor: Color(0xFF15803D),
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
            backgroundColor: Colors.red.shade700,
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
            backgroundColor: Colors.red.shade700,
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportar novedad', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '¿Qué ocurrió en la ruta?',
              style: TextStyle(color: colors.onSurface, fontSize: 16.5, fontWeight: FontWeight.w800),
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
                  selectedColor: isDark ? const Color(0x33EF4444) : const Color(0xFFFEE2E2),
                  backgroundColor: colors.surface,
                  side: BorderSide(color: selected ? const Color(0xFFDC2626) : colors.outline),
                  labelStyle: TextStyle(
                    color: selected
                        ? (isDark ? const Color(0xFFFECACA) : const Color(0xFFB91C1C))
                        : colors.onSurface,
                    fontWeight: FontWeight.w700,
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
              style: TextStyle(color: colors.onSurface, fontSize: 15),
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Detalle (puedes editarlo)',
                labelStyle: TextStyle(color: muted),
                filled: true,
                fillColor: colors.surface,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: colors.outline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: colors.primary, width: 1.6),
                ),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _isSubmitting ? null : _mostrarOpcionesFoto,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 190,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.outline),
                ),
                clipBehavior: Clip.antiAlias,
                child: _imageBytes == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo_rounded, size: 40, color: colors.primary),
                          const SizedBox(height: 10),
                          Text(
                            'Agregar foto (opcional)',
                            style: TextStyle(color: colors.onSurface, fontSize: 14.5, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Toca para usar cámara o galería',
                            style: TextStyle(color: muted, fontSize: 12.5),
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
                                color: Colors.black.withValues(alpha: 0.72),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.edit, size: 14, color: Colors.white),
                                  SizedBox(width: 5),
                                  Text(
                                    'Cambiar foto',
                                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
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
                  backgroundColor: const Color(0xFFDC2626),
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
