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
  Timer? _gpsTimer;
  Timer? _elapsedTimer;

  Position? _currentPosition;
  bool _isTracking = true;
  bool _isRestoringQueue = true;
  bool _capturando = false;
  int _secondsElapsed = 0;
  int _pointsSentCount = 0;
  final List<Map<String, dynamic>> _offlinePointsQueue = [];

  @override
  void initState() {
    super.initState();
    _startElapsedTimer();
    _inicializar();
  }

  Future<void> _inicializar() async {
    final pendientes = await _apiService.loadOfflineQueue();
    if (!mounted) return;
    setState(() {
      _offlinePointsQueue
        ..clear()
        ..addAll(pendientes);
      _isRestoringQueue = false;
    });
    await _startTracking();
  }

  void _startElapsedTimer() {
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _secondsElapsed++);
      }
    });
  }

  Future<void> _startTracking() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _isTracking = false);
        _mostrarAvisoUbicacion(
          'El GPS del teléfono está desactivado. Actívalo para transmitir la ruta.',
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        if (mounted) setState(() => _isTracking = false);
        _mostrarAvisoUbicacion('Se necesita permiso de ubicación para transmitir la ruta.');
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _isTracking = false);
        _mostrarAvisoUbicacion(
          'El permiso de ubicación fue bloqueado. Habilítalo desde los ajustes del teléfono.',
          abrirAjustes: true,
        );
        return;
      }

      if (!mounted) return;
      setState(() => _isTracking = true);

      await _captureAndSendGps();
      _gpsTimer?.cancel();
      _gpsTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
        await _captureAndSendGps();
      });
    } catch (e) {
      debugPrint('Error iniciando el rastreo GPS: $e');
      if (mounted) setState(() => _isTracking = false);
    }
  }

  void _mostrarAvisoUbicacion(String mensaje, {bool abrirAjustes = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: Colors.orange.shade800,
        action: abrirAjustes
            ? SnackBarAction(
                label: 'Ajustes',
                textColor: Colors.white,
                onPressed: Geolocator.openAppSettings,
              )
            : null,
      ),
    );
  }

  Future<void> _captureAndSendGps() async {
    if (!_isTracking || _capturando) return;
    _capturando = true;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );

      if (mounted) {
        setState(() => _currentPosition = position);
      }

      final speedKmh = (position.speed * 3.6).clamp(0.0, 160.0).toDouble();
      final success = await _apiService.sendLocation(
        widget.jornadaId,
        position.latitude,
        position.longitude,
        speedKmh: speedKmh,
        accuracy: position.accuracy,
      );

      if (success) {
        if (mounted) {
          setState(() => _pointsSentCount++);
        }
        await _vaciarColaOffline();
      } else {
        _encolarPunto(position, speedKmh);
      }
    } catch (e) {
      debugPrint('Error obteniendo coordenadas GPS: $e');
    } finally {
      _capturando = false;
    }
  }

  void _encolarPunto(Position position, double speedKmh) {
    _offlinePointsQueue.add({
      'jornada': widget.jornadaId,
      'latitud': position.latitude.toStringAsFixed(6),
      'longitud': position.longitude.toStringAsFixed(6),
      'velocidad_kmh': double.parse(speedKmh.toStringAsFixed(1)),
      'precision_metros': double.parse(position.accuracy.toStringAsFixed(1)),
      'timestamp': position.timestamp.toUtc().toIso8601String(),
    });
    _apiService.saveOfflineQueue(_offlinePointsQueue);
    if (mounted) setState(() {});
  }

  Future<void> _vaciarColaOffline() async {
    if (_offlinePointsQueue.isEmpty) return;
    final exito = await _apiService.sincronizarLote(List<Map<String, dynamic>>.from(_offlinePointsQueue));
    if (!exito) return;
    _offlinePointsQueue.clear();
    await _apiService.saveOfflineQueue(_offlinePointsQueue);
    if (mounted) setState(() {});
  }

  String _formatElapsedTime(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _gpsTimer?.cancel();
    _elapsedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final speed = _currentPosition != null ? (_currentPosition!.speed * 3.6).toStringAsFixed(1) : '0.0';
    final accuracy = _currentPosition != null
        ? '±${_currentPosition!.accuracy.toStringAsFixed(1)} m'
        : 'Buscando satélites...';

    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        title: Text('Jornada #${widget.jornadaId} en Curso'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              // Radar Status Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x3310B981)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: _isTracking ? const Color(0xFF10B981) : Colors.orange,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isTracking ? 'GPS Activo y Transmitiendo' : 'GPS Fuera de Línea',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ],
                    ),
                    Text(
                      _formatElapsedTime(_secondsElapsed),
                      style: const TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (_isRestoringQueue)
                const LinearProgressIndicator(color: Color(0xFF10B981))
              else if (_offlinePointsQueue.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0x33F59E0B),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFF59E0B)),
                  ),
                  child: Text(
                    '${_offlinePointsQueue.length} punto(s) GPS en cola. Se enviarán al recuperar la señal.',
                    style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 12),
                  ),
                ),
              const SizedBox(height: 20),

              // Telemetry Speedometer Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0x3310B981)),
                  boxShadow: const [
                    BoxShadow(color: Colors.black45, blurRadius: 20, offset: Offset(0, 8)),
                  ],
                ),
                child: Column(
                  children: [
                    const Icon(Icons.speed, size: 40, color: Color(0xFF10B981)),
                    const SizedBox(height: 10),
                    Text(
                      speed,
                      style: const TextStyle(color: Colors.white, fontSize: 52, fontWeight: FontWeight.w900),
                    ),
                    const Text('Km/h Velocidad en Ruta', style: TextStyle(color: Colors.white54, fontSize: 13)),
                    const SizedBox(height: 20),
                    const Divider(color: Colors.white12),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildTelemetryMini('Precisión Satelital', accuracy, Icons.satellite_alt),
                        _buildTelemetryMini('Puntos Emitidos', '$_pointsSentCount', Icons.cloud_upload),
                        if (_offlinePointsQueue.isNotEmpty)
                          _buildTelemetryMini('En Cola Offline', '${_offlinePointsQueue.length}', Icons.cloud_off, isWarning: true),
                      ],
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Report Incident Button
              ElevatedButton.icon(
                icon: const Icon(Icons.warning_amber_rounded, size: 24),
                label: const Text('Reportar Incidencia con Foto', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => IncidentScreen(jornadaId: widget.jornadaId)),
                  );
                },
              ),
              const SizedBox(height: 14),

              // Finish Journey Button
              OutlinedButton.icon(
                icon: const Icon(Icons.stop_circle_outlined, size: 24, color: Colors.white70),
                label: const Text('Finalizar Jornada de Trabajo', style: TextStyle(fontSize: 16, color: Colors.white)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                  side: const BorderSide(color: Colors.white24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () => _confirmFinishJourney(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTelemetryMini(String label, String value, IconData icon, {bool isWarning = false}) {
    return Column(
      children: [
        Icon(icon, size: 18, color: isWarning ? Colors.orangeAccent : const Color(0xFF34D399)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: isWarning ? Colors.orangeAccent : Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
      ],
    );
  }

  void _confirmFinishJourney() {
    final tonController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('¿Finalizar Jornada?', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Se detendrá el rastreo GPS y se registrará la culminación del recorrido en el servidor central.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: tonController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Toneladas recolectadas (opcional)',
                labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                hintText: 'Ej. 4.5',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Continuar en ruta', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            onPressed: () async {
              final toneladas = double.tryParse(tonController.text.trim().replaceAll(',', '.'));
              Navigator.pop(ctx);

              if (_offlinePointsQueue.isNotEmpty) {
                await _vaciarColaOffline();
              }
              final ok = await _apiService.finalizarJornada(widget.jornadaId, toneladas: toneladas);
              if (!mounted) return;
              if (!ok) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('No se pudo finalizar la jornada. Revisa tu conexión e intenta de nuevo.'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
                return;
              }
              _gpsTimer?.cancel();
              _elapsedTimer?.cancel();
              _isTracking = false;
              await _apiService.saveOfflineQueue(_offlinePointsQueue);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Sí, Finalizar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ).whenComplete(tonController.dispose);
  }
}
