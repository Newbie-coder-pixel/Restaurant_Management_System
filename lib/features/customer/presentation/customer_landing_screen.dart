// lib/features/customer/presentation/customer_landing_screen.dart
//
// CHANGES v4:
// 1. All changes from v3 retained
// 2. The "Orders" tab now has 2 sub-tabs:
//    - "History" → CustomerOrderHistoryScreen
//    - "Track Order" → _EmbeddedOrderTracker

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'customer_login_screen.dart';
import 'customer_my_bookings_screen.dart';
import 'customer_chatbot_screen.dart';
import 'customer_order_history_screen.dart'; // ← ADDED THIS
import '../providers/customer_auth_provider.dart';
import '../providers/cart_provider.dart';
import 'widgets/cart_bottom_bar.dart';
import '../../../../core/services/notification_service.dart';

// ── Active branches provider ─────────────────────────────────────────
final _customerBranchesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await Supabase.instance.client
      .from('branches')
      .select(
          'id, name, address, phone, opening_time, closing_time, latitude, longitude')
      .eq('is_active', true)
      .order('name');
  return (res as List).cast<Map<String, dynamic>>();
});

// ── Nearest Branch State ──────────────────────────────────────────
abstract class _NearestState {}

class _NearestInitial extends _NearestState {}

class _NearestLoading extends _NearestState {}

class _NearestLoaded extends _NearestState {
  final Map<String, dynamic> branch;
  final double distanceKm;
  _NearestLoaded(this.branch, this.distanceKm);
}

class _NearestDenied extends _NearestState {}

class _NearestError extends _NearestState {
  final String msg;
  _NearestError(this.msg);
}

// ── Nearest Branch Notifier ─────────────────────────────────────
class _NearestBranchNotifier extends StateNotifier<_NearestState> {
  _NearestBranchNotifier() : super(_NearestInitial());

  Future<void> detect(List<Map<String, dynamic>> branches) async {
    state = _NearestLoading();

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      state = _NearestError('GPS is not active. Enable location in settings.');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      state = _NearestDenied();
      return;
    }

    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      state = _NearestError('Failed to get location. Please try again.');
      return;
    }

    final branchesWithCoord = branches.where((b) {
      final lat = b['latitude'];
      final lng = b['longitude'];
      return lat != null && lng != null;
    }).toList();

    if (branchesWithCoord.isEmpty) {
      state = _NearestError('Branch coordinate data is not yet available.');
      return;
    }

    Map<String, dynamic>? nearest;
    double minDist = double.infinity;

    for (final b in branchesWithCoord) {
      final lat = (b['latitude'] as num).toDouble();
      final lng = (b['longitude'] as num).toDouble();
      final dist = _haversine(pos.latitude, pos.longitude, lat, lng);
      if (dist < minDist) {
        minDist = dist;
        nearest = b;
      }
    }

    if (nearest != null) {
      state = _NearestLoaded(nearest, minDist);
    } else {
      state = _NearestError('Could not find the nearest branch.');
    }
  }

  void deny() => state = _NearestDenied();
  void reset() => state = _NearestInitial();

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _rad(double deg) => deg * pi / 180;
}

final _nearestBranchProvider =
    StateNotifierProvider<_NearestBranchNotifier, _NearestState>(
        (ref) => _NearestBranchNotifier());

// ════════════════════════════════════════════
// MAIN SCREEN
// ════════════════════════════════════════════
class CustomerLandingScreen extends ConsumerStatefulWidget {
  final int initialTab;
  const CustomerLandingScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<CustomerLandingScreen> createState() =>
      _CustomerLandingScreenState();
}

