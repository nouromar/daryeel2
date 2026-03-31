import 'package:flutter/material.dart';

class PrimaryActionBarWidget extends StatelessWidget {
  const PrimaryActionBarWidget({
    super.key,
    required this.primaryLabel,
    this.onPrimaryPressed,
  });

  final String primaryLabel;
  final VoidCallback? onPrimaryPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPrimaryPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(primaryLabel),
      ),
    );
  }
}
