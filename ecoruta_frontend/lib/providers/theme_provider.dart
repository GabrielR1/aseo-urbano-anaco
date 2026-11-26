import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ThemeProvider with ChangeNotifier {
  static const _storageKey = 'app_theme_mode';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // Modo claro de alto contraste por defecto (ideal bajo el sol y a juego con el panel web).
  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final saved = await _storage.read(key: _storageKey);
      if (saved == 'dark') {
        _themeMode = ThemeMode.dark;
        notifyListeners();
      } else if (saved == 'light') {
        _themeMode = ThemeMode.light;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('No se pudo leer la preferencia de tema: $e');
    }
  }

  Future<void> toggleTheme() async {
    _themeMode = isDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    try {
      await _storage.write(key: _storageKey, value: isDark ? 'dark' : 'light');
    } catch (e) {
      debugPrint('No se pudo guardar la preferencia de tema: $e');
    }
  }
}