class _CustomerLandingScreenState
    extends ConsumerState<CustomerLandingScreen> {
  late int _tab;
  late final ValueNotifier<int> _tabNotifier;
  User? _cachedUser;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _tabNotifier = ValueNotifier<int>(_tab);
    _tabNotifier.addListener(() {
      if (mounted) setState(() => _tab = _tabNotifier.value);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      final perm = await Geolocator.checkPermission();
      if ((perm == LocationPermission.always ||
              perm == LocationPermission.whileInUse) &&
          mounted) {
        final branchesAsync = ref.read(_customerBranchesProvider);
        final branches = branchesAsync.valueOrNull ?? [];
        if (branches.isNotEmpty) {
          ref.read(_nearestBranchProvider.notifier).detect(branches);
        }
      }
    });
  }

  @override
  void dispose() {
    _tabNotifier.dispose();
    super.dispose();
  }

  void switchTab(int index) => _tabNotifier.value = index;

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(customerUserProvider);

    userAsync.whenData((u) {
      if (u != null) _cachedUser = u;
    });

    final User? user = userAsync.maybeWhen(
      data: (u) => u,
      orElse: () => _cachedUser,
    );

    if (user == null && userAsync.isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8F9FA),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFE94560)),
        ),
      );
    }

    if (user == null) {
      return CustomerLoginScreen(onLoginSuccess: () {});
    }

    final cart = ref.watch(cartProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(user),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!cart.isEmpty && _tab == 0)
            CartBottomBar(
              cart: cart,
              onCheckout: () => context.go('/customer/checkout'),
            ),
          _buildBottomNav(),
        ],
      ),
    );
  }

  String _displayName(User user) {
    final meta = user.userMetadata;
    if (meta != null) {
      final fullName = meta['full_name'];
      if (fullName is String && fullName.isNotEmpty) return fullName;
      final name = meta['name'];
      if (name is String && name.isNotEmpty) return name;
    }
    final email = user.email;
    if (email != null && email.isNotEmpty) return email;
    final phone = user.phone;
    if (phone != null && phone.isNotEmpty) return phone;
    return 'Customer';
  }

  String _avatarUrl(User user) {
    final meta = user.userMetadata;
    if (meta == null) return '';
    final url = meta['avatar_url'];
    if (url is String && url.isNotEmpty) return url;
    final picture = meta['picture'];
    if (picture is String && picture.isNotEmpty) return picture;
    return '';
  }

  // ── TOP BAR ──────────────────────────────────────────────────
  Widget _buildTopBar(User user) {
    // ← CHANGED 'Track Order' → 'Orders'
    const titles = ['Home', 'Table Booking', 'Orders', 'AI Chat'];
    final displayName = _displayName(user);
    final firstName = displayName.split(' ').first;
    final initial =
        firstName.isNotEmpty ? firstName[0].toUpperCase() : 'P';
    final avatarUrl = _avatarUrl(user);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1A2E), Color(0xFF0F3460)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3), width: 2),
            ),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFFE94560),
              backgroundImage:
                  avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
              onBackgroundImageError:
                  avatarUrl.isNotEmpty ? (_, __) {} : null,
              child: avatarUrl.isEmpty
                  ? Text(initial,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700))
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titles[_tab.clamp(0, titles.length - 1)],
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700),
                ),
                Text(
                  'Hi, $firstName 👋',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.logout_rounded,
                  color: Colors.white70, size: 20),
              onPressed: _confirmLogout,
              padding: const EdgeInsets.all(8),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24)),
        title: const Text('Log out?',
            style: TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: const Text('You will be logged out of your account.',
            style: TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style:
                    TextStyle(fontFamily: 'Poppins', color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await NotificationService.removeToken();
              await Supabase.instance.client.auth.signOut();
            },
            child: const Text('Log Out',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Color(0xFFE94560),
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ── BODY ─────────────────────────────────────────────────────
  Widget _buildBody() {
    return Stack(
      children: [
        Visibility(
          visible: _tab == 0,
          maintainState: true,
          child: _HomeTab(onSwitchTab: switchTab),
        ),
        Visibility(
          visible: _tab == 1,
          maintainState: false,
          child: const CustomerMyBookingsScreen(),
        ),
        // ← REPLACED _EmbeddedOrderTracker with _OrderTab
        Visibility(
          visible: _tab == 2,
          maintainState: true,
          child: const _OrderTab(),
        ),
        Visibility(
          visible: _tab == 3,
          maintainState: true,
          child: const CustomerChatbotScreen(),
        ),
      ],
    );
  }

  // ── BOTTOM NAV ───────────────────────────────────────────────
  Widget _buildBottomNav() {
    const items = [
      (Icons.home_outlined, Icons.home_rounded, 'Home'),
      (Icons.calendar_today_outlined, Icons.calendar_today_rounded, 'Booking'),
      (Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Orders'),
      (Icons.smart_toy_outlined, Icons.smart_toy_rounded, 'AI Chat'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, -4))
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: Row(
            children: List.generate(items.length, (i) {
              final (outline, filled, label) = items[i];
              final active = _tab == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _tab = i),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: active
                          ? const Color(0xFFE94560).withValues(alpha: 0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            active ? filled : outline,
                            key: ValueKey(active),
                            color: active
                                ? const Color(0xFFE94560)
                                : const Color(0xFF9CA3AF),
                            size: 24,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: active
                                ? const Color(0xFFE94560)
                                : const Color(0xFF9CA3AF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════
// ORDER TAB — History & Track Order sub-tabs
// ════════════════════════════════════════════
class _OrderTab extends StatefulWidget {
  const _OrderTab();

  @override
  State<_OrderTab> createState() => _OrderTabState();
}

class _OrderTabState extends State<_OrderTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Sub-tab bar
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabCtrl,
            labelStyle: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
            unselectedLabelStyle: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
            labelColor: const Color(0xFFE94560),
            unselectedLabelColor: const Color(0xFF9CA3AF),
            indicatorColor: const Color(0xFFE94560),
            indicatorWeight: 3,
            tabs: const [
              Tab(text: 'History'),
              Tab(text: 'Track Order'),
            ],
          ),
        ),
        // ── Sub-tab content
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: const [
              CustomerOrderHistoryScreen(),
              _EmbeddedOrderTracker(),
            ],
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════
// EMBEDDED ORDER TRACKER
// ════════════════════════════════════════════
class _EmbeddedOrderTracker extends StatefulWidget {
  const _EmbeddedOrderTracker();

  @override
  State<_EmbeddedOrderTracker> createState() => _EmbeddedOrderTrackerState();
}

class _EmbeddedOrderTrackerState extends State<_EmbeddedOrderTracker> {
  final _ctrl = TextEditingController();
  Map<String, dynamic>? _order;
  List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  String? _error;
  RealtimeChannel? _channel;

  @override
  void dispose() {
    _ctrl.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  // Deliberately does NOT merge payload.newRecord directly into _order — see
  // the matching comment in customer_order_tracker_screen.dart's
  // _subscribeRealtime. Re-fetches via get_order_by_number (not
  // get_order_by_id, which deliberately DOES include customer_phone/email)
  // so this screen can't pick up PII via a live-update path that bypasses
  // the same protection its initial search already has.
  void _subscribeRealtime(String orderId) {
    _channel?.unsubscribe();
    _channel = Supabase.instance.client
        .channel('embedded_tracker_$orderId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: orderId,
          ),
          callback: (_) async {
            final orderNumber = _order?['order_number'] as String?;
            if (orderNumber == null) return;
            final rows = await Supabase.instance.client.rpc('get_order_by_number', params: {
              'p_order_number': orderNumber,
            }) as List<dynamic>;
            if (mounted && rows.isNotEmpty) {
              setState(() => _order = rows.first as Map<String, dynamic>);
            }
          },
        )
        .subscribe();
  }

  Future<void> _search() async {
    final code = _ctrl.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _order = null;
      _items = [];
    });
    _channel?.unsubscribe();

    try {
      // Goes through the get_order_by_number RPC rather than a direct table
      // SELECT — this is reachable with no login and a guessable "A001"-style
      // number, so it must never return more than the one exact match, and
      // must never expose customer_phone/customer_email (see
      // supabase/migrations/20260805040000_get_order_by_number_rpc.sql — a
      // direct SELECT here was, until this fix, live-exploitable to dump
      // every customer's name/phone/email from the last 24h with no filter).
      final orders = await Supabase.instance.client
          .rpc('get_order_by_number', params: {'p_order_number': code}) as List<dynamic>;

      if (orders.isEmpty) {
        if (mounted) {
          setState(() {
            _error =
                'Order not found. Please check your order number again.';
            _loading = false;
          });
        }
        return;
      }

      final order = Map<String, dynamic>.from(orders.first);
      // get_order_items RPC rather than a direct SELECT — see
      // supabase/migrations/20260805050000_full_order_pii_lockdown.sql.
      final items = await Supabase.instance.client.rpc('get_order_items', params: {
        'p_order_id': order['id'],
      }) as List<dynamic>;

      if (mounted) {
        setState(() {
          _order = order;
          _items = items.cast();
          _loading = false;
        });
        _subscribeRealtime(order['id'] as String);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'An error occurred. Please try again.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (_order != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1D9E75).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: Color(0xFF1D9E75), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                const Text('Live tracking active',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1D9E75))),
              ],
            ),
          ),
        ),

      // Search box
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ]),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Enter Order Number',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
          const SizedBox(height: 6),
          const Text('The order number is on your receipt or confirmation screen.',
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TextField(
                  controller: _ctrl,
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: (_) => _search(),
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2),
                  decoration: const InputDecoration(
                    hintText: 'Example: WEB-20260327-1234',
                    hintStyle: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.normal,
                        color: Colors.grey,
                        letterSpacing: 0),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                  ),
                ),
              )),
            const SizedBox(width: 12),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              child: ElevatedButton(
                onPressed: _loading ? null : _search,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE94560),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(52, 52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : const Icon(Icons.search_rounded, size: 24)),
            ),
          ]),
        ])),

      if (_error != null) ...[
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.red.withValues(alpha: 0.2))),
          child: Row(children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(_error!,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: Colors.red))),
          ])),
      ],

      if (_order != null) ...[
        const SizedBox(height: 20),
        _OrderStatusCard(order: _order!, items: _items),
      ],

      if (_order == null && _error == null && !_loading) ...[
        const SizedBox(height: 60),
        Center(
          child: Column(children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.receipt_long_outlined,
                  size: 48, color: Colors.grey[400]),
            ),
            const SizedBox(height: 16),
            Text(
              'Enter your order number above\nto see its status.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: Colors.grey[500],
                  height: 1.6),
            ),
          ])),
      ],
    ]);
  }
}

