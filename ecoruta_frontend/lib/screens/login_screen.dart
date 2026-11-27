import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  Timer? _slowHintTimer;
  bool _isLoading = false;
  bool _showSlowServerHint = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final notice = auth.sessionNotice;
      if (notice != null && notice.isNotEmpty) {
        auth.clearSessionNotice();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(notice),
            backgroundColor: Colors.orange.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _slowHintTimer?.cancel();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final user = _usernameController.text.trim();
    final pass = _passwordController.text.trim();

    if (user.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Ingresa tu usuario y contraseña para continuar.'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _showSlowServerHint = false;
    });
    _slowHintTimer?.cancel();
    _slowHintTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isLoading) {
        setState(() => _showSlowServerHint = true);
      }
    });

    final auth = context.read<AuthProvider>();
    final success = await auth.login(user, pass);
    _slowHintTimer?.cancel();

    if (mounted) {
      setState(() {
        _isLoading = false;
        _showSlowServerHint = false;
      });
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(auth.lastError ?? 'Usuario o contraseña incorrectos.'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _openPasswordResetDialog() async {
    String emailValue = '';
    final colors = Theme.of(context).colorScheme;
    final submittedEmail = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recuperar contraseña', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ingresa el correo registrado en tu cuenta y te enviaremos un enlace para crear una nueva contraseña.',
              style: TextStyle(fontSize: 13.5),
            ),
            const SizedBox(height: 14),
            TextFormField(
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              onChanged: (v) => emailValue = v,
              decoration: InputDecoration(
                labelText: 'Correo electrónico',
                hintText: 'tucorreo@gmail.com',
                prefixIcon: Icon(Icons.email_outlined, color: colors.primary),
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: colors.onPrimary,
            ),
            onPressed: () => Navigator.of(ctx).pop(emailValue.trim()),
            child: const Text('Enviar enlace', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (!mounted || submittedEmail == null || submittedEmail.isEmpty) return;

    final api = ApiService();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Enviando enlace de recuperación...'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );

    final ok = await api.requestPasswordReset(submittedEmail);
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Si el correo está registrado, te enviamos un enlace para restablecer tu contraseña.'
              : (api.lastError ?? 'No se pudo enviar el correo de recuperación.'),
        ),
        backgroundColor: ok ? const Color(0xFF15803D) : Colors.red.shade700,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openServerConfig() async {
    String urlValue = ApiService.baseUrl;
    final colors = Theme.of(context).colorScheme;
    final newUrl = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.cloud_outlined, color: colors.primary, size: 22),
              const SizedBox(width: 8),
              const Text('Conexión al servidor', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Elige un servidor o escribe una dirección:',
                style: TextStyle(color: colors.onSurface.withValues(alpha: 0.7), fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    label: const Text('Nube (Render)', style: TextStyle(fontSize: 12)),
                    onPressed: () => setDialogState(() => urlValue = ApiService.defaultProductionUrl),
                  ),
                  ActionChip(
                    label: const Text('Local (PC)', style: TextStyle(fontSize: 12)),
                    onPressed: () => setDialogState(() => urlValue = ApiService.defaultLocalUrl),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: ValueKey(urlValue),
                initialValue: urlValue,
                onChanged: (v) => urlValue = v,
                style: const TextStyle(fontSize: 13.5),
                decoration: InputDecoration(
                  filled: true,
                  hintText: ApiService.defaultProductionUrl,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
              ),
              onPressed: () => Navigator.of(ctx).pop(urlValue.trim()),
              child: const Text('Guardar', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
    if (!mounted || newUrl == null || newUrl.isEmpty) return;
    await ApiService().saveServerUrl(newUrl);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Servidor configurado: ${ApiService.serverLabel}'),
        backgroundColor: const Color(0xFF15803D),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final themeProvider = context.read<ThemeProvider>();
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);
    final inputFill = isDark ? const Color(0xFF090D16) : const Color(0xFFF8FAFC);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 8,
              right: 8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, color: muted),
                    tooltip: isDark ? 'Modo día' : 'Modo noche',
                    onPressed: themeProvider.toggleTheme,
                  ),
                  IconButton(
                    icon: Icon(Icons.tune_rounded, color: muted),
                    tooltip: 'Cambiar servidor',
                    onPressed: _openServerConfig,
                  ),
                ],
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFCBD5E1),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/images/logo_institucional.png',
                          height: 82,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'App para Choferes',
                        style: TextStyle(fontSize: 15, color: muted, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 22),
                      Container(
                        padding: const EdgeInsets.all(22.0),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: colors.outline.withValues(alpha: isDark ? 0.4 : 0.85)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _usernameController,
                              style: TextStyle(color: colors.onSurface, fontSize: 16, fontWeight: FontWeight.w500),
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.username],
                              decoration: InputDecoration(
                                labelText: 'Usuario',
                                labelStyle: TextStyle(color: muted),
                                prefixIcon: Icon(Icons.person_outline, color: colors.primary),
                                filled: true,
                                fillColor: inputFill,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: colors.outline),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: colors.primary, width: 1.8),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              style: TextStyle(color: colors.onSurface, fontSize: 16, fontWeight: FontWeight.w500),
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.password],
                              onSubmitted: (_) {
                                if (!_isLoading) _login();
                              },
                              decoration: InputDecoration(
                                labelText: 'Contraseña',
                                labelStyle: TextStyle(color: muted),
                                prefixIcon: Icon(Icons.lock_outline, color: colors.primary),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                    color: muted,
                                  ),
                                  onPressed: () {
                                    setState(() => _obscurePassword = !_obscurePassword);
                                  },
                                ),
                                filled: true,
                                fillColor: inputFill,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: colors.outline),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: colors.primary, width: 1.8),
                                ),
                              ),
                            ),
                            const SizedBox(height: 22),
                            SizedBox(
                              height: 54,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: colors.primary,
                                  foregroundColor: colors.onPrimary,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: _isLoading
                                    ? SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.6,
                                          color: colors.onPrimary,
                                        ),
                                      )
                                    : const Text(
                                        'Entrar',
                                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _isLoading ? null : _openPasswordResetDialog,
                              child: Text(
                                '¿Olvidaste tu contraseña?',
                                style: TextStyle(
                                  color: colors.primary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (_showSlowServerHint) ...[
                              const SizedBox(height: 12),
                              Text(
                                'Conectando con el servidor, esto puede tardar unos segundos...',
                                style: TextStyle(color: muted, fontSize: 12.5),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: _openServerConfig,
                        borderRadius: BorderRadius.circular(999),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.cloud_done_outlined, size: 15, color: muted),
                              const SizedBox(width: 6),
                              Text(
                                'Servidor: ${ApiService.serverLabel}',
                                style: TextStyle(color: muted, fontSize: 12.5, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
