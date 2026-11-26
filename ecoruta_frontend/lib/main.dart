import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/api_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService().initServerUrl();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const EcoRutaApp(),
    ),
  );
}

class EcoRutaApp extends StatelessWidget {
  const EcoRutaApp({super.key});

  ThemeData _buildLightTheme() {
    const primaryGreen = Color(0xFF15803D);
    return ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      fontFamily: 'Roboto',
      scaffoldBackgroundColor: const Color(0xFFF1F5F9),
      colorScheme: const ColorScheme.light(
        primary: primaryGreen,
        onPrimary: Colors.white,
        secondary: Color(0xFF1D4ED8),
        onSecondary: Colors.white,
        surface: Colors.white,
        onSurface: Color(0xFF0F172A),
        surfaceContainerHighest: Color(0xFFE2E8F0),
        outline: Color(0xFFCBD5E1),
        error: Color(0xFFDC2626),
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF0F172A),
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.transparent,
      ),
      cardColor: Colors.white,
      dividerColor: const Color(0xFFE2E8F0),
    );
  }

  ThemeData _buildDarkTheme() {
    const primaryGreen = Color(0xFF10B981);
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: 'Roboto',
      scaffoldBackgroundColor: const Color(0xFF090D16),
      colorScheme: const ColorScheme.dark(
        primary: primaryGreen,
        onPrimary: Color(0xFF052E16),
        secondary: Color(0xFF60A5FA),
        onSecondary: Color(0xFF0F172A),
        surface: Color(0xFF111827),
        onSurface: Color(0xFFF8FAFC),
        surfaceContainerHighest: Color(0xFF1E293B),
        outline: Color(0xFF334155),
        error: Color(0xFFEF4444),
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.transparent,
      ),
      cardColor: const Color(0xFF111827),
      dividerColor: const Color(0xFF1E293B),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    return MaterialApp(
      title: 'Aseo Urbano Chofer',
      debugShowCheckedModeBanner: false,
      themeMode: themeProvider.themeMode,
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      home: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          if (auth.isLoading) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }
          if (auth.isAuthenticated) {
            return const HomeScreen();
          }
          return const LoginScreen();
        },
      ),
    );
  }
}
