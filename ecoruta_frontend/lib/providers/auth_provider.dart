import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AuthProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  bool _isAuthenticated = false;
  bool _isLoading = true;
  String? _sessionNotice;

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get lastError => _apiService.lastError;
  String? get sessionNotice => _sessionNotice;

  AuthProvider() {
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    final token = await _apiService.getToken();
    _isAuthenticated = token != null;
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> login(String username, String password) async {
    _sessionNotice = null;
    final success = await _apiService.login(username, password);
    if (success) {
      _isAuthenticated = true;
      notifyListeners();
    }
    return success;
  }

  Future<void> logout({String? notice}) async {
    await _apiService.logout();
    _isAuthenticated = false;
    _sessionNotice = notice;
    notifyListeners();
  }

  void clearSessionNotice() {
    _sessionNotice = null;
  }
}
