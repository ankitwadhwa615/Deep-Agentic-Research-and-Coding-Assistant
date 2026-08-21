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
  String? refreshToken;
  UserProfile? user;
  Future<String?>? _refreshing;

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('access_token');
    final savedRefreshToken = prefs.getString('refresh_token');
    final raw = prefs.getString('user');
    if (saved != null && savedRefreshToken != null && raw != null) {
      try {
        token = saved;
        refreshToken = savedRefreshToken;
        user = UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        final valid = await validToken();
        if (valid == null) throw const ApiException('Session expired.');
        user = await _api.me(valid);
        await _save();
      } catch (_) {
        await _clear(prefs);
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
      refreshToken = result.refreshToken;
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
    await prefs.setString('refresh_token', refreshToken!);
    await prefs.setString('user', jsonEncode(user!.toJson()));
  }

  /// Returns a usable access token, refreshing it when it expires within a minute.
  Future<String?> validToken({bool forceRefresh = false}) async {
    if (token == null || refreshToken == null) return null;
    if (!forceRefresh && !_expiresSoon(token!)) return token;
    return _refreshAccessToken();
  }

  bool _expiresSoon(String value) {
    try {
      final parts = value.split('.');
      if (parts.length != 3) return true;
      final payload = jsonDecode(utf8.decode(base64Url.decode(
          base64Url.normalize(parts[1])))) as Map<String, dynamic>;
      final expiresAt = payload['exp'];
      if (expiresAt is! num) return true;
      return DateTime.now().toUtc().millisecondsSinceEpoch >=
          (expiresAt * 1000 - 60000);
    } catch (_) {
      return true;
    }
  }

  Future<String?> _refreshAccessToken() async {
    final pending = _refreshing;
    if (pending != null) return pending;
    final future = _doRefresh();
    _refreshing = future;
    try {
      return await future;
    } finally {
      _refreshing = null;
    }
  }

  Future<String?> _doRefresh() async {
    try {
      final result = await _api.refresh(refreshToken!);
      token = result.token;
      refreshToken = result.refreshToken;
      user = result.user;
      await _save();
      notifyListeners();
      return token;
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      await _clear(prefs);
      notifyListeners();
      return null;
    }
  }

  Future<void> _clear(SharedPreferences prefs) async {
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('user');
    token = null;
    refreshToken = null;
    user = null;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await _clear(prefs);
    notifyListeners();
  }
}