// ════════════════════════════════════════════
// HOME TAB
// ════════════════════════════════════════════
class _HomeTab extends ConsumerStatefulWidget {
  final void Function(int) onSwitchTab;
  const _HomeTab({required this.onSwitchTab});

  @override
  ConsumerState<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<_HomeTab> {
  final branchSectionKey = GlobalKey();
  final _scrollController = ScrollController();

  void Function(int) get onSwitchTab => widget.onSwitchTab;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBranches() {
    final ctx = branchSectionKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(customerUserProvider);
    final user = userAsync.valueOrNull;
    final branchesAsync = ref.watch(_customerBranchesProvider);
    final nearestState = ref.watch(_nearestBranchProvider);
    final displayName = _safeName(user);

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(20),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Welcome banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A1A2E), Color(0xFF0F3460)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F3460).withValues(alpha: 0.2),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  )
                ]),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Welcome,',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 14)),
                    const SizedBox(height: 6),
                    Text(displayName,
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    const Text('What would you like to do today?',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white70,
                            fontSize: 13)),
                  ])),
            const SizedBox(height: 20),

            // ── Nearest Branch Banner
            branchesAsync.maybeWhen(
              data: (branches) => _NearestBranchBanner(
                nearestState: nearestState,
                branches: branches,
                onNavigate: (branchId) =>
                    context.push('/customer/menu/$branchId'),
                onDetect: () => ref
                    .read(_nearestBranchProvider.notifier)
                    .detect(branches),
                onDeny: () =>
                    ref.read(_nearestBranchProvider.notifier).deny(),
                onRetry: () => ref
                    .read(_nearestBranchProvider.notifier)
                    .detect(branches),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: 24),

            // ── Quick Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Quick Actions',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: Color(0xFF1A1A2E))),
                TextButton(
                  onPressed: _scrollToBranches,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text('View All',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          color: Color(0xFFE94560),
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: _ActionCard(
                  icon: Icons.restaurant_menu_rounded,
                  label: 'Order Food',
                  subtitle: 'View menu & order',
                  color: const Color(0xFFE94560),
                  onTap: _scrollToBranches)),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: _ActionCard(
                  icon: Icons.calendar_today_rounded,
                  label: 'Table Booking',
                  subtitle: 'Reserve now',
                  color: const Color(0xFF0F3460),
                  onTap: () => onSwitchTab(1))),
              const SizedBox(width: 14),
              Expanded(
                child: _ActionCard(
                  icon: Icons.receipt_long_rounded,
                  label: 'Track Order',
                  subtitle: 'Status & history',
                  color: const Color(0xFF1D9E75),
                  onTap: () => onSwitchTab(2))),
            ]),
            const SizedBox(height: 28),

            // ── Our Branches
            Container(
              key: branchSectionKey,
              child: const Text('Our Branches',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: Color(0xFF1A1A2E)))),
            const SizedBox(height: 6),
            const Text('Choose a branch to view the menu & order',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: Color(0xFF9CA3AF))),
            const SizedBox(height: 16),

            branchesAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(
                      color: Color(0xFFE94560)))),
              error: (e, _) => Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: Colors.red.withValues(alpha: 0.2))),
                child: const Row(children: [
                  Icon(Icons.error_outline, color: Colors.red, size: 18),
                  SizedBox(width: 10),
                  Text('Failed to load branches',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          color: Colors.red)),
                ])),
              data: (branches) {
                if (branches.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('No active branches yet',
                          style: TextStyle(
                              fontFamily: 'Poppins', color: Colors.grey)),
                    ));
                }
                return Column(
                  children: branches
                      .map((b) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _BranchCard(branch: b),
                      ))
                      .toList());
              },
            ),
            const SizedBox(height: 12),
          ]),
    );
  }

  static String _safeName(User? user) {
    if (user == null) return 'Customer';
    final meta = user.userMetadata;
    if (meta != null) {
      final fullName = meta['full_name'];
      if (fullName is String && fullName.isNotEmpty) {
        return fullName.split(' ').first;
      }
      final name = meta['name'];
      if (name is String && name.isNotEmpty) {
        return name.split(' ').first;
      }
    }
    final email = user.email;
    if (email != null && email.isNotEmpty) return email.split('@').first;
    return 'Customer';
  }
}

