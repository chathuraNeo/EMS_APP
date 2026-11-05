import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/app_config.dart';

class SessionService {
  SessionService._();

  static final SessionService instance = SessionService._();

  WebViewCookieManager? _cookieManager;

  WebViewCookieManager get _cookies =>
      _cookieManager ??= WebViewCookieManager();

  Map<String, String> parseCookieHeader(String header) {
    final cookies = <String, String>{};
    final cleaned = header.replaceAll('"', '').trim();
    if (cleaned.isEmpty || cleaned == 'null') return cookies;

    for (final part in cleaned.split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0) continue;
      final name = part.substring(0, separator).trim();
      final value = part.substring(separator + 1).trim();
      if (name.isNotEmpty) {
        cookies[name] = value;
      }
    }
    return cookies;
  }

  String? accessIdFromCookies(Map<String, String> cookies) {
    if (AppConfig.accessIdCookieName.isEmpty) return null;
    return cookies[AppConfig.accessIdCookieName];
  }

  Future<Map<String, String>> readCookies({String? documentCookie}) async {
    final cookies = <String, String>{};

    try {
      final stored = await _cookies.getCookies(
        domain: Uri.parse(AppConfig.websiteBaseUrl),
      );
      for (final cookie in stored) {
        cookies[cookie.name] = cookie.value;
      }
    } catch (error) {
      debugPrint('ems session: cookie manager read failed: $error');
    }

    if (documentCookie != null) {
      cookies.addAll(parseCookieHeader(documentCookie));
    }

    return cookies;
  }

  Future<String> cookieHeader() async {
    final cookies = await readCookies();
    if (cookies.isEmpty) return '';
    return cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  Future<String?> readAccessId({String? documentCookie}) async {
    final cookies = await readCookies(documentCookie: documentCookie);
    return accessIdFromCookies(cookies);
  }

  bool shouldBlockAccess({required String url, String? accessId}) {
    if (AppConfig.isAdminUrl(url)) return true;
    return AppConfig.isBlockedAccessId(accessId);
  }

  void logBlockedAttempt({required String reason, String? accessId, String? url}) {
    debugPrint(
      'ems session blocked: reason=$reason accessId=$accessId url=$url',
    );
  }

  Future<void> logout() async {
    try {
      await _cookies.clearCookies();
    } catch (error) {
      debugPrint('ems session: clear cookies failed: $error');
    }
  }
}
