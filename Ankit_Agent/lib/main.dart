import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _apiBaseUrl = String.fromEnvironment(
    'https://deep-agentic-research-and-coding.onrender.com',
    defaultValue: 'http://10.0.2.2:8000');
final apiProvider = Provider((_) => ApiClient(_apiBaseUrl));
final authProvider =
    ChangeNotifierProvider((ref) => AuthController(ref.read(apiProvider)));
final chatProvider = ChangeNotifierProvider(
    (ref) => ChatController(ref.read(apiProvider), ref.read(authProvider)));

void main() => runApp(const ProviderScope(child: MyApp()));

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Ankit's Agent",
      theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF111816),
          colorScheme: const ColorScheme.dark(
              primary: Color(0xFFC7F06C),
              onPrimary: Color(0xFF172010),
              secondary: Color(0xFF84DCC6),
              surface: Color(0xFF1B2622),
              onSurface: Color(0xFFF1F4EC),
              error: Color(0xFFFFB4AB)),
          inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF202C27),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 17))),
      home: const SplashGate());
}

class UserProfile {
  const UserProfile(
      {required this.id, required this.name, required this.email});
  final String id, name, email;
  factory UserProfile.fromJson(Map<String, dynamic> j) =>
      UserProfile(id: j['id'], name: j['name'], email: j['email']);
  Map<String, String> toJson() => {'id': id, 'name': name, 'email': email};
}

class AuthResult {
  const AuthResult(this.token, this.user);
  final String token;
  final UserProfile user;
}

class ChatMessage {
  ChatMessage(this.role, this.content, {this.streaming = false});
  final String role;
  String content;
  bool streaming;
}

class ChatSession {
  const ChatSession({required this.id, required this.title});
  final String id, title;
  factory ChatSession.fromJson(Map<String, dynamic> j) =>
      ChatSession(id: j['id'], title: j['title'] ?? 'New chat');
}

class ApiEvent {
  const ApiEvent(this.type, this.data);
  final String type;
  final Map<String, dynamic> data;
}

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

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
        user = UserProfile.fromJson(jsonDecode(raw));
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
  Future<String?> _authenticate(Future<AuthResult> Function() call) async {
    submitting = true;
    notifyListeners();
    try {
      final result = await call();
      token = result.token;
      user = result.user;
      await _save();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not reach the agent service. Check the server address.';
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('access_token', token!);
    await p.setString('user', jsonEncode(user!.toJson()));
  }

  Future<void> logout() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('access_token');
    await p.remove('user');
    token = null;
    user = null;
    notifyListeners();
  }
}

class ChatController extends ChangeNotifier {
  ChatController(this._api, this._auth);
  final ApiClient _api;
  final AuthController _auth;
  List<ChatSession> sessions = [];
  List<ChatMessage> messages = [];
  String? sessionId, activeAgent;
  bool loading = false, streaming = false;
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
    try {
      await for (final event
          in _api.streamChat(_auth.token!, query.trim(), sessionId!)) {
        if (event.type == 'token' && event.data['source'] == 'main') {
          reply.content += event.data['content'] as String? ?? '';
        }
        if (event.type == 'delegation') {
          activeAgent = event.data['agent'] as String?;
        }
        if (event.type == 'error') {
          throw ApiException(
              event.data['detail'] as String? ?? 'The request failed.');
        }
        notifyListeners();
      }
      reply.streaming = false;
      await loadSessions();
    } on ApiException catch (e) {
      reply.content =
          reply.content.isEmpty ? 'Sorry, $e' : '${reply.content}\n\n_${e}_';
      reply.streaming = false;
    } catch (_) {
      reply.content = reply.content.isEmpty
          ? 'Sorry, the stream disconnected. Please try again.'
          : reply.content;
      reply.streaming = false;
    } finally {
      streaming = false;
      activeAgent = null;
      notifyListeners();
    }
  }
}

class ApiClient {
  ApiClient(this.baseUrl) : _client = http.Client();
  final String baseUrl;
  final http.Client _client;
  Uri _uri(String path) => Uri.parse('$baseUrl$path');
  Map<String, String> _headers([String? token]) => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token'
      };
  Future<Map<String, dynamic>> _json(http.Response r) async {
    final b = r.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw ApiException(
          b['detail'] as String? ?? 'Request failed (${r.statusCode}).');
    }
    return b;
  }

  Future<AuthResult> register(String n, String e, String p) async {
    final b = await _json(await _client.post(_uri('/auth/register'),
        headers: _headers(),
        body: jsonEncode({'name': n, 'email': e, 'password': p})));
    return AuthResult(b['access_token'], UserProfile.fromJson(b['user']));
  }

  Future<AuthResult> login(String e, String p) async {
    final b = await _json(await _client.post(_uri('/auth/login'),
        headers: _headers(), body: jsonEncode({'email': e, 'password': p})));
    return AuthResult(b['access_token'], UserProfile.fromJson(b['user']));
  }

  Future<UserProfile> me(String t) async {
    final b =
        await _json(await _client.get(_uri('/auth/me'), headers: _headers(t)));
    return UserProfile.fromJson(b['user']);
  }

  Future<List<ChatSession>> sessions(String t) async {
    final b = await _json(
        await _client.get(_uri('/chat/sessions'), headers: _headers(t)));
    return (b['sessions'] as List).map((e) => ChatSession.fromJson(e)).toList();
  }

  Future<List<ChatMessage>> history(String t, String id) async {
    final b = await _json(await _client.get(_uri('/chat/sessions/$id/history'),
        headers: _headers(t)));
    return (b['messages'] as List)
        .map((e) => ChatMessage(e['role'], e['content']))
        .toList();
  }

  Stream<ApiEvent> streamChat(
      String token, String query, String session) async* {
    final req = http.Request('POST', _uri('/chat/stream'))
      ..headers.addAll(_headers(token))
      ..body = jsonEncode({'query': query, 'session_id': session});
    final r = await _client.send(req);
    if (r.statusCode != 200) {
      final b = await r.stream.bytesToString();
      throw ApiException(_detail(b));
    }
    String? event;
    await for (final line
        in r.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.startsWith('event:')) {
        event = line.substring(6).trim();
      }
      if (line.startsWith('data:')) {
        yield ApiEvent(event ?? 'message',
            jsonDecode(line.substring(5).trim()) as Map<String, dynamic>);
      }
    }
  }

  String _detail(String value) {
    try {
      return (jsonDecode(value) as Map<String, dynamic>)['detail'] ??
          'Request failed.';
    } catch (_) {
      return 'Request failed.';
    }
  }
}

class SplashGate extends ConsumerStatefulWidget {
  const SplashGate({super.key});
  @override
  ConsumerState<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends ConsumerState<SplashGate> {
  bool done = false;
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1300), () {
      if (mounted) setState(() => done = true);
    });
  }

  @override
  Widget build(BuildContext c) {
    final a = ref.watch(authProvider);
    if (!done || a.loading) return const SplashScreen();
    return a.user == null ? const AuthScreen() : const ChatScreen();
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
      body: DecoratedBox(
          decoration: const BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF111816), Color(0xFF23312B)])),
          child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            const AgentMark(size: 86),
            const SizedBox(height: 24),
            Text("Ankit's Agent",
                style: Theme.of(c)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Think deeper. Build smarter.'),
            const SizedBox(height: 34),
            const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2))
          ]))));
}

