import 'package:flutter/material.dart';

class ListItemProgressIndicator extends StatelessWidget {
  const ListItemProgressIndicator({super.key, this.value});

  final double? value;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 24,
    child: CircularProgressIndicator(strokeWidth: 2, value: value),
  );
}
