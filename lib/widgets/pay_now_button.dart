import 'package:flutter/material.dart';

import '../core/app_theme.dart';

class PayNowButton extends StatelessWidget {
  const PayNowButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: onPressed,
      backgroundColor: AppTheme.neoBlue,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.add_card_rounded),
      label: const Text('Pay Now'),
    );
  }
}
