import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/firebase_options.dart';
import 'notification_api.dart';

typedef PushTokenRegistrar = Future<bool> Function(String token, String platform);

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {}
}

class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  static const MethodChannel _channel = MethodChannel(
    'com.neosolution.ems/notifications',
  );

  final ValueNotifier<int> notificationsOpened = ValueNotifier(0);
  final ValueNotifier<int> inboxRefresh = ValueNotifier(0);

  bool _ready = false;
  bool _registering = false;
  bool _loggedIn = false;
  bool _openNotificationsRequested = false;
  String? _savedToken;
  PushTokenRegistrar? _registrar;
  Completer<bool>? _webRegisterCompleter;

  bool consumeOpenRequest() {
    final requested = _openNotificationsRequested;
    _openNotificationsRequested = false;
    return requested;
  }

  void requestOpenNotifications() {
    _openNotificationsRequested = true;
    notificationsOpened.value++;
  }

  void requestInboxRefresh() {
    inboxRefresh.value++;
  }

  void setRegistrar(PushTokenRegistrar? registrar) {
    _registrar = registrar;
  }

  void clearLoginSession() {
    _loggedIn = false;
    _savedToken = null;
    _registrar = null;
  }

  Future<bool> waitForWebRegister(Future<void> Function() start) async {
    _webRegisterCompleter = Completer<bool>();
    try {
      await start();
      return await _webRegisterCompleter!.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => false,
      );
    } catch (error) {
      debugPrint('ems push web register start failed: $error');
      return false;
    }
  }

  void completeWebRegister(dynamic payload) {
    final completer = _webRegisterCompleter;
    if (completer == null || completer.isCompleted) return;
    final map = payload is Map ? payload : const {};
    final status = int.tryParse('${map['status']}') ?? 0;
    debugPrint('ems push web register: $status ${map['body'] ?? map['error']}');
    completer.complete(status >= 200 && status < 300);
  }

  Future<void> init() async {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      await _ensureAndroidChannel();
      _channel.setMethodCallHandler(_onNativeCall);
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpened);
      FirebaseMessaging.instance.onTokenRefresh.listen(_onTokenRefresh);
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        requestOpenNotifications();
      }
      await _checkNativeLaunch();
      _ready = true;
    } catch (error) {
      debugPrint('ems push init failed: $error');
    }
  }

  Future<void> _onNativeCall(MethodCall call) async {
    if (call.method == 'opened') {
      requestOpenNotifications();
    }
  }

  Future<void> _checkNativeLaunch() async {
    if (!Platform.isAndroid) return;
    try {
      final opened = await _channel.invokeMethod<bool>('didOpenFromNotification');
      if (opened == true) {
        requestOpenNotifications();
      }
    } catch (_) {}
  }

  void _onMessageOpened(RemoteMessage message) {
    requestOpenNotifications();
    requestInboxRefresh();
  }

  Future<void> registerAfterLogin() async {
    if (!_ready || _registering) return;
    _loggedIn = true;
    _registering = true;
    try {
      String? token;
      for (var attempt = 0; attempt < 5 && (token == null || token.isEmpty); attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(Duration(seconds: attempt * 2));
        }
        token = await FirebaseMessaging.instance.getToken();
      }
      if (token == null || token.isEmpty) {
        debugPrint('ems push token missing after login');
        return;
      }
      // Always send the device token to the server on login so the token
      // is bound to the currently authenticated member/user account.
      await _registerToken(token);
    } catch (error) {
      debugPrint('ems push token failed: $error');
    } finally {
      _registering = false;
    }
  }

  Future<void> _onTokenRefresh(String token) async {
    if (!_loggedIn) return;
    if (_savedToken == token) return;
    await _registerToken(token);
  }

  Future<void> _registerToken(String token) async {
    if (!_loggedIn) return;
    final platform = Platform.isIOS ? 'ios' : 'android';
    var saved = false;

    final registrar = _registrar;
    if (registrar != null) {
      try {
        saved = await registrar(token, platform);
      } catch (error) {
        debugPrint('ems push web register failed: $error');
      }
    }

    if (!saved) {
      try {
        await NotificationApi.instance.registerToken(
          token: token,
          platform: platform,
        );
        saved = true;
      } catch (error) {
        debugPrint('ems push http register failed: $error');
      }
    }

    if (saved) {
      _savedToken = token;
    }
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    requestInboxRefresh();
    final title = message.notification?.title ?? message.data['title'] ?? 'EMS';
    final body = message.notification?.body ?? message.data['body'] ?? '';
    if (title.toString().trim().isEmpty && body.toString().trim().isEmpty) {
      return;
    }
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('show', {
          'title': title.toString(),
          'body': body.toString(),
        });
      } catch (error) {
        debugPrint('ems push foreground show failed: $error');
      }
    }
  }

  Future<void> _ensureAndroidChannel() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('ensureChannel');
    } catch (error) {
      debugPrint('ems push channel failed: $error');
    }
  }
}
