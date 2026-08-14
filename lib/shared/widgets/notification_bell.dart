// lib/shared/widgets/notification_bell.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';
import '../models/order_event_model.dart';
import '../providers/recent_order_events_provider.dart';

const _lastSeenPrefsKey = 'order_events_last_seen';

/// Bell + unread badge for the staff AppDrawer/shell header. The event
/// history itself lives in [recentOrderEventsProvider] (app-root-scoped),
/// not in this widget's own State — see that file for why. "Unread" is a
/// client-side "last seen" timestamp (shared_preferences), not a per-user
/// read-receipts table — a restaurant floor is realistically one device per
/// staff member per shift, so a local timestamp is trivially correct and
/// costs zero DB writes (doesn't sync "read" state across a staff member's
/// own multiple devices, an acceptable trade-off). The badge count resets
/// on open, but the event list itself only ever clears when the staff
/// member taps Clear All.
class NotificationBell extends ConsumerStatefulWidget {
  const NotificationBell({super.key});

  @override
  ConsumerState<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends ConsumerState<NotificationBell> {
  DateTime? _lastSeen;
  bool _prefsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadLastSeen();
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

  int _unreadCount(List<OrderEvent> recent) {
    if (!_prefsLoaded) return 0;
    if (_lastSeen == null) return recent.length;
    return recent.where((e) => e.createdAt.isAfter(_lastSeen!)).length;
  }

  Future<void> _openList() async {
    final now = DateTime.now();
    await showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => const _RecentEventsSheet(),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSeenPrefsKey, now.toIso8601String());
    if (!mounted) return;
    setState(() => _lastSeen = now);
  }

  @override
  Widget build(BuildContext context) {
    final recent = ref.watch(recentOrderEventsProvider);
    final unread = _unreadCount(recent);
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

class _RecentEventsSheet extends ConsumerWidget {
  const _RecentEventsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(recentOrderEventsProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Recent Order Updates',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                TextButton(
                  onPressed: events.isEmpty
                      ? null
                      : () =>
                          ref.read(recentOrderEventsProvider.notifier).clearAll(),
                  child: const Text('Clear All'),
                ),
              ],
            ),
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
                      trailing: _CategoryChip(label: event.categoryLabel),
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

class _CategoryChip extends StatelessWidget {
  final String label;
  const _CategoryChip({required this.label});

  Color get _color {
    switch (label) {
      case 'Kitchen':
        return AppColors.orderPreparing;
      case 'Service':
        return AppColors.orderReady;
      case 'Payment':
        return AppColors.iconAccentBlue;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: _color,
        ),
      ),
    );
  }
}
