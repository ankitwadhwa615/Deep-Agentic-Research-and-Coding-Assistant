import 'package:web/web.dart' as web;

const _deployedApiBaseUrl =
    'https://deep-agentic-research-and-coding.onrender.com';

String get defaultApiBaseUrl {
  final host = web.window.location.hostname;
  if (host == 'localhost' || host == '127.0.0.1') {
    return 'http://$host:8000';
  }
  return _deployedApiBaseUrl;
}
