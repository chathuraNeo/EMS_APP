import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import 'session_service.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.isRead = false,
    this.subscriptionId,
    this.imagePth,
  });

  final int id;
  final String type;
  final String title;
  final String body;
  final DateTime? createdAt;
  final bool isRead;
  final String? subscriptionId;
  final String? imagePth;

  String get typeLabel {
    return switch (type) {
      'all' => 'All members',
      'subscription' => 'Subscription',
      'auto' => 'Automatic',
      _ => type,
    };
  }

  String? get imageUrl {
    final value = imagePth?.trim() ?? '';
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    return '${AppConfig.websiteBaseUrl}/${value.replaceFirst(RegExp(r'^/+'), '')}';
  }

  String get timeLabel {
    final value = createdAt;
    if (value == null) return '';
    final local = value.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '${local.day} ${months[local.month - 1]} ${local.year} · $hour:$minute $suffix';
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final image = '${json['image_url'] ?? json['image_pth'] ?? ''}'.trim();
    return AppNotification(
      id: int.tryParse('${json['id']}') ?? 0,
      type: '${json['type'] ?? ''}',
      title: '${json['title'] ?? ''}',
      body: '${json['body'] ?? ''}',
      isRead: json['is_read'] == true || '${json['is_read']}' == '1',
      subscriptionId: json['subscription_id']?.toString(),
      imagePth: image.isEmpty ? null : image,
      createdAt: DateTime.tryParse('${json['created_at'] ?? json['sdt'] ?? ''}'),
    );
  }

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      type: type,
      title: title,
      body: body,
      createdAt: createdAt,
      isRead: isRead ?? this.isRead,
      subscriptionId: subscriptionId,
      imagePth: imagePth,
    );
  }
}

typedef NotificationWebFetcher = Future<NotificationWebResponse?> Function({
  required String url,
  String method,
  String? body,
});

class NotificationWebResponse {
  const NotificationWebResponse({required this.status, this.body = ''});

  final int status;
  final String body;
}

class NotificationApi {
  NotificationApi._();
  static final NotificationApi instance = NotificationApi._();

  NotificationWebFetcher? _webFetcher;

  void setWebFetcher(NotificationWebFetcher? fetcher) {
    _webFetcher = fetcher;
  }

  static List<AppNotification> parseInboxPayload(dynamic decoded) {
    final list = decoded is Map && decoded['notifications'] is List
        ? decoded['notifications'] as List
        : decoded is List
            ? decoded
            : const [];

    return list
        .whereType<Map>()
        .map((item) => AppNotification.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<Map<String, String>> _headers() async {
    final cookie = await SessionService.instance.cookieHeader();
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/x-www-form-urlencoded',
      if (cookie.isNotEmpty) 'Cookie': cookie,
    };
  }

  Future<List<AppNotification>> fetchInbox() async {
    final web = await _webRequest(
      url: AppConfig.notificationListUrl,
      method: 'GET',
    );
    if (web != null) {
      if (web.status >= 200 && web.status < 300) {
        return parseInboxPayload(_decodeBody(web.body));
      }
      debugPrint('EMS inbox web fetch failed: ${web.status} ${web.body}');
    }

    final response = await http.get(
      Uri.parse(AppConfig.notificationListUrl),
      headers: await _headers(),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Could not load notifications (${response.statusCode})');
    }

    return parseInboxPayload(_decodeBody(response.body));
  }

  Future<void> markRead(int id) async {
    final body = 'notification_id=$id';
    final web = await _webRequest(
      url: AppConfig.notificationMarkReadUrl,
      method: 'POST',
      body: body,
    );
    if (web != null && web.status >= 200 && web.status < 300) {
      return;
    }

    await http.post(
      Uri.parse(AppConfig.notificationMarkReadUrl),
      headers: await _headers(),
      body: {'notification_id': '$id'},
    );
  }

  Future<NotificationWebResponse?> _webRequest({
    required String url,
    required String method,
    String? body,
  }) async {
    final fetcher = _webFetcher;
    if (fetcher == null) return null;
    try {
      return await fetcher(url: url, method: method, body: body);
    } catch (error) {
      debugPrint('EMS notification web fetch failed: $error');
      return null;
    }
  }

  dynamic _decodeBody(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return const {};
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      final start = trimmed.indexOf('{');
      final end = trimmed.lastIndexOf('}');
      if (start >= 0 && end > start) {
        return jsonDecode(trimmed.substring(start, end + 1));
      }
      rethrow;
    }
  }

  Future<void> registerToken({
    required String token,
    String platform = 'android',
  }) async {
    final response = await http.post(
      Uri.parse(AppConfig.notificationRegisterTokenUrl),
      headers: await _headers(),
      body: {
        'token': token,
        'platform': platform,
      },
    );
    debugPrint('EMS push register: ${response.statusCode} ${response.body}');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Token register failed (${response.statusCode})');
    }
  }
}