// ════════════════════════════════════════════
// NEAREST BRANCH BANNER
// ════════════════════════════════════════════
class _NearestBranchBanner extends StatelessWidget {
  final _NearestState nearestState;
  final List<Map<String, dynamic>> branches;
  final void Function(String branchId) onNavigate;
  final VoidCallback onDetect;
  final VoidCallback onDeny;
  final VoidCallback onRetry;

  const _NearestBranchBanner({
    required this.nearestState,
    required this.branches,
    required this.onNavigate,
    required this.onDetect,
    required this.onDeny,
    required this.onRetry,
  });

  bool get _hasCoordinates =>
      branches.any((b) => b['latitude'] != null && b['longitude'] != null);

  @override
  Widget build(BuildContext context) {
    if (!_hasCoordinates) return const SizedBox.shrink();
    if (nearestState is _NearestDenied) return const SizedBox.shrink();

    if (nearestState is _NearestInitial) {
      return _PromptCard(
        onTap: () => _LocationPermissionSheet.show(
          context,
          onGranted: onDetect,
          onDenied: onDeny,
        ),
      );
    }

    if (nearestState is _NearestLoading) {
      return const _LoadingCard();
    }

    if (nearestState is _NearestLoaded) {
      final loaded = nearestState as _NearestLoaded;
      return _ResultCard(
        branch: loaded.branch,
        distanceKm: loaded.distanceKm,
        onTap: () => onNavigate(loaded.branch['id'] as String),
        onRefresh: onDetect,
      );
    }

    if (nearestState is _NearestError) {
      final err = nearestState as _NearestError;
      return _ErrorCard(message: err.msg, onRetry: onRetry);
    }

    return const SizedBox.shrink();
  }
}

