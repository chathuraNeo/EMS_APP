import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_config.dart';
import 'core/app_theme.dart';
import 'screens/splash_screen.dart';
import 'services/connectivity_service.dart';
import 'services/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setSystemUIOverlayStyle(AppTheme.systemOverlay);
  ConnectivityService.instance.start();

  // Run the app immediately so the native splash transitions to the Flutter UI smoothly without hanging
  runApp(const MyApp());

  // Initialize push notifications asynchronously
  unawaited(PushNotificationService.instance.init());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      theme: AppTheme.theme,
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(),
    );
  }
}