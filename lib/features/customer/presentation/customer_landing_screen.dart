// lib/features/customer/presentation/customer_landing_screen.dart
//
// CHANGES v2:
// 1. _OrderTrackerBody dihapus → pakai CustomerOrderTrackerScreen (tanpa Scaffold)
// 2. Home tab: tambah section "Cabang Kami" fetch dari Supabase → klik ke menu
// 3. _BookingCard: tambah tombol "Hubungi Kami" → WhatsApp/telp staff
// 4. _tabNotifier diganti _tabNotifier (tetap) tapi expose via method publik
//    supaya bisa dipanggil dari child widget

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'customer_login_screen.dart';
import 'customer_my_bookings_screen.dart';
import 'customer_chatbot_screen.dart';
import '../providers/customer_auth_provider.dart';

// ── Provider cabang aktif (dipakai di Home tab) ──────────────────
final _customerBranchesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await Supabase.instance.client
      .from('branches')
      .select('id, name, address, phone, opening_time, closing_time')
      .eq('is_active', true)
      .order('name');
  return (res as List).cast<Map<String, dynamic>>();
});

// ════════════════════════════════════════════
// SCREEN UTAMA
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

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _tabNotifier = ValueNotifier<int>(_tab);
    _tabNotifier.addListener(() {
      if (mounted) setState(() => _tab = _tabNotifier.value);
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

    return userAsync.when(
      loading: () => const Scaffold(
        backgroundColor: Color(0xFFF8F9FA),
        body: Center(
            child: CircularProgressIndicator(color: Color(0xFFE94560)))),
      error: (e, _) => CustomerLoginScreen(onLoginSuccess: () {}),
      data: (user) {
        if (user == null) {
          return CustomerLoginScreen(onLoginSuccess: () {});
        }
        return Scaffold(
          backgroundColor: const Color(0xFFF8F9FA),
          body: SafeArea(
            child: Column(children: [
              _buildTopBar(user),
              Expanded(child: _buildBody()),
            ]),
          ),
          bottomNavigationBar: _buildBottomNav(),
        );
      },
    );
  }

  // ── Safe helpers ─────────────────────────────────────────────
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
    return 'Pelanggan';
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
    const titles = ['Beranda', 'Booking Saya', 'Cek Pesanan', 'Chat AI'];
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
      child: Row(children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: const Color(0xFFE94560),
          backgroundImage:
              avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
          onBackgroundImageError:
              avatarUrl.isNotEmpty ? (_, __) {} : null,
          child: avatarUrl.isEmpty
              ? Text(initial,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700))
              : null,
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
                  'Halo, $firstName 👋',
                  style: const TextStyle(
                      color: Colors.white60, fontSize: 11),
                ),
              ]),
        ),
        IconButton(
          icon: const Icon(Icons.logout_rounded,
              color: Colors.white54, size: 20),
          onPressed: _confirmLogout,
        ),
      ]),
    );
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('Keluar?',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700)),
        content: const Text('Kamu akan keluar dari akun.',
            style: TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal',
                style: TextStyle(
                    fontFamily: 'Poppins', color: Colors.grey))),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await Supabase.instance.client.auth.signOut();
            },
            child: const Text('Keluar',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Color(0xFFE94560),
                    fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  // ── BODY ─────────────────────────────────────────────────────
  Widget _buildBody() {
    return Stack(children: [
      Visibility(
        visible: _tab == 0,
        maintainState: true,
        child: _HomeTab(onSwitchTab: switchTab)),
      Visibility(
        visible: _tab == 1,
        maintainState: true,
        child: const CustomerMyBookingsScreen()),
      // FIX: Ganti _OrderTrackerBody lama → CustomerOrderTrackerScreen
      // tanpa Scaffold (embedded mode)
      Visibility(
        visible: _tab == 2,
        maintainState: true,
        child: const _EmbeddedOrderTracker()),
      Visibility(
        visible: _tab == 3,
        maintainState: true,
        child: const CustomerChatbotScreen()),
    ]);
  }

  // ── BOTTOM NAV ───────────────────────────────────────────────
  Widget _buildBottomNav() {
    const items = [
      (Icons.home_outlined, Icons.home_rounded, 'Beranda'),
      (Icons.calendar_today_outlined, Icons.calendar_today_rounded,
          'Booking'),
      (Icons.receipt_long_outlined, Icons.receipt_long_rounded,
          'Pesanan'),
      (Icons.smart_toy_outlined, Icons.smart_toy_rounded, 'Chat AI'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, -2))
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: List.generate(items.length, (i) {
              final (outline, filled, label) = items[i];
              final active = _tab == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _tab = i),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    margin:
                        const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: active
                          ? const Color(0xFFE94560)
                              .withValues(alpha: 0.08)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10)),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(active ? filled : outline,
                              color: active
                                  ? const Color(0xFFE94560)
                                  : const Color(0xFF9CA3AF),
                              size: 22),
                          const SizedBox(height: 3),
                          Text(label,
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 10,
                                  fontWeight: active
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  color: active
                                      ? const Color(0xFFE94560)
                                      : const Color(0xFF9CA3AF))),
                        ]),
                  )));
            }),
          ))));
  }
}

