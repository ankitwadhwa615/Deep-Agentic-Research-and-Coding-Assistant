import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../services/api_client.dart';

class AuthController extends ChangeNotifier {
  AuthController(this._api) {
    _restore();
  }
  final ApiClient _api;
  bool loading = true, submitting = false;
  String? token;
  UserProfile? user;
  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('access_token');
    final raw = prefs.getString('user');
    if (saved != null && raw != null) {
      try {
        token = saved;
        user = UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        user = await _api.me(saved);
        await _save();
      } catch (_) {
        await prefs.remove('access_token');
        await prefs.remove('user');
        token = null;
        user = null;
      }
    }
    loading = false;
    notifyListeners();
  }

  Future<String?> login(String email, String password) =>
      _authenticate(() => _api.login(email, password));
  Future<String?> register(String name, String email, String password) =>
      _authenticate(() => _api.register(name, email, password));
  Future<String?> forgotPassword(String email, String password) async {
    try {
      await _api.forgotPassword(email, password);
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not reach the agent service. Check the server address.';
    }
  }

  Future<String?> _authenticate(Future<AuthResult> Function() call) async {
    submitting = true;
    notifyListeners();
    try {
      final result = await call();
      token = result.token;
      user = result.user;
      await _save();
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not reach the agent service. Check the server address.';
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', token!);
    await prefs.setString('user', jsonEncode(user!.toJson()));
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('user');
    token = null;
    user = null;
    notifyListeners();
  }
}
