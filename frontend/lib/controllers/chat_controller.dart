import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import 'auth_controller.dart';

class ChatController extends ChangeNotifier {
  ChatController(this._api, this._auth);
  final ApiClient _api;
  final AuthController _auth;
  List<ChatSession> sessions = [];
  List<ChatMessage> messages = [];
  String? sessionId, activeAgent;
  bool loading = false, streaming = false, uploading = false;
  UploadedAttachment? attachment;
  Uint8List? attachmentBytes;
  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-${Random.secure().nextInt(0xFFFFFFFF).toRadixString(16)}';
  Future<void> loadSessions() async {
    final token = await _auth.validToken();
    if (token == null) return;
    try {
      sessions = await _api.sessions(token);
      notifyListeners();
    } catch (_) {}
  }

  void newChat() {
    sessionId = _newId();
    messages = [];
    activeAgent = null;
    attachment = null;
    attachmentBytes = null;
    notifyListeners();
  }

  Future<String?> uploadAttachment(Uint8List bytes, String filename) async {
    if (uploading) return 'An upload is already in progress.';
    final token = await _auth.validToken();
    if (token == null) return 'Please sign in first.';
    uploading = true;
    notifyListeners();
    try {
      attachmentBytes = bytes;
      attachment = await _api.upload(token, bytes, filename);
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not upload the attachment. Please try again.';
    } finally {
      uploading = false;
      notifyListeners();
    }
  }

  void clearAttachment() {
    attachment = null;
    attachmentBytes = null;
    notifyListeners();
  }

  Future<void> openSession(ChatSession session) async {
    sessionId = session.id;
    loading = true;
    notifyListeners();
    try {
      final token = await _auth.validToken();
      if (token == null) throw const ApiException('Please sign in first.');
      messages = await _api.history(token, session.id);
    } catch (_) {
      messages = [];
    }
    loading = false;
    notifyListeners();
  }

  Future<String?> deleteSession(ChatSession session) async {
    if (streaming) return 'Wait for the current response to finish.';
    final token = await _auth.validToken();
    if (token == null) return 'Please sign in first.';
    try {
      await _api.deleteSession(token, session.id);
      sessions = sessions.where((item) => item.id != session.id).toList();
      if (sessionId == session.id) newChat();
      notifyListeners();
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not delete this chat. Please try again.';
    }
  }

  Future<void> send(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty || streaming) return;
    sessionId ??= _newId();
    final userMessage = ChatMessage('user', trimmedQuery,
        attachmentBytes: attachmentBytes, attachmentName: attachment?.filename);
    messages = [...messages, userMessage];
    final token = await _auth.validToken();
    if (token == null) {
      messages = [
        ...messages,
        ChatMessage('assistant', 'Please sign in before sending a message.')
      ];
      notifyListeners();
      return;
    }
    final reply = ChatMessage('assistant', '', streaming: true);
    messages = [...messages, reply];
    streaming = true;
    activeAgent = null;
    notifyListeners();
    final stopwatch = Stopwatch()..start();
    try {
      await for (final event in _api.streamChat(
          token, trimmedQuery, sessionId!, attachment?.fileId)) {
        if (event.type == 'token' && event.data['source'] == 'main')
          reply.content += event.data['content'] as String? ?? '';
        if (event.type == 'delegation')
          activeAgent = event.data['agent'] as String?;
        if (event.type == 'error')
          throw ApiException(
              event.data['detail'] as String? ?? 'The request failed.');
        messages = [...messages];
        notifyListeners();
      }
      reply.streaming = false;
      reply.responseTime = stopwatch.elapsed;
      await loadSessions();
    } on ApiException catch (error) {
      reply.content = reply.content.isEmpty
          ? 'Sorry, $error'
          : '${reply.content}\n\n_${error}_';
      reply.streaming = false;
      reply.responseTime = stopwatch.elapsed;
    } catch (_) {
      reply.content = reply.content.isEmpty
          ? 'Sorry, the stream disconnected. Please try again.'
          : reply.content;
      reply.streaming = false;
      reply.responseTime = stopwatch.elapsed;
    } finally {
      stopwatch.stop();
      streaming = false;
      activeAgent = null;
      attachment = null;
      attachmentBytes = null;
      notifyListeners();
    }
  }
}