// ════════════════════════════════════════════
// EMBEDDED ORDER TRACKER
// Wrapper tipis supaya CustomerOrderTrackerScreen bisa
// dipakai tanpa Scaffold (embedded di tab)
// ════════════════════════════════════════════
class _EmbeddedOrderTracker extends StatefulWidget {
  const _EmbeddedOrderTracker();

  @override
  State<_EmbeddedOrderTracker> createState() =>
      _EmbeddedOrderTrackerState();
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
          callback: (payload) {
            if (mounted && payload.newRecord.isNotEmpty) {
              setState(() {
                _order = {..._order!, ...payload.newRecord};
              });
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
      final orders = await Supabase.instance.client
          .from('orders')
          .select()
          .ilike('order_number', '%$code%')
          .limit(1);

      if ((orders as List).isEmpty) {
        if (mounted) {
          setState(() {
            _error =
                'Pesanan tidak ditemukan. Periksa kembali nomor pesananmu.';
            _loading = false;
          });
        }
        return;
      }

      final order = Map<String, dynamic>.from(orders.first);
      final items = await Supabase.instance.client
          .from('order_items')
          .select('*, menu_items(name)')
          .eq('order_id', order['id'])
          .order('created_at');

      if (mounted) {
        setState(() {
          _order = order;
          _items = (items as List).cast();
          _loading = false;
        });
        _subscribeRealtime(order['id'] as String);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Terjadi kesalahan. Coba lagi.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      // Header realtime indicator
      if (_order != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Container(
              width: 8, height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFF1D9E75), shape: BoxShape.circle)),
            const SizedBox(width: 4),
            const Text('Live tracking aktif',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: Color(0xFF1D9E75))),
          ]),
        ),

      // Search box
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8)]),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Masukkan Nomor Pesanan',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
              const SizedBox(height: 4),
              const Text(
                  'Nomor pesanan ada di struk atau layar konfirmasi.',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: Colors.grey)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    textCapitalization: TextCapitalization.characters,
                    onSubmitted: (_) => _search(),
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5),
                    decoration: InputDecoration(
                      hintText: 'Contoh: WEB-20260327-1234',
                      hintStyle: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.normal,
                          color: Colors.grey,
                          letterSpacing: 0),
                      filled: true,
                      fillColor: const Color(0xFFF3F4F6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none)),
                  )),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _loading ? null : _search,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE94560),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(52, 52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                  child: _loading
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.search_rounded)),
              ]),
            ])),

      // Error
      if (_error != null) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: Colors.red.withValues(alpha: 0.2))),
          child: Row(children: [
            const Icon(Icons.error_outline,
                color: Colors.red, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(_error!,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: Colors.red))),
          ])),
      ],

      // Order card
      if (_order != null) ...[
        const SizedBox(height: 16),
        _OrderStatusCard(order: _order!, items: _items),
      ],

      // Empty state
      if (_order == null && _error == null && !_loading) ...[
        const SizedBox(height: 40),
        const Center(
          child: Column(children: [
            Icon(Icons.receipt_long_outlined,
                size: 56, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              'Masukkan nomor pesanan di atas\nuntuk melihat status.',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.grey,
                  height: 1.6),
              textAlign: TextAlign.center),
          ])),
      ],
    ]);
  }
}

