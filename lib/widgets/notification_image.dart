import 'package:flutter/material.dart';

import '../core/app_theme.dart';

class NotificationImage extends StatelessWidget {
  const NotificationImage({
    super.key,
    required this.url,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.heroTag,
    this.onTap,
  });

  final String url;
  final double? height;
  final BorderRadius borderRadius;
  final Object? heroTag;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final image = Image.network(
      url,
      height: height,
      width: double.infinity,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _Placeholder(
          height: height,
          child: const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.gold500,
            ),
          ),
        );
      },
      errorBuilder: (_, _, _) => _Placeholder(
        height: height,
        child: const Icon(
          Icons.photo_outlined,
          color: AppTheme.gold500,
          size: 36,
        ),
      ),
    );

    final clipped = ClipRRect(
      borderRadius: borderRadius,
      child: heroTag == null ? image : Hero(tag: heroTag!, child: image),
    );

    if (onTap == null) return clipped;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: clipped,
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.child, this.height});

  final Widget child;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height ?? 180,
      width: double.infinity,
      color: AppTheme.cream100,
      alignment: Alignment.center,
      child: child,
    );
  }
}
