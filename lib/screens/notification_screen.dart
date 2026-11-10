import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../services/notification_api.dart';
import '../services/push_notification_service.dart';
import '../widgets/notification_image.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({
    super.key,
    this.onClose,
    this.onOpenWebNotifications,
    this.onOpenAddNotification,
  });

  final VoidCallback? onClose;
  final VoidCallback? onOpenWebNotifications;
  final VoidCallback? onOpenAddNotification;

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  bool _loading = true;
  String? _error;
  List<AppNotification> _items = [];
  int _loadSeq = 0;

  @override
  void initState() {
    super.initState();
    PushNotificationService.instance.inboxRefresh.addListener(_onInboxRefresh);
    _load();
  }

  @override
  void dispose() {
    PushNotificationService.instance.inboxRefresh.removeListener(_onInboxRefresh);
    super.dispose();
  }

  void _onInboxRefresh() {
    if (mounted) {
      _load();
    }
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;
    if (_items.isEmpty && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final items = await NotificationApi.instance.fetchInbox();
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _loading = false;
        _error = 'Could not load notifications. Pull to refresh.';
      });
    }
  }

  Future<void> _open(AppNotification item) async {
    if (!item.isRead && item.id > 0) {
      try {
        await NotificationApi.instance.markRead(item.id);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _items = [
            for (final row in _items)
              if (row.id == item.id) row.copyWith(isRead: true) else row,
          ];
        });
      }
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationDetailPage(item: item.copyWith(isRead: true)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppTheme.card,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 20, 8),
              child: Row(
                children: [
                  if (widget.onClose != null) ...[
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.ink),
                      onPressed: widget.onClose,
                      tooltip: 'Back',
                    ),
                    const SizedBox(width: 4),
                  ],
                  const Text(
                    'Notifications',
                    style: TextStyle(
                      color: AppTheme.ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (widget.onOpenAddNotification != null) ...[
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFD97706),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: widget.onOpenAddNotification,
                      icon: const Icon(Icons.notification_add_rounded, size: 16),
                      label: const Text('Add Notice', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (widget.onOpenWebNotifications != null) ...[
                    IconButton(
                      tooltip: 'Web Broadcast Center',
                      icon: const Icon(Icons.list_alt_rounded, color: AppTheme.ink, size: 22),
                      onPressed: widget.onOpenWebNotifications,
                    ),
                  ],
                ],
              ),
            ),
            if (widget.onOpenWebNotifications != null || widget.onOpenAddNotification != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.campaign_outlined, color: Color(0xFF2563EB), size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Cash Owner Broadcast Center',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                        ),
                      ),
                      if (widget.onOpenWebNotifications != null)
                        InkWell(
                          onTap: widget.onOpenWebNotifications,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            child: Text(
                              'View List',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF2563EB)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                color: AppTheme.green700,
                onRefresh: _load,
                child: _buildBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.green700),
      );
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(36),
        children: [
          const SizedBox(height: 48),
          const Icon(Icons.notifications_none_rounded, size: 48, color: AppTheme.gold500),
          const SizedBox(height: 16),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.inkMuted, height: 1.45),
          ),
        ],
      );
    }

    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(36),
        children: const [
          SizedBox(height: 48),
          Icon(Icons.notifications_none_rounded, size: 48, color: AppTheme.gold500),
          SizedBox(height: 16),
          Text(
            'No mosque alerts yet. Admin messages and automatic payment or subscription alerts will show here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.inkMuted, height: 1.45),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = _items[index];
        final imageUrl = item.imageUrl;
        return Material(
          color: AppTheme.card,
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0x14000000)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _open(item),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (imageUrl != null)
                  NotificationImage(
                    url: imageUrl,
                    height: 176,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(18),
                    ),
                    heroTag: 'notification-image-${item.id}',
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(
                          color: item.isRead ? AppTheme.cream100 : AppTheme.gold500,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              [
                                item.typeLabel,
                                if (item.timeLabel.isNotEmpty) item.timeLabel,
                              ].join('  ·  '),
                              style: const TextStyle(
                                color: AppTheme.green700,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.title,
                              style: TextStyle(
                                color: AppTheme.ink,
                                fontSize: 16,
                                fontWeight: item.isRead ? FontWeight.w600 : FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.body,
                              maxLines: imageUrl == null ? 2 : 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppTheme.inkMuted,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class NotificationDetailPage extends StatefulWidget {
  const NotificationDetailPage({super.key, required this.item});

  final AppNotification item;

  @override
  State<NotificationDetailPage> createState() => _NotificationDetailPageState();
}

class _NotificationDetailPageState extends State<NotificationDetailPage> {
  late AppNotification _item;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    if (_item.id > 0 && (_item.body.trim().isEmpty || _item.title.trim() == 'Notification')) {
      _loadFullDetails();
    }
  }

  Future<void> _loadFullDetails() async {
    setState(() => _loading = true);
    try {
      final items = await NotificationApi.instance.fetchInbox();
      final match = items.firstWhere(
        (it) => it.id == _item.id,
        orElse: () => _item,
      );
      if (mounted && match.id == _item.id && match.body.isNotEmpty) {
        setState(() {
          _item = match.copyWith(isRead: true);
          _loading = false;
        });
        return;
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final imageUrl = item.imageUrl;

    return Scaffold(
      backgroundColor: AppTheme.card,
      appBar: AppBar(
        title: const Text('Notification'),
        backgroundColor: AppTheme.green950,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text(
            [
              item.typeLabel,
              if (item.timeLabel.isNotEmpty) item.timeLabel,
            ].join('  ·  '),
            style: const TextStyle(
              color: AppTheme.green700,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            item.title,
            style: const TextStyle(
              color: AppTheme.ink,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 12),
          if (_loading && item.body.trim().isEmpty) ...[
            const SizedBox(height: 24),
            const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppTheme.green700,
                ),
              ),
            ),
          ] else ...[
            Text(
              item.body,
              style: const TextStyle(
                color: AppTheme.inkMuted,
                fontSize: 16,
                height: 1.55,
              ),
            ),
            if (imageUrl != null) ...[
              const SizedBox(height: 20),
              NotificationImage(
                url: imageUrl,
                height: 240,
                borderRadius: const BorderRadius.all(Radius.circular(18)),
                heroTag: 'notification-image-${item.id}',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => NotificationImageViewer(
                        url: imageUrl,
                        title: item.title,
                        heroTag: 'notification-image-${item.id}',
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              const Text(
                'Tap the image to view full size',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.inkMuted, fontSize: 12),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class NotificationImageViewer extends StatelessWidget {
  const NotificationImageViewer({
    super.key,
    required this.url,
    required this.title,
    required this.heroTag,
  });

  final String url;
  final String title;
  final Object heroTag;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Hero(
            tag: heroTag,
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 64,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