// ════════════════════════════════════════════
// HOME TAB
// ════════════════════════════════════════════
class _HomeTab extends ConsumerWidget {
  final void Function(int) onSwitchTab;
  const _HomeTab({required this.onSwitchTab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(customerUserProvider);
    final user = userAsync.valueOrNull;
    final branchesAsync = ref.watch(_customerBranchesProvider);
    final displayName = _safeName(user);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Welcome banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A1A2E), Color(0xFF0F3460)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(16)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Selamat datang,',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(displayName,
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    const Text('Apa yang ingin kamu lakukan hari ini?',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white60,
                            fontSize: 12)),
                  ])),
            const SizedBox(height: 20),

            // ── Quick Actions
            const Text('Aksi Cepat',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Color(0xFF1A1A2E))),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: _ActionCard(
                  icon: Icons.calendar_today_rounded,
                  label: 'Booking Meja',
                  subtitle: 'Reservasi sekarang',
                  color: const Color(0xFF0F3460),
                  onTap: () => onSwitchTab(1))),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionCard(
                  icon: Icons.receipt_long_rounded,
                  label: 'Cek Pesanan',
                  subtitle: 'Status & riwayat',
                  color: const Color(0xFF1D9E75),
                  onTap: () => onSwitchTab(2))),
            ]),
            const SizedBox(height: 24),

            // ── Cabang Kami
            const Text('Cabang Kami',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Color(0xFF1A1A2E))),
            const SizedBox(height: 4),
            const Text('Pilih cabang untuk melihat menu & memesan',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: Color(0xFF9CA3AF))),
            const SizedBox(height: 12),

            branchesAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(
                      color: Color(0xFFE94560)))),
              error: (e, _) => Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.red.withValues(alpha: 0.2))),
                child: const Row(children: [
                  Icon(Icons.error_outline,
                      color: Colors.red, size: 16),
                  SizedBox(width: 8),
                  Text('Gagal memuat cabang',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          color: Colors.red)),
                ])),
              data: (branches) {
                if (branches.isEmpty) {
                  return const Center(
                    child: Text('Belum ada cabang aktif',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.grey)));
                }
                return Column(
                  children: branches
                      .map((b) => _BranchCard(branch: b))
                      .toList());
              },
            ),
            const SizedBox(height: 8),
          ]),
    );
  }

  static String _safeName(User? user) {
    if (user == null) return 'Pelanggan';
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
    return 'Pelanggan';
  }
}

// ── Branch Card ───────────────────────────────────────────────────
class _BranchCard extends StatelessWidget {
  final Map<String, dynamic> branch;
  const _BranchCard({required this.branch});

  @override
  Widget build(BuildContext context) {
    final name = branch['name'] as String? ?? 'Cabang';
    final address = branch['address'] as String? ?? '';
    final open = (branch['opening_time'] as String?)?.substring(0, 5) ?? '10:00';
    final close = (branch['closing_time'] as String?)?.substring(0, 5) ?? '22:00';

    return GestureDetector(
      onTap: () => context.push('/customer/menu/${branch['id']}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2))]),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A1A2E), Color(0xFF0F3460)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.store_rounded,
                color: Colors.white, size: 22)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Color(0xFF1A1A2E))),
                  if (address.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(address,
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            color: Color(0xFF9CA3AF)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.access_time_outlined,
                        size: 12, color: Color(0xFF6B7280)),
                    const SizedBox(width: 4),
                    Text('$open – $close WIB',
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            color: Color(0xFF6B7280))),
                  ]),
                ])),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFE94560),
              borderRadius: BorderRadius.circular(20)),
            child: const Text('Menu',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white))),
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
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
          color: color.withValues(alpha: 0.3),
          blurRadius: 10,
          offset: const Offset(0, 4))]),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 10),
            Text(label,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 10)),
          ])));
}

