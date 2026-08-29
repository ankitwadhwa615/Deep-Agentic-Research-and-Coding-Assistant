import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../core/providers.dart';
import '../models/models.dart';
import '../widgets/agent_mark.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _composer = TextEditingController(), _scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => ref.read(chatProvider).loadSessions());
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    ref.read(chatProvider).send(_composer.text);
    _composer.clear();
    Future.delayed(const Duration(milliseconds: 80), () {
      if (_scroll.hasClients)
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null) return;
    final file = result.files.single;
    if (file.bytes == null)
      return _error('The selected file could not be read.');
    await _upload(file.bytes!, file.name);
  }

  Future<void> _pickPhoto() async {
    if (kIsWeb) {
      final result = await FilePicker.platform
          .pickFiles(type: FileType.image, withData: true);
      if (result == null) return;
      final file = result.files.single;
      if (file.bytes == null) {
        return _error('The selected image could not be read.');
      }
      return _upload(file.bytes!, file.name);
    }
    final photo = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (photo != null) await _upload(await photo.readAsBytes(), photo.name);
  }

  Future<void> _upload(Uint8List bytes, String filename) async {
    final error =
        await ref.read(chatProvider).uploadAttachment(bytes, filename);
    if (mounted && error != null) _error(error);
  }

  void _error(String message) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatProvider);
    final user = ref.watch(authProvider).user!;
    final sid = chat.sessionId ?? 'new';
    return Scaffold(
        drawer: _ChatDrawer(user: user),
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
                      ? _EmptyState(name: user.name)
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                          itemCount: chat.messages.length +
                              (chat.activeAgent == null ? 0 : 1),
                          itemBuilder: (_, index) => index ==
                                  chat.messages.length
                              ? _AgentStatus(name: chat.activeAgent!)
                              : _MessageBubble(message: chat.messages[index]))),
          _Composer(
              controller: _composer,
              busy: chat.streaming || chat.uploading,
              attachment: chat.attachment,
              onPickFile: _pickFile,
              onPickPhoto: _pickPhoto,
              onClearAttachment: () => ref.read(chatProvider).clearAttachment(),
              onSend: _send)
        ]));
  }
}

class _ChatDrawer extends ConsumerWidget {
  const _ChatDrawer({required this.user});
  final UserProfile user;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatProvider);
    return Drawer(
        child: SafeArea(
            child: Column(children: [
      Padding(
          padding: const EdgeInsets.all(14),
          child: FilledButton.icon(
              onPressed: () {
                ref.read(chatProvider).newChat();
                Navigator.pop(context);
              },
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.add),
              label: const Text('New conversation'))),
      const Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Align(
              alignment: Alignment.centerLeft,
              child: Text('RECENT CHATS',
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.1,
                      color: Color(0xFFB7C8BE))))),
      Expanded(
          child: ListView.builder(
              itemCount: chat.sessions.length,
              itemBuilder: (_, i) {
                final session = chat.sessions[i];
                return ListTile(
                    leading: const Icon(Icons.forum_outlined, size: 19),
                    title: Text(session.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    selected: session.id == chat.sessionId,
                    onTap: () {
                      ref.read(chatProvider).openSession(session);
                      Navigator.pop(context);
                    });
              })),
      const Divider(),
      ListTile(
          leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.secondary,
              child: Text(user.name.isEmpty ? '?' : user.name[0].toUpperCase(),
                  style: const TextStyle(color: Color(0xFF172010)))),
          title: Text(user.name),
          subtitle: Text(user.email, overflow: TextOverflow.ellipsis),
          trailing: IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => ref.read(authProvider).logout()))
    ])));
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => Center(
      child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const AgentMark(size: 64),
            const SizedBox(height: 22),
            Text('What are we exploring, $name?',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            const Text('Ask for research, a plan, code, or a careful review.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFB7C8BE)))
          ])));
}

