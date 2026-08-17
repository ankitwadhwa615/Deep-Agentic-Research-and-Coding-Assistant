import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final hello =Provider<String>((ref){
  return "subscribe";
});

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscribe = ref.watch(hello);
    return Scaffold(
      body: Center(
        child:Text(
          subscribe
        ),
      ),
    );
  }
}