// ── Banner sub-widgets ────────────────────────────────────────────

class _PromptCard extends StatelessWidget {
  final VoidCallback onTap;
  const _PromptCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF0F4FF), Color(0xFFE8EEFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: const Color(0xFFBFD0FF), width: 1.5),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F3460).withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            )
          ]),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A1A2E), Color(0xFF0F3460)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.location_on_rounded,
                color: Colors.white, size: 22)),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text('Find the nearest branch',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E))),
              SizedBox(height: 4),
              Text('Tap to enable location',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: Color(0xFF6B7280))),
            ])),
          const Icon(Icons.chevron_right,
              color: Color(0xFF0F3460), size: 24),
        ]),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF0F4FF), Color(0xFFE8EEFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16)),
      child: const Row(children: [
        SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor:
                  AlwaysStoppedAnimation(Color(0xFF0F3460)))),
        SizedBox(width: 14),
        Text('Finding the nearest branch...',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF0F3460))),
      ]),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final Map<String, dynamic> branch;
  final double distanceKm;
  final VoidCallback onTap;
  final VoidCallback onRefresh;

  const _ResultCard({
    required this.branch,
    required this.distanceKm,
    required this.onTap,
    required this.onRefresh,
  });

  String _formatDist(double km) {
    if (km < 1) return '${(km * 1000).round()} m';
    return '${km.toStringAsFixed(1)} km';
  }

  bool _isOpen() {
    final openStr = branch['opening_time'] as String?;
    final closeStr = branch['closing_time'] as String?;
    if (openStr == null || closeStr == null) return true;
    try {
      final now = TimeOfDay.now();
      final openParts = openStr.split(':');
      final closeParts = closeStr.split(':');
      final openMin =
          int.parse(openParts[0]) * 60 + int.parse(openParts[1]);
      final closeMin =
          int.parse(closeParts[0]) * 60 + int.parse(closeParts[1]);
      final nowMin = now.hour * 60 + now.minute;
      // Handle closing time crossing midnight (e.g. 10:00 - 01:00)
      if (closeMin < openMin) {
        return nowMin >= openMin || nowMin <= closeMin;
      }
      return nowMin >= openMin && nowMin <= closeMin;
    } catch (_) {
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = branch['name'] as String? ?? 'Branch';
    final address = branch['address'] as String? ?? '';
    final isOpen = _isOpen();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF0F4FF), Color(0xFFE8EEFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: const Color(0xFFBFD0FF), width: 1.5),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F3460).withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            )
          ]),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A1A2E), Color(0xFF0F3460)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.store_rounded,
                color: Colors.white, size: 20)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(children: [
                Flexible(
                  child: Text(name,
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A2E)),
                      overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isOpen
                        ? const Color(0xFFE8F5E9)
                        : const Color(0xFFFCE4EC),
                    borderRadius: BorderRadius.circular(6)),
                  child: Text(
                    isOpen ? 'Open' : 'Closed',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isOpen
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFFC62828)))),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.location_on_outlined,
                    size: 14, color: Color(0xFF0F3460)),
                const SizedBox(width: 4),
                Text(_formatDist(distanceKm),
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F3460))),
                if (address.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  const Text('•',
                      style: TextStyle(color: Color(0xFF9CA3AF))),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(address,
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: Color(0xFF9CA3AF)),
                        overflow: TextOverflow.ellipsis)),
                ],
              ]),
            ])),
          const SizedBox(width: 8),
          Column(children: [
            const Icon(Icons.chevron_right,
                color: Color(0xFF0F3460), size: 22),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: onRefresh,
              child: Container(
                padding: const EdgeInsets.all(4),
                child: const Icon(Icons.refresh_rounded,
                    color: Color(0xFF9CA3AF), size: 18)),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withValues(alpha: 0.2))),
      child: Row(children: [
        const Icon(Icons.error_outline, color: Colors.red, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(message,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: Colors.red))),
        GestureDetector(
          onTap: onRetry,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF0F3460).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('Try Again',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: Color(0xFF0F3460),
                    fontWeight: FontWeight.w600))),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════
