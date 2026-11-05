import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DevicePermissionsService {
  DevicePermissionsService._();
  static final DevicePermissionsService instance = DevicePermissionsService._();

  static const MethodChannel _channel = MethodChannel('com.neosolution.ems/permissions');

  Future<Map<String, bool>> checkPermissions() async {
    if (!Platform.isAndroid) {
      return {'camera': true, 'location': true, 'notifications': true};
    }
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('checkPermissions');
      if (res == null) return {'camera': false, 'location': false, 'notifications': false};
      return {
        'camera': res['camera'] == true,
        'location': res['location'] == true,
        'notifications': res['notifications'] == true,
      };
    } catch (e) {
      debugPrint('ems checkPermissions error: $e');
      return {'camera': false, 'location': false, 'notifications': false};
    }
  }

  Future<Map<String, bool>> requestAllPermissions() async {
    if (!Platform.isAndroid) {
      return {'camera': true, 'location': true, 'notifications': true};
    }
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('requestPermissions');
      if (res == null) return {'camera': false, 'location': false, 'notifications': false};
      return {
        'camera': res['camera'] == true,
        'location': res['location'] == true,
        'notifications': res['notifications'] == true,
      };
    } catch (e) {
      debugPrint('ems requestAllPermissions error: $e');
      return {'camera': false, 'location': false, 'notifications': false};
    }
  }

  Future<bool> requestCameraPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final res = await _channel.invokeMethod<bool>('requestCameraPermission');
      return res == true;
    } catch (e) {
      debugPrint('ems requestCameraPermission error: $e');
      return true;
    }
  }

  Future<bool> requestLocationPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final res = await _channel.invokeMethod<bool>('requestLocationPermission');
      return res == true;
    } catch (e) {
      debugPrint('ems requestLocationPermission error: $e');
      return true;
    }
  }
}
