import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../controllers/auth_controller.dart';
import '../controllers/chat_controller.dart';
import '../services/api_client.dart';
import 'default_api_url.dart';

/// Supply a deployed endpoint using --dart-define=API_BASE_URL=https://api.example.com.
const _configuredApiBaseUrl = String.fromEnvironment('API_BASE_URL');
final apiBaseUrl =
    _configuredApiBaseUrl.isEmpty ? defaultApiBaseUrl : _configuredApiBaseUrl;
final apiProvider = Provider((_) => ApiClient(apiBaseUrl));
final authProvider =
    ChangeNotifierProvider((ref) => AuthController(ref.read(apiProvider)));
final chatProvider = ChangeNotifierProvider(
    (ref) => ChatController(ref.read(apiProvider), ref.read(authProvider)));