// LOCATION PERMISSION BOTTOM SHEET
// ════════════════════════════════════════════
class _LocationPermissionSheet extends StatelessWidget {
  final VoidCallback onGranted;
  final VoidCallback onDenied;

  const _LocationPermissionSheet({
    required this.onGranted,
    required this.onDenied,
  });

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onGranted,
    required VoidCallback onDenied,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _LocationPermissionSheet(
        onGranted: onGranted,
        onDenied: onDenied,
      ),
    );
  }

  Future<void> _handleAllow(BuildContext context) async {
    Navigator.of(context).pop();

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      onDenied();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      onDenied();
      return;
    }

    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      onGranted();
    } else {
      onDenied();
    }
  }

  void _handleDeny(BuildContext context) {
    Navigator.of(context).pop();
    onDenied();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, MediaQuery.of(context).padding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 5,
            decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(3))),
          const SizedBox(height: 28),
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1A1A2E), Color(0xFF0F3460)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle),
            child: const Icon(Icons.location_on_rounded,
                size: 40, color: Colors.white)),
          const SizedBox(height: 20),
          const Text('Allow Location Access',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A2E))),
          const SizedBox(height: 10),
          Text(
            'We use your location to\nshow the nearest restaurant branch.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                color: Colors.grey[600],
                height: 1.5)),
          const SizedBox(height: 22),
          _benefitRow(Icons.store_rounded, 'Nearest branch to your location'),
          const SizedBox(height: 8),
          _benefitRow(
              Icons.access_time_rounded, 'Relevant open/closed info'),
          const SizedBox(height: 8),
          _benefitRow(
              Icons.navigation_rounded, 'Navigate directly to the branch'),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _handleAllow(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A2E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0),
              child: const Text('Allow Location Access',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w700)))),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => _handleDeny(context),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
              child: Text('Skip',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w600)))),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.lock_outline, size: 12, color: Colors.grey[400]),
            const SizedBox(width: 6),
            Text('Location is only used while the app is open',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: Colors.grey[400])),
          ]),
        ],
      ),
    );
  }

  Widget _benefitRow(IconData icon, String text) {
    return Row(children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1A2E), Color(0xFF0F3460)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 18, color: Colors.white)),
      const SizedBox(width: 14),
      Text(text,
          style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: Color(0xFF424242),
              fontWeight: FontWeight.w500)),
    ]);
  }
}

// ── Branch Card ───────────────────────────────────────────────────
class _BranchCard extends StatelessWidget {
  final Map<String, dynamic> branch;
  const _BranchCard({required this.branch});

  bool _isOpen() {
    final openStr = branch['opening_time'] as String?;
    final closeStr = branch['closing_time'] as String?;
    if (openStr == null || closeStr == null) return true;
    try {
      final now = TimeOfDay.now();
      final openParts = openStr.split(':');
      final closeParts = closeStr.split(':');
      final openMin =
          int.parse(openParts[0]) * 60 + int.parse(openParts[1]);
      final closeMin =
          int.parse(closeParts[0]) * 60 + int.parse(closeParts[1]);
      final nowMin = now.hour * 60 + now.minute;
      // Handle closing time crossing midnight (e.g. 10:00 - 01:00)
      if (closeMin < openMin) {
        return nowMin >= openMin || nowMin <= closeMin;
      }
      return nowMin >= openMin && nowMin <= closeMin;
    } catch (_) {
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = branch['name'] as String? ?? 'Branch';
    final address = branch['address'] as String? ?? '';
    final open =
        (branch['opening_time'] as String?)?.substring(0, 5) ?? '10:00';
    final close =
        (branch['closing_time'] as String?)?.substring(0, 5) ?? '22:00';
    final isOpen = _isOpen();

    return GestureDetector(
      onTap: () => context.go('/customer/menu/${branch['id']}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ]),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Row(children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1A1A2E), Color(0xFF0F3460)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.store_rounded,
                    color: Colors.white, size: 26)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text(name,
                              style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: Color(0xFF1A1A2E)),
                              overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isOpen
                                ? const Color(0xFFE8F5E9)
                                : const Color(0xFFFCE4EC),
                            borderRadius: BorderRadius.circular(6)),
                          child: Text(
                            isOpen ? 'Open' : 'Closed',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: isOpen
                                    ? const Color(0xFF2E7D32)
                                    : const Color(0xFFC62828)))),
                      ]),
                      if (address.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(address,
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                color: Color(0xFF9CA3AF)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                      const SizedBox(height: 6),
                      Row(children: [
                        const Icon(Icons.access_time_outlined,
                            size: 14, color: Color(0xFF6B7280)),
                        const SizedBox(width: 6),
                        Text('$open – $close WIB',
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                color: Color(0xFF6B7280))),
                      ]),
                    ])),
            ])),
          GestureDetector(
            onTap: isOpen
                ? () => context.go('/customer/menu/${branch['id']}')
                : null,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: isOpen
                    ? const Color(0xFFE94560)
                    : const Color(0xFFE5E7EB),
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(20))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isOpen
                        ? Icons.restaurant_menu_rounded
                        : Icons.do_not_disturb_alt_outlined,
                    color:
                        isOpen ? Colors.white : const Color(0xFF9CA3AF),
                    size: 18),
                  const SizedBox(width: 10),
                  Text(
                    isOpen ? '🍽️ Order Now' : 'Currently Closed',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isOpen
                            ? Colors.white
                            : const Color(0xFF9CA3AF))),
                ])),
          ),
        ])));
  }
}

// ── Action Card ───────────────────────────────────────────────────
class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const _ActionCard(
      {required this.icon,
      required this.label,
      required this.subtitle,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withValues(alpha: 0.85)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 6))
        ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
        const SizedBox(height: 14),
        Text(label,
            style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15)),
        const SizedBox(height: 4),
        Text(subtitle,
            style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 11)),
      ])),
  );
}

