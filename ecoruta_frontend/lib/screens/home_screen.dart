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
  List<dynamic> _notificaciones = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final gam = await _apiService.getGamificacion();
    final jornadas = await _apiService.getMisJornadas();
    if (mounted) {
      setState(() {
        _gamificacion = gam;
        _notificaciones = jornadas;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);

    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        title: const Text('Aseo Urbano - Chofer', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Actualizar datos',
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: () => auth.logout(),
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
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Driver Eco Gamification Card
                    _buildDriverProfileCard(),
                    const SizedBox(height: 20),

                    // Active Assigned Journey Card
                    _buildAssignedJourneyCard(),
                    const SizedBox(height: 28),

                    // Primary Start Journey Button
                    ElevatedButton.icon(
                      icon: const Icon(Icons.navigation, size: 26),
                      label: const Text(
                        'Iniciar Jornada de Recolección',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 64),
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        elevation: 6,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () async {
                        if (_notificaciones.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('No tienes una jornada asignada. Solicita una asignación en el panel web.'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                          return;
                        }
                        final jornadaId = _notificaciones[0]['id'] as int;
                        await _apiService.iniciarJornada(jornadaId);
                        if (!context.mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RouteActiveScreen(jornadaId: jornadaId),
                          ),
                        ).then((_) => _loadData());
                      },
                    ),
                    const SizedBox(height: 24),

                    // Badges and Recognitions Section
                    _buildIncentivesSection(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildDriverProfileCard() {
    final nivel = _gamificacion?['nivel'] ?? '🥉 Bronce Eco';
    final puntos = _gamificacion?['puntos_totales'] ?? 0;
    final km = _gamificacion?['km_recorridos_totales'] ?? 0.0;
    final choferNombre = _gamificacion?['chofer'] ?? 'Conductor Activo';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x3310B981)),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 15, offset: Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    choferNombre,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const Text('Operador de Unidad Recolectora', style: TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0x3310B981),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF10B981)),
                ),
                child: Text(
                  nivel,
                  style: const TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white12),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('Puntos Eco', '$puntos pts', Icons.stars, Colors.amber),
              _buildStatItem('Distancia', '${km.toStringAsFixed(1)} Km', Icons.speed, Colors.cyan),
              _buildStatItem('Jornadas', '${_gamificacion?['jornadas_exitosas'] ?? 0}', Icons.done_all, Colors.greenAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color iconColor) {
    return Column(
      children: [
        Icon(icon, color: iconColor, size: 24),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ],
    );
  }

  Widget _buildAssignedJourneyCard() {
    if (_notificaciones.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.white54),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'No tienes jornadas pendientes asignadas en este momento.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    final notif = _notificaciones.first;
    final esEnCurso = notif['estado'] == 'en_curso';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: esEnCurso ? const Color(0xFF10B981) : Colors.blueAccent.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                esEnCurso ? 'Jornada en Curso (${notif['vehiculo_placa']})' : 'Jornada Asignada (${notif['vehiculo_placa']})',
                style: TextStyle(
                  color: esEnCurso ? const Color(0xFF34D399) : Colors.lightBlueAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              Text(notif['fecha'] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${notif['ruta_nombre'] ?? ''} • ${notif['vehiculo_modelo'] ?? ''}',
            style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildIncentivesSection() {
    final insignias = (_gamificacion?['insignias'] as List?) ?? [];
    if (insignias.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tus Reconocimientos y Bonos',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ...insignias.map((ins) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.workspace_premium, color: Colors.amber, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(ins['titulo'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(ins['descripcion'] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                  ),
                  if (ins['bono_usd'] != null && ins['bono_usd'] > 0)
                    Text('+\$${ins['bono_usd']}', style: const TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            )),
      ],
    );
  }
}
