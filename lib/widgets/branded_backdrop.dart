import 'package:flutter/material.dart';

import '../core/app_theme.dart';

class BrandedBackdrop extends StatelessWidget {
  const BrandedBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppTheme.neoBlue,
      child: SizedBox.expand(),
    );
  }
}
