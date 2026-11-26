import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import 'fuel_screen.dart';
import 'incident_screen.dart';

class RouteActiveScreen extends StatefulWidget {
  final int jornadaId;
  final int? vehiculoId;
  final String? rutaNombre;
  final String? rutaZona;
  final String? rutaDescripcion;
  final List<List<double>> rutaWaypoints;
  final List<List<double>> trayectoriaInicial;
  final String? vehiculoPlaca;
  final String? vehiculoModelo;
  final double distanciaInicialKm;
  final double distanciaEstimadaKm;

  const RouteActiveScreen({
    super.key,
    required this.jornadaId,
    this.vehiculoId,
    this.rutaNombre,
    this.rutaZona,
    this.rutaDescripcion,
    this.rutaWaypoints = const [],
    this.trayectoriaInicial = const [],
    this.vehiculoPlaca,
    this.vehiculoModelo,
    this.distanciaInicialKm = 0.0,
    this.distanciaEstimadaKm = 0.0,
  });

  @override
  State<RouteActiveScreen> createState() => _RouteActiveScreenState();
}

class _RouteActiveScreenState extends State<RouteActiveScreen> {
  static const LatLng _anacoCenter = LatLng(9.4410, -64.4600);

  final ApiService _apiService = ApiService();
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionSub;
  Timer? _elapsedTimer;

  Position? _currentPosition;
  Position? _lastRecordedPosition;
  DateTime? _lastSentAt;
  bool _isTracking = true;
  bool _sending = false;
  bool _followUser = true;
  int _secondsElapsed = 0;
  double _totalDistanceKm = 0.0;
  String? _gpsWarning;
  bool _canOpenSettings = false;
  final List<Map<String, dynamic>> _offlinePointsQueue = [];
  late final List<LatLng> _routeWaypoints;
  late final List<LatLng> _traveledTrail;

