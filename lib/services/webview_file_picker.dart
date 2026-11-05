import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../core/app_theme.dart';
import 'device_permissions_service.dart';

class WebViewFilePicker {
  WebViewFilePicker(this._contextOf);

  final BuildContext? Function() _contextOf;
  final ImagePicker _images = ImagePicker();
  bool _isBusy = false;

  static const double _maxDimension = 1920;
  static const int _targetQuality = 82;
  static const Duration _operationTimeout = Duration(minutes: 3);

  Future<List<String>> onShowFileSelector(FileSelectorParams params) async {
    if (_isBusy) return const [];
    _isBusy = true;
    try {
      return await _handleFileSelection(params).timeout(
        _operationTimeout,
        onTimeout: () => const [],
      );
    } catch (e) {
      debugPrint('WebViewFilePicker error: $e');
      return const [];
    } finally {
      _isBusy = false;
    }
  }

  Future<List<String>> _handleFileSelection(FileSelectorParams params) async {
    // Check if capture is directly requested (e.g. capture="environment" for meter/camera)
    if (params.isCaptureEnabled) {
      await DevicePermissionsService.instance.requestCameraPermission();
      final photo = await _images.pickImage(
        source: ImageSource.camera,
        imageQuality: _targetQuality,
        maxWidth: _maxDimension,
        maxHeight: _maxDimension,
      );
      return _urisFromXFile(photo);
    }

    final accept = params.acceptTypes.map((type) => type.toLowerCase()).join(',');
    final wantsImage = accept.isEmpty ||
        accept.contains('*/*') ||
        accept.contains('image') ||
        accept.contains('jpg') ||
        accept.contains('jpeg') ||
        accept.contains('png') ||
        accept.contains('webp');

    if (wantsImage) {
      final choice = await _chooseImageSource();
      if (choice == null) return const [];

      // Allow modal bottom sheet dismiss animation to finish smoothly
      await Future<void>.delayed(const Duration(milliseconds: 220));

      if (choice == _FileChoice.camera) {
        await DevicePermissionsService.instance.requestCameraPermission();
        final photo = await _images.pickImage(
          source: ImageSource.camera,
          imageQuality: _targetQuality,
          maxWidth: _maxDimension,
          maxHeight: _maxDimension,
        );
        return _urisFromXFile(photo);
      }

      if (choice == _FileChoice.gallery) {
        if (params.mode == FileSelectorMode.openMultiple) {
          final files = await _images.pickMultiImage(
            imageQuality: _targetQuality,
            maxWidth: _maxDimension,
            maxHeight: _maxDimension,
          );
          if (files.isEmpty) return const [];
          return [
            for (final f in files)
              if (f.path.isNotEmpty) Uri.file(f.path).toString(),
          ];
        } else {
          final photo = await _images.pickImage(
            source: ImageSource.gallery,
            imageQuality: _targetQuality,
            maxWidth: _maxDimension,
            maxHeight: _maxDimension,
          );
          return _urisFromXFile(photo);
        }
      }

      if (choice == _FileChoice.files) {
        return _pickFiles(params, FileType.image);
      }
    }

    return _pickFiles(params, FileType.any);
  }

  Future<void> recoverLostDataIfNeeded(void Function(String uri) onRecovered) async {
    if (!Platform.isAndroid) return;
    try {
      final response = await _images.retrieveLostData();
      if (response.isEmpty) return;
      final file = response.file;
      if (file != null && file.path.isNotEmpty) {
        onRecovered(Uri.file(file.path).toString());
      }
    } catch (_) {}
  }

  Future<List<String>> _pickFiles(
    FileSelectorParams params,
    FileType type,
  ) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: params.mode == FileSelectorMode.openMultiple,
        type: type,
        withData: false,
      );
      if (result == null) return const [];
      return [
        for (final file in result.files)
          if (file.path != null && file.path!.isNotEmpty) Uri.file(file.path!).toString(),
      ];
    } catch (e) {
      debugPrint('FilePicker error: $e');
      return const [];
    }
  }

  Future<List<String>> _urisFromXFile(XFile? file) async {
    if (file == null || file.path.isEmpty) return const [];
    return [Uri.file(file.path).toString()];
  }

  Future<_FileChoice?> _chooseImageSource() async {
    final context = _contextOf();
    if (context == null || !context.mounted) return _FileChoice.gallery;

    return showModalBottomSheet<_FileChoice>(
      context: context,
      backgroundColor: AppTheme.card,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Upload receipt / photo',
                  style: TextStyle(
                    color: AppTheme.green950,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Take a photo or choose an image from device.',
                  style: TextStyle(
                    color: AppTheme.inkMuted,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                _SourceTile(
                  icon: Icons.photo_camera_rounded,
                  title: 'Take photo',
                  subtitle: 'Use camera for receipt or meter board',
                  onTap: () => Navigator.pop(sheetContext, _FileChoice.camera),
                ),
                _SourceTile(
                  icon: Icons.photo_library_rounded,
                  title: 'Choose from gallery',
                  subtitle: 'Pick existing photo or screenshot',
                  onTap: () => Navigator.pop(sheetContext, _FileChoice.gallery),
                ),
                _SourceTile(
                  icon: Icons.folder_open_rounded,
                  title: 'Browse files',
                  subtitle: 'Images or PDF documents',
                  onTap: () => Navigator.pop(sheetContext, _FileChoice.files),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

enum _FileChoice { camera, gallery, files }

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppTheme.cream,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.green700,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: AppTheme.gold300),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppTheme.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppTheme.inkMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppTheme.inkMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