class AgentMark extends StatelessWidget {
  const AgentMark({super.key, this.size = 44});
  final double size;
  @override
  Widget build(BuildContext c) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: Theme.of(c).colorScheme.primary,
          borderRadius: BorderRadius.circular(size * .3)),
      child: Icon(Icons.auto_awesome_rounded,
          color: const Color(0xFF172010), size: size * .55));
}

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final name = TextEditingController(),
      email = TextEditingController(),
      password = TextEditingController();
  bool registering = false, obscure = true;
  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final error = registering
        ? await ref
            .read(authProvider)
            .register(name.text, email.text, password.text)
        : await ref.read(authProvider).login(email.text, password.text);
    if (mounted && error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext c) {
    final auth = ref.watch(authProvider);
    return Scaffold(
        body: SafeArea(
            child: Center(
                child: SingleChildScrollView(
                    padding: const EdgeInsets.all(28),
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const AgentMark(size: 56),
                              const SizedBox(height: 34),
                              Text(
                                  registering
                                      ? 'Create your workspace'
                                      : 'Welcome back',
                                  style: Theme.of(c)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 8),
                              Text(registering
                                  ? 'Your research partner is ready when you are.'
                                  : 'Continue your conversations with Ankit’s Agent.'),
                              const SizedBox(height: 30),
                              if (registering)
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: TextField(
                                        controller: name,
                                        decoration: const InputDecoration(
                                            labelText: 'Your name'))),
                              TextField(
                                  controller: email,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: const InputDecoration(
                                      labelText: 'Email address')),
                              const SizedBox(height: 12),
                              TextField(
                                  controller: password,
                                  obscureText: obscure,
                                  onSubmitted: (_) => submit(),
                                  decoration: InputDecoration(
                                      labelText: 'Password',
                                      suffixIcon: IconButton(
                                          onPressed: () => setState(
                                              () => obscure = !obscure),
                                          icon: Icon(obscure
                                              ? Icons.visibility_outlined
                                              : Icons
                                                  .visibility_off_outlined)))),
                              if (registering)
                                const Padding(
                                    padding: EdgeInsets.only(top: 8),
                                    child: Text('Use at least 8 characters.',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFFB7C8BE)))),
                              const SizedBox(height: 22),
                              FilledButton(
                                  onPressed: auth.submitting ? null : submit,
                                  style: FilledButton.styleFrom(
                                      minimumSize: const Size.fromHeight(54)),
                                  child: auth.submitting
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : Text(registering
                                          ? 'Create account'
                                          : 'Sign in')),
                              const SizedBox(height: 14),
                              Center(
                                  child: TextButton(
                                      onPressed: auth.submitting
                                          ? null
                                          : () => setState(
                                              () => registering = !registering),
                                      child: Text(registering
                                          ? 'Already have an account? Sign in'
                                          : 'New here? Create an account')))
                            ]))))));
  }
}

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final composer = TextEditingController(), scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => ref.read(chatProvider).loadSessions());
  }

  @override
  void dispose() {
    composer.dispose();
    scroll.dispose();
    super.dispose();
  }

  void send() {
    ref.read(chatProvider).send(composer.text);
    composer.clear();
    Future.delayed(const Duration(milliseconds: 80), () {
      if (scroll.hasClients) {
        scroll.animateTo(scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext c) {
    final chat = ref.watch(chatProvider);
    final user = ref.watch(authProvider).user!;
    final sid = chat.sessionId ?? 'new';
    return Scaffold(
        drawer: ChatDrawer(user: user),
        appBar: AppBar(
            titleSpacing: 4,
            title:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("Ankit's Agent",
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              Text(
                  'User: ${user.id.substring(0, min(8, user.id.length))}  •  Session: ${sid.substring(0, min(8, sid.length))}',
                  style:
                      const TextStyle(fontSize: 10, color: Color(0xFFB7C8BE)))
            ]),
            actions: [
              IconButton(
                  onPressed: chat.newChat,
                  tooltip: 'New chat',
                  icon: const Icon(Icons.edit_square))
            ]),
        body: Column(children: [
          Expanded(
              child: chat.loading
                  ? const Center(child: CircularProgressIndicator())
                  : chat.messages.isEmpty
                      ? EmptyState(name: user.name)
                      : ListView.builder(
                          controller: scroll,
                          padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                          itemCount: chat.messages.length +
                              (chat.activeAgent == null ? 0 : 1),
                          itemBuilder: (c, i) => i == chat.messages.length
                              ? AgentStatus(name: chat.activeAgent!)
                              : MessageBubble(message: chat.messages[i]))),
          Composer(controller: composer, busy: chat.streaming, onSend: send)
        ]));
  }
}

class ChatDrawer extends ConsumerWidget {
  const ChatDrawer({super.key, required this.user});
  final UserProfile user;
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final chat = ref.watch(chatProvider);
    return Drawer(
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: FilledButton.icon(
              onPressed: () {
                ref.read(chatProvider).newChat();
                Navigator.pop(c);
              },
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.add),
              label: const Text('New conversation'),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text('RECENT CHATS',
                    style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.1,
                        color: Color(0xFFB7C8BE)))),
          ),
          Expanded(
              child: ListView.builder(
                  itemCount: chat.sessions.length,
                  itemBuilder: (_, i) {
                    final s = chat.sessions[i];
                    return ListTile(
                        leading: const Icon(Icons.forum_outlined, size: 19),
                        title: Text(s.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        selected: s.id == chat.sessionId,
                        onTap: () {
                          ref.read(chatProvider).openSession(s);
                          Navigator.pop(c);
                        });
                  })),
          const Divider(),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(c).colorScheme.secondary,
              child: Text(
                user.name.isEmpty ? '?' : user.name[0].toUpperCase(),
                style: const TextStyle(color: Color(0xFF172010)),
              ),
            ),
            title: Text(user.name),
            subtitle: Text(user.email, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => ref.read(authProvider).logout(),
            ),
          ),
        ]),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.name});
  final String name;
  @override
  Widget build(BuildContext c) => Center(
      child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const AgentMark(size: 64),
            const SizedBox(height: 22),
            Text('What are we exploring, $name?',
                textAlign: TextAlign.center,
                style: Theme.of(c)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            const Text('Ask for research, a plan, code, or a careful review.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFB7C8BE)))
          ])));
}

