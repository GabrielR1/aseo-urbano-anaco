import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import 'incident_screen.dart';

class RouteActiveScreen extends StatefulWidget {
  final int jornadaId;
  final String? rutaNombre;
  final String? rutaZona;
  final String? rutaDescripcion;
  final String? vehiculoPlaca;
  final String? vehiculoModelo;
  final double distanciaInicialKm;
  final double distanciaEstimadaKm;

  const RouteActiveScreen({
    super.key,
    required this.jornadaId,
    this.rutaNombre,
    this.rutaZona,
    this.rutaDescripcion,
    this.vehiculoPlaca,
    this.vehiculoModelo,
    this.distanciaInicialKm = 0.0,
    this.distanciaEstimadaKm = 0.0,
  });

  @override
  State<RouteActiveScreen> createState() => _RouteActiveScreenState();
}

class _RouteActiveScreenState extends State<RouteActiveScreen> {
  final ApiService _apiService = ApiService();
  StreamSubscription<Position>? _positionSub;
  Timer? _elapsedTimer;

  Position? _currentPosition;
  Position? _lastRecordedPosition;
  DateTime? _lastSentAt;
  bool _isTracking = true;
  bool _sending = false;
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
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
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

      await _positionSub?.cancel();

      // Captura inicial inmediata para no esperar al primer movimiento.
      try {
        final initial = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 15),
          ),
        );
        await _onPositionUpdate(initial, forceSend: true);
      } catch (e) {
        debugPrint('Lectura inicial GPS pendiente: $e');
      }

      if (!mounted || !_isTracking) return;

      // Stream continuo en vivo: actualiza velocímetro y km con suavidad y menos batería.
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen(
        (pos) => _onPositionUpdate(pos),
        onError: (err) {
          debugPrint('Error en stream GPS: $err');
          if (mounted) {
            setState(() {
              _gpsWarning = 'Buscando mejor señal satelital...';
            });
          }
        },
      );
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

  Future<void> _onPositionUpdate(Position position, {bool forceSend = false}) async {
    if (!mounted || !_isTracking) return;

    double movedMeters = 0.0;
    if (_lastRecordedPosition != null) {
      movedMeters = Geolocator.distanceBetween(
        _lastRecordedPosition!.latitude,
        _lastRecordedPosition!.longitude,
        position.latitude,
        position.longitude,
      );
    }

    double deltaKm = 0.0;
    if (_lastRecordedPosition != null && movedMeters >= 5 && movedMeters < 5000) {
      deltaKm = movedMeters / 1000.0;
    }

    setState(() {
      _currentPosition = position;
      _totalDistanceKm += deltaKm;
      _gpsWarning = null;
    });

    final now = DateTime.now();
    final elapsedSinceSend = _lastSentAt == null ? 999 : now.difference(_lastSentAt!).inSeconds;
    final shouldSend = forceSend || _lastSentAt == null || elapsedSinceSend >= 8 || movedMeters >= 15;
    if (!shouldSend || _sending) return;

    _lastRecordedPosition = position;
    _lastSentAt = now;
    _sending = true;

    try {
      final speedKmh = (position.speed * 3.6).clamp(0.0, 160.0).toDouble();
      final success = await _apiService.sendLocation(
        widget.jornadaId,
        position.latitude,
        position.longitude,
        speedKmh: speedKmh,
        accuracy: position.accuracy,
      );

      if (_apiService.sessionExpired && mounted) {
        await _positionSub?.cancel();
        _elapsedTimer?.cancel();
        if (!mounted) return;
        await context.read<AuthProvider>().logout(
              notice: 'Tu sesión venció. Inicia sesión nuevamente.',
            );
        return;
      }

      if (success) {
        await _vaciarColaOffline();
      } else {
        _encolarPunto(position, speedKmh);
      }
    } finally {
      _sending = false;
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
        title: const Text('¿Salir de la pantalla?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          'Tu ruta seguirá abierta en el servidor, pero el GPS dejará de transmitirse hasta que vuelvas a entrar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Quedarme', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    return salir == true;
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _elapsedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);
    final themeProvider = context.read<ThemeProvider>();

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
    final detalleSectores = (widget.rutaDescripcion != null && widget.rutaDescripcion!.trim().isNotEmpty)
        ? widget.rutaDescripcion!.trim()
        : (widget.rutaZona ?? '').trim();

    final hasEstimado = widget.distanciaEstimadaKm > 0;
    final progreso = hasEstimado ? (_totalDistanceKm / widget.distanciaEstimadaKm).clamp(0.0, 1.0) : 0.0;
    final porcentaje = (progreso * 100).round();

    final Color statusColor;
    final String statusText;
    if (!_isTracking) {
      statusColor = const Color(0xFFDC2626);
      statusText = 'GPS detenido';
    } else if (_offlinePointsQueue.isNotEmpty) {
      statusColor = const Color(0xFFD97706);
      statusText = 'Sin señal • ${_offlinePointsQueue.length} por enviar';
    } else if (_currentPosition == null) {
      statusColor = const Color(0xFF2563EB);
      statusText = 'Buscando señal GPS...';
    } else {
      statusColor = colors.primary;
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
        appBar: AppBar(
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
                  style: TextStyle(fontSize: 12, color: muted),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
              onPressed: themeProvider.toggleTheme,
              tooltip: isDark ? 'Modo día' : 'Modo noche',
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Indicador único de estado GPS
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: statusColor.withValues(alpha: 0.55), width: 1.4),
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
                          style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w700, fontSize: 14),
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
                            style: TextStyle(color: colors.primary, fontWeight: FontWeight.w800),
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
                      color: isDark ? const Color(0x22F59E0B) : const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFD97706)),
                    ),
                    child: Text(
                      _gpsWarning!,
                      style: TextStyle(
                        color: isDark ? const Color(0xFFFCD34D) : const Color(0xFF92400E),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // Panel de telemetría con alto contraste + barra de progreso
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: colors.outline.withValues(alpha: isDark ? 0.5 : 0.9)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        speed,
                        style: TextStyle(
                          color: colors.primary,
                          fontSize: 64,
                          fontWeight: FontWeight.w900,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Km/h',
                        style: TextStyle(color: muted, fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 20),
                      Divider(color: theme.dividerColor, height: 1),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetric(context, '${_totalDistanceKm.toStringAsFixed(1)} km', 'Recorridos'),
                          ),
                          Container(width: 1, height: 34, color: theme.dividerColor),
                          Expanded(
                            child: _buildMetric(context, _formatElapsedTime(_secondsElapsed), 'Tiempo en ruta'),
                          ),
                        ],
                      ),
                      if (hasEstimado) ...[
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Progreso estimado',
                              style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${_totalDistanceKm.toStringAsFixed(1)} / ${widget.distanciaEstimadaKm.toStringAsFixed(1)} km ($porcentaje%)',
                              style: TextStyle(color: colors.onSurface, fontSize: 12.5, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: progreso,
                            minHeight: 8,
                            backgroundColor: colors.surfaceContainerHighest,
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                if (detalleSectores.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: colors.outline.withValues(alpha: isDark ? 0.4 : 0.85)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.map_outlined, size: 18, color: colors.secondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            detalleSectores,
                            style: TextStyle(color: colors.onSurface.withValues(alpha: 0.85), fontSize: 13, height: 1.35),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const Spacer(),

                ElevatedButton.icon(
                  icon: const Icon(Icons.warning_amber_rounded, size: 24),
                  label: const Text('Reportar novedad', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 58),
                    backgroundColor: const Color(0xFFDC2626),
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
                  icon: Icon(Icons.flag_rounded, size: 22, color: colors.onSurface),
                  label: Text(
                    'Finalizar ruta',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: colors.onSurface),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 58),
                    side: BorderSide(color: colors.outline, width: 1.6),
                    backgroundColor: colors.surface,
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

  Widget _buildMetric(BuildContext context, String value, String label) {
    final theme = Theme.of(context);
    final muted = theme.brightness == Brightness.dark ? const Color(0xFF94A3B8) : const Color(0xFF475569);
    return Column(
      children: [
        Text(value, style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w800, fontSize: 20)),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }

  void _confirmFinishJourney() {
    final tonController = TextEditingController();
    final colors = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Terminaste la ruta?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Se guardará el recorrido completado y se detendrá el GPS.'),
            const SizedBox(height: 14),
            TextField(
              controller: tonController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                labelText: 'Toneladas recolectadas (opcional)',
                hintText: 'Ej. 4.5',
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Seguir'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: colors.onPrimary,
            ),
            onPressed: () async {
              final toneladas = double.tryParse(tonController.text.trim().replaceAll(',', '.'));
              Navigator.pop(ctx);

              if (_offlinePointsQueue.isNotEmpty) {
                await _vaciarColaOffline();
              }
              final ok = await _apiService.finalizarJornada(widget.jornadaId, toneladas: toneladas);
              if (!mounted) return;
              if (_apiService.sessionExpired) {
                await _positionSub?.cancel();
                _elapsedTimer?.cancel();
                if (!mounted) return;
                await context.read<AuthProvider>().logout(
                      notice: 'Tu sesión venció. Inicia sesión nuevamente.',
                    );
                return;
              }
              if (!ok) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('No se pudo finalizar la ruta. Revisa tu conexión e intenta de nuevo.'),
                    backgroundColor: Colors.red.shade700,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              await _positionSub?.cancel();
              _elapsedTimer?.cancel();
              _isTracking = false;
              await _apiService.saveOfflineQueue(_offlinePointsQueue);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Finalizar', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    ).whenComplete(tonController.dispose);
  }
}
