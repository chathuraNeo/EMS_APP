import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_config.dart';
import '../core/app_theme.dart';
import '../services/push_notification_service.dart';
import 'main_navigation.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.destination,
    this.onAnimationComplete,
    this.duration = AppConfig.splashDuration,
  });

  final Widget? destination;
  final VoidCallback? onAnimationComplete;
  final Duration duration;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final AnimationController _pulseController;
  late final Widget _activeDestination;
  bool _navigated = false;
  bool _overlayVisible = true;
  bool _overlayFading = false;
  bool _webReady = false;
  bool _waitingForWeb = false;
  bool _showSlowNetworkHint = false;
  Timer? _maxWaitTimer;
  Timer? _slowNetworkTimer;
  VoidCallback? _notifListener;

  @override
  void initState() {
    super.initState();

    _activeDestination = widget.destination ??
        MainNavigation(onInitialLoadFinished: _onWebReady);

    _controller = AnimationController(vsync: this, duration: widget.duration);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );

    _notifListener = () {
      if (mounted) {
        _onWebReady();
        if (!_controller.isCompleted) {
          _controller.forward();
        }
      }
    };
    PushNotificationService.instance.notificationsOpened.addListener(_notifListener!);

    _controller.addListener(() {
      if (!_webReady && _controller.value >= 0.65) {
        // If user tapped a notification, don't hold splash waiting for web
        if (PushNotificationService.instance.hasPendingNotification) {
          _onWebReady();
          return;
        }
        if (!_waitingForWeb) {
          _waitingForWeb = true;
          _controller.stop();
          _pulseController.repeat(reverse: true);
          _slowNetworkTimer = Timer(const Duration(milliseconds: 2800), () {
            if (mounted && _waitingForWeb) {
              setState(() => _showSlowNetworkHint = true);
            }
          });
        }
      }
    });

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _onComplete();
      }
    });

    // Failsafe timeout: if network is extremely slow, reveal app after 8.5 seconds
    _maxWaitTimer = Timer(const Duration(milliseconds: 8500), () {
      _onWebReady();
    });

    _controller.forward();
  }

  void _onWebReady() {
    if (_webReady || !mounted) return;
    _webReady = true;
    _maxWaitTimer?.cancel();
    _slowNetworkTimer?.cancel();
    if (_waitingForWeb) {
      _waitingForWeb = false;
      _pulseController.stop();
      _controller.forward();
    }
  }

  void _onComplete() {
    if (_navigated || !mounted) return;
    _navigated = true;
    _maxWaitTimer?.cancel();

    if (widget.onAnimationComplete != null) {
      widget.onAnimationComplete!();
      return;
    }

    if (widget.destination != null && widget.destination is! MainNavigation) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => widget.destination!,
          transitionsBuilder: (_, animation, _, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 700),
        ),
      );
      return;
    }

    setState(() {
      _overlayFading = true;
    });

    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() {
          _overlayVisible = false;
        });
      }
    });
  }

  @override
  void dispose() {
    if (_notifListener != null) {
      PushNotificationService.instance.notificationsOpened.removeListener(_notifListener!);
    }
    _maxWaitTimer?.cancel();
    _slowNetworkTimer?.cancel();
    _pulseController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOverlayActive = _overlayVisible && !_overlayFading;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isOverlayActive
          ? const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
              statusBarBrightness: Brightness.dark,
              systemNavigationBarColor: Colors.white,
              systemNavigationBarIconBrightness: Brightness.dark,
            )
          : AppTheme.systemOverlay,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: _activeDestination,
            ),
            if (_overlayVisible)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: _overlayFading,
                  child: AnimatedOpacity(
                    opacity: _overlayFading ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 380),
                    curve: Curves.easeOut,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        _onWebReady();
                        _controller.forward();
                      },
                      child: LayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      final h = constraints.maxHeight;

                      final cx = w / 2.0;
                      final initialCircleY = h * 0.354;
                      final circleRadius = (w * 0.215).clamp(64.0, 120.0);
                      final anchorRadius =
                          (circleRadius * 0.31).clamp(20.0, 36.0);

                      final logoWidth = circleRadius * 1.48;
                      final logoHeight = logoWidth * (324.0 / 762.0);

                      return AnimatedBuilder(
                        animation: Listenable.merge([_controller, _pulseController]),
                        builder: (context, _) {
                          final t = _controller.value;
                          final pulseVal = _waitingForWeb ? _pulseController.value : 0.0;
                          final pulseScale = _waitingForWeb ? (1.0 + 0.038 * (pulseVal - 0.5)) : 1.0;

                          double currentIrisRadius = circleRadius;
                          double circleY = initialCircleY;
                          double lineProgress = 0.0;
                          double anchorProgress = 0.0;
                          double sheetTop = h;

                          if (t < 0.25) {
                            final p1 = (t / 0.25).clamp(0.0, 1.0);
                            final e1 = Curves.easeInOutCubic.transform(p1);
                            final maxR = math.sqrt(w * w + h * h);
                            currentIrisRadius =
                                maxR - (maxR - circleRadius) * e1;
                            circleY = initialCircleY;
                            sheetTop = h;
                            lineProgress = 0.0;
                            anchorProgress = 0.0;
                          } else if (t < 0.65) {
                            currentIrisRadius = circleRadius;
                            circleY = initialCircleY;
                            sheetTop = h;

                            if (t < 0.50) {
                              final p2 = ((t - 0.25) / 0.25).clamp(0.0, 1.0);
                              lineProgress = Curves.easeOutCubic.transform(p2);
                            } else {
                              lineProgress = 1.0;
                            }

                            if (lineProgress > 0.65) {
                              final ap =
                                  ((lineProgress - 0.65) / 0.35).clamp(
                                0.0,
                                1.0,
                              );
                              anchorProgress = Curves.easeOutBack
                                  .transform(ap)
                                  .clamp(0.0, 1.0);
                            }
                          } else if (t < 0.95) {
                            currentIrisRadius = circleRadius;
                            final p4 = ((t - 0.65) / 0.30).clamp(0.0, 1.0);

                            final circleP = (p4 / 0.75).clamp(0.0, 1.0);
                            final eCircle = Curves.easeInOutCubic.transform(
                              circleP,
                            );
                            circleY = initialCircleY -
                                eCircle *
                                    (initialCircleY + circleRadius + 60.0);

                            final sheetP =
                                ((p4 - 0.12) / 0.88).clamp(0.0, 1.0);
                            final eSheet =
                                Curves.easeInOutCubic.transform(sheetP);
                            sheetTop = h - eSheet * h;

                            lineProgress = 1.0;
                            anchorProgress = 1.0;
                          } else {
                            circleY = -circleRadius - 100.0;
                            sheetTop = 0.0;
                            lineProgress = 1.0;
                            anchorProgress = 1.0;
                          }

                          final isCircleVisible = (circleY + circleRadius) > 0;

                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              CustomPaint(
                                size: Size(w, h),
                                painter: _SplashAnimationPainter(
                                  progress: t,
                                  circleY: circleY,
                                  circleRadius: circleRadius,
                                  irisRadius: currentIrisRadius,
                                  anchorRadius: anchorRadius,
                                  lineProgress: lineProgress,
                                  anchorProgress: anchorProgress,
                                  sheetTop: sheetTop,
                                  backgroundColor: AppTheme.neoBlue,
                                  foregroundColor: Colors.white,
                                  pulseProgress: pulseVal,
                                  isWaiting: _waitingForWeb,
                                ),
                              ),

                              if (isCircleVisible)
                                Positioned(
                                  left: cx - (logoWidth / 2.0),
                                  top: circleY - (logoHeight / 2.0),
                                  width: logoWidth,
                                  height: logoHeight,
                                  child: Transform.scale(
                                    scale: pulseScale,
                                    child: Image.asset(
                                      AppConfig.logoAsset,
                                      fit: BoxFit.contain,
                                      filterQuality: FilterQuality.high,
                                      errorBuilder: (_, _, _) =>
                                          const SizedBox.shrink(),
                                    ),
                                  ),
                                ),

                              if (_waitingForWeb && _showSlowNetworkHint)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  top: initialCircleY + circleRadius + 28,
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.18),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: const Text(
                                        'Connecting securely...',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 28,
                                child: Opacity(
                                  opacity: (1.0 - (t - 0.65) / 0.25)
                                      .clamp(0.0, 1.0),
                                  child: const Text(
                                    AppConfig.poweredBy,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SplashAnimationPainter extends CustomPainter {
  const _SplashAnimationPainter({
    required this.progress,
    required this.circleY,
    required this.circleRadius,
    required this.irisRadius,
    required this.anchorRadius,
    required this.lineProgress,
    required this.anchorProgress,
    required this.sheetTop,
    required this.backgroundColor,
    required this.foregroundColor,
    this.pulseProgress = 0.0,
    this.isWaiting = false,
  });

  final double progress;
  final double circleY;
  final double circleRadius;
  final double irisRadius;
  final double anchorRadius;
  final double lineProgress;
  final double anchorProgress;
  final double sheetTop;
  final Color backgroundColor;
  final Color foregroundColor;
  final double pulseProgress;
  final bool isWaiting;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2.0;
    final w = size.width;
    final h = size.height;

    final paintBg = Paint()
      ..color = backgroundColor
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;

    final paintWhite = Paint()
      ..color = foregroundColor
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;

    final paintLine = Paint()
      ..color = foregroundColor
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;

    if (progress < 0.25) {
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paintBg);
      canvas.drawCircle(Offset(cx, circleY), irisRadius, paintWhite);
    } else if (progress < 0.65) {
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paintBg);
      canvas.drawCircle(Offset(cx, circleY), circleRadius, paintWhite);

      final startY = circleY + circleRadius;
      final targetEndY = h;
      final endY = startY + (targetEndY - startY) * lineProgress;

      if (endY > startY) {
        canvas.drawLine(Offset(cx, startY), Offset(cx, endY), paintLine);
      }

      if (anchorProgress > 0.0) {
        final currentAnchorR = anchorRadius * anchorProgress;
        canvas.drawCircle(Offset(cx, h), currentAnchorR, paintWhite);
      }
    } else {
      if (sheetTop > 0.0) {
        canvas.drawRect(Rect.fromLTWH(0, 0, w, sheetTop), paintBg);
      }

      if (sheetTop < h) {
        canvas.drawCircle(Offset(cx, sheetTop), anchorRadius, paintWhite);
      }

      if ((circleY + circleRadius) > 0.0) {
        // Soft aura breathing ring while waiting for webview to finish loading
        if (isWaiting && pulseProgress > 0.0) {
          final auraRadius = circleRadius + 14.0 * pulseProgress;
          final paintAura = Paint()
            ..color = Colors.white.withOpacity(0.28 * (1.0 - pulseProgress))
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.0;
          canvas.drawCircle(Offset(cx, circleY), auraRadius, paintAura);
        }
        canvas.drawCircle(Offset(cx, circleY), circleRadius, paintWhite);
      }

      final lineTop = math.max(0.0, circleY + circleRadius);
      final lineBot = sheetTop;
      if (lineBot > lineTop) {
        canvas.drawLine(Offset(cx, lineTop), Offset(cx, lineBot), paintLine);
      }
    }
  }

  @override
  bool shouldRepaint(_SplashAnimationPainter old) {
    return old.progress != progress ||
        old.circleY != circleY ||
        old.circleRadius != circleRadius ||
        old.irisRadius != irisRadius ||
        old.anchorRadius != anchorRadius ||
        old.lineProgress != lineProgress ||
        old.anchorProgress != anchorProgress ||
        old.sheetTop != sheetTop ||
        old.pulseProgress != pulseProgress ||
        old.isWaiting != isWaiting;
  }
}
