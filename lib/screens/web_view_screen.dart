import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../core/app_config.dart';
import '../core/app_theme.dart';
import '../services/connectivity_service.dart';
import '../services/device_permissions_service.dart';
import '../services/notification_api.dart';
import '../services/push_notification_service.dart';
import '../services/session_service.dart';
import '../services/webview_file_picker.dart';
import 'admin_blocked_screen.dart';

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({
    super.key,
    required this.initialUrl,
    this.onShowNavigationChanged,
    this.onPaymentListVisibleChanged,
    this.onUserRoleChanged,
    this.onInitialLoadFinished,
  });

  final String initialUrl;
  final ValueChanged<bool>? onShowNavigationChanged;
  final ValueChanged<bool>? onPaymentListVisibleChanged;
  final ValueChanged<UserRole>? onUserRoleChanged;
  final VoidCallback? onInitialLoadFinished;

  @override
  State<WebViewScreen> createState() => WebViewScreenState();
}

class WebViewScreenState extends State<WebViewScreen>
    with AutomaticKeepAliveClientMixin {
  late final WebViewController _controller;

  bool _online = true;
  bool _checking = true;
  bool _adminBlocked = false;
  bool _showNavigation = false;
  bool _paymentListVisible = false;
  String? _pendingPage;
  UserRole _currentRole = UserRole.unknown;
  late final WebViewFilePicker _filePicker;
  bool _initialLoadReported = false;

  void _markInitialLoadFinished() {
    if (_initialLoadReported) return;
    _initialLoadReported = true;
    widget.onInitialLoadFinished?.call();
  }

  UserRole get currentRole => _currentRole;

  void _setRole(UserRole role) {
    if (role == UserRole.unknown || _currentRole == role) return;
    _currentRole = role;
    widget.onUserRoleChanged?.call(role);
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    _filePicker = WebViewFilePicker(() => mounted ? context : null);

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppTheme.cream)
      ..enableZoom(false)
      ..setUserAgent(
        Platform.isIOS
            ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 EMS-App/1.0'
            : 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36 EMS-App/1.0',
      )
      ..addJavaScriptChannel(
        'EMSApp',
        onMessageReceived: _onAppMessage,
      )
      ..addJavaScriptChannel(
        'BMJMApp',
        onMessageReceived: _onAppMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (AppConfig.isAdminUrl(request.url)) {
              _blockAdmin(reason: 'admin_url', url: request.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onProgress: (progress) {
            if (!mounted) return;
            if (progress >= 100) {
              _markInitialLoadFinished();
            }
          },
          onPageStarted: (url) {
            if (AppConfig.isAdminUrl(url)) {
              _blockAdmin(reason: 'admin_url', url: url);
              return;
            }
            final r = AppConfig.roleFromUrl(url);
            if (r != UserRole.unknown) {
              _setRole(r);
            }
            if (!AppConfig.shouldShowAppNavigation(url)) {
              _setShowNavigation(false);
            }
            _installAdminUrlGuard();
            _controller.runJavaScript('''
              (function(){
                document.documentElement.classList.add('ems-in-app');
                document.documentElement.classList.add('bmjm-in-app');
                if (document.body) {
                  document.body.classList.add('ems-in-app');
                  document.body.classList.add('bmjm-in-app');
                }
                try { document.cookie = "ems_in_app=1; path=/; max-age=31536000"; } catch(e) {}
              })();
            ''');
            _hideSiteMenuButton();
          },
          onPageFinished: (url) {
            if (!mounted || _adminBlocked || url == 'about:blank') return;
            if (AppConfig.isAdminUrl(url)) {
              _blockAdmin(reason: 'admin_url', url: url);
              return;
            }
            _markInitialLoadFinished();
            _onPageReady(url);
          },
          onUrlChange: (change) {
            final url = change.url;
            if (url == null) return;
            if (AppConfig.isAdminUrl(url)) {
              _blockAdmin(reason: 'admin_url', url: url);
              return;
            }
            final r = AppConfig.roleFromUrl(url);
            if (r != UserRole.unknown) {
              _setRole(r);
            }
            if (!AppConfig.shouldShowAppNavigation(url)) {
              _setShowNavigation(false);
            }
          },
          onWebResourceError: (error) {
            if (!_isNetworkError(error)) return;
            _markInitialLoadFinished();
            ConnectivityService.instance.markOffline();
            if (mounted) setState(() => _online = false);
          },
        ),
      );

    ConnectivityService.instance.isOnline.addListener(_onConnectivityChanged);

    _enableNativeCapabilities();
    _bootstrap();
  }

  Future<void> _enableNativeCapabilities() async {
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      await platform.setOnShowFileSelector(_filePicker.onShowFileSelector);
      await platform.setAllowFileAccess(true);
      await platform.setAllowContentAccess(true);
      await platform.setGeolocationEnabled(true);
      await platform.setGeolocationPermissionsPromptCallbacks(
        onShowPrompt: (request) async => const GeolocationPermissionsResponse(
          allow: true,
          retain: true,
        ),
      );
      await platform.setOnPlatformPermissionRequest(
        (request) => request.grant(),
      );
    } else if (platform is WebKitWebViewController) {
      await platform.setOnPlatformPermissionRequest(
        (request) => request.grant(),
      );
    }

    _filePicker.recoverLostDataIfNeeded((uri) {
      debugPrint('ems recovered lost photo uri: $uri');
    });
  }

  Future<void> _bootstrap() async {
    unawaited(DevicePermissionsService.instance.requestAllPermissions());
    final online = await ConnectivityService.instance.hasConnection();
    if (!mounted) return;
    setState(() {
      _online = online;
      _checking = false;
    });
    if (online) {
      _loadInitial();
    } else {
      _markInitialLoadFinished();
    }
  }

  void _onConnectivityChanged() {
    if (!mounted) return;
    final online = ConnectivityService.instance.isOnline.value;
    final wasOffline = !_online;
    setState(() => _online = online);
    if (online && wasOffline) {
      _loadInitial();
    }
  }

  bool _isNetworkError(WebResourceError error) {
    const networkTypes = {
      WebResourceErrorType.hostLookup,
      WebResourceErrorType.connect,
      WebResourceErrorType.timeout,
    };
    if (networkTypes.contains(error.errorType)) return true;

    final description = error.description.toUpperCase();
    return description.contains('NAME_NOT_RESOLVED') ||
        description.contains('INTERNET_DISCONNECTED') ||
        description.contains('ADDRESS_UNREACHABLE') ||
        description.contains('CONNECTION_ABORTED') ||
        description.contains('TIMED_OUT') ||
        description.contains('NETWORK_CHANGED');
  }

  void _loadInitial() {
    if (AppConfig.isAdminUrl(widget.initialUrl)) {
      _blockAdmin(reason: 'admin_url', url: widget.initialUrl);
      return;
    }
    _controller.loadRequest(Uri.parse(widget.initialUrl));
  }

  void _onAppMessage(JavaScriptMessage message) {
    try {
      final payload = jsonDecode(message.message);
      if (payload is! Map) return;
      final type = payload['type']?.toString();
      if (type == 'admin_blocked') {
        _blockAdmin(
          reason: payload['reason']?.toString() ?? 'login_access_id',
          accessId: payload['accessId']?.toString(),
          url: payload['url']?.toString() ?? AppConfig.adminDashboardUrl,
        );
        return;
      }
      if (type == 'role_detected') {
        final rStr = payload['role']?.toString();
        final level = payload['level']?.toString();
        final url = payload['url']?.toString();
        UserRole detected = AppConfig.roleFromString(rStr);
        if (detected == UserRole.unknown) {
          detected = AppConfig.roleFromAccessId(level);
        }
        if (detected == UserRole.unknown) {
          detected = AppConfig.roleFromUrl(url);
        }
        _setRole(detected);
        return;
      }
      if (type == 'token_registered') {
        PushNotificationService.instance.completeWebRegister(payload);
        return;
      }
      if (type == 'bridge') {
        _completeBridge(payload);
        return;
      }
      if (type == 'ui') {
        _setPaymentListVisible(payload['paymentList'] == true);
      }
    } catch (_) {
      if (message.message.contains('admin_blocked')) {
        _blockAdmin(reason: 'login_access_id');
      }
    }
  }

  Future<void> _onPageReady(String url) async {
    if (_adminBlocked || AppConfig.isAdminUrl(url)) {
      _setShowNavigation(false);
      return;
    }
    await _installAdminUrlGuard();
    await _hideSiteMenuButton();
    await _installFileUploadFix();
    await _installUiBridge();
    await _checkAccessCookie(url);
    if (_adminBlocked) {
      _setShowNavigation(false);
      return;
    }
    await _detectAndApplyRole(url);
    final isReady = await _isMemberSessionReady(url);
    _setShowNavigation(isReady);
    if (isReady) {
      PushNotificationService.instance.setRegistrar(_registerTokenInWebView);
      NotificationApi.instance.setWebFetcher(_webFetch);
      PushNotificationService.instance.registerAfterLogin();
    }
    await _tryOpenPending();
  }

  Future<void> _detectAndApplyRole(String url) async {
    UserRole detected = AppConfig.roleFromUrl(url);
    if (detected == UserRole.unknown) {
      try {
        final res = await _controller.runJavaScriptReturningResult('''
          (function(){
            if (typeof member_dashboard_01_A_OPEN === 'function') return 'member';
            if (typeof manager_dashboard_01_A_OPEN === 'function') return 'manager';
            if (typeof cash_owner_dashboard_01_A_OPEN === 'function') return 'cash_owner';
            var p = (window.location.pathname || '').toLowerCase();
            if (p.indexOf('member_dashboard') !== -1) return 'member';
            if (p.indexOf('manager_dashboard') !== -1) return 'manager';
            if (p.indexOf('cash_owner_dashboard') !== -1) return 'cash_owner';
            return '';
          })();
        ''');
        final str = res.toString().replaceAll('"', '').trim();
        detected = AppConfig.roleFromString(str);
      } catch (_) {}
    }
    if (detected != UserRole.unknown) {
      _setRole(detected);
    }
  }

  final Map<String, Completer<Map<String, dynamic>>> _bridgeWaiters = {};
  int _bridgeId = 0;

  void _setShowNavigation(bool show) {
    if (show && !_showNavigation) {
      PushNotificationService.instance.setRegistrar(_registerTokenInWebView);
      NotificationApi.instance.setWebFetcher(_webFetch);
      PushNotificationService.instance.registerAfterLogin();
    } else if (!show && _showNavigation) {
      PushNotificationService.instance.clearLoginSession();
      NotificationApi.instance.setWebFetcher(null);
    }
    if (_showNavigation == show) return;
    _showNavigation = show;
    widget.onShowNavigationChanged?.call(show);
    if (!show) {
      _setPaymentListVisible(false);
    }
  }

  void _setPaymentListVisible(bool visible) {
    if (_paymentListVisible == visible) return;
    _paymentListVisible = visible;
    widget.onPaymentListVisibleChanged?.call(visible);
  }

  void _completeBridge(dynamic payload) {
    final map = payload is Map ? Map<String, dynamic>.from(payload) : <String, dynamic>{};
    final id = map['id']?.toString() ?? '';
    final waiter = _bridgeWaiters.remove(id);
    if (waiter == null || waiter.isCompleted) return;
    waiter.complete(map);
  }

  Future<NotificationWebResponse?> _webFetch({
    required String url,
    String method = 'GET',
    String? body,
  }) async {
    final id = 'bridge-${++_bridgeId}';
    final waiter = Completer<Map<String, dynamic>>();
    _bridgeWaiters[id] = waiter;
    await _controller.runJavaScript('''
      (function(){
        fetch(${jsonEncode(url)}, {
          method: ${jsonEncode(method)},
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/x-www-form-urlencoded'
          },
          credentials: 'include',
          body: ${body == null ? 'undefined' : jsonEncode(body)}
        }).then(function(res){
          return res.text().then(function(text){
            var bridge = window.EMSApp || window.BMJMApp;
            if (bridge) {
              bridge.postMessage(JSON.stringify({
                type: 'bridge',
                id: ${jsonEncode(id)},
                status: res.status,
                body: text
              }));
            }
          });
        }).catch(function(err){
          var bridge = window.EMSApp || window.BMJMApp;
          if (bridge) {
            bridge.postMessage(JSON.stringify({
              type: 'bridge',
              id: ${jsonEncode(id)},
              status: 0,
              error: String(err)
            }));
          }
        });
      })();
    ''');
    try {
      final payload = await waiter.future.timeout(const Duration(seconds: 15));
      return NotificationWebResponse(
        status: int.tryParse('${payload['status']}') ?? 0,
        body: '${payload['body'] ?? ''}',
      );
    } catch (_) {
      _bridgeWaiters.remove(id);
      return null;
    }
  }

  Future<bool> _registerTokenInWebView(String token, String platform) {
    return PushNotificationService.instance.waitForWebRegister(() async {
      final body =
          'token=${Uri.encodeQueryComponent(token)}&platform=${Uri.encodeQueryComponent(platform)}';
      await _controller.runJavaScript('''
        (function(){
          fetch(${jsonEncode(AppConfig.notificationRegisterTokenUrl)}, {
            method: 'POST',
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/x-www-form-urlencoded'
            },
            credentials: 'include',
            body: ${jsonEncode(body)}
          }).then(function(res){
            return res.text().then(function(text){
              var bridge = window.EMSApp || window.BMJMApp;
              if (bridge) {
                bridge.postMessage(JSON.stringify({
                  type: 'token_registered',
                  status: res.status,
                  body: text
                }));
              }
            });
          }).catch(function(err){
            var bridge = window.EMSApp || window.BMJMApp;
            if (bridge) {
              bridge.postMessage(JSON.stringify({
                type: 'token_registered',
                status: 0,
                error: String(err)
              }));
            }
          });
        })();
      ''');
    });
  }

  Future<bool> _isMemberSessionReady(String url) async {
    if (!AppConfig.shouldShowAppNavigation(url)) return false;
    try {
      final result = await _controller.runJavaScriptReturningResult('''
        (function(){
          if (document.querySelector('#email') && document.querySelector('#password')) return 'no';
          if (typeof cash_owner_dashboard_01_A_OPEN === 'function') return 'yes';
          if (typeof manager_dashboard_01_A_OPEN === 'function') return 'yes';
          if (typeof member_dashboard_01_A_OPEN === 'function') return 'yes';
          if (typeof user_dashboard_01_A_OPEN === 'function') return 'yes';
          if (typeof user_dashboard_00_OPEN === 'function') return 'yes';
          if (typeof main_dashboard_00_OPEN === 'function') return 'yes';
          if (document.querySelector('#appSidebar') || document.querySelector('.app-sidebar')) return 'yes';
          if (document.querySelector('.bmjm-sidebar-nav-item')) return 'yes';
          var html = document.documentElement ? document.documentElement.innerHTML : '';
          if (html.length > 8000) return 'yes';
          return 'no';
        })();
      ''');
      return result.toString().contains('yes');
    } catch (_) {
      return false;
    }
  }

  Future<void> _checkAccessCookie(String url) async {
    if (_adminBlocked) return;

    String? documentCookie;
    try {
      documentCookie = (await _controller.runJavaScriptReturningResult(
        'document.cookie',
      ))
          .toString();
    } catch (_) {}

    final accessId = await SessionService.instance.readAccessId(
      documentCookie: documentCookie,
    );

    if (SessionService.instance.shouldBlockAccess(url: url, accessId: accessId)) {
      await _blockAdmin(
        reason: 'access_cookie',
        accessId: accessId,
        url: url,
      );
    }
  }

  Future<void> _blockAdmin({
    required String reason,
    String? accessId,
    String? url,
  }) async {
    if (_adminBlocked) return;

    SessionService.instance.logBlockedAttempt(
      reason: reason,
      accessId: accessId,
      url: url,
    );

    if (mounted) {
      setState(() => _adminBlocked = true);
    }
    _setShowNavigation(false);
    _markInitialLoadFinished();

    try {
      await _controller.loadRequest(Uri.parse('about:blank'));
    } catch (_) {}

    await SessionService.instance.logout();
  }

  Future<void> _returnToLogin() async {
    await SessionService.instance.logout();
    if (!mounted) return;
    setState(() => _adminBlocked = false);
    _setShowNavigation(false);
    await _controller.loadRequest(Uri.parse(AppConfig.homeUrl));
  }

  Future<void> openSiteSection(String page) async {
    _pendingPage = page;
    await _tryOpenPending();
  }

  Future<void> _tryOpenPending() async {
    final page = _pendingPage;
    if (page == null || !_online || _adminBlocked) return;

    try {
      final result = await _controller.runJavaScriptReturningResult(
        _openSectionScript(page),
      );
      final value = result.toString();
      if (value.contains('ok') || value.contains('click')) {
        _pendingPage = null;
      }
      await _hideSiteMenuButton();
      await _installFileUploadFix();
      await _installUiBridge();
    } catch (_) {
      // Page may still be login or mid-navigation; retry on next finish.
    }
  }

  Future<void> _hideSiteMenuButton() async {
    if (!_online) return;
    try {
      await _controller.runJavaScript(_hideMenuScript);
    } catch (_) {}
  }

  Future<void> _installFileUploadFix() async {
    if (!_online || _adminBlocked) return;
    try {
      await _controller.runJavaScript(_fileUploadFixScript);
    } catch (_) {}
  }

  Future<void> _installUiBridge() async {
    if (!_online || _adminBlocked) return;
    try {
      await _controller.runJavaScript(_uiBridgeScript);
    } catch (_) {}
  }

  Future<void> _installAdminUrlGuard() async {
    if (!_online || _adminBlocked) return;
    try {
      await _controller.runJavaScript(_adminUrlGuardScript);
    } catch (_) {}
  }

  String _openSectionScript(String page) {
    return '''
      (function(){
        var target = ${jsonEncode(page)};
        var actions = {
          // Member section actions
          member_home: ['member_dashboard_01_A_OPEN'],
          member_claims: ['member_dashboard_02_A_OPEN'],
          member_funds: ['member_dashboard_03_A_OPEN'],
          member_return: ['member_dashboard_05_A_OPEN'],
          member_vehicles: ['member_dashboard_06_A_OPEN'],

          // Cash Owner section actions
          cash_owner_home: ['cash_owner_dashboard_01_A_OPEN'],
          cash_owner_payment: ['cash_owner_dashboard_06_A_OPEN'],
          cash_owner_expense: ['cash_owner_dashboard_05_A_OPEN'],
          cash_owner_cheques: ['cash_owner_dashboard_11_A_OPEN'],
          cash_owner_users: ['cash_owner_dashboard_10_A_OPEN'],
          cash_owner_user_audit: ['cash_owner_dashboard_09_C_OPEN'],
          cash_owner_wallet_transfer: ['Cash_owner_dashboard_wallet_transfer_open_modal'],
          cash_owner_banks: ['cash_owner_dashboard_02_A_OPEN'],
          cash_owner_cash_safes: ['cash_owner_dashboard_03_A_OPEN'],
          cash_owner_reports: ['cash_owner_dashboard_12_A_OPEN'],
          cash_owner_vehicles: ['cash_owner_dashboard_13_A_OPEN'],
          cash_owner_settings: ['cash_owner_dashboard_08_A_OPEN'],
          cash_owner_categories: ['cash_owner_dashboard_07_A_OPEN'],
          cash_owner_topup_history: ['cash_owner_dashboard_09_A_OPEN'],
          cash_owner_wallet_audit: ['cash_owner_dashboard_09_B_OPEN'],

          // Manager section actions
          manager_home: ['manager_dashboard_01_A_OPEN'],
          manager_members: ['manager_dashboard_02_A_OPEN'],
          manager_claims: ['manager_dashboard_03_A_OPEN'],
          manager_payment: ['manager_dashboard_04_A_OPEN'],
          manager_vehicles: ['manager_dashboard_08_A_OPEN'],
          manager_settings: ['manager_dashboard_06_A_OPEN'],

          // Common aliases & fallbacks
          home: [
            'member_dashboard_01_A_OPEN',
            'cash_owner_dashboard_01_A_OPEN',
            'manager_dashboard_01_A_OPEN',
            'main_dashboard_00_OPEN',
            'user_dashboard_00_OPEN',
            'user_dashboard_01_A_OPEN'
          ],
          dashboard: [
            'member_dashboard_01_A_OPEN',
            'cash_owner_dashboard_01_A_OPEN',
            'manager_dashboard_01_A_OPEN',
            'main_dashboard_00_OPEN',
            'user_dashboard_00_OPEN',
            'user_dashboard_01_A_OPEN'
          ],
          payment: [
            'cash_owner_dashboard_06_A_OPEN',
            'manager_dashboard_04_A_OPEN',
            'member_dashboard_03_A_OPEN',
            'main_dashboard_02_A_OPEN',
            'user_dashboard_02_A_OPEN'
          ],
          pay_now: [
            'user_dashboard_pay_now',
            'user_dashboard_02_B_OPEN',
            'main_dashboard_02_B_OPEN'
          ],
          settings: [
            'cash_owner_dashboard_08_A_OPEN',
            'manager_dashboard_06_A_OPEN',
            'member_dashboard_04_A_OPEN',
            'main_dashboard_05_01_OPEN',
            'user_dashboard_05_01_OPEN',
            'user_dashboard_05_OPEN'
          ],
          vehicles: [
            'member_dashboard_06_A_OPEN',
            'manager_dashboard_08_A_OPEN',
            'cash_owner_dashboard_13_A_OPEN'
          ]
        };

        var fns = actions[target] || [target];
        for (var i = 0; i < fns.length; i++) {
          var fn = window[fns[i]];
          if (typeof fn === 'function') {
            try { fn(); return 'ok'; } catch (e) {}
          }
        }

        if (target === 'pay_now') {
          var payBtn = document.querySelector('.btn-pay-action');
          if (payBtn) {
            payBtn.click();
            return 'click';
          }
        }

        var tabMap = {
          member_home: 'summary',
          member_claims: 'expenses',
          member_funds: 'payments',
          member_return: 'return',
          member_vehicles: 'vehicles',
          cash_owner_home: 'summary',
          cash_owner_payment: 'payments',
          cash_owner_expense: 'expenses',
          cash_owner_cheques: 'checks',
          cash_owner_users: 'manage_users',
          cash_owner_user_audit: 'user_balance_audit',
          cash_owner_wallet_transfer: 'wallet_transfer',
          cash_owner_banks: 'bank_accounts',
          cash_owner_cash_safes: 'cash_accounts',
          cash_owner_reports: 'reports',
          cash_owner_vehicles: 'vehicles',
          cash_owner_settings: 'settings',
          cash_owner_categories: 'categories',
          cash_owner_topup_history: 'topup_history',
          cash_owner_wallet_audit: 'wallet_audit',
          manager_home: 'summary',
          manager_members: 'assigned_members',
          manager_claims: 'expenses',
          manager_payment: 'payments',
          manager_vehicles: 'vehicles',
          manager_settings: 'settings'
        };
        var tab = tabMap[target] || target;

        var navTab = document.querySelector('.nav-item[data-tab="' + tab + '"]')
          || document.querySelector('[data-page="' + tab + '"]');
        if (navTab) {
          navTab.click();
          return 'click';
        }

        var item = document.querySelector('.bmjm-sidebar-nav-item[data-page="' + tab + '"]');
        if (item) {
          item.click();
          return 'click';
        }

        var link = document.querySelector('[data-page="' + tab + '"] a');
        if (link) {
          link.click();
          return 'click';
        }

        return 'missing';
      })();
    ''';
  }

  static const String _adminUrlGuardScript = '''
    (function(){
      function isAdminUrl(url) {
        var value = String(url || '').toLowerCase();
        return value.indexOf('admin_dashboard') !== -1
          || value.indexOf('admin-dashboard') !== -1
          || value.indexOf('admindashboard') !== -1
          || value.indexOf('main-dashboard.php') !== -1
          || value.indexOf('main_dashboard.php') !== -1
          || value.indexOf('maindashboard.php') !== -1;
      }
      function notify(reason, url, accessId) {
        try {
          var bridge = window.EMSApp || window.BMJMApp;
          if (bridge) {
            bridge.postMessage(JSON.stringify({
              type: 'admin_blocked',
              reason: reason || 'admin_url',
              url: String(url || ''),
              accessId: accessId || ''
            }));
          }
        } catch (e) {}
      }
      function notifyRole(role, level, url) {
        try {
          var bridge = window.EMSApp || window.BMJMApp;
          if (bridge) {
            bridge.postMessage(JSON.stringify({
              type: 'role_detected',
              role: role || '',
              level: level || '',
              url: url || ''
            }));
          }
        } catch (e) {}
      }
      function block(reason, url, accessId) {
        notify(reason, url, accessId);
        try { window.location.replace('about:blank'); } catch (e) {}
      }

      if (isAdminUrl(window.location.href)) {
        block('admin_url', window.location.href);
        return;
      }

      if (!window.__emsAdminNavGuard) {
        window.__emsAdminNavGuard = true;
        document.addEventListener('click', function(event) {
          var link = event.target && event.target.closest ? event.target.closest('a') : null;
          if (!link || !isAdminUrl(link.href)) return;
          event.preventDefault();
          event.stopPropagation();
          block('admin_link', link.href);
        }, true);

        try {
          var assign = window.location.assign.bind(window.location);
          var replace = window.location.replace.bind(window.location);
          window.location.assign = function(url) {
            if (isAdminUrl(url)) { block('admin_assign', url); return; }
            return assign(url);
          };
          window.location.replace = function(url) {
            if (isAdminUrl(url)) { block('admin_replace', url); return; }
            return replace(url);
          };
        } catch (e) {}

        setInterval(function() {
          if (isAdminUrl(window.location.href)) {
            block('admin_url', window.location.href);
          }
        }, 200);
      }

      function hookLoginAjax() {
        if (window.__emsLoginGuard) return;
        if (typeof window.\$ === 'undefined' || !\$.ajax) {
          setTimeout(hookLoginAjax, 80);
          return;
        }
        window.__emsLoginGuard = true;
        var origAjax = \$.ajax;
        \$.ajax = function(options) {
          var settings = options || {};
          var origSuccess = settings.success;
          settings.success = function(res) {
            try {
              var json = typeof res === 'object' ? res : JSON.parse(res);
              var row = json && json[0];
              if (row && (row.error === '0' || !row.error)) {
                var level = String(row.access_level_id || row.main_user_account_access_level_list_id || '');
                var role = String(row.role || '').toLowerCase();
                var redirectUrl = String(row.redirect_url || '').toLowerCase();
                // Block ONLY admin access (level 1 / role 'admin').
                // The other 3 users (Cash Owner: 2, Manager: 3, Member: 4) use the app freely!
                if (level === '${AppConfig.adminAccessId}' || role === 'admin' || redirectUrl.indexOf('admin_dashboard') !== -1 || redirectUrl.indexOf('main-dashboard') !== -1) {
                  block('login_access_id', row.redirect_url || '${AppConfig.adminDashboardUrl}', level);
                  return;
                }
                notifyRole(role, level, row.redirect_url);
              }
            } catch (e) {}
            if (typeof origSuccess === 'function') {
              return origSuccess.apply(this, arguments);
            }
          };
          return origAjax.call(this, settings);
        };
      }
      hookLoginAjax();
    })();
  ''';

  static const String _fileUploadFixScript = '''
    (function(){
      function patchFileInputs() {
        var input = document.getElementById('ud2d-file-input');
        var dropzone = document.getElementById('ud2d-dropzone');
        if (!input) return;
        input.setAttribute('accept', input.getAttribute('accept') || 'image/*');
        if (dropzone) {
          var style = window.getComputedStyle(dropzone);
          if (style.position === 'static') {
            dropzone.style.position = 'relative';
          }
          dropzone.removeAttribute('onclick');
          dropzone.onclick = null;
          if (input.parentElement !== dropzone) {
            dropzone.appendChild(input);
          }
        }
        input.style.setProperty('display', 'block', 'important');
        input.style.setProperty('opacity', '0.011', 'important');
        input.style.setProperty('position', 'absolute', 'important');
        input.style.setProperty('left', '0', 'important');
        input.style.setProperty('top', '0', 'important');
        input.style.setProperty('width', '100%', 'important');
        input.style.setProperty('height', '100%', 'important');
        input.style.setProperty('z-index', '6', 'important');
        input.style.setProperty('cursor', 'pointer', 'important');
        input.style.setProperty('font-size', '64px', 'important');
        input.style.setProperty('margin', '0', 'important');
        input.style.setProperty('padding', '0', 'important');
        input.setAttribute('data-ems-file-ready', '1');
      }
      patchFileInputs();
      if (!window.__emsFilePatchObs) {
        window.__emsFilePatchObs = true;
        new MutationObserver(patchFileInputs).observe(
          document.documentElement,
          { childList: true, subtree: true }
        );
      }
    })();
  ''';

  static const String _uiBridgeScript = '''
    (function(){
      function visible(el) {
        if (!el) return false;
        var st = window.getComputedStyle(el);
        if (st.display === 'none' || st.visibility === 'hidden') return false;
        return el.offsetWidth > 0 && el.offsetHeight > 0;
      }
      window.__emsUiBridgeRun = function() {
        var list = document.getElementById('user_dashboard_02_A');
        var isList = visible(list);
        if (window.__emsPayListVisible === isList) return;
        window.__emsPayListVisible = isList;
        try {
          var bridge = window.EMSApp || window.BMJMApp;
          if (bridge) {
            bridge.postMessage(JSON.stringify({
              type: 'ui',
              paymentList: isList
            }));
          }
        } catch (e) {}
      };
      window.__emsUiBridgeRun();
      if (!window.__emsUiBridgeObs) {
        window.__emsUiBridgeObs = true;
        new MutationObserver(window.__emsUiBridgeRun).observe(
          document.documentElement,
          { childList: true, subtree: true, attributes: true, attributeFilter: ['style', 'class'] }
        );
      }
    })();
  ''';

  static const String _hideMenuScript = '''
    (function(){
      function applyAppClasses() {
        if (document.documentElement) {
          document.documentElement.classList.add('ems-in-app');
          document.documentElement.classList.add('bmjm-in-app');
        }
        if (document.body) {
          document.body.classList.add('ems-in-app');
          document.body.classList.add('bmjm-in-app');
          document.body.classList.remove('sidebar-open', 'bmjm-mobile-menu-open');
        }
        try { document.cookie = "ems_in_app=1; path=/; max-age=31536000"; } catch(e) {}
      }
      applyAppClasses();

      function injectCss() {
        if (document.getElementById('ems-app-hide-menu')) return;
        var style = document.createElement('style');
        style.id = 'ems-app-hide-menu';
        style.textContent = [
          /* Unconditionally hide all sidebars and sidebar toggles in mobile app */
          '.app-sidebar,',
          '#appSidebar,',
          'aside.app-sidebar,',
          '.sidebar-backdrop,',
          '#sidebarBackdrop,',
          '.mobile-hamburger-btn,',
          '#mobileSidebarToggle,',
          'button#mobileSidebarToggle,',
          '.sidebar-mobile-close-btn,',
          '.sidebar-brand,',
          '.sidebar-nav,',
          '.sidebar-footer,',
          '.bmjm-sidebar,',
          '#bmjm-sidebar-root,',
          'aside.bmjm-sidebar,',
          '.mobile-menu-fab,',
          '.bmjm-menu-fab,',
          '.bmjm-sidebar-toggle,',
          '.bmjm-mobile-toggle,',
          '.bmjm-hamburger,',
          '#bmjm-menu-btn,',
          '#bmjm-sidebar-toggle,',
          '.mobile-menu-btn,',
          '.sidebar-toggle-btn,',
          'button.menu-toggle,',
          '.bmjm-mobile-menu,',
          '.user-dash-menu,',
          '.bmjm-mobile-menu-button,',
          '.bmjm-sidebar-close,',
          '.ud-menu-btn {',
          '  display: none !important;',
          '  visibility: hidden !important;',
          '  opacity: 0 !important;',
          '  pointer-events: none !important;',
          '  width: 0 !important;',
          '  min-width: 0 !important;',
          '  max-width: 0 !important;',
          '  height: 0 !important;',
          '  min-height: 0 !important;',
          '  max-height: 0 !important;',
          '  overflow: hidden !important;',
          '  transform: translateX(-9999px) !important;',
          '  margin: 0 !important;',
          '  padding: 0 !important;',
          '  position: absolute !important;',
          '  left: -9999px !important;',
          '  top: -9999px !important;',
          '}',
          /* Full width main container without sidebar offset */
          '.app-main,',
          'main.app-main {',
          '  margin-left: 0 !important;',
          '  margin-right: 0 !important;',
          '  width: 100% !important;',
          '  max-width: 100% !important;',
          '  padding-left: 0 !important;',
          '}',
          /* Unconditionally show the Cash Owner brand logo in mobile app topbar */
          '.topbar-brand-logo-wrap {',
          '  display: inline-flex !important;',
          '  visibility: visible !important;',
          '  opacity: 1 !important;',
          '  align-items: center !important;',
          '  justify-content: center !important;',
          '  margin-right: 10px !important;',
          '  flex-shrink: 0 !important;',
          '}',
          '.page-title-box {',
          '  display: flex !important;',
          '  flex-direction: column !important;',
          '  min-width: 0 !important;',
          '}',
          '.page-title-box h1 {',
          '  font-size: 13.5px !important;',
          '  line-height: 1.2 !important;',
          '  white-space: nowrap !important;',
          '  overflow: hidden !important;',
          '  text-overflow: ellipsis !important;',
          '}',
          '@media (max-width:900px) {',
          '  .dashboard2-topbar,',
          '  .dashboard3-topbar {',
          '    grid-template-columns:minmax(0,1fr) auto !important;',
          '  }',
          '}',
          '.ud2c-app,',
          '.ud2d-app,',
          '.ud2e-app,',
          '.payment-new-app,',
          '.notify-app {',
          '  grid-template-columns:minmax(0,1fr) !important;',
          '  grid-template-areas:"topbar" "main" !important;',
          '}',
          '.btn-pay-action {',
          '  display:none !important;',
          '}'
        ].join('');
        (document.head || document.documentElement).appendChild(style);
      }

      function hideNode(el) {
        if (!el) return;
        el.setAttribute('data-ems-hidden-menu', '1');
        el.classList.remove('sidebar-open', 'open', 'active');
        el.style.setProperty('display', 'none', 'important');
        el.style.setProperty('visibility', 'hidden', 'important');
        el.style.setProperty('opacity', '0', 'important');
        el.style.setProperty('pointer-events', 'none', 'important');
        el.style.setProperty('width', '0px', 'important');
        el.style.setProperty('height', '0px', 'important');
        el.style.setProperty('transform', 'translateX(-9999px)', 'important');
      }

      function hideSiteSidebar() {
        var selectors = [
          '.app-sidebar',
          '#appSidebar',
          'aside.app-sidebar',
          '.sidebar-backdrop',
          '#sidebarBackdrop',
          '.mobile-hamburger-btn',
          '#mobileSidebarToggle',
          'button#mobileSidebarToggle',
          '.sidebar-mobile-close-btn',
          '.bmjm-sidebar',
          '#bmjm-sidebar-root',
          '.mobile-menu-fab',
          '.bmjm-mobile-menu-button',
          '.bmjm-sidebar-close'
        ];
        document.querySelectorAll(selectors.join(',')).forEach(hideNode);

        if (document.body) {
          document.body.classList.remove('sidebar-open', 'open', 'bmjm-mobile-menu-open');
        }

        /* Guarantee topbar brand logo displays */
        document.querySelectorAll('.topbar-brand-logo-wrap').forEach(function(wrap) {
          wrap.style.setProperty('display', 'inline-flex', 'important');
          wrap.style.setProperty('visibility', 'visible', 'important');
          wrap.style.setProperty('opacity', '1', 'important');
        });

        /* Neutralize sidebar toggle functions */
        try {
          window.open_mobile_sidebar = function() {};
          window.openMemberMobileSidebar = function() {};
          window.openCashOwnerMobileSidebar = function() {};
          window.openManagerMobileSidebar = function() {};
          window.toggleMemberMobileSidebar = function() {};
          window.toggleCashOwnerMobileSidebar = function() {};
          window.toggleManagerMobileSidebar = function() {};
          window.closeMemberMobileSidebar = function() {};
          window.closeCashOwnerMobileSidebar = function() {};
          window.closeManagerMobileSidebar = function() {};
        } catch (e) {}
      }

      function isGold(color) {
        var m = String(color || '').match(/rgba?\\((\\d+),\\s*(\\d+),\\s*(\\d+)/);
        if (!m) return false;
        var r = +m[1], g = +m[2], b = +m[3];
        return r > 160 && r < 250 && g > 110 && g < 210 && b < 110;
      }

      function hideGoldMenuFab() {
        var nodes = document.querySelectorAll('button, a, div');
        for (var i = 0; i < nodes.length; i++) {
          var el = nodes[i];
          if (el.getAttribute('data-ems-hidden-menu') === '1') continue;
          var st = window.getComputedStyle(el);
          if (st.display === 'none' || st.visibility === 'hidden') continue;
          if (st.position !== 'fixed' && st.position !== 'absolute') continue;
          var rect = el.getBoundingClientRect();
          if (rect.width < 40 || rect.width > 76 || rect.height < 40 || rect.height > 76) continue;
          if (Math.abs(rect.width - rect.height) > 12) continue;
          if (window.innerWidth - rect.right > 36) continue;
          if (rect.top < 72) continue;
          var markup = (el.className + ' ' + el.id + ' ' + el.innerHTML).toLowerCase();
          var hamburger = /menu|hamburger|sidebar|toggle|nav/.test(markup)
            || el.querySelectorAll('line, .bar').length >= 3;
          if (isGold(st.backgroundColor) || hamburger) {
            hideNode(el);
          }
        }
      }

      window.__emsAppHideMenuRun = function() {
        applyAppClasses();
        injectCss();
        hideSiteSidebar();
        hideGoldMenuFab();
      };

      window.__emsAppHideMenuRun();

      /* Run regularly for the first 3 seconds to catch dynamic AJAX loads */
      var runs = 0;
      var hideTimer = setInterval(function() {
        runs++;
        window.__emsAppHideMenuRun();
        if (runs > 20) clearInterval(hideTimer);
      }, 150);

      new MutationObserver(window.__emsAppHideMenuRun).observe(
        document.documentElement,
        { childList: true, subtree: true }
      );
    })();
  ''';

  Future<void> retry() async {
    setState(() => _checking = true);
    final online = await ConnectivityService.instance.hasConnection();
    if (!mounted) return;
    setState(() {
      _online = online;
      _checking = false;
    });
    if (online) {
      _loadInitial();
    } else {
      _markInitialLoadFinished();
    }
  }

  Future<bool> handleBack() async {
    if (_adminBlocked) {
      await _returnToLogin();
      return true;
    }
    if (!_online) return false;
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    ConnectivityService.instance.isOnline.removeListener(_onConnectivityChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_adminBlocked) {
      return AdminBlockedScreen(onBackToLogin: _returnToLogin);
    }

    if (_checking) {
      return const ColoredBox(
        color: AppTheme.cream,
        child: Center(
          child: CircularProgressIndicator(color: AppTheme.green700),
        ),
      );
    }

    if (!_online) {
      return const ColoredBox(color: AppTheme.neoBlue);
    }

    return WebViewWidget(controller: _controller);
  }
}
