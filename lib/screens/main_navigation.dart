import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_config.dart';
import '../core/app_theme.dart';
import '../services/connectivity_service.dart';
import '../services/notification_api.dart';
import '../services/push_notification_service.dart';
import 'no_internet_screen.dart';
import 'more_hub_screen.dart';
import 'notification_screen.dart';
import 'web_view_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({
    super.key,
    this.initialIndex = 0,
    this.onInitialLoadFinished,
  });

  final int initialIndex;
  final VoidCallback? onInitialLoadFinished;

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  late int _currentIndex;
  int _lastWebIndex = 0;
  bool _showNavigation = false;
  bool _paymentListVisible = false;
  bool _pendingNotificationTab = false;
  UserRole _currentRole = UserRole.unknown;

  final _webKey = GlobalKey<WebViewScreenState>();

  List<RoleNavItem> get _navItems => AppConfig.navItemsForRole(_currentRole);

  int get _notificationIndex =>
      _navItems.indexWhere((it) => it.isNotification);

  int get _moreIndex =>
      _navItems.indexWhere((it) => it.isMore);

  bool get _isNotificationActive =>
      _notificationIndex != -1 && _currentIndex == _notificationIndex;

  bool get _isMoreActive =>
      _moreIndex != -1 && _currentIndex == _moreIndex;

  bool get _showPayNowButton => false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    if (!_isNotificationActive) {
      _lastWebIndex = _currentIndex;
    }
    if (PushNotificationService.instance.consumeOpenRequest()) {
      _pendingNotificationTab = true;
      final notifIdx = _notificationIndex;
      if (notifIdx != -1) {
        _currentIndex = notifIdx;
      }
    }
    ConnectivityService.instance.isOnline.addListener(_onConnectivityChanged);
    PushNotificationService.instance.notificationsOpened
        .addListener(_onNotificationOpened);
    PushNotificationService.instance.openedNotificationDetail
        .addListener(_onNotificationDetailOpened);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingDetail();
    });
  }

  void _onConnectivityChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _retryConnection() async {
    final online = await ConnectivityService.instance.refresh();
    if (!mounted) return;
    if (online) {
      _webKey.currentState?.retry();
    }
  }

  void _onRoleChanged(UserRole role) {
    if (!mounted || _currentRole == role) return;
    setState(() {
      final wasNotif = _isNotificationActive;
      _currentRole = role;
      final items = _navItems;
      if (wasNotif) {
        final newNotif = _notificationIndex;
        _currentIndex = newNotif != -1 ? newNotif : 0;
      } else {
        if (_currentIndex >= items.length) {
          _currentIndex = 0;
          _lastWebIndex = 0;
        }
      }
    });
  }

  void _onShowNavigationChanged(bool show) {
    if (!mounted || _showNavigation == show) return;
    setState(() {
      _showNavigation = show;
      if (!show) {
        if (!_isNotificationActive) {
          _currentIndex = 0;
          _lastWebIndex = 0;
        }
        _paymentListVisible = false;
      } else if (_pendingNotificationTab) {
        final notifIdx = _notificationIndex;
        _currentIndex = notifIdx != -1 ? notifIdx : 0;
        _pendingNotificationTab = false;
      }
    });
  }

  void _onNotificationOpened() {
    _openNotificationTab();
  }

  void _onNotificationDetailOpened() {
    _checkPendingDetail();
  }

  Future<void> _checkPendingDetail() async {
    final detail = PushNotificationService.instance.openedNotificationDetail.value;
    if (detail == null || !mounted) return;
    PushNotificationService.instance.openedNotificationDetail.value = null;

    _openNotificationTab();

    var itemToShow = detail;
    if (detail.id > 0 && (detail.body.trim().isEmpty || detail.title.trim() == 'Notification')) {
      try {
        final list = await NotificationApi.instance.fetchInbox().timeout(
          const Duration(milliseconds: 600),
          onTimeout: () => const [],
        );
        final match = list.firstWhere(
          (it) => it.id == detail.id,
          orElse: () => detail,
        );
        if (match.id == detail.id && match.body.isNotEmpty) {
          itemToShow = match.copyWith(isRead: true);
        }
      } catch (_) {}
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationDetailPage(item: itemToShow),
      ),
    );
  }

  void _openNotificationTab() {
    PushNotificationService.instance.requestInboxRefresh();
    final notifIdx = _notificationIndex;
    if (notifIdx == -1) return;
    if (!mounted) {
      _pendingNotificationTab = true;
      return;
    }
    setState(() {
      _currentIndex = notifIdx;
      _pendingNotificationTab = false;
    });
  }

  void _onTabTapped(int index) {
    if (!_showNavigation) return;
    final items = _navItems;
    if (index < 0 || index >= items.length) return;
    final item = items[index];

    final isSameTab = (_currentIndex == index);

    setState(() {
      _currentIndex = index;
      if (!item.isNotification && !item.isMore) {
        _lastWebIndex = index;
      }
      if (item.sectionKey == 'payment' || item.sectionKey.contains('payment')) {
        _paymentListVisible = true;
      }
    });

    if (item.isNotification) {
      PushNotificationService.instance.requestInboxRefresh();
    } else if (!item.isMore && item.sectionKey.isNotEmpty) {
      if (isSameTab) {
        _webKey.currentState?.reload();
      } else {
        _webKey.currentState?.openSiteSection(item.sectionKey, refreshData: true);
      }
    }
  }

  void _openSectionFromHub(String sectionKey) {
    final items = _navItems;
    final matchingIdx = items.indexWhere((it) => it.sectionKey == sectionKey);
    setState(() {
      if (matchingIdx != -1) {
        _currentIndex = matchingIdx;
        _lastWebIndex = matchingIdx;
      } else {
        _currentIndex = _lastWebIndex;
      }
      _paymentListVisible = sectionKey.contains('payment');
    });
    _webKey.currentState?.openSiteSection(sectionKey, refreshData: true);
  }

  void _onPaymentListVisibleChanged(bool visible) {
    if (!mounted || _paymentListVisible == visible) return;
    setState(() => _paymentListVisible = visible);
  }

  void _openPayNow() {
    if (!_showNavigation) return;
    setState(() {
      _currentIndex = 1;
      _lastWebIndex = 1;
      _paymentListVisible = false;
    });
    _webKey.currentState?.openSiteSection(AppConfig.payNowPage);
  }

  Future<void> _onPopAttempt() async {
    if (_isNotificationActive || _isMoreActive) {
      setState(() => _currentIndex = _lastWebIndex);
      return;
    }

    if (await _webKey.currentState?.handleBack() == true) {
      return;
    }

    if (_currentIndex != 0) {
      setState(() {
        _currentIndex = 0;
        _lastWebIndex = 0;
      });
      final items = _navItems;
      if (items.isNotEmpty && items[0].sectionKey.isNotEmpty) {
        _webKey.currentState?.openSiteSection(items[0].sectionKey);
      }
      return;
    }

    SystemNavigator.pop();
  }

  @override
  void dispose() {
    ConnectivityService.instance.isOnline.removeListener(_onConnectivityChanged);
    PushNotificationService.instance.notificationsOpened
        .removeListener(_onNotificationOpened);
    PushNotificationService.instance.openedNotificationDetail
        .removeListener(_onNotificationDetailOpened);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _navItems;
    final safeIndex = _currentIndex.clamp(0, items.isEmpty ? 0 : items.length - 1);
    final isCompact = items.length >= 6;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemOverlay,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          _onPopAttempt();
        },
        child: Stack(
          children: [
            Scaffold(
              backgroundColor: AppTheme.card,
              body: SafeArea(
              bottom: !_showNavigation,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  WebViewScreen(
                    key: _webKey,
                    initialUrl: AppConfig.userDashboardUrl,
                    onShowNavigationChanged: _onShowNavigationChanged,
                    onPaymentListVisibleChanged: _onPaymentListVisibleChanged,
                    onUserRoleChanged: _onRoleChanged,
                    onInitialLoadFinished: widget.onInitialLoadFinished,
                  ),
                  if (_isNotificationActive)
                    NotificationScreen(
                      onClose: !_showNavigation
                          ? () => setState(() => _currentIndex = _lastWebIndex)
                          : null,
                    ),
                  if (_showNavigation && _isMoreActive)
                    MoreHubScreen(
                      currentRole: _currentRole,
                      onOpenSection: _openSectionFromHub,
                      onOpenNotifications: _openNotificationTab,
                    ),
                ],
              ),
            ),
            bottomNavigationBar: _showNavigation && items.isNotEmpty
                ? DecoratedBox(
                    decoration: const BoxDecoration(
                      color: AppTheme.card,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 12,
                          offset: Offset(0, -2),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      top: false,
                      child: BottomNavigationBar(
                        currentIndex: safeIndex,
                        onTap: _onTabTapped,
                        type: BottomNavigationBarType.fixed,
                        backgroundColor: AppTheme.card,
                        selectedItemColor: AppTheme.green700,
                        unselectedItemColor: const Color(0xFF8B978F),
                        selectedFontSize: isCompact ? 10 : 11,
                        unselectedFontSize: isCompact ? 9.5 : 11,
                        selectedLabelStyle: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: isCompact ? 10 : 11,
                          letterSpacing: isCompact ? -0.2 : 0,
                        ),
                        unselectedLabelStyle: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: isCompact ? 9.5 : 11,
                          letterSpacing: isCompact ? -0.2 : 0,
                        ),
                        elevation: 0,
                        items: items.map((item) {
                          return BottomNavigationBarItem(
                            icon: Icon(item.icon, size: isCompact ? 21 : 24),
                            activeIcon: Icon(item.activeIcon, size: isCompact ? 21 : 24),
                            label: item.label,
                          );
                        }).toList(),
                      ),
                    ),
                  )
                : null,
          ),
          if (!ConnectivityService.instance.isOnline.value)
            Positioned.fill(
              child: NoInternetScreen(onRetry: _retryConnection),
            ),
        ],
      ),
    ),
  );
  }
}
