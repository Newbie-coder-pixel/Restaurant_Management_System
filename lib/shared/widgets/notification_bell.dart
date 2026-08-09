// lib/shared/widgets/notification_bell.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';
import '../models/order_event_model.dart';
import '../providers/order_events_provider.dart';

const _lastSeenPrefsKey = 'order_events_last_seen';
const _maxRecentEvents = 30;

/// Bell + unread badge for the staff AppDrawer header. Unread state is a
/// client-side "last seen" timestamp (shared_preferences), not a per-user
/// read-receipts table — this is a deliberate v1 simplification: a restaurant
/// floor is realistically one device per staff member per shift, so a local
/// timestamp is trivially correct and costs zero DB writes, at the cost of
/// not syncing "read" state across a staff member's own multiple devices
/// (acceptable trade-off, can be upgraded later without touching the
/// order_events schema).
class NotificationBell extends ConsumerStatefulWidget {
  final String branchId;
  const NotificationBell({super.key, required this.branchId});

  @override
  ConsumerState<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends ConsumerState<NotificationBell> {
  final List<OrderEvent> _recent = [];
  DateTime? _lastSeen;
  bool _prefsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadLastSeen();
    ref.listenManual(orderEventsForBranchProvider(widget.branchId),
        (prev, next) {
      next.whenData((event) {
        if (!mounted) return;
        setState(() {
          _recent.insert(0, event);
          if (_recent.length > _maxRecentEvents) {
            _recent.removeRange(_maxRecentEvents, _recent.length);
          }
        });
      });
    });
  }

  Future<void> _loadLastSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final iso = prefs.getString(_lastSeenPrefsKey);
    if (!mounted) return;
    setState(() {
      _lastSeen = iso != null ? DateTime.tryParse(iso) : null;
      _prefsLoaded = true;
    });
  }

  int get _unreadCount {
    if (!_prefsLoaded) return 0;
    if (_lastSeen == null) return _recent.length;
    return _recent.where((e) => e.createdAt.isAfter(_lastSeen!)).length;
  }

  Future<void> _openList() async {
    final now = DateTime.now();
    await showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _RecentEventsSheet(events: _recent),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSeenPrefsKey, now.toIso8601String());
    if (!mounted) return;
    setState(() => _lastSeen = now);
  }

  @override
  Widget build(BuildContext context) {
    final unread = _unreadCount;
    return IconButton(
      tooltip: 'Recent order updates',
      onPressed: _openList,
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 9 ? '9+' : '$unread'),
        child: const Icon(Icons.notifications_rounded, color: AppColors.textSecondary),
      ),
    );
  }
}

class _RecentEventsSheet extends StatelessWidget {
  final List<OrderEvent> events;
  const _RecentEventsSheet({required this.events});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Recent Order Updates',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (events.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Nothing yet.'),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: events.length,
                  itemBuilder: (context, i) {
                    final event = events[i];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.circle_notifications_rounded),
                      title: Text(event.message),
                      subtitle: Text(_relativeTime(event.createdAt)),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
