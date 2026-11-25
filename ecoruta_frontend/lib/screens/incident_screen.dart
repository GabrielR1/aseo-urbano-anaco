import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
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
  File? _image;
  bool _isSubmitting = false;

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null) {
      setState(() => _image = File(pickedFile.path));
    }
  }

  Future<void> _submitIncident() async {
    if (_descController.text.isEmpty || _image == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, ingresa descripción y toma una foto.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      Position position = await Geolocator.getCurrentPosition();
      
      var uri = Uri.parse('${ApiService.baseUrl}/logistica/incidencias/');
      var request = http.MultipartRequest('POST', uri);
      
      final token = await _apiService.getToken();
      if (token != null) {
        request.headers['Authorization'] = 'Token $token';
      }

      request.fields['jornada'] = widget.jornadaId.toString();
      request.fields['descripcion'] = _descController.text;
      request.fields['latitud'] = position.latitude.toStringAsFixed(6);
      request.fields['longitud'] = position.longitude.toStringAsFixed(6);
      
      var pic = await http.MultipartFile.fromPath('foto', _image!.path);
      request.files.add(pic);

      var response = await request.send();

      setState(() => _isSubmitting = false);

      if (response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Incidencia reportada correctamente')),
          );
          Navigator.pop(context);
        }
      } else {
        throw Exception('Failed to submit');
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al enviar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reportar Incidencia')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            TextField(
              controller: _descController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Descripción del problema',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            _image == null
                ? Container(
                    height: 200,
                    width: double.infinity,
                    color: Colors.grey[300],
                    child: const Icon(Icons.camera_alt, size: 50, color: Colors.grey),
                  )
                : Image.file(_image!, height: 200, width: double.infinity, fit: BoxFit.cover),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.camera),
              label: const Text('Tomar Foto'),
              onPressed: _takePhoto,
            ),
            const SizedBox(height: 48),
            _isSubmitting
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _submitIncident,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Enviar Reporte', style: TextStyle(fontSize: 18)),
                  ),
          ],
        ),
      ),
    );
  }
}
