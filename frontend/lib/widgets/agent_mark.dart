import 'package:flutter/material.dart';

class AgentMark extends StatelessWidget {
  const AgentMark({super.key, this.size = 44});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(size * .3),
        ),
        child: Icon(Icons.auto_awesome_rounded,
            color: const Color(0xFF172010), size: size * .55),
      );
}