  @override
  void initState() {
    super.initState();
    _totalDistanceKm = widget.distanciaInicialKm;
    _routeWaypoints = widget.rutaWaypoints.map((p) => LatLng(p[0], p[1])).toList();
    _traveledTrail = widget.trayectoriaInicial.map((p) => LatLng(p[0], p[1])).toList();
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

    final currentLatLng = LatLng(position.latitude, position.longitude);
    setState(() {
      _currentPosition = position;
      _totalDistanceKm += deltaKm;
      _gpsWarning = null;
      if (_traveledTrail.isEmpty || movedMeters >= 5) {
        _traveledTrail.add(currentLatLng);
        if (_traveledTrail.length > 400) {
          _traveledTrail.removeAt(0);
        }
      }
    });

    if (_followUser) {
      try {
        _mapController.move(currentLatLng, _mapController.camera.zoom);
      } catch (_) {}
    }

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

  void _centrarEnMi() {
    setState(() => _followUser = true);
    if (_currentPosition != null) {
      _mapController.move(LatLng(_currentPosition!.latitude, _currentPosition!.longitude), 16.5);
    } else if (_routeWaypoints.isNotEmpty) {
      _mapController.move(_routeWaypoints.first, 15.0);
    } else {
      _mapController.move(_anacoCenter, 14.5);
    }
  }

  void _verTodaLaRuta() {
    setState(() => _followUser = false);
    final puntos = <LatLng>[
      ..._routeWaypoints,
      ..._traveledTrail,
      if (_currentPosition != null) LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
    ];
    if (puntos.length >= 2) {
      _mapController.fitCamera(
        CameraFit.bounds(bounds: LatLngBounds.fromPoints(puntos), padding: const EdgeInsets.all(42)),
      );
    } else if (puntos.length == 1) {
      _mapController.move(puntos.first, 15.5);
    } else {
      _mapController.move(_anacoCenter, 14.0);
    }
  }

  Future<void> _abrirEnGoogleMaps() async {
    Uri uri;
    if (_routeWaypoints.isNotEmpty) {
      final dest = _routeWaypoints.last;
      final middle = _routeWaypoints.length > 2
          ? _routeWaypoints.sublist(1, _routeWaypoints.length - 1).take(8)
          : const Iterable<LatLng>.empty();
      final params = <String, String>{
        'api': '1',
        'destination': '${dest.latitude},${dest.longitude}',
        'travelmode': 'driving',
      };
      if (_currentPosition != null) {
        params['origin'] = '${_currentPosition!.latitude},${_currentPosition!.longitude}';
      } else if (_routeWaypoints.length > 1) {
        params['origin'] = '${_routeWaypoints.first.latitude},${_routeWaypoints.first.longitude}';
      }
      if (middle.isNotEmpty) {
        params['waypoints'] = middle.map((p) => '${p.latitude},${p.longitude}').join('|');
      }
      uri = Uri.https('www.google.com', '/maps/dir/', params);
    } else {
      final query = '${widget.rutaZona ?? widget.rutaNombre ?? 'Anaco'}, Anaco, Anzoátegui, Venezuela';
      uri = Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': query});
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir Google Maps en este dispositivo.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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

    final hasEstimado = widget.distanciaEstimadaKm > 0;
    final progreso = hasEstimado ? (_totalDistanceKm / widget.distanciaEstimadaKm).clamp(0.0, 1.0) : 0.0;
    final porcentaje = (progreso * 100).round();

    final LatLng initialCenter = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : (_routeWaypoints.isNotEmpty
            ? _routeWaypoints.first
            : (_traveledTrail.isNotEmpty ? _traveledTrail.last : _anacoCenter));

    final tileUrl = isDark
        ? 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
        : 'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';

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
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
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
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Barra compacta de estado GPS
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withValues(alpha: 0.55), width: 1.3),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          statusText,
                          style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w700, fontSize: 13.5),
                        ),
                      ),
                      if (!_isTracking)
                        TextButton(
                          onPressed: _canOpenSettings ? Geolocator.openAppSettings : _startTracking,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            _canOpenSettings ? 'Ajustes' : 'Reintentar',
                            style: TextStyle(color: colors.primary, fontWeight: FontWeight.w800, fontSize: 13),
                          ),
                        ),
                    ],
                  ),
                ),

                if (_gpsWarning != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0x22F59E0B) : const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFD97706)),
                    ),
                    child: Text(
                      _gpsWarning!,
                      style: TextStyle(
                        color: isDark ? const Color(0xFFFCD34D) : const Color(0xFF92400E),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 10),

                // Mapa en vivo con ruta trazada (azul), recorrido completado (verde) y camión actual
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: colors.outline.withValues(alpha: 0.7)),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Stack(
                        children: [
                          FlutterMap(
                            mapController: _mapController,
                            options: MapOptions(
                              initialCenter: initialCenter,
                              initialZoom: 15.0,
                              onPositionChanged: (_, hasGesture) {
                                if (hasGesture && _followUser) {
                                  setState(() => _followUser = false);
                                }
                              },
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: tileUrl,
                                userAgentPackageName: 'com.aseourbanoanaco.chofer',
                              ),
                              PolylineLayer(
                                polylines: [
                                  if (_routeWaypoints.length >= 2)
                                    Polyline(
                                      points: _routeWaypoints,
                                      color: const Color(0xAA1D4ED8),
                                      strokeWidth: 5.0,
                                    ),
                                  if (_traveledTrail.length >= 2)
                                    Polyline(
                                      points: _traveledTrail,
                                      color: const Color(0xFF15803D),
                                      strokeWidth: 5.5,
                                    ),
                                ],
                              ),
                              MarkerLayer(
                                markers: [
                                  // Puntos numerados de la ruta asignada
                                  for (int i = 0; i < _routeWaypoints.length; i++)
                                    Marker(
                                      point: _routeWaypoints[i],
                                      width: 26,
                                      height: 26,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: i == 0
                                              ? const Color(0xFF15803D)
                                              : (i == _routeWaypoints.length - 1
                                                  ? const Color(0xFFDC2626)
                                                  : const Color(0xFF1D4ED8)),
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.white, width: 2),
                                          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          '${i + 1}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ),
                                  // Posición actual del chofer
                                  if (_currentPosition != null)
                                    Marker(
                                      point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                                      width: 38,
                                      height: 38,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF10B981),
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.white, width: 3),
                                          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
                                        ),
                                        child: const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 19),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          // Leyenda discreta arriba a la izquierda
                          Positioned(
                            top: 10,
                            left: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: colors.surface.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: colors.outline.withValues(alpha: 0.6)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildLegendDot(const Color(0xFF1D4ED8), 'Ruta'),
                                  const SizedBox(width: 10),
                                  _buildLegendDot(const Color(0xFF15803D), 'Recorrido'),
                                ],
                              ),
                            ),
                          ),
                          // Controles flotantes del mapa a la derecha
                          Positioned(
                            right: 10,
                            bottom: 10,
                            child: Column(
                              children: [
                                _buildMapButton(
                                  context,
                                  icon: Icons.my_location_rounded,
                                  tooltip: 'Centrar en mi ubicación',
                                  active: _followUser,
                                  onTap: _centrarEnMi,
                                ),
                                const SizedBox(height: 8),
                                _buildMapButton(
                                  context,
                                  icon: Icons.route_rounded,
                                  tooltip: 'Ver ruta completa',
                                  onTap: _verTodaLaRuta,
                                ),
                                const SizedBox(height: 8),
                                _buildMapButton(
                                  context,
                                  icon: Icons.directions_rounded,
                                  tooltip: 'Abrir en Google Maps',
                                  highlight: true,
                                  onTap: _abrirEnGoogleMaps,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // Panel compacto de telemetría + progreso
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.outline.withValues(alpha: isDark ? 0.45 : 0.85)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: _buildMetric(context, '$speed km/h', 'Velocidad', accent: colors.primary)),
                          Container(width: 1, height: 28, color: theme.dividerColor),
                          Expanded(child: _buildMetric(context, '${_totalDistanceKm.toStringAsFixed(1)} km', 'Recorridos')),
                          Container(width: 1, height: 28, color: theme.dividerColor),
                          Expanded(child: _buildMetric(context, _formatElapsedTime(_secondsElapsed), 'Tiempo')),
                        ],
                      ),
                      if (hasEstimado) ...[
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Progreso estimado',
                              style: TextStyle(color: muted, fontSize: 11.5, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${_totalDistanceKm.toStringAsFixed(1)} / ${widget.distanciaEstimadaKm.toStringAsFixed(1)} km ($porcentaje%)',
                              style: TextStyle(color: colors.onSurface, fontSize: 11.5, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: progreso,
                            minHeight: 7,
                            backgroundColor: colors.surfaceContainerHighest,
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // Acciones rápidas en ruta
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.warning_amber_rounded, size: 21),
                        label: const Text('Novedad', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 52),
                          backgroundColor: const Color(0xFFDC2626),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => IncidentScreen(jornadaId: widget.jornadaId)),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.local_gas_station_rounded, size: 20, color: Color(0xFFD97706)),
                        label: Text(
                          'Combustible',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: colors.onSurface),
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 52),
                          side: BorderSide(color: colors.outline, width: 1.5),
                          backgroundColor: colors.surface,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FuelScreen(vehiculoIdInicial: widget.vehiculoId),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  icon: const Icon(Icons.flag_rounded, size: 22),
                  label: const Text(
                    'Finalizar ruta',
                    style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
                  ),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 54),
                    backgroundColor: colors.primary,
                    foregroundColor: colors.onPrimary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _buildMapButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool active = false,
    bool highlight = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    final bg = highlight
        ? const Color(0xFF1D4ED8)
        : (active ? colors.primary : colors.surface.withValues(alpha: 0.95));
    final fg = (highlight || active) ? Colors.white : colors.onSurface;
    return Material(
      color: bg,
      elevation: 3,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, color: fg, size: 22),
          ),
        ),
      ),
    );
  }

  Widget _buildMetric(BuildContext context, String value, String label, {Color? accent}) {
    final theme = Theme.of(context);
    final muted = theme.brightness == Brightness.dark ? const Color(0xFF94A3B8) : const Color(0xFF475569);
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(color: accent ?? theme.colorScheme.onSurface, fontWeight: FontWeight.w800, fontSize: 16.5),
        ),
        const SizedBox(height: 1),
        Text(label, style: TextStyle(color: muted, fontSize: 11, fontWeight: FontWeight.w600)),
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
