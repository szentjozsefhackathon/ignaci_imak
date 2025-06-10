import 'package:flutter/material.dart';

class AlarmTile extends StatelessWidget {
  const AlarmTile({
    super.key,
    required this.title,
    required this.onPressed,
    this.onDismissed,
  });

  final String title;
  final VoidCallback onPressed;
  final VoidCallback? onDismissed;

  @override
  Widget build(BuildContext context) => Dismissible(
    key: key!,
    direction: onDismissed != null
        ? DismissDirection.endToStart
        : DismissDirection.none,
    background: Container(
      color: Colors.red,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 30),
      child: const Icon(Icons.delete, size: 30, color: Colors.white),
    ),
    onDismissed: (_) => onDismissed?.call(),
    child: ListTile(
      title: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: Text(title),
      ),
      trailing: const Icon(Icons.keyboard_arrow_right_rounded),
      onTap: onPressed,
    ),
  );
}
