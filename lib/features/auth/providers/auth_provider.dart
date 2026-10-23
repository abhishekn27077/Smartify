import 'package:flutter/material.dart';
import 'package:smartify/core/errors/failures.dart';
import 'package:smartify/features/auth/models/user_session_model.dart';
import 'package:smartify/features/auth/services/auth_service.dart';

/// SMARTIFY Authentication & Session State Provider
class AuthProvider extends ChangeNotifier {
  final AuthService _service;

  AuthProvider({AuthService? service}) : _service = service ?? AuthService();

  UserSessionModel? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  UserSessionModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  String get currentRole => _currentUser?.role ?? 'student';

  Future<void> initializeSession() async {
    _isLoading = true;
    notifyListeners();
    try {
      final session = await _service.getCurrentSession();
      if (session != null) {
        _currentUser = session;
      }
    } catch (e) {
      debugPrint('AuthProvider.initializeSession error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _currentUser =
          await _service.signIn(email: email.trim(), password: password);
      return true;
    } catch (e) {
      if (e is Failure) {
        _errorMessage = e.message;
      } else {
        _errorMessage = 'Invalid email or password.';
      }
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> register(
    String email,
    String password,
    String fullName, {
    String academicProgram = 'MCA',
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _currentUser = await _service.signUp(
        email: email.trim(),
        password: password,
        fullName: fullName.trim(),
        academicProgram: academicProgram,
      );
      return true;
    } catch (e) {
      _errorMessage = 'Registration failed: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _service.signOut();
    _currentUser = null;
    _errorMessage = null;
    notifyListeners();
  }
}
