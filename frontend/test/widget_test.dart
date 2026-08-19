import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ankit_agent/main.dart';

void main() {
  testWidgets('shows the application splash screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    expect(find.text("Ankit's Agent"), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1300));
  });
}
