import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class FuelScreen extends StatefulWidget {
  final int? vehiculoIdInicial;
  final String? vehiculoLabelInicial;

  const FuelScreen({
    super.key,
    this.vehiculoIdInicial,
    this.vehiculoLabelInicial,
  });

  @override
  State<FuelScreen> createState() => _FuelScreenState();
}

class _FuelScreenState extends State<FuelScreen> {
  static const List<int> _litrosRapidos = [20, 40, 60, 80, 100];

  final ApiService _apiService = ApiService();
  final _litrosController = TextEditingController();
  final _costoController = TextEditingController();
  final _kmController = TextEditingController();

  List<Map<String, dynamic>> _vehiculos = [];
  int? _vehiculoSeleccionado;
  Uint8List? _imageBytes;
  String _imageName = 'comprobante.jpg';
  bool _loadingVehiculos = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _vehiculoSeleccionado = widget.vehiculoIdInicial;
    _cargarVehiculos();
  }

  @override
  void dispose() {
    _litrosController.dispose();
    _costoController.dispose();
    _kmController.dispose();
    super.dispose();
  }

  Future<void> _cargarVehiculos() async {
    final lista = await _apiService.getVehiculosCombustible();
    if (!mounted) return;
    if (_apiService.sessionExpired) {
      await context.read<AuthProvider>().logout(
            notice: 'Tu sesión venció. Inicia sesión nuevamente.',
          );
      if (mounted) Navigator.popUntil(context, (route) => route.isFirst);
      return;
    }

    int? seleccionado = _vehiculoSeleccionado;
    final ids = lista.map((v) => v['id'] as int).toSet();
    if (seleccionado == null || !ids.contains(seleccionado)) {
      seleccionado = lista.isNotEmpty ? lista.first['id'] as int : null;
    }

    setState(() {
      _vehiculos = lista;
      _vehiculoSeleccionado = seleccionado;
      _loadingVehiculos = false;
    });
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
        _imageName = picked.name.isEmpty ? 'comprobante.jpg' : picked.name;
      });
    } catch (e) {
      debugPrint('No se pudo obtener foto del comprobante: $e');
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
                title: const Text('Tomar foto del recibo'),
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

  Future<void> _enviar() async {
    if (_vehiculoSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona la unidad a la que cargaste combustible.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final litros = double.tryParse(_litrosController.text.trim().replaceAll(',', '.'));
    if (litros == null || litros <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa una cantidad válida de litros (mayor a 0).'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final costoText = _costoController.text.trim().replaceAll(',', '.');
    final costo = costoText.isEmpty ? 0.0 : double.tryParse(costoText);
    if (costo == null || costo < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El costo total no es válido.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final kmText = _kmController.text.trim();
    final km = kmText.isEmpty ? 0 : int.tryParse(kmText);
    if (km == null || km < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El kilometraje debe ser un número entero positivo.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final ok = await _apiService.registrarCombustible(
      vehiculoId: _vehiculoSeleccionado!,
      litros: litros,
      costoTotal: costo,
      kilometrajeActual: km,
      comprobanteBytes: _imageBytes,
      comprobanteName: _imageName,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (_apiService.sessionExpired) {
      await context.read<AuthProvider>().logout(
            notice: 'Tu sesión venció. Inicia sesión nuevamente.',
          );
      if (mounted) Navigator.popUntil(context, (route) => route.isFirst);
      return;
    }

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Carga de ${litros.toStringAsFixed(1)} L registrada correctamente.'),
          backgroundColor: const Color(0xFF15803D),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_apiService.lastError ?? 'No se pudo registrar el combustible.'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
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
        title: const Text('Cargar combustible', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loadingVehiculos
          ? Center(child: CircularProgressIndicator(color: colors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Unidad',
                    style: TextStyle(color: muted, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<int>(
                    initialValue: _vehiculoSeleccionado,
                    isExpanded: true,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: colors.surface,
                      prefixIcon: Icon(Icons.local_shipping_outlined, color: colors.primary),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: colors.outline),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: colors.primary, width: 1.6),
                      ),
                    ),
                    items: _vehiculos
                        .map(
                          (v) => DropdownMenuItem<int>(
                            value: v['id'] as int,
                            child: Text(
                              '[${v['placa']}] ${v['modelo']}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _isSubmitting ? null : (val) => setState(() => _vehiculoSeleccionado = val),
                  ),
                  const SizedBox(height: 18),

                  Text(
                    'Litros cargados',
                    style: TextStyle(color: muted, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _litrosRapidos.map((cant) {
                      final active = _litrosController.text.trim() == '$cant';
                      return ChoiceChip(
                        label: Text('$cant L'),
                        selected: active,
                        selectedColor: isDark ? const Color(0x33D97706) : const Color(0xFFFEF3C7),
                        backgroundColor: colors.surface,
                        side: BorderSide(color: active ? const Color(0xFFD97706) : colors.outline),
                        labelStyle: TextStyle(
                          color: active
                              ? (isDark ? const Color(0xFFFCD34D) : const Color(0xFFB45309))
                              : colors.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                        onSelected: _isSubmitting
                            ? null
                            : (_) => setState(() => _litrosController.text = '$cant'),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _litrosController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(color: colors.onSurface, fontSize: 16, fontWeight: FontWeight.w600),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Cantidad exacta (Litros)',
                      hintText: 'Ej. 45.5',
                      prefixIcon: const Icon(Icons.local_gas_station_rounded, color: Color(0xFFD97706)),
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
                    ),
                  ),
                  const SizedBox(height: 14),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _costoController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: TextStyle(color: colors.onSurface, fontSize: 15),
                          decoration: InputDecoration(
                            labelText: 'Costo \$ (opcional)',
                            hintText: '0.00',
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
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _kmController,
                          keyboardType: TextInputType.number,
                          style: TextStyle(color: colors.onSurface, fontSize: 15),
                          decoration: InputDecoration(
                            labelText: 'Odómetro km (opc.)',
                            hintText: 'Ej. 12450',
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
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  InkWell(
                    onTap: _isSubmitting ? null : _mostrarOpcionesFoto,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      height: 140,
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
                                Icon(Icons.receipt_long_rounded, size: 34, color: colors.primary),
                                const SizedBox(height: 8),
                                Text(
                                  'Foto del comprobante (opcional)',
                                  style: TextStyle(color: colors.onSurface, fontSize: 14, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Toca para usar cámara o galería',
                                  style: TextStyle(color: muted, fontSize: 12),
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
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.72),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: const Text(
                                      'Cambiar foto',
                                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
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
                      onPressed: _isSubmitting ? null : _enviar,
                      icon: _isSubmitting
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: colors.onPrimary),
                            )
                          : const Icon(Icons.check_circle_outline_rounded),
                      label: Text(
                        _isSubmitting ? 'Guardando...' : 'Registrar combustible',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
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
