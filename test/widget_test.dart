import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ems/core/app_config.dart';
import 'package:ems/main.dart';
import 'package:ems/services/notification_api.dart';
import 'package:ems/services/session_service.dart';
import 'package:ems/widgets/pay_now_button.dart';

void main() {
  test('website urls and EMS app info are configured in one place', () {
    expect(AppConfig.appName, 'EMS');
    expect(AppConfig.appDisplayName, 'Expense Management System');
    expect(AppConfig.websiteBaseUrl, 'https://ems.neosolution.lk');
    expect(AppConfig.homeUrl, contains('Login.php'));
    expect(AppConfig.cashOwnerDashboardUrl, contains('Cash_Owner_Dashboard.php'));
    expect(AppConfig.managerDashboardUrl, contains('Manager_Dashboard.php'));
    expect(AppConfig.memberDashboardUrl, contains('Member_Dashboard.php'));
    expect(AppConfig.adminDashboardUrl, contains('Admin_Dashboard.php'));
    expect(AppConfig.notificationListUrl, contains('list_notifications.php'));
    expect(AppConfig.notificationRegisterTokenUrl, contains('register_token.php'));
    expect(AppConfig.tabPageForIndex(1), AppConfig.paymentPage);
    expect(AppConfig.tabPageForIndex(2), AppConfig.settingsPage);
    expect(AppConfig.payNowPage, 'pay_now');
  });

  test('admin dashboard urls are blocked', () {
    expect(AppConfig.isAdminUrl(AppConfig.adminDashboardUrl), isTrue);
    expect(
      AppConfig.isAdminUrl('${AppConfig.adminDashboardUrl}?x=1'),
      isTrue,
    );
    expect(
      AppConfig.isAdminUrl('https://ems.neosolution.lk/UxUi/Main/Admin_Dashboard.php'),
      isTrue,
    );
    expect(AppConfig.isAdminUrl('about:blank'), isFalse);
    expect(AppConfig.isAdminUrl(AppConfig.cashOwnerDashboardUrl), isFalse);
    expect(AppConfig.isAdminUrl(AppConfig.managerDashboardUrl), isFalse);
    expect(AppConfig.isAdminUrl(AppConfig.memberDashboardUrl), isFalse);
    expect(AppConfig.isAdminUrl(AppConfig.homeUrl), isFalse);
  });

  test('app navigation is hidden until user dashboard', () {
    expect(AppConfig.shouldShowAppNavigation(AppConfig.homeUrl), isFalse);
    expect(AppConfig.shouldShowAppNavigation(AppConfig.cashOwnerDashboardUrl), isTrue);
    expect(AppConfig.shouldShowAppNavigation(AppConfig.managerDashboardUrl), isTrue);
    expect(AppConfig.shouldShowAppNavigation(AppConfig.memberDashboardUrl), isTrue);
    expect(AppConfig.shouldShowAppNavigation(AppConfig.adminDashboardUrl), isFalse);
    expect(AppConfig.shouldShowAppNavigation('about:blank'), isFalse);
    expect(AppConfig.isLoginUrl(AppConfig.homeUrl), isTrue);
  });

  test('access id cookie check blocks admin and allows another 3 users', () {
    // Admin (access_level_id = 1) is blocked:
    expect(AppConfig.isBlockedAccessId('1'), isTrue);
    expect(AppConfig.isAllowedAccessId('1'), isFalse);

    // Another 3 users are allowed:
    // 1. Cash Owner (access_level_id = 2)
    expect(AppConfig.isAllowedAccessId('2'), isTrue);
    expect(AppConfig.isBlockedAccessId('2'), isFalse);

    // 2. Manager (access_level_id = 3)
    expect(AppConfig.isAllowedAccessId('3'), isTrue);
    expect(AppConfig.isBlockedAccessId('3'), isFalse);

    // 3. Member (access_level_id = 4)
    expect(AppConfig.isAllowedAccessId('4'), isTrue);
    expect(AppConfig.isBlockedAccessId('4'), isFalse);

    expect(AppConfig.isBlockedAccessId(null), isFalse);

    final session = SessionService.instance;
    expect(
      session.shouldBlockAccess(
        url: AppConfig.cashOwnerDashboardUrl,
        accessId: '1',
      ),
      isTrue,
    );
    expect(
      session.shouldBlockAccess(
        url: AppConfig.cashOwnerDashboardUrl,
        accessId: '2',
      ),
      isFalse,
    );
    expect(
      session.shouldBlockAccess(
        url: AppConfig.managerDashboardUrl,
        accessId: '3',
      ),
      isFalse,
    );
    expect(
      session.shouldBlockAccess(
        url: AppConfig.memberDashboardUrl,
        accessId: '4',
      ),
      isFalse,
    );
  });

  test('inbox json is parsed from the website payload', () {
    final items = NotificationApi.parseInboxPayload({
      'ok': true,
      'notifications': [
        {
          'id': 7,
          'type': 'all',
          'title': 'testnotifications',
          'body': 'testnotification sendforallmembers',
          'created_at': '2026-09-12 18:15:00',
        },
      ],
    });
    expect(items, hasLength(1));
    expect(items.first.title, 'testnotifications');
    expect(items.first.body, contains('sendforallmembers'));
  });

  test('notification image paths become website urls', () {
    final relative = AppNotification.fromJson({
      'id': '1',
      'type': 'all',
      'title': 'Title',
      'body': 'Body',
      'image_pth': 'Data/Notifications/photo.png',
    });
    expect(
      relative.imageUrl,
      '${AppConfig.websiteBaseUrl}/Data/Notifications/photo.png',
    );

    final absolute = AppNotification.fromJson({
      'id': '2',
      'type': 'auto',
      'title': 'Title',
      'body': 'Body',
      'image_pth': 'https://cdn.example.com/a.png',
    });
    expect(absolute.imageUrl, 'https://cdn.example.com/a.png');
  });

  testWidgets('shows splash branding', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text(AppConfig.poweredBy), findsOneWidget);
  });

  testWidgets('pay now button shows the payment action', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          floatingActionButton: PayNowButton(onPressed: () {}),
        ),
      ),
    );
    expect(find.text('Pay Now'), findsOneWidget);
    expect(find.byIcon(Icons.add_card_rounded), findsOneWidget);
  });
}
