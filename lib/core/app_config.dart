import 'package:flutter/material.dart';

enum UserRole {
  cashOwner,
  manager,
  member,
  unknown;

  String get displayName => switch (this) {
    UserRole.cashOwner => 'Cash Owner',
    UserRole.manager => 'Manager',
    UserRole.member => 'Member',
    UserRole.unknown => 'User',
  };
}

class RoleNavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String sectionKey;
  final bool isNotification;
  final bool isMore;

  const RoleNavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    this.sectionKey = '',
    this.isNotification = false,
    this.isMore = false,
  });
}

class AppConfig {
  static const String appName = 'EMS';
  static const String appDisplayName = 'Expense Management System';
  static const String poweredBy = 'Powered by NEO SOLUTION';

  static String roleDisplayName(UserRole role) => role.displayName;

  static const String websiteBaseUrl = 'https://ems.neosolution.lk';

  static const String homeUrl = '$websiteBaseUrl/Login.php';

  static const String cashOwnerDashboardUrl =
      '$websiteBaseUrl/UxUi/Main/Cash_Owner_Dashboard.php';
  static const String managerDashboardUrl =
      '$websiteBaseUrl/UxUi/Main/Manager_Dashboard.php';
  static const String memberDashboardUrl =
      '$websiteBaseUrl/UxUi/Main/Member_Dashboard.php';

  static const String userDashboardUrl = cashOwnerDashboardUrl;

  static const String adminDashboardUrl =
      '$websiteBaseUrl/UxUi/Main/Admin_Dashboard.php';

  static const String notificationListUrl =
      '$websiteBaseUrl/View-List/notification/notification_inbox/view_notification_inbox_list.php';

  static const String notificationRegisterTokenUrl =
      '$websiteBaseUrl/View-List/notification/notification_inbox/add_edit_notification_inbox.php';

  static const String notificationMarkReadUrl =
      '$websiteBaseUrl/View-List/notification/notification_inbox/change_notification_inbox_status.php';

  static const String fcmAllTopic = 'ems_all';
  static const String fcmSubscriptionTopicPrefix = 'ems_sub_';

  static const String accessIdCookieName = 'main_user_account_cook';

  static const String adminAccessId = '1';
  static const String cashOwnerAccessId = '2';
  static const String managerAccessId = '3';
  static const String memberAccessId = '4';

  static const Set<String> blockedAccessIds = {adminAccessId};
  static const Set<String> allowedAccessIds = {
    cashOwnerAccessId,
    managerAccessId,
    memberAccessId,
  };

  static const String dashboardPage = 'dashboard';
  static const String paymentPage = 'payment';
  static const String payNowPage = 'pay_now';
  static const String settingsPage = 'settings';
  static const String cashOwnerNotificationsPage = 'cash_owner_notifications';
  static const String cashOwnerAddNotificationPage = 'cash_owner_add_notification';

  static const String logoAsset = 'assets/logo.png';
  static const String footerAsset = '';
  static const String networkAsset = 'assets/network.png';
  static const String backgroundAsset = 'assets/bg.png';

  static const Duration splashDuration = Duration(milliseconds: 2600);

  static List<RoleNavItem> navItemsForRole(UserRole role) {
    return switch (role) {
      UserRole.member => const [
        RoleNavItem(
          label: 'Home',
          icon: Icons.home_outlined,
          activeIcon: Icons.home_rounded,
          sectionKey: 'member_home',
        ),
        RoleNavItem(
          label: 'My Claim',
          icon: Icons.receipt_long_outlined,
          activeIcon: Icons.receipt_long_rounded,
          sectionKey: 'member_claims',
        ),
        RoleNavItem(
          label: 'Funds',
          icon: Icons.account_balance_wallet_outlined,
          activeIcon: Icons.account_balance_wallet_rounded,
          sectionKey: 'member_funds',
        ),
        RoleNavItem(
          label: 'Return',
          icon: Icons.assignment_return_outlined,
          activeIcon: Icons.assignment_return_rounded,
          sectionKey: 'member_return',
        ),
        RoleNavItem(
          label: 'Vehicle',
          icon: Icons.directions_car_outlined,
          activeIcon: Icons.directions_car_rounded,
          sectionKey: 'member_vehicles',
        ),
        RoleNavItem(
          label: 'Notification',
          icon: Icons.notifications_none_rounded,
          activeIcon: Icons.notifications_rounded,
          isNotification: true,
        ),
      ],
      UserRole.cashOwner => const [
        RoleNavItem(
          label: 'Home',
          icon: Icons.dashboard_outlined,
          activeIcon: Icons.dashboard_rounded,
          sectionKey: 'cash_owner_home',
        ),
        RoleNavItem(
          label: 'Payment',
          icon: Icons.payments_outlined,
          activeIcon: Icons.payments_rounded,
          sectionKey: 'cash_owner_payment',
        ),
        RoleNavItem(
          label: 'Expense',
          icon: Icons.receipt_outlined,
          activeIcon: Icons.receipt_rounded,
          sectionKey: 'cash_owner_expense',
        ),
        RoleNavItem(
          label: 'Cheques',
          icon: Icons.fact_check_outlined,
          activeIcon: Icons.fact_check_rounded,
          sectionKey: 'cash_owner_cheques',
        ),
        RoleNavItem(
          label: 'More',
          icon: Icons.grid_view_outlined,
          activeIcon: Icons.grid_view_rounded,
          sectionKey: 'more_hub',
          isMore: true,
        ),
        RoleNavItem(
          label: 'Notification',
          icon: Icons.notifications_none_rounded,
          activeIcon: Icons.notifications_rounded,
          isNotification: true,
        ),
      ],
      UserRole.manager => const [
        RoleNavItem(
          label: 'Home',
          icon: Icons.dashboard_outlined,
          activeIcon: Icons.dashboard_rounded,
          sectionKey: 'manager_home',
        ),
        RoleNavItem(
          label: 'Members',
          icon: Icons.people_outline_rounded,
          activeIcon: Icons.people_rounded,
          sectionKey: 'manager_members',
        ),
        RoleNavItem(
          label: 'Claims',
          icon: Icons.receipt_long_outlined,
          activeIcon: Icons.receipt_long_rounded,
          sectionKey: 'manager_claims',
        ),
        RoleNavItem(
          label: 'Payment',
          icon: Icons.payments_outlined,
          activeIcon: Icons.payments_rounded,
          sectionKey: 'manager_payment',
        ),
        RoleNavItem(
          label: 'More',
          icon: Icons.grid_view_outlined,
          activeIcon: Icons.grid_view_rounded,
          sectionKey: 'more_hub',
          isMore: true,
        ),
        RoleNavItem(
          label: 'Notification',
          icon: Icons.notifications_none_rounded,
          activeIcon: Icons.notifications_rounded,
          isNotification: true,
        ),
      ],
      UserRole.unknown => const [
        RoleNavItem(
          label: 'Home',
          icon: Icons.home_outlined,
          activeIcon: Icons.home_rounded,
          sectionKey: 'home',
        ),
        RoleNavItem(
          label: 'Payment',
          icon: Icons.payments_outlined,
          activeIcon: Icons.payments_rounded,
          sectionKey: 'payment',
        ),
        RoleNavItem(
          label: 'Setting',
          icon: Icons.settings_outlined,
          activeIcon: Icons.settings_rounded,
          sectionKey: 'settings',
        ),
        RoleNavItem(
          label: 'Notification',
          icon: Icons.notifications_none_rounded,
          activeIcon: Icons.notifications_rounded,
          isNotification: true,
        ),
      ],
    };
  }

  static UserRole roleFromAccessId(String? accessId) {
    if (accessId == null) return UserRole.unknown;
    return switch (accessId.trim()) {
      cashOwnerAccessId => UserRole.cashOwner,
      managerAccessId => UserRole.manager,
      memberAccessId => UserRole.member,
      _ => UserRole.unknown,
    };
  }

  static UserRole roleFromString(String? roleStr) {
    if (roleStr == null) return UserRole.unknown;
    final r = roleStr.trim().toLowerCase();
    if (r == 'cash_owner' || r == 'cashowner' || r == 'owner') {
      return UserRole.cashOwner;
    }
    if (r == 'manager') return UserRole.manager;
    if (r == 'member') return UserRole.member;
    return UserRole.unknown;
  }

  static UserRole roleFromUrl(String? url) {
    if (url == null || url.isEmpty) return UserRole.unknown;
    final lower = url.toLowerCase();
    if (lower.contains('cash_owner_dashboard')) return UserRole.cashOwner;
    if (lower.contains('manager_dashboard')) return UserRole.manager;
    if (lower.contains('member_dashboard')) return UserRole.member;
    return UserRole.unknown;
  }

  static String dashboardUrlForRole(UserRole role) {
    return switch (role) {
      UserRole.cashOwner => cashOwnerDashboardUrl,
      UserRole.manager => managerDashboardUrl,
      UserRole.member => memberDashboardUrl,
      UserRole.unknown => userDashboardUrl,
    };
  }

  static String? tabPageForIndex(
    int index, {
    UserRole role = UserRole.unknown,
  }) {
    final items = navItemsForRole(role);
    if (index >= 0 && index < items.length) {
      final item = items[index];
      return item.isNotification ? null : item.sectionKey;
    }
    return switch (index) {
      0 => dashboardPage,
      1 => paymentPage,
      2 => settingsPage,
      _ => null,
    };
  }

  static const List<String> blockedAdminUrlFragments = [
    'admin_dashboard',
    'admin-dashboard',
    'admindashboard',
    'main-dashboard.php',
    'main_dashboard.php',
    'maindashboard.php',
  ];

  static bool isAdminUrl(String url) {
    final lower = url.toLowerCase().trim();
    if (lower.isEmpty || lower == 'about:blank') return false;
    if (blockedAdminUrlFragments.any(lower.contains)) return true;

    final parsed = Uri.tryParse(url);
    final adminPath = Uri.parse(adminDashboardUrl).path.toLowerCase();
    return parsed != null && parsed.path.toLowerCase() == adminPath;
  }

  static bool isLoginUrl(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    return path.endsWith('login.php') ||
        path.endsWith('index.php') ||
        path.contains('user-login.php') ||
        path.contains('forgot-password.php') ||
        path.contains('user-registration.php') ||
        path.contains('otp-two-step-verification.php');
  }

  static bool shouldShowAppNavigation(String url) {
    if (url.isEmpty || url == 'about:blank') return false;
    if (isAdminUrl(url) || isLoginUrl(url)) return false;
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    return path.contains('cash_owner_dashboard') ||
        path.contains('manager_dashboard') ||
        path.contains('member_dashboard') ||
        path.contains('user_dashboard.php') ||
        path.contains('user-dashboard.php');
  }

  static bool isBlockedAccessId(String? accessId) {
    if (accessId == null || accessId.isEmpty) return false;
    return blockedAccessIds.contains(accessId.trim());
  }

  static bool isAllowedAccessId(String? accessId) {
    if (accessId == null || accessId.isEmpty) return false;
    return allowedAccessIds.contains(accessId.trim());
  }
}
