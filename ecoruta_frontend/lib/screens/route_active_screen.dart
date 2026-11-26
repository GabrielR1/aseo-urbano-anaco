import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/api_service.dart';
import 'incident_screen.dart';

class RouteActiveScreen extends StatefulWidget {
  final int jornadaId;
  final String? rutaNombre;
  final String? vehiculoPlaca;
  final String? vehiculoModelo;
  final double distanciaInicialKm;

  const RouteActiveScreen({
    super.key,
    required this.jornadaId,
    this.rutaNombre,
    this.vehiculoPlaca,
    this.vehiculoModelo,
    this.distanciaInicialKm = 0.0,
  });

  @override
  State<RouteActiveScreen> createState() => _RouteActiveScreenState();
}

class _RouteActiveScreenState extends State<RouteActiveScreen> {
  final ApiService _apiService = ApiService();
  Timer? _gpsTimer;
  Timer? _elapsedTimer;

  Position? _currentPosition;
  Position? _lastRecordedPosition;
  bool _isTracking = true;
  bool _capturando = false;
  int _secondsElapsed = 0;
  double _totalDistanceKm = 0.0;
  String? _gpsWarning;
  bool _canOpenSettings = false;
  final List<Map<String, dynamic>> _offlinePointsQueue = [];

  @override
  void initState() {
    super.initState();
    _totalDistanceKm = widget.distanciaInicialKm;
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
        if (mounted) {
          setState(() {
            _isTracking = false;
            _gpsWarning = 'El GPS está desactivado. Actívalo para registrar tu ruta.';
            _canOpenSettings = false;
          });
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        if (mounted) {
          setState(() {
            _isTracking = false;
            _gpsWarning = 'Permite el acceso a tu ubicación para transmitir la ruta.';
            _canOpenSettings = false;
          });
        }
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _isTracking = false;
            _gpsWarning = 'El permiso de ubicación está bloqueado en ajustes.';
            _canOpenSettings = true;
          });
        }
        return;
      }

      if (!mounted) return;
      setState(() {
        _isTracking = true;
        _gpsWarning = null;
        _canOpenSettings = false;
      });

      await _captureAndSendGps();
      _gpsTimer?.cancel();
      _gpsTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
        await _captureAndSendGps();
      });
    } catch (e) {
      debugPrint('Error iniciando el rastreo GPS: $e');
      if (mounted) {
        setState(() {
          _isTracking = false;
          _gpsWarning = 'No se pudo activar el GPS. Toca reintentar.';
        });
      }
    }
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

      double deltaKm = 0.0;
      if (_lastRecordedPosition != null) {
        final meters = Geolocator.distanceBetween(
          _lastRecordedPosition!.latitude,
          _lastRecordedPosition!.longitude,
          position.latitude,
          position.longitude,
        );
        if (meters >= 5 && meters < 5000) {
          deltaKm = meters / 1000.0;
        }
      }
      _lastRecordedPosition = position;

      if (mounted) {
        setState(() {
          _currentPosition = position;
          _totalDistanceKm += deltaKm;
          _gpsWarning = null;
        });
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
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<bool> _confirmLeaveScreen() async {
    final salir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('¿Salir de la pantalla?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'Tu ruta seguirá abierta en el servidor, pero el GPS dejará de transmitirse hasta que vuelvas a entrar.',
          style: TextStyle(color: Colors.white70, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Quedarme', style: TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salir', style: TextStyle(color: Colors.white60)),
          ),
        ],
      ),
    );
    return salir == true;
  }

  @override
  void dispose() {
    _gpsTimer?.cancel();
    _elapsedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final speed = _currentPosition != null
        ? (_currentPosition!.speed * 3.6).clamp(0.0, 160.0).round().toString()
        : '0';
    final tituloRuta = (widget.rutaNombre != null && widget.rutaNombre!.isNotEmpty)
        ? widget.rutaNombre!
        : 'Ruta #${widget.jornadaId}';
    final subtituloVehiculo = [
      if (widget.vehiculoPlaca != null && widget.vehiculoPlaca!.isNotEmpty) widget.vehiculoPlaca!,
      if (widget.vehiculoModelo != null && widget.vehiculoModelo!.isNotEmpty) widget.vehiculoModelo!,
    ].join(' • ');

    final Color statusColor;
    final String statusText;
    if (!_isTracking) {
      statusColor = const Color(0xFFEF4444);
      statusText = 'GPS detenido';
    } else if (_offlinePointsQueue.isNotEmpty) {
      statusColor = const Color(0xFFF59E0B);
      statusText = 'Sin señal • ${_offlinePointsQueue.length} por enviar';
    } else if (_currentPosition == null) {
      statusColor = const Color(0xFF38BDF8);
      statusText = 'Buscando señal GPS...';
    } else {
      statusColor = const Color(0xFF10B981);
      statusText = 'En ruta • GPS conectado';
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _confirmLeaveScreen();
        if (leave && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF090D16),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F172A),
          foregroundColor: Colors.white,
          elevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tituloRuta,
                style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
                overflow: TextOverflow.ellipsis,
              ),
              if (subtituloVehiculo.isNotEmpty)
                Text(
                  subtituloVehiculo,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Indicador único de estado GPS (sin duplicados)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: statusColor.withValues(alpha: 0.45)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          statusText,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                      ),
                      if (!_isTracking)
                        TextButton(
                          onPressed: _canOpenSettings ? Geolocator.openAppSettings : _startTracking,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            _canOpenSettings ? 'Ajustes' : 'Reintentar',
                            style: const TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.w800),
                          ),
                        ),
                    ],
                  ),
                ),

                if (_gpsWarning != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0x22F59E0B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0x66F59E0B)),
                    ),
                    child: Text(
                      _gpsWarning!,
                      style: const TextStyle(color: Color(0xFFFCD34D), fontSize: 12.5),
                    ),
                  ),
                ],

                const SizedBox(height: 18),

                // Panel principal limpio con solo 3 datos útiles para el chofer
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF172133), Color(0xFF0F172A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0x3310B981)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        speed,
                        style: const TextStyle(
                          color: Color(0xFF34D399),
                          fontSize: 64,
                          fontWeight: FontWeight.w900,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Km/h',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 24),
                      const Divider(color: Colors.white12, height: 1),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetric('${_totalDistanceKm.toStringAsFixed(1)} km', 'Recorridos'),
                          ),
                          Container(width: 1, height: 34, color: Colors.white12),
                          Expanded(
                            child: _buildMetric(_formatElapsedTime(_secondsElapsed), 'Tiempo en ruta'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Botones táctiles grandes y claros
                ElevatedButton.icon(
                  icon: const Icon(Icons.warning_amber_rounded, size: 24),
                  label: const Text('Reportar novedad', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 58),
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => IncidentScreen(jornadaId: widget.jornadaId)),
                    );
                  },
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.flag_rounded, size: 22, color: Colors.white70),
                  label: const Text(
                    'Finalizar ruta',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 58),
                    side: const BorderSide(color: Color(0xFF334155), width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _confirmFinishJourney,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetric(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20)),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
      ],
    );
  }

  void _confirmFinishJourney() {
    final tonController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('¿Terminaste la ruta?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Se guardará el recorrido completado y se detendrá el GPS.',
              style: TextStyle(color: Colors.white70, fontSize: 13.5),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: tonController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                labelText: 'Toneladas recolectadas (opcional)',
                labelStyle: const TextStyle(color: Colors.white60, fontSize: 13),
                hintText: 'Ej. 4.5',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Seguir', style: TextStyle(color: Colors.white60)),
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
                    content: Text('No se pudo finalizar la ruta. Revisa tu conexión e intenta de nuevo.'),
                    backgroundColor: Colors.redAccent,
                    behavior: SnackBarBehavior.floating,
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
            child: const Text('Finalizar', style: TextStyle(color: Color(0xFF052E16), fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    ).whenComplete(tonController.dispose);
  }
}