// ════════════════════════════════════════════
// ORDER STATUS CARD
// ════════════════════════════════════════════
class _OrderStatusCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final List<Map<String, dynamic>> items;
  const _OrderStatusCard({required this.order, required this.items});

  static const _statusLabels = {
    'new': '🆕 New Order',
    'preparing': '👨‍🍳 Preparing',
    'ready': '✅ Ready to Serve',
    'served': '🍽️ Served',
    'paid': '💳 Paid',
    'cancelled': '❌ Cancelled',
  };
  static const _statusColors = {
    'new': Color(0xFF6B7280),
    'preparing': Color(0xFFD97706),
    'ready': Color(0xFF1D9E75),
    'served': Color(0xFF0F3460),
    'paid': Color(0xFF1D9E75),
    'cancelled': Color(0xFFE94560),
  };
  static const _statusMessages = {
    'new': '⏳ Your order is waiting for kitchen confirmation.',
    'preparing': '🔥 The kitchen is preparing your order, almost there!',
    'ready': '🎉 Your order is ready! A server will bring it to you shortly.',
    'served': '😊 Your order has been served. Enjoy your meal!',
    'paid': '✅ Payment complete. Thank you for visiting!',
    'cancelled': '❌ This order was cancelled.',
  };

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String? ?? 'new';
    final paymentStatus = order['payment_status'] as String?;
    final statusLabel = _statusLabels[status] ?? status;
    final statusColor = _statusColors[status] ?? Colors.grey;
    final statusMsg = _statusMessages[status] ?? '';
    final total = (order['total_amount'] as num?)?.toDouble() ?? 0;
    final customerName = order['customer_name'] as String?;
    final notes = order['notes'] as String?;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ]),
      child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(order['order_number'] as String? ?? '',
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w800,
                          fontSize: 18)),
                  if (customerName != null)
                    Text('Under the name: $customerName',
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            color: Colors.grey)),
                ])),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(24)),
            child: Text(statusLabel,
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: statusColor))),
        ]),
        if (statusMsg.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12)),
            child: Text(statusMsg,
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: statusColor,
                    height: 1.4))),
        ],
        const Divider(height: 24, thickness: 1),
        _StatusProgress(status: status, paymentStatus: paymentStatus),
        const SizedBox(height: 20),
        const Text('Order Items',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 15)),
        const SizedBox(height: 12),
        ...items.map((item) {
          final name =
              (item['menu_items'] as Map?)?['name'] as String? ?? '-';
          final qty = item['quantity'] as int? ?? 1;
          final sub = (item['subtotal'] as num?)?.toDouble() ?? 0;
          final special = item['special_requests'] as String?;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE94560)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text('${qty}x',
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                color: Color(0xFFE94560),
                                fontWeight: FontWeight.w700,
                                fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(name,
                          style: const TextStyle(
                              fontFamily: 'Poppins', fontSize: 13))),
                    Text('Rp ${_fmt(sub)}',
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ]),
                  if (special != null && special.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 40, top: 6),
                      child: Row(children: [
                        const Icon(Icons.edit_note,
                            size: 12, color: Color(0xFFD97706)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(special,
                              style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11,
                                  color: Color(0xFFD97706)))),
                      ])),
                ]));
        }),
        if (notes != null && notes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12)),
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.notes, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(notes,
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: Colors.grey))),
                ])),
        ],
        const Divider(height: 24, thickness: 1),
        Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
              Text('Rp ${_fmt(total)}',
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: Color(0xFFE94560))),
            ]),
        if (paymentStatus != 'paid' && status != 'cancelled') ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline,
                  size: 14, color: Color(0xFF0F3460)),
              SizedBox(width: 8),
              Expanded(
                child: Text('💡 Pay at the cashier when the order is ready.',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        color: Color(0xFF0F3460))),
              ),
            ]),
          ),
        ],
      ]));
  }

  String _fmt(double v) {
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

// ── Status Progress ───────────────────────────────────────────────
class _StatusProgress extends StatelessWidget {
  final String status;
  final String? paymentStatus;
  const _StatusProgress({required this.status, this.paymentStatus});

  @override
  Widget build(BuildContext context) {
    const steps = ['new', 'preparing', 'ready', 'served', 'paid'];
    const labels = ['New', 'Cooking', 'Ready', 'Served', 'Paid'];
    final currentIdx = steps.indexOf(status);
    final isCancelled = status == 'cancelled';
    // Orders paid up front never actually get `status` set to 'paid' by the
    // webhook (see midtrans-webhook/index.ts) — payment_status is the real
    // signal for the last step, independent of kitchen progress.
    final isPaid = paymentStatus == 'paid';

    if (isCancelled) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFE94560).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.cancel_outlined,
                color: Color(0xFFE94560), size: 20),
          ),
          const SizedBox(width: 10),
          const Text('Order cancelled',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: Color(0xFFE94560),
                  fontWeight: FontWeight.w700)),
        ]));
    }

    return Row(
      children: steps.asMap().entries.map((e) {
        final idx = e.key;
        final isLast = idx == steps.length - 1;
        final isActive = idx <= currentIdx || (isLast && isPaid);
        final isCurrent = idx == currentIdx;

        return Expanded(
          child: Row(children: [
            Expanded(
              child: Column(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: isCurrent ? 32 : 24,
                  height: isCurrent ? 32 : 24,
                  decoration: BoxDecoration(
                    gradient: isActive
                        ? const LinearGradient(
                            colors: [Color(0xFFE94560), Color(0xFFC93550)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isActive ? null : const Color(0xFFE5E7EB),
                    shape: BoxShape.circle,
                    boxShadow: isCurrent
                        ? [
                            BoxShadow(
                                color: const Color(0xFFE94560)
                                    .withValues(alpha: 0.4),
                                blurRadius: 10,
                                offset: const Offset(0, 2))
                          ]
                        : []),
                  child: isActive
                      ? const Icon(Icons.check,
                          color: Colors.white, size: 16)
                      : null),
                const SizedBox(height: 6),
                Text(labels[idx],
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        fontWeight: isCurrent
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isActive
                            ? const Color(0xFFE94560)
                            : Colors.grey[400]),
                    textAlign: TextAlign.center),
              ])),
            if (!isLast)
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 3,
                  decoration: BoxDecoration(
                    gradient: idx < currentIdx
                        ? const LinearGradient(
                            colors: [Color(0xFFE94560), Color(0xFFC93550)],
                          )
                        : null,
                    color: idx < currentIdx ? null : const Color(0xFFE5E7EB),
                  ),
                )),
          ]));
      }).toList());
  }
}