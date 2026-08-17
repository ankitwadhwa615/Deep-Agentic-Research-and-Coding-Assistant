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
  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-${Random.secure().nextInt(1 << 32).toRadixString(16)}';
  Future<void> loadSessions() async {
    if (_auth.token == null) return;
    try {
      sessions = await _api.sessions(_auth.token!);
      notifyListeners();
    } catch (_) {}
  }

  void newChat() {
    sessionId = _newId();
    messages = [];
    activeAgent = null;
    attachment = null;
    notifyListeners();
  }

  Future<String?> uploadAttachment(Uint8List bytes, String filename) async {
    if (_auth.token == null || uploading) return 'Please sign in first.';
    uploading = true;
    notifyListeners();
    try {
      attachment = await _api.upload(_auth.token!, bytes, filename);
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
    notifyListeners();
  }

  Future<void> openSession(ChatSession session) async {
    sessionId = session.id;
    loading = true;
    notifyListeners();
    try {
      messages = await _api.history(_auth.token!, session.id);
    } catch (_) {
      messages = [];
    }
    loading = false;
    notifyListeners();
  }

  Future<void> send(String query) async {
    if (query.trim().isEmpty || streaming || _auth.token == null) return;
    sessionId ??= _newId();
    messages.add(ChatMessage('user', query.trim()));
    final reply = ChatMessage('assistant', '', streaming: true);
    messages.add(reply);
    streaming = true;
    activeAgent = null;
    notifyListeners();
    var sent = false;
    try {
      await for (final event in _api.streamChat(
          _auth.token!, query.trim(), sessionId!, attachment?.fileId)) {
        if (event.type == 'token' && event.data['source'] == 'main')
          reply.content += event.data['content'] as String? ?? '';
        if (event.type == 'delegation')
          activeAgent = event.data['agent'] as String?;
        if (event.type == 'error')
          throw ApiException(
              event.data['detail'] as String? ?? 'The request failed.');
        notifyListeners();
      }
      reply.streaming = false;
      sent = true;
      await loadSessions();
    } on ApiException catch (error) {
      reply.content = reply.content.isEmpty
          ? 'Sorry, $error'
          : '${reply.content}\n\n_${error}_';
      reply.streaming = false;
    } catch (_) {
      reply.content = reply.content.isEmpty
          ? 'Sorry, the stream disconnected. Please try again.'
          : reply.content;
      reply.streaming = false;
    } finally {
      streaming = false;
      activeAgent = null;
      if (sent) attachment = null;
      notifyListeners();
    }
  }
}
