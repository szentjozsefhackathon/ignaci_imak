import 'package:flutter/material.dart';

class DataSyncListItemProgressIndicator extends StatelessWidget {
  const DataSyncListItemProgressIndicator({super.key, this.value});

  final double? value;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 24,
    child: CircularProgressIndicator(strokeWidth: 2, value: value),
  );
}
