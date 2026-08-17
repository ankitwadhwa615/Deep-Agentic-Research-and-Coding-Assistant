import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

export 'app.dart' show MyApp;

void main() => runApp(const ProviderScope(child: MyApp()));
