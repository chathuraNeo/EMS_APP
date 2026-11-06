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
  bool _isLoading = true;
  double _loadProgress = 0.0;

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
      ..setBackgroundColor(AppTheme.card)
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
            setState(() {
              _loadProgress = progress / 100.0;
            });
            if (progress >= 100) {
              _markInitialLoadFinished();
              if (_isLoading) {
                setState(() => _isLoading = false);
              }
            }
          },
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              _isLoading = true;
            });
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
            _installInputUx();
          },
          onPageFinished: (url) {
            if (!mounted || _adminBlocked || url == 'about:blank') return;
            if (AppConfig.isAdminUrl(url)) {
              _blockAdmin(reason: 'admin_url', url: url);
              return;
            }
            setState(() {
              _isLoading = false;
              _loadProgress = 1.0;
            });
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
            // Auto-recover if WebContent process was terminated (e.g., iOS memory reclaim)
            if (error.errorType == WebResourceErrorType.webContentProcessTerminated ||
                error.errorType == WebResourceErrorType.webViewInvalidated) {
              debugPrint('ems webview process terminated, recovering...');
              _controller.reload();
              return;
            }

            if (!_isNetworkError(error)) return;
            _markInitialLoadFinished();
            ConnectivityService.instance.markOffline();
            if (mounted) {
              setState(() {
                _online = false;
                _isLoading = false;
              });
            }
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
    if (error.isForMainFrame == false) return false;

    const networkTypes = {
      WebResourceErrorType.hostLookup,
      WebResourceErrorType.connect,
      WebResourceErrorType.timeout,
      WebResourceErrorType.failedSslHandshake,
      WebResourceErrorType.io,
    };
    if (error.errorType != null && networkTypes.contains(error.errorType)) {
      return true;
    }

    // iOS NSURLError codes (negative values from NSURLErrorDomain)
    final code = error.errorCode;
    if (code == -1009 || // kCFURLErrorNotConnectedToInternet
        code == -1001 || // kCFURLErrorTimedOut
        code == -1003 || // kCFURLErrorCannotFindHost
        code == -1004 || // kCFURLErrorCannotConnectToHost
        code == -1005 || // kCFURLErrorNetworkConnectionLost
        code == -1006 || // kCFURLErrorDNSLookupFailed
        code == -1200) { // kCFURLErrorSecureConnectionFailed
      return true;
    }

    final description = error.description.toUpperCase();
    return description.contains('NAME_NOT_RESOLVED') ||
        description.contains('INTERNET_DISCONNECTED') ||
        description.contains('ADDRESS_UNREACHABLE') ||
        description.contains('CONNECTION_ABORTED') ||
        description.contains('TIMED_OUT') ||
        description.contains('NETWORK_CHANGED') ||
        description.contains('NSURLERRORDOMAIN');
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
      await _installInputUx();
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

  Future<void> openSiteSection(String page, {bool refreshData = true}) async {
    _pendingPage = page;
    await _tryOpenPending(refreshData: refreshData);
  }

  Future<void> _tryOpenPending({bool refreshData = true}) async {
    final page = _pendingPage;
    if (page == null || !_online || _adminBlocked) return;

    try {
      final currentUrl = await _controller.currentUrl() ?? '';
      if (currentUrl.isNotEmpty && !AppConfig.shouldShowAppNavigation(currentUrl)) {
        final targetUrl = AppConfig.dashboardUrlForRole(_currentRole);
        await _controller.loadRequest(Uri.parse(targetUrl));
        return;
      }

      final result = await _controller.runJavaScriptReturningResult(
        _openSectionScript(page, refreshData: refreshData),
      );
      final value = result.toString();
      if (value.contains('ok') || value.contains('click')) {
        _pendingPage = null;
      } else if (value.contains('missing')) {
        final targetUrl = AppConfig.dashboardUrlForRole(_currentRole);
        if (currentUrl != targetUrl) {
          await _controller.loadRequest(Uri.parse(targetUrl));
        }
      }
      await _hideSiteMenuButton();
      await _installFileUploadFix();
      await _installUiBridge();
      await _installInputUx();
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

  Future<void> _installInputUx() async {
    if (!_online || _adminBlocked) return;
    try {
      await _controller.runJavaScript(_inputUxScript);
    } catch (_) {}
  }

  String _openSectionScript(String page, {bool refreshData = true}) {
    return '''
      (function(){
        var target = ${jsonEncode(page)};
        var refresh = ${refreshData ? 'true' : 'false'};
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
            try {
              fn();
              if (refresh) {
                try {
                  if (typeof refreshAllMemberData === 'function') refreshAllMemberData();
                  if (typeof updateCharts === 'function') updateCharts();
                  if (typeof loadExpensesList === 'function') loadExpensesList();
                  if (typeof loadPaymentsList === 'function') loadPaymentsList();
                  if (typeof loadMembersList === 'function') loadMembersList();
                  if (typeof renderSummaryKPIs === 'function') renderSummaryKPIs();
                  if (typeof Member_dashboard_02_A_expenses_list_SET_DB === 'function') Member_dashboard_02_A_expenses_list_SET_DB(1);
                  if (typeof Member_dashboard_03_A_funds_received_list_SET_DB === 'function') Member_dashboard_03_A_funds_received_list_SET_DB(1);
                } catch (err) {}
              }
              return 'ok';
            } catch (e) {}
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

  static const String _inputUxScript = r'''
    (function(){
      if (window.__emsWebViewInputUxObs) return;
      window.__emsWebViewInputUxObs = true;

      function isAmount(el) {
        if (!el || el.tagName !== 'INPUT') return false;
        var exp = el.getAttribute('data-input-type');
        if (exp === 'amount' || exp === 'decimal') return true;
        var id = (el.id || '').toLowerCase();
        var name = (el.name || '').toLowerCase();
        var cls = (el.className || '').toLowerCase();
        var ph = (el.placeholder || '').toLowerCase();
        var step = el.getAttribute('step');
        var type = (el.type || '').toLowerCase();
        var kw = ['amount','balance','float','price','litres','liters','cost','rate','transfer','topup','fee','total','spent','limit','threshold','odometer','mileage'];
        for (var i = 0; i < kw.length; i++) {
          if (id.indexOf(kw[i]) !== -1 || name.indexOf(kw[i]) !== -1) return true;
        }
        if (cls.indexOf('amount') !== -1 || ph.indexOf('0.00') !== -1 || ph.indexOf('rs.') !== -1) return true;
        if (type === 'number' && (step === '0.01' || step === '0.1' || step === 'any')) return true;
        return false;
      }

      function isOtp(el) {
        if (!el || el.tagName !== 'INPUT') return false;
        if (el.getAttribute('data-input-type') === 'otp') return true;
        var cls = (el.className || '').toLowerCase();
        var id = (el.id || '').toLowerCase();
        var name = (el.name || '').toLowerCase();
        if (cls.indexOf('otp-digit') !== -1 || cls.indexOf('erp-otp-input') !== -1) return true;
        if (id.indexOf('otpdigit') !== -1 || id.indexOf('otp-digit') !== -1) return true;
        if (name.indexOf('otp') !== -1 && el.maxLength === 1) return true;
        var p = el.parentElement;
        if (p && ((p.className || '').toLowerCase().indexOf('otp') !== -1)) return true;
        return false;
      }

      function isPhone(el) {
        if (!el || el.tagName !== 'INPUT') return false;
        if (el.type === 'tel') return true;
        var id = (el.id || '').toLowerCase();
        var name = (el.name || '').toLowerCase();
        return id.indexOf('mobile') !== -1 || id.indexOf('phone') !== -1 || id.indexOf('whatsapp') !== -1 ||
               name.indexOf('mobile') !== -1 || name.indexOf('phone') !== -1 || name.indexOf('whatsapp') !== -1;
      }

      function isStrictNum(el) {
        if (!el || el.tagName !== 'INPUT') return false;
        var id = (el.id || '').toLowerCase();
        return id.indexOf('bankaccno') !== -1 || id.indexOf('bankacno') !== -1 || id.indexOf('checkformnumber') !== -1;
      }

      function getOtpGroup(input) {
        var p = input.closest('form') || input.closest('.otp-inputs') || input.closest('.erp-otp-group') || input.parentElement;
        if (!p) return [input];
        var list = Array.from(p.querySelectorAll('.otp-digit, .erp-otp-input, input[data-input-type="otp"], input[maxlength="1"]'));
        return list.length > 0 ? list : [input];
      }

      function enhance(el) {
        if (!el || el.nodeType !== 1 || el.tagName !== 'INPUT') return;
        if (el.hasAttribute('data-ems-app-ux')) return;
        var t = (el.type || 'text').toLowerCase();
        if (t === 'hidden' || t === 'checkbox' || t === 'radio' || t === 'submit' || t === 'button' || t === 'file') return;

        if (isOtp(el)) {
          el.setAttribute('data-ems-app-ux', 'otp');
          el.setAttribute('inputmode', 'numeric');
          el.setAttribute('pattern', '[0-9]*');
          el.setAttribute('maxlength', '1');
          el.setAttribute('autocorrect', 'off');
          el.setAttribute('autocapitalize', 'none');
          if (el.type !== 'tel') { try { el.type = 'tel'; } catch(e){} }
          var g = getOtpGroup(el);
          if (g[0] === el) { el.setAttribute('autocomplete', 'one-time-code'); }
          else { el.setAttribute('autocomplete', 'off'); }

          el.addEventListener('keydown', function(e) {
            var grp = getOtpGroup(this);
            var idx = grp.indexOf(this);
            if (e.key === 'Backspace') {
              e.preventDefault();
              if (this.value) { this.value = ''; }
              else if (idx > 0) { grp[idx - 1].value = ''; grp[idx - 1].focus(); }
              return;
            }
            if (e.key === 'ArrowLeft' && idx > 0) { e.preventDefault(); grp[idx - 1].focus(); return; }
            if (e.key === 'ArrowRight' && idx < grp.length - 1) { e.preventDefault(); grp[idx + 1].focus(); return; }
            if (e.key === 'Tab' || e.key === 'Enter' || e.ctrlKey || e.metaKey) return;
            if (/^[0-9]$/.test(e.key)) {
              e.preventDefault();
              this.value = e.key;
              if (idx < grp.length - 1) { grp[idx + 1].focus(); }
              var done = grp.every(function(b){ return /^[0-9]$/.test(b.value.trim()); });
              if (done) {
                var f = grp[0].closest('form');
                if (f) { setTimeout(function(){ if (f.requestSubmit) f.requestSubmit(); else f.submit(); }, 80); }
              }
              return;
            }
            if (e.key.length === 1) { e.preventDefault(); }
          });

          el.addEventListener('input', function() {
            var raw = this.value.replace(/\D/g, '');
            var grp = getOtpGroup(this);
            var idx = grp.indexOf(this);
            if (raw.length > 1) {
              for (var i = 0; i < raw.length && (idx + i) < grp.length; i++) {
                grp[idx + i].value = raw[i];
              }
              var next = Math.min(idx + raw.length, grp.length - 1);
              grp[next].focus();
              return;
            }
            this.value = raw.slice(0, 1);
            if (this.value && idx < grp.length - 1) { grp[idx + 1].focus(); }
          });
          return;
        }

        if (isAmount(el)) {
          el.setAttribute('data-ems-app-ux', 'amount');
          el.setAttribute('inputmode', 'decimal');
          el.setAttribute('autocomplete', 'off');
          el.setAttribute('autocorrect', 'off');
          el.setAttribute('autocapitalize', 'none');
          el.addEventListener('keydown', function(e) {
            if (e.key === 'Backspace' || e.key === 'Delete' || e.key === 'Tab' || e.key === 'Enter' || e.key === 'Escape' ||
                e.key === 'ArrowLeft' || e.key === 'ArrowRight' || e.ctrlKey || e.metaKey) return;
            if (e.key === '.' || e.key === ',') {
              if (this.value.indexOf('.') !== -1 || this.value.indexOf(',') !== -1) { e.preventDefault(); }
              return;
            }
            if (/^[0-9]$/.test(e.key)) return;
            e.preventDefault();
          });
          el.addEventListener('input', function() {
            var v = this.value.replace(/,/g, '.').replace(/[^0-9.]/g, '');
            var p = v.split('.');
            if (p.length > 2) { v = p[0] + '.' + p.slice(1).join(''); }
            if (v !== this.value) {
              var pos = this.selectionStart;
              this.value = v;
              try { this.setSelectionRange(pos, pos); } catch(err){}
            }
          });
          return;
        }

        if (isStrictNum(el)) {
          el.setAttribute('data-ems-app-ux', 'num');
          el.setAttribute('inputmode', 'numeric');
          el.setAttribute('pattern', '[0-9]*');
          el.addEventListener('input', function() {
            var v = this.value.replace(/\D/g, '');
            if (v !== this.value) { this.value = v; }
          });
          return;
        }

        if (isPhone(el)) {
          el.setAttribute('data-ems-app-ux', 'phone');
          el.setAttribute('inputmode', 'tel');
          if (el.type !== 'tel') { try { el.type = 'tel'; } catch(e){} }
          return;
        }
      }

      function scan() {
        var arr = document.querySelectorAll('input');
        for (var i = 0; i < arr.length; i++) { enhance(arr[i]); }
      }
      scan();
      new MutationObserver(function(muts) {
        for (var i = 0; i < muts.length; i++) {
          for (var j = 0; j < muts[i].addedNodes.length; j++) {
            var n = muts[i].addedNodes[j];
            if (n.nodeType === 1) {
              if (n.tagName === 'INPUT') enhance(n);
              else if (n.querySelectorAll) {
                var sub = n.querySelectorAll('input');
                for (var k = 0; k < sub.length; k++) enhance(sub[k]);
              }
            }
          }
        }
      }).observe(document.documentElement || document.body, { childList: true, subtree: true });
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

  Future<void> reload() async {
    final online = await ConnectivityService.instance.hasConnection();
    if (!mounted) return;
    if (!online) {
      setState(() => _online = false);
      return;
    }
    setState(() {
      _online = true;
      _isLoading = true;
    });

    try {
      final res = await _controller.runJavaScriptReturningResult('''
        (function(){
          var refreshed = false;
          if (typeof refreshAllMemberData === 'function') {
            try { refreshAllMemberData(); refreshed = true; } catch (e) {}
          }
          if (typeof updateCharts === 'function' || typeof loadExpensesList === 'function') {
            try {
              if (typeof loadExpensesList === 'function') loadExpensesList();
              if (typeof loadPaymentsList === 'function') loadPaymentsList();
              if (typeof updateCharts === 'function') updateCharts();
              if (typeof renderSummaryKPIs === 'function') renderSummaryKPIs();
              refreshed = true;
            } catch (e) {}
          }
          if (typeof Member_dashboard_02_A_expenses_list_SET_DB === 'function') {
            try { Member_dashboard_02_A_expenses_list_SET_DB(1); refreshed = true; } catch (e) {}
          }
          if (typeof Member_dashboard_03_A_funds_received_list_SET_DB === 'function') {
            try { Member_dashboard_03_A_funds_received_list_SET_DB(1); refreshed = true; } catch (e) {}
          }
          return refreshed ? 'refreshed' : 'reload';
        })();
      ''');
      if (res.toString().contains('refreshed')) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) setState(() => _isLoading = false);
        return;
      }
    } catch (_) {}

    await _controller.reload();
  }

  Future<void> retry() async {
    setState(() => _checking = true);
    final online = await ConnectivityService.instance.refresh();
    if (!mounted) return;
    setState(() {
      _online = online;
      _checking = false;
      _isLoading = online;
    });
    if (online) {
      if (_pendingPage != null) {
        await _tryOpenPending();
      } else {
        await _controller.reload();
      }
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
        color: AppTheme.card,
        child: Center(
          child: CircularProgressIndicator(color: AppTheme.green700),
        ),
      );
    }

    if (!_online) {
      return const ColoredBox(color: AppTheme.neoBlue);
    }

    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        // Top linear progress bar only for subsequent in-app page reloads and tab switches
        if (_isLoading && _initialLoadReported)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SizedBox(
              height: 2.5,
              child: LinearProgressIndicator(
                value: _loadProgress > 0 && _loadProgress < 1.0 ? _loadProgress : null,
                backgroundColor: Colors.transparent,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.green700),
              ),
            ),
          ),
      ],
    );
  }
}
