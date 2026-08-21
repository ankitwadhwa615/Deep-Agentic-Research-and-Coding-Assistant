import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/models.dart';

class ApiClient {
  ApiClient(this.baseUrl) : _client = http.Client();
  final String baseUrl;
  final http.Client _client;
  Uri _uri(String path) => Uri.parse('$baseUrl$path');
  Map<String, String> _headers([String? token]) => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token'
      };
  Future<Map<String, dynamic>> _json(http.Response response) async {
    final body = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300)
      throw ApiException(body['detail'] as String? ??
          'Request failed (${response.statusCode}).');
    return body;
  }

  Future<AuthResult> register(
      String name, String email, String password) async {
    final body = await _json(await _client.post(_uri('/auth/register'),
        headers: _headers(),
        body:
            jsonEncode({'name': name, 'email': email, 'password': password})));
    return _authResult(body);
  }

  Future<AuthResult> login(String email, String password) async {
    final body = await _json(await _client.post(_uri('/auth/login'),
        headers: _headers(),
        body: jsonEncode({'email': email, 'password': password})));
    return _authResult(body);
  }

  Future<AuthResult> refresh(String refreshToken) async {
    final body = await _json(await _client.post(_uri('/auth/refresh'),
        headers: _headers(), body: jsonEncode({'refresh_token': refreshToken})));
    return _authResult(body);
  }

  AuthResult _authResult(Map<String, dynamic> body) {
    final refreshToken = body['refresh_token'];
    if (refreshToken is! String || refreshToken.isEmpty) {
      throw const ApiException(
          'The agent service is running an older version. Deploy the backend token-refresh changes and try again.');
    }
    return AuthResult(body['access_token'] as String, refreshToken,
        UserProfile.fromJson(body['user'] as Map<String, dynamic>));
  }

  Future<void> forgotPassword(String email, String newPassword) async {
    await _json(await _client.post(_uri('/auth/forgot-password'),
        headers: _headers(),
        body: jsonEncode({'email': email, 'new_password': newPassword})));
  }

  Future<UserProfile> me(String token) async {
    final body = await _json(
        await _client.get(_uri('/auth/me'), headers: _headers(token)));
    return UserProfile.fromJson(body['user'] as Map<String, dynamic>);
  }

  Future<List<ChatSession>> sessions(String token) async {
    final body = await _json(
        await _client.get(_uri('/chat/sessions'), headers: _headers(token)));
    return (body['sessions'] as List)
        .map((value) => ChatSession.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  Future<List<ChatMessage>> history(String token, String id) async {
    final body = await _json(await _client
        .get(_uri('/chat/sessions/$id/history'), headers: _headers(token)));
    return (body['messages'] as List).map((value) {
      final json = value as Map<String, dynamic>;
      return ChatMessage(json['role'] as String, json['content'] as String);
    }).toList();
  }

  Stream<ApiEvent> streamChat(
      String token, String query, String session, String? fileId) async* {
    if (kIsWeb) {
      final body = await _json(await _client.post(_uri('/chat'),
          headers: _headers(token),
          body: jsonEncode({
            'query': query,
            'session_id': session,
            if (fileId != null) 'file_id': fileId
          })));
      yield ApiEvent('token', {
        'source': 'main',
        'content': body['response'] as String? ?? '',
      });
      yield const ApiEvent('complete', {});
      return;
    }
    final request = http.Request('POST', _uri('/chat/stream'))
      ..headers.addAll(_headers(token))
      ..body = jsonEncode({
        'query': query,
        'session_id': session,
        if (fileId != null) 'file_id': fileId
      });
    final response = await _client.send(request);
    if (response.statusCode != 200)
      throw ApiException(_detail(await response.stream.bytesToString()));
    String? event;
    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.startsWith('event:')) event = line.substring(6).trim();
      if (line.startsWith('data:'))
        yield ApiEvent(event ?? 'message',
            jsonDecode(line.substring(5).trim()) as Map<String, dynamic>);
    }
  }

  Future<UploadedAttachment> upload(
      String token, Uint8List bytes, String filename) async {
    final request = http.MultipartRequest('POST', _uri('/upload'))
      ..headers['Authorization'] = 'Bearer $token'
      ..files
          .add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final response = await _client.send(request);
    final body = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300)
      throw ApiException(_detail(body));
    final json = jsonDecode(body) as Map<String, dynamic>;
    return UploadedAttachment(
        fileId: json['file_id'] as String,
        filename: json['filename'] as String);
  }

  String _detail(String value) {
    try {
      return (jsonDecode(value) as Map<String, dynamic>)['detail'] as String? ??
          'Request failed.';
    } catch (_) {
      return 'Request failed.';
    }
  }
}
