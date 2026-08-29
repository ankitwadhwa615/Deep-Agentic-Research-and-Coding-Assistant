import 'dart:typed_data';

class UserProfile {
  const UserProfile(
      {required this.id, required this.name, required this.email});
  final String id, name, email;
  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String);
  Map<String, String> toJson() => {'id': id, 'name': name, 'email': email};
}

class AuthResult {
  const AuthResult(this.token, this.refreshToken, this.user);
  final String token, refreshToken;
  final UserProfile user;
}

class ChatMessage {
  ChatMessage(this.role, this.content,
      {this.streaming = false,
      this.attachmentBytes,
      this.attachmentName,
      this.responseTime});
  final String role;
  String content;
  bool streaming;
  final Uint8List? attachmentBytes;
  final String? attachmentName;
  Duration? responseTime;
}

class ChatSession {
  const ChatSession({required this.id, required this.title});
  final String id, title;
  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
      id: json['id'] as String, title: json['title'] as String? ?? 'New chat');
}

class ApiEvent {
  const ApiEvent(this.type, this.data);
  final String type;
  final Map<String, dynamic> data;
}

class UploadedAttachment {
  const UploadedAttachment({required this.fileId, required this.filename});
  final String fileId, filename;
}

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}
