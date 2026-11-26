import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
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
    if (mounted) {
      setState(() {
        _gamificacion = results[0] as Map<String, dynamic>?;
        _jornadas = results[1] as List<dynamic>;
        _isLoading = false;
      });
    }
  }

  Future<void> _abrirJornada(Map<String, dynamic> jornada) async {
    final jornadaId = jornada['id'] as int;
    setState(() => _startingJornadaId = jornadaId);

    final ok = await _apiService.iniciarJornada(jornadaId);
    if (!mounted) return;
    setState(() => _startingJornadaId = null);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No se pudo iniciar la ruta. Revisa tu conexión e intenta de nuevo.'),
          backgroundColor: Colors.redAccent.shade700,
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
          vehiculoPlaca: (jornada['vehiculo_placa'] ?? '').toString(),
          vehiculoModelo: (jornada['vehiculo_modelo'] ?? '').toString(),
          distanciaInicialKm: (jornada['distancia_real_km'] is num)
              ? (jornada['distancia_real_km'] as num).toDouble()
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
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('¿Cerrar sesión?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'Tendrás que ingresar tu usuario y contraseña la próxima vez.',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salir', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final choferNombre = (_gamificacion?['chofer'] ?? 'Chofer').toString();
    final nivel = (_gamificacion?['nivel'] ?? '').toString();

    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
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
                style: const TextStyle(fontSize: 12, color: Color(0xFF34D399), fontWeight: FontWeight.w600),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _isLoading ? null : _loadData,
            tooltip: 'Actualizar',
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Color(0xFFFCA5A5)),
            onPressed: () => _confirmLogout(auth),
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : RefreshIndicator(
              onRefresh: _loadData,
              color: const Color(0xFF10B981),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(18.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Protagonista: Tu ruta de hoy (con botón integrado, sin redundancias)
                    _buildPrimaryJourneySection(),
                    const SizedBox(height: 18),

                    // 2. Otras rutas asignadas (solo si hay más de una)
                    if (_jornadas.length > 1) ...[
                      _buildOtherJourneysSection(),
                      const SizedBox(height: 18),
                    ],

                    // 3. Resumen compacto del chofer
                    _buildCompactStatsRow(),

                    // 4. Bonos e insignias (solo si existen)
                    _buildIncentivesSection(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildPrimaryJourneySection() {
    if (_jornadas.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          children: [
            const Icon(Icons.route_rounded, size: 42, color: Color(0xFF475569)),
            const SizedBox(height: 12),
            const Text(
              'Sin rutas asignadas ahora',
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'Desliza hacia abajo para actualizar cuando te asignen una salida.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Revisar de nuevo'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF34D399),
                side: const BorderSide(color: Color(0xFF10B981)),
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
    final fecha = (principal['fecha'] ?? '').toString();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: esEnCurso
              ? const [Color(0xFF0F2922), Color(0xFF111827)]
              : const [Color(0xFF172133), Color(0xFF111827)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: esEnCurso ? const Color(0xFF10B981) : const Color(0xFF334155),
          width: esEnCurso ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: esEnCurso
                      ? const Color(0xFF10B981).withValues(alpha: 0.2)
                      : const Color(0xFFF59E0B).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  esEnCurso ? 'EN CURSO' : 'LISTA PARA SALIR',
                  style: TextStyle(
                    color: esEnCurso ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Text(fecha, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5)),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            rutaNombre,
            style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800, height: 1.2),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1D4ED8).withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  placa,
                  style: const TextStyle(
                    color: Color(0xFF93C5FD),
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  zona.isNotEmpty ? '$modelo • $zona' : modelo,
                  style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _startingJornadaId != null ? null : () => _abrirJornada(principal),
              icon: iniciando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF052E16)),
                    )
                  : Icon(esEnCurso ? Icons.play_arrow_rounded : Icons.navigation_rounded, size: 24),
              label: Text(
                esEnCurso ? 'Continuar ruta' : 'Iniciar ruta',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: const Color(0xFF052E16),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtherJourneysSection() {
    final extras = _jornadas.skip(1).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Otras rutas asignadas',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w700),
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
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (item['ruta_nombre'] ?? '').toString(),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${item['vehiculo_placa'] ?? ''} • ${item['fecha'] ?? ''}',
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _startingJornadaId != null ? null : () => _abrirJornada(item),
                  child: iniciando
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Iniciar', style: TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildCompactStatsRow() {
    final jornadas = _gamificacion?['jornadas_exitosas'] ?? 0;
    final kmRaw = _gamificacion?['km_recorridos_totales'];
    final km = (kmRaw is num) ? kmRaw.toDouble() : 0.0;
    final puntos = _gamificacion?['puntos_totales'] ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildMiniStat('$jornadas', 'Completadas'),
          Container(width: 1, height: 30, color: Colors.white12),
          _buildMiniStat('${km.toStringAsFixed(1)} km', 'Recorridos'),
          Container(width: 1, height: 30, color: Colors.white12),
          _buildMiniStat('$puntos', 'Puntos'),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5)),
      ],
    );
  }

  Widget _buildIncentivesSection() {
    final insignias = (_gamificacion?['insignias'] as List?) ?? [];
    if (insignias.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Reconocimientos',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...insignias.map((ins) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.workspace_premium_rounded, color: Colors.amber, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (ins['titulo'] ?? '').toString(),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5),
                          ),
                          Text(
                            (ins['descripcion'] ?? '').toString(),
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                    if (ins['bono_usd'] != null && (ins['bono_usd'] as num) > 0)
                      Text(
                        '+\$${ins['bono_usd']}',
                        style: const TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.w800, fontSize: 13.5),
                      ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
