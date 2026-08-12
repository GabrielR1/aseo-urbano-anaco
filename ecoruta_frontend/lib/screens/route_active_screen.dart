import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import 'incident_screen.dart';

class RouteActiveScreen extends StatefulWidget {
  final int jornadaId;
  const RouteActiveScreen({super.key, required this.jornadaId});

  @override
  State<RouteActiveScreen> createState() => _RouteActiveScreenState();
}

class _RouteActiveScreenState extends State<RouteActiveScreen> {
  final ApiService _apiService = ApiService();
  Timer? _timer;
  Position? _currentPosition;
  bool _isTracking = true;

  @override
  void initState() {
    super.initState();
    _startTracking();
  }

  Future<void> _startTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _isTracking = false);
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _isTracking = false);
        return;
      }
    }

    setState(() => _isTracking = true);

    // Update location every 15 seconds for this prototype
    _timer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      Position position = await Geolocator.getCurrentPosition();
      setState(() => _currentPosition = position);
      await _apiService.sendLocation(widget.jornadaId, position.latitude, position.longitude);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ruta en Curso'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.gps_fixed, size: 80, color: Colors.green),
              const SizedBox(height: 24),
              Text(
                _isTracking ? 'Registrando ubicación...' : 'Seguimiento de GPS pausado',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              if (_currentPosition != null)
                Text(
                  'Lat: ${_currentPosition!.latitude}\nLng: ${_currentPosition!.longitude}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
              const Spacer(),
              ElevatedButton.icon(
                icon: const Icon(Icons.warning),
                label: const Text('Reportar Incidencia', style: TextStyle(fontSize: 18)),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 60),
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => IncidentScreen(jornadaId: widget.jornadaId)),
                  );
                },
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.stop),
                label: const Text('Finalizar Jornada', style: TextStyle(fontSize: 18)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 60),
                ),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