// ════════════════════════════════════════════
// ORDER STATUS CARD (dipakai di _EmbeddedOrderTracker)
// Copy dari CustomerOrderTrackerScreen supaya embedded
// ════════════════════════════════════════════
class _OrderStatusCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final List<Map<String, dynamic>> items;
  const _OrderStatusCard(
      {required this.order, required this.items});

  static const _statusLabels = {
    'new': '🆕 Pesanan Baru',
    'preparing': '👨‍🍳 Sedang Dimasak',
    'ready': '✅ Siap Disajikan',
    'served': '🍽️ Sudah Disajikan',
    'paid': '💳 Lunas',
    'cancelled': '❌ Dibatalkan',
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
    'new': '⏳ Pesananmu sedang menunggu konfirmasi dapur.',
    'preparing': '🔥 Dapur sedang memasak pesananmu, sebentar lagi!',
    'ready': '🎉 Pesananmu siap! Pelayan akan segera mengantarkan.',
    'served': '😊 Pesananmu sudah disajikan. Selamat menikmati!',
    'paid': '✅ Pembayaran selesai. Terima kasih sudah berkunjung!',
    'cancelled': '❌ Pesanan ini dibatalkan.',
  };

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String? ?? 'new';
    final statusLabel = _statusLabels[status] ?? status;
    final statusColor = _statusColors[status] ?? Colors.grey;
    final statusMsg = _statusMessages[status] ?? '';
    final total = (order['total_amount'] as num?)?.toDouble() ?? 0;
    final customerName = order['customer_name'] as String?;
    final notes = order['notes'] as String?;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 8)]),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(order['order_number'] as String? ?? '',
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w800,
                              fontSize: 16)),
                      if (customerName != null)
                        Text('Atas nama: $customerName',
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                color: Colors.grey)),
                    ])),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20)),
                child: Text(statusLabel,
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: statusColor))),
            ]),
            if (statusMsg.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10)),
                child: Text(statusMsg,
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: statusColor,
                        height: 1.4))),
            ],
            const Divider(height: 20),
            _StatusProgress(status: status),
            const SizedBox(height: 16),
            const Text('Item Pesanan',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
            const SizedBox(height: 8),
            ...items.map((item) {
              final name = (item['menu_items'] as Map?)?['name']
                      as String? ?? '-';
              final qty = item['quantity'] as int? ?? 1;
              final sub =
                  (item['subtotal'] as num?)?.toDouble() ?? 0;
              final special = item['special_requests'] as String?;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text('${qty}x ',
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                color: Colors.grey,
                                fontSize: 12)),
                        Expanded(
                          child: Text(name,
                              style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12))),
                        Text('Rp ${_fmt(sub)}',
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                fontWeight: FontWeight.w500)),
                      ]),
                      if (special != null && special.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(
                              left: 24, top: 2),
                          child: Text('⚡ $special',
                              style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11,
                                  color: Color(0xFFD97706)))),
                    ]));
            }),
            if (notes != null && notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(8)),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.notes,
                          size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(notes,
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11,
                                color: Colors.grey))),
                    ])),
            ],
            const Divider(height: 16),
            Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                  Text('Rp ${_fmt(total)}',
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: Color(0xFFE94560))),
                ]),
            if (status != 'paid' && status != 'cancelled') ...[
              const SizedBox(height: 10),
              const Text(
                  '💡 Pembayaran di kasir saat pesanan siap.',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: Colors.grey)),
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
  const _StatusProgress({required this.status});

  @override
  Widget build(BuildContext context) {
    const steps = ['new', 'preparing', 'ready', 'served', 'paid'];
    const labels = ['Baru', 'Masak', 'Siap', 'Saji', 'Lunas'];
    final currentIdx = steps.indexOf(status);
    final isCancelled = status == 'cancelled';

    if (isCancelled) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cancel_outlined,
                  color: Color(0xFFE94560), size: 18),
              SizedBox(width: 6),
              Text('Pesanan dibatalkan',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: Color(0xFFE94560),
                      fontWeight: FontWeight.w600)),
            ]));
    }

    return Row(
      children: steps.asMap().entries.map((e) {
        final idx = e.key;
        final isActive = idx <= currentIdx;
        final isCurrent = idx == currentIdx;
        final isLast = idx == steps.length - 1;

        return Expanded(
          child: Row(children: [
            Expanded(
              child: Column(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: isCurrent ? 24 : 20,
                  height: isCurrent ? 24 : 20,
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFFE94560)
                        : const Color(0xFFE5E7EB),
                    shape: BoxShape.circle,
                    boxShadow: isCurrent
                        ? [BoxShadow(
                            color: const Color(0xFFE94560)
                                .withValues(alpha: 0.4),
                            blurRadius: 8)]
                        : []),
                  child: isActive
                      ? const Icon(Icons.check,
                          color: Colors.white, size: 12)
                      : null),
                const SizedBox(height: 4),
                Text(labels[idx],
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 9,
                        fontWeight: isCurrent
                            ? FontWeight.w700
                            : FontWeight.normal,
                        color: isActive
                            ? const Color(0xFFE94560)
                            : Colors.grey),
                    textAlign: TextAlign.center),
              ])),
            if (!isLast)
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 2,
                  color: idx < currentIdx
                      ? const Color(0xFFE94560)
                      : const Color(0xFFE5E7EB))),
          ]));
      }).toList());
  }
}