import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import 'route_active_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _apiService = ApiService();
  Map<String, dynamic>? _gamificacion;
  List<dynamic> _jornadas = [];
  bool _isLoading = true;
  int? _startingJornadaId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _apiService.getGamificacion(),
      _apiService.getMisJornadas(),
    ]);
    if (!mounted) return;
    if (_apiService.sessionExpired) {
      await context.read<AuthProvider>().logout(
            notice: 'Tu sesión venció. Inicia sesión nuevamente.',
          );
      return;
    }
    setState(() {
      _gamificacion = results[0] as Map<String, dynamic>?;
      _jornadas = results[1] as List<dynamic>;
      _isLoading = false;
    });
  }

  Future<void> _abrirJornada(Map<String, dynamic> jornada) async {
    final jornadaId = jornada['id'] as int;
    setState(() => _startingJornadaId = jornadaId);

    final ok = await _apiService.iniciarJornada(jornadaId);
    if (!mounted) return;
    setState(() => _startingJornadaId = null);

    if (_apiService.sessionExpired) {
      await context.read<AuthProvider>().logout(
            notice: 'Tu sesión venció. Inicia sesión nuevamente.',
          );
      return;
    }

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No se pudo iniciar la ruta. Revisa tu conexión e intenta de nuevo.'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RouteActiveScreen(
          jornadaId: jornadaId,
          rutaNombre: (jornada['ruta_nombre'] ?? 'Ruta #$jornadaId').toString(),
          rutaZona: (jornada['ruta_zona'] ?? '').toString(),
          rutaDescripcion: (jornada['ruta_descripcion'] ?? '').toString(),
          vehiculoPlaca: (jornada['vehiculo_placa'] ?? '').toString(),
          vehiculoModelo: (jornada['vehiculo_modelo'] ?? '').toString(),
          distanciaInicialKm: (jornada['distancia_real_km'] is num)
              ? (jornada['distancia_real_km'] as num).toDouble()
              : 0.0,
          distanciaEstimadaKm: (jornada['distancia_estimada_km'] is num)
              ? (jornada['distancia_estimada_km'] as num).toDouble()
              : 0.0,
        ),
      ),
    );
    if (mounted) _loadData();
  }

  Future<void> _confirmLogout(AuthProvider auth) async {
    final salir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cerrar sesión?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Tendrás que ingresar tu usuario y contraseña la próxima vez.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salir', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (salir == true) {
      await auth.logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final themeProvider = context.read<ThemeProvider>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final choferNombre = (_gamificacion?['chofer'] ?? 'Chofer').toString();
    final nivel = (_gamificacion?['nivel'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hola, $choferNombre',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              overflow: TextOverflow.ellipsis,
            ),
            if (nivel.isNotEmpty)
              Text(
                nivel,
                style: TextStyle(fontSize: 12, color: colors.primary, fontWeight: FontWeight.w700),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
            onPressed: themeProvider.toggleTheme,
            tooltip: isDark ? 'Modo día' : 'Modo noche',
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _isLoading ? null : _loadData,
            tooltip: 'Actualizar',
          ),
          IconButton(
            icon: Icon(Icons.logout_rounded, color: colors.error),
            onPressed: () => _confirmLogout(auth),
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colors.primary))
          : RefreshIndicator(
              onRefresh: _loadData,
              color: colors.primary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(18.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildPrimaryJourneySection(context),
                    const SizedBox(height: 16),
                    if (_jornadas.length > 1) ...[
                      _buildOtherJourneysSection(context),
                      const SizedBox(height: 16),
                    ],
                    _buildCompactStatsRow(context),
                    _buildIncentivesSection(context),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildPrimaryJourneySection(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);

    if (_jornadas.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.outline.withValues(alpha: isDark ? 0.4 : 0.85)),
        ),
        child: Column(
          children: [
            Icon(Icons.route_rounded, size: 42, color: muted),
            const SizedBox(height: 12),
            Text(
              'Sin rutas asignadas ahora',
              style: TextStyle(color: colors.onSurface, fontSize: 17, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Desliza hacia abajo para actualizar cuando te asignen una salida.',
              style: TextStyle(color: muted, fontSize: 13.5, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Revisar de nuevo', style: TextStyle(fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.primary,
                side: BorderSide(color: colors.primary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );
    }

    final principal = Map<String, dynamic>.from(_jornadas.first as Map);
    final jornadaId = principal['id'] as int;
    final esEnCurso = principal['estado'] == 'en_curso';
    final iniciando = _startingJornadaId == jornadaId;
    final placa = (principal['vehiculo_placa'] ?? '').toString();
    final modelo = (principal['vehiculo_modelo'] ?? '').toString();
    final rutaNombre = (principal['ruta_nombre'] ?? 'Ruta asignada').toString();
    final zona = (principal['ruta_zona'] ?? '').toString();
    final descripcion = (principal['ruta_descripcion'] ?? '').toString().trim();
    final fecha = (principal['fecha'] ?? '').toString();
    final distReal = (principal['distancia_real_km'] is num) ? (principal['distancia_real_km'] as num).toDouble() : 0.0;
    final distEst = (principal['distancia_estimada_km'] is num) ? (principal['distancia_estimada_km'] as num).toDouble() : 0.0;
    final progreso = (distEst > 0) ? (distReal / distEst).clamp(0.0, 1.0) : 0.0;

    final badgeBg = esEnCurso
        ? (isDark ? const Color(0x3310B981) : const Color(0xFFDCFCE7))
        : (isDark ? const Color(0x33F59E0B) : const Color(0xFFFEF3C7));
    final badgeFg = esEnCurso
        ? (isDark ? const Color(0xFF34D399) : const Color(0xFF15803D))
        : (isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309));
    final plateBg = isDark ? const Color(0x333B82F6) : const Color(0xFFDBEAFE);
    final plateFg = isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: esEnCurso ? colors.primary : colors.outline.withValues(alpha: isDark ? 0.5 : 0.9),
          width: esEnCurso ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(999)),
                child: Text(
                  esEnCurso ? 'EN CURSO' : 'LISTA PARA SALIR',
                  style: TextStyle(color: badgeFg, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4),
                ),
              ),
              Text(fecha, style: TextStyle(color: muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            rutaNombre,
            style: TextStyle(color: colors.onSurface, fontSize: 21, fontWeight: FontWeight.w800, height: 1.2),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: plateBg, borderRadius: BorderRadius.circular(6)),
                child: Text(
                  placa,
                  style: TextStyle(color: plateFg, fontWeight: FontWeight.w800, fontSize: 12.5, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  zona.isNotEmpty ? '$modelo • $zona' : modelo,
                  style: TextStyle(color: muted, fontSize: 13.5, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (descripcion.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.outline.withValues(alpha: 0.5)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.location_on_outlined, size: 16, color: colors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      descripcion,
                      style: TextStyle(color: colors.onSurface.withValues(alpha: 0.85), fontSize: 12.5, height: 1.35),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (distEst > 0) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  esEnCurso ? 'Avance del recorrido' : 'Distancia estimada',
                  style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                Text(
                  esEnCurso
                      ? '${distReal.toStringAsFixed(1)} / ${distEst.toStringAsFixed(1)} km'
                      : '${distEst.toStringAsFixed(1)} km',
                  style: TextStyle(color: colors.onSurface, fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            if (esEnCurso) ...[
              const SizedBox(height: 6),
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
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _startingJornadaId != null ? null : () => _abrirJornada(principal),
              icon: iniciando
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: colors.onPrimary),
                    )
                  : Icon(esEnCurso ? Icons.play_arrow_rounded : Icons.navigation_rounded, size: 24),
              label: Text(
                esEnCurso ? 'Continuar ruta' : 'Iniciar ruta',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtherJourneysSection(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);
    final extras = _jornadas.skip(1).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Otras rutas asignadas',
          style: TextStyle(color: muted, fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ...extras.map((raw) {
          final item = Map<String, dynamic>.from(raw as Map);
          final jId = item['id'] as int;
          final iniciando = _startingJornadaId == jId;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.outline.withValues(alpha: isDark ? 0.4 : 0.8)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (item['ruta_nombre'] ?? '').toString(),
                        style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w700, fontSize: 14.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${item['vehiculo_placa'] ?? ''} • ${item['fecha'] ?? ''}',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _startingJornadaId != null ? null : () => _abrirJornada(item),
                  child: iniciando
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text('Iniciar', style: TextStyle(color: colors.primary, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildCompactStatsRow(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final jornadas = _gamificacion?['jornadas_exitosas'] ?? 0;
    final kmRaw = _gamificacion?['km_recorridos_totales'];
    final km = (kmRaw is num) ? kmRaw.toDouble() : 0.0;
    final puntos = _gamificacion?['puntos_totales'] ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline.withValues(alpha: isDark ? 0.4 : 0.85)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildMiniStat(context, '$jornadas', 'Completadas'),
          Container(width: 1, height: 30, color: theme.dividerColor),
          _buildMiniStat(context, '${km.toStringAsFixed(1)} km', 'Recorridos'),
          Container(width: 1, height: 30, color: theme.dividerColor),
          _buildMiniStat(context, '$puntos', 'Puntos'),
        ],
      ),
    );
  }

  Widget _buildMiniStat(BuildContext context, String value, String label) {
    final theme = Theme.of(context);
    final muted = theme.brightness == Brightness.dark ? const Color(0xFF94A3B8) : const Color(0xFF475569);
    return Column(
      children: [
        Text(value, style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildIncentivesSection(BuildContext context) {
    final insignias = (_gamificacion?['insignias'] as List?) ?? [];
    if (insignias.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reconocimientos',
            style: TextStyle(color: muted, fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...insignias.map((ins) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.outline.withValues(alpha: isDark ? 0.4 : 0.85)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.workspace_premium_rounded, color: Color(0xFFD97706), size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (ins['titulo'] ?? '').toString(),
                            style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w700, fontSize: 13.5),
                          ),
                          Text(
                            (ins['descripcion'] ?? '').toString(),
                            style: TextStyle(color: muted, fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                    if (ins['bono_usd'] != null && (ins['bono_usd'] as num) > 0)
                      Text(
                        '+\$${ins['bono_usd']}',
                        style: TextStyle(color: colors.primary, fontWeight: FontWeight.w800, fontSize: 13.5),
                      ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