class AgentStatus extends StatelessWidget {
  const AgentStatus({super.key, required this.name});
  final String name;
  @override
  Widget build(BuildContext c) => Padding(
      padding: const EdgeInsets.only(left: 10, top: 3, bottom: 12),
      child: Row(children: [
        const SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 10),
        Text('$name is working…',
            style: const TextStyle(fontSize: 12, color: Color(0xFFC7F06C)))
      ]));
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message});
  final ChatMessage message;
  @override
  Widget build(BuildContext c) {
    final user = message.role == 'user';
    return Align(
        alignment: user ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
            padding: const EdgeInsets.only(bottom: 15),
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 650),
                child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 13),
                    decoration: BoxDecoration(
                        color: user
                            ? const Color(0xFF314238)
                            : const Color(0xFF1B2622),
                        borderRadius: BorderRadius.circular(18).copyWith(
                            bottomRight: user ? const Radius.circular(4) : null,
                            bottomLeft:
                                !user ? const Radius.circular(4) : null),
                        border: !user
                            ? Border.all(color: const Color(0xFF2B3933))
                            : null),
                    child: SelectableText(
                        message.content.isEmpty && message.streaming
                            ? 'Thinking…'
                            : message.content,
                        style: const TextStyle(height: 1.45))))));
  }
}

class Composer extends StatelessWidget {
  const Composer(
      {super.key,
      required this.controller,
      required this.busy,
      required this.onSend});
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;
  @override
  Widget build(BuildContext c) => SafeArea(
      top: false,
      child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          child: Container(
              decoration: BoxDecoration(
                  color: const Color(0xFF202C27),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFF35453E))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.auto_awesome_outlined, size: 20)),
                Expanded(
                    child: TextField(
                        controller: controller,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.newline,
                        onSubmitted: (_) {
                          if (!busy) onSend();
                        },
                        decoration: const InputDecoration(
                            hintText: 'Message Ankit’s Agent',
                            fillColor: Colors.transparent,
                            border: InputBorder.none))),
                Padding(
                    padding: const EdgeInsets.all(6),
                    child: IconButton(
                        onPressed: busy ? null : onSend,
                        style: IconButton.styleFrom(
                            backgroundColor: Theme.of(c).colorScheme.primary,
                            foregroundColor: const Color(0xFF172010)),
                        icon: Icon(busy
                            ? Icons.hourglass_top
                            : Icons.arrow_upward_rounded)))
              ]))));
}
