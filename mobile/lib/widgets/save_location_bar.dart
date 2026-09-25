import 'package:flutter/material.dart';

class SaveLocationBar extends StatelessWidget {
  final String displayPath;
  final VoidCallback onChangePressed;

  const SaveLocationBar({
    super.key,
    required this.displayPath,
    required this.onChangePressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            displayPath,
            style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5)),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TextButton(
          onPressed: onChangePressed,
          child: const Text('변경'),
        ),
      ],
    );
  }
}