class _AgentStatus extends StatelessWidget {
  const _AgentStatus({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => Padding(
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final ChatMessage message;

  bool get _isImageAttachment {
    final name = message.attachmentName?.toLowerCase() ?? '';
    return const ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp']
        .any(name.endsWith);
  }

  TextSpan _formattedText(BuildContext context) {
    final baseStyle = const TextStyle(height: 1.45);
    final headingStyle = baseStyle.copyWith(
        fontSize: 18, fontWeight: FontWeight.w700, height: 1.35);
    final boldStyle = baseStyle.copyWith(fontWeight: FontWeight.w700);
    final spans = <TextSpan>[];
    final lines = message.content.split('\n');
    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      final heading = RegExp(r'^#{1,6}\s+(.*)$').firstMatch(line);
      if (heading != null) {
        spans.add(TextSpan(text: heading.group(1), style: headingStyle));
      } else if (RegExp(r'^\s*([-*_]\s*){3,}$').hasMatch(line)) {
        spans.add(TextSpan(
            text: '────────────────────',
            style: baseStyle.copyWith(color: Colors.white38)));
      } else {
        final bullet = RegExp(r'^(\s*)\*\s+(.*)$').firstMatch(line);
        final formattedLine =
            bullet == null ? line : '${bullet.group(1)}• ${bullet.group(2)}';
        final markdown = RegExp(r'(\*\*[^*]+\*\*|\*[^*]+\*)');
        var cursor = 0;
        for (final match in markdown.allMatches(formattedLine)) {
          if (match.start > cursor) {
            spans.add(TextSpan(
                text: formattedLine.substring(cursor, match.start),
                style: baseStyle));
          }
          final token = match.group(0)!;
          final isBold = token.startsWith('**');
          spans.add(TextSpan(
              text: token.substring(
                  isBold ? 2 : 1, token.length - (isBold ? 2 : 1)),
              style: isBold
                  ? boldStyle
                  : baseStyle.copyWith(fontStyle: FontStyle.italic)));
          cursor = match.end;
        }
        if (cursor < formattedLine.length) {
          spans.add(TextSpan(
              text: formattedLine.substring(cursor), style: baseStyle));
        }
      }
      if (lineIndex < lines.length - 1) {
        spans.add(const TextSpan(text: '\n'));
      }
    }
    return TextSpan(children: spans, style: baseStyle);
  }

  String _responseTimeLabel(Duration duration) {
    if (duration.inMilliseconds < 1000) {
      return '${duration.inMilliseconds} ms';
    }
    return '${(duration.inMilliseconds / 1000).toStringAsFixed(1)} s';
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
            padding: const EdgeInsets.only(bottom: 15),
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 650),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 13),
                          decoration: BoxDecoration(
                              color: isUser
                                  ? const Color(0xFF314238)
                                  : const Color(0xFF1B2622),
                              borderRadius: BorderRadius.circular(18).copyWith(
                                  bottomRight:
                                      isUser ? const Radius.circular(4) : null,
                                  bottomLeft: !isUser
                                      ? const Radius.circular(4)
                                      : null),
                              border: !isUser
                                  ? Border.all(color: const Color(0xFF2B3933))
                                  : null),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (message.attachmentBytes != null &&
                                    _isImageAttachment)
                                  ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.memory(
                                          message.attachmentBytes!,
                                          width: 280,
                                          height: 220,
                                          fit: BoxFit.cover)),
                                if (message.attachmentBytes != null &&
                                    !_isImageAttachment)
                                  Row(children: [
                                    const Icon(Icons.attach_file, size: 18),
                                    const SizedBox(width: 6),
                                    Flexible(
                                        child: Text(message.attachmentName ??
                                            'Attached file'))
                                  ]),
                                if (message.attachmentBytes != null &&
                                    _isImageAttachment &&
                                    message.content.isNotEmpty)
                                  const SizedBox(height: 10),
                                SelectableText.rich(
                                    message.content.isEmpty && message.streaming
                                        ? const TextSpan(
                                            text: 'Thinking…',
                                            style: TextStyle(height: 1.45))
                                        : _formattedText(context))
                              ])),
                      if (!isUser && !message.streaming) ...[
                        const SizedBox(height: 3),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                              tooltip: 'Copy response',
                              visualDensity: VisualDensity.compact,
                              onPressed: message.content.isEmpty
                                  ? null
                                  : () => Clipboard.setData(
                                      ClipboardData(text: message.content)),
                              icon: const Icon(Icons.copy_outlined, size: 19)),
                          if (message.responseTime != null)
                            Text(_responseTimeLabel(message.responseTime!),
                                style: const TextStyle(
                                    fontSize: 12, color: Color(0xFFB7C8BE)))
                        ])
                      ]
                    ]))));
  }
}

class _Composer extends StatelessWidget {
  const _Composer(
      {required this.controller,
      required this.busy,
      required this.attachment,
      required this.onPickFile,
      required this.onPickPhoto,
      required this.onClearAttachment,
      required this.onSend});
  final TextEditingController controller;
  final bool busy;
  final UploadedAttachment? attachment;
  final VoidCallback onPickFile, onPickPhoto, onClearAttachment, onSend;
  @override
  Widget build(BuildContext context) => SafeArea(
      top: false,
      child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          child: Container(
              decoration: BoxDecoration(
                  color: const Color(0xFF202C27),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFF35453E))),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (attachment != null)
                  Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 8, 0),
                      child: Row(children: [
                        const Icon(Icons.attach_file, size: 18),
                        const SizedBox(width: 7),
                        Expanded(
                            child: Text(attachment!.filename,
                                maxLines: 1, overflow: TextOverflow.ellipsis)),
                        IconButton(
                            tooltip: 'Remove attachment',
                            onPressed: busy ? null : onClearAttachment,
                            icon: const Icon(Icons.close, size: 18))
                      ])),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  PopupMenuButton<String>(
                      enabled: !busy,
                      tooltip: 'Add attachment',
                      icon: const Icon(Icons.add_circle_outline),
                      onSelected: (value) =>
                          value == 'file' ? onPickFile() : onPickPhoto(),
                      itemBuilder: (_) => const [
                            PopupMenuItem(
                                value: 'file', child: Text('Upload file')),
                            PopupMenuItem(
                                value: 'photo', child: Text('Choose photo'))
                          ]),
                  Expanded(
                      child: Focus(
                          onKeyEvent: (_, event) {
                            if (event is KeyDownEvent &&
                                event.logicalKey == LogicalKeyboardKey.enter &&
                                !HardwareKeyboard.instance.isShiftPressed) {
                              if (!busy && controller.text.trim().isNotEmpty) {
                                onSend();
                              }
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: TextField(
                              controller: controller,
                              minLines: 1,
                              maxLines: 5,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) {
                                if (!busy) onSend();
                              },
                              decoration: const InputDecoration(
                                  hintText: 'Message Ankit’s Agent',
                                  fillColor: Colors.transparent,
                                  border: InputBorder.none)))),
                  Padding(
                      padding: const EdgeInsets.all(6),
                      child: IconButton(
                          onPressed: busy ? null : onSend,
                          style: IconButton.styleFrom(
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary,
                              foregroundColor: const Color(0xFF172010)),
                          icon: Icon(busy
                              ? Icons.hourglass_top
                              : Icons.arrow_upward_rounded)))
                ])
              ]))));
}
