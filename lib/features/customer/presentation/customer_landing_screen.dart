// lib/features/customer/presentation/customer_landing_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'customer_login_screen.dart';
import 'customer_my_bookings_screen.dart';
import 'customer_chatbot_screen.dart';
import '../providers/customer_auth_provider.dart';

class CustomerLandingScreen extends ConsumerStatefulWidget {
  final int initialTab;
  const CustomerLandingScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<CustomerLandingScreen> createState() =>
      _CustomerLandingScreenState();
}

class _CustomerLandingScreenState extends ConsumerState<CustomerLandingScreen> {
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

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(customerUserProvider);

    return userAsync.when(
      loading: () => const Scaffold(
        backgroundColor: Color(0xFFF8F9FA),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFE94560)))),
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

  // ── safe helper: ambil display name tanpa crash ──
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

  // ── TOP BAR ──
  Widget _buildTopBar(User user) {
    const titles = ['Beranda', 'Booking Saya', 'Cek Pesanan', 'Chat AI'];
    final displayName = _displayName(user);
    final firstName = displayName.split(' ').first;
    // Safe: pastikan firstName tidak kosong sebelum ambil [0]
    final initial = firstName.isNotEmpty ? firstName[0].toUpperCase() : 'P';
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
          backgroundImage: avatarUrl.isNotEmpty
              ? NetworkImage(avatarUrl)
              : null,
          onBackgroundImageError: avatarUrl.isNotEmpty
              ? (_, __) {} // silent fail jika gambar gagal load
              : null,
          child: avatarUrl.isEmpty
              ? Text(initial,
                  style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700))
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              titles[_tab.clamp(0, titles.length - 1)],
              style: const TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            Text(
              'Halo, $firstName 👋',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ]),
        ),
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: Colors.white54, size: 20),
          onPressed: _confirmLogout,
        ),
      ]),
    );
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Keluar?',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: const Text('Kamu akan keluar dari akun.',
          style: TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal',
              style: TextStyle(fontFamily: 'Poppins', color: Colors.grey))),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await Supabase.instance.client.auth.signOut();
            },
            child: const Text('Keluar',
              style: TextStyle(
                fontFamily: 'Poppins', color: Color(0xFFE94560),
                fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  // ── BODY ──
  Widget _buildBody() {
    return Stack(children: [
      Visibility(
        visible: _tab == 0,
        maintainState: true,
        child: const _HomeTab()),
      Visibility(
        visible: _tab == 1,
        maintainState: true,
        child: const CustomerMyBookingsScreen()),
      Visibility(
        visible: _tab == 2,
        maintainState: true,
        child: const _OrderTrackerBody()),
      Visibility(
        visible: _tab == 3,
        maintainState: true,
        child: const CustomerChatbotScreen()),
    ]);
  }

  // ── BOTTOM NAV ──
  Widget _buildBottomNav() {
    const items = [
      (Icons.home_outlined,           Icons.home_rounded,            'Beranda'),
      (Icons.calendar_today_outlined, Icons.calendar_today_rounded,  'Booking'),
      (Icons.receipt_long_outlined,   Icons.receipt_long_rounded,    'Pesanan'),
      (Icons.smart_toy_outlined,      Icons.smart_toy_rounded,       'Chat AI'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 10, offset: const Offset(0, -2))]),
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
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: active
                        ? const Color(0xFFE94560).withValues(alpha: 0.08)
                        : Colors.transparent,
                      borderRadius: BorderRadius.circular(10)),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                        active ? filled : outline,
                        color: active
                          ? const Color(0xFFE94560)
                          : const Color(0xFF9CA3AF),
                        size: 22),
                      const SizedBox(height: 3),
                      Text(label, style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                        color: active
                          ? const Color(0xFFE94560)
                          : const Color(0xFF9CA3AF))),
                    ]),
                  )));
            }),
          ))));
  }
}

// ══════════════════════════════════════════════
// HOME TAB
// ══════════════════════════════════════════════
class _HomeTab extends ConsumerWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(customerUserProvider);
    final user = userAsync.valueOrNull;

    final displayName = _safeName(user);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Welcome banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A1A2E), Color(0xFF0F3460)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Selamat datang,', style: TextStyle(
              fontFamily: 'Poppins', color: Colors.white.withValues(alpha: 0.7),
              fontSize: 13)),
            const SizedBox(height: 4),
            Text(displayName, style: const TextStyle(
              fontFamily: 'Poppins', color: Colors.white,
              fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('Apa yang ingin kamu lakukan hari ini?',
              style: TextStyle(fontFamily: 'Poppins',
                color: Colors.white60, fontSize: 12)),
          ])),
        const SizedBox(height: 20),

        // Quick actions
        const Text('Aksi Cepat', style: TextStyle(
          fontFamily: 'Poppins', fontWeight: FontWeight.w700,
          fontSize: 15, color: Color(0xFF1A1A2E))),
        const SizedBox(height: 12),
        _QuickActions(
          onBooking: () {
            // Pakai tabNotifier dari ancestor — tidak perlu akses setState langsung
            final notifier = context
                .findAncestorStateOfType<_CustomerLandingScreenState>()
                ?._tabNotifier;
            notifier?.value = 1;
          },
          onTrack: () {
            final notifier = context
                .findAncestorStateOfType<_CustomerLandingScreenState>()
                ?._tabNotifier;
            notifier?.value = 2;
          },
        ),
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

class _QuickActions extends StatelessWidget {
  final VoidCallback onBooking;
  final VoidCallback onTrack;
  const _QuickActions({required this.onBooking, required this.onTrack});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: _ActionCard(
        icon: Icons.calendar_today_rounded,
        label: 'Booking Meja',
        subtitle: 'Reservasi sekarang',
        color: const Color(0xFF0F3460),
        onTap: onBooking)),
      const SizedBox(width: 12),
      Expanded(child: _ActionCard(
        icon: Icons.receipt_long_rounded,
        label: 'Cek Pesanan',
        subtitle: 'Status & riwayat',
        color: const Color(0xFF1D9E75),
        onTap: onTrack)),
    ]);
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const _ActionCard({required this.icon, required this.label,
    required this.subtitle, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color, borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
          color: color.withValues(alpha: 0.3),
          blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: Colors.white, size: 22),
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(
          fontFamily: 'Poppins', color: Colors.white,
          fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 2),
        Text(subtitle, style: TextStyle(
          fontFamily: 'Poppins',
          color: Colors.white.withValues(alpha: 0.7), fontSize: 10)),
      ])));
}

// ══════════════════════════════════════════════
// ORDER TRACKER TAB (tanpa Scaffold)
// ══════════════════════════════════════════════
class _OrderTrackerBody extends StatefulWidget {
  const _OrderTrackerBody();

  @override
  State<_OrderTrackerBody> createState() => _OrderTrackerBodyState();
}

class _OrderTrackerBodyState extends State<_OrderTrackerBody> {
  final _ctrl = TextEditingController();
  Map<String, dynamic>? _order;
  List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final code = _ctrl.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() { _loading = true; _error = null; _order = null; _items = []; });
    try {
      final orders = await Supabase.instance.client
          .from('orders').select()
          .ilike('order_number', '%$code%').limit(1);
      if ((orders as List).isEmpty) {
        if (mounted) setState(() { _error = 'Pesanan tidak ditemukan'; _loading = false; });
        return;
      }
      final order = orders.first;
      final items = await Supabase.instance.client
          .from('order_items').select('*, menu_items(name)')
          .eq('order_id', order['id']).order('created_at');
      if (mounted) {
        setState(() {
          _order = order;
          _items = List<Map<String, dynamic>>.from(items as List);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'Error: $e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Masukkan Nomor Pesanan', style: TextStyle(
            fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(
              controller: _ctrl,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(fontFamily: 'Poppins',
                fontWeight: FontWeight.w700, letterSpacing: 1.5),
              decoration: InputDecoration(
                hintText: 'Contoh: WEB-1234567',
                hintStyle: const TextStyle(fontFamily: 'Poppins',
                  fontWeight: FontWeight.normal,
                  color: Colors.grey, letterSpacing: 0),
                filled: true, fillColor: const Color(0xFFF3F4F6),
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
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.search_rounded)),
          ]),
        ])),
      if (_error != null) ...[
        const SizedBox(height: 20),
        Center(child: Text(_error!, style: const TextStyle(
          fontFamily: 'Poppins', color: Colors.red))),
      ],
      if (_order != null) ...[
        const SizedBox(height: 16),
        _OrderCard(order: _order!, items: _items),
      ],
      if (_order == null && _error == null) ...[
        const SizedBox(height: 40),
        const Center(child: Column(children: [
          Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey),
          SizedBox(height: 12),
          Text('Masukkan nomor pesanan\nuntuk melihat status.',
            style: TextStyle(fontFamily: 'Poppins', color: Colors.grey, height: 1.6),
            textAlign: TextAlign.center),
        ])),
      ],
    ]);
  }
}

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final List<Map<String, dynamic>> items;
  const _OrderCard({required this.order, required this.items});

  static const _statusLabels = {
    'new': '🆕 Pesanan Baru', 'preparing': '👨‍🍳 Sedang Dimasak',
    'ready': '✅ Siap Disajikan', 'served': '🍽️ Sudah Disajikan',
    'paid': '💳 Lunas', 'cancelled': '❌ Dibatalkan',
  };
  static const _statusColors = {
    'new': Color(0xFF6B7280), 'preparing': Color(0xFFD97706),
    'ready': Color(0xFF1D9E75), 'served': Color(0xFF0F3460),
    'paid': Color(0xFF1D9E75), 'cancelled': Color(0xFFE94560),
  };

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String? ?? 'new';
    final statusLabel = _statusLabels[status] ?? status;
    final statusColor = _statusColors[status] ?? Colors.grey;
    final total = (order['total_amount'] as num?)?.toDouble() ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(order['order_number'] as String? ?? '',
            style: const TextStyle(fontFamily: 'Poppins',
              fontWeight: FontWeight.w800, fontSize: 16))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20)),
            child: Text(statusLabel, style: TextStyle(
              fontFamily: 'Poppins', fontSize: 11,
              fontWeight: FontWeight.w600, color: statusColor))),
        ]),
        const Divider(height: 20),
        _StatusProgress(status: status),
        const SizedBox(height: 16),
        const Text('Item Pesanan', style: TextStyle(
          fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 8),
        ...items.map((item) {
          final name = (item['menu_items'] as Map?)?['name'] as String? ?? '-';
          final qty = item['quantity'] as int? ?? 1;
          final sub = (item['subtotal'] as num?)?.toDouble() ?? 0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Text('${qty}x ', style: const TextStyle(
                fontFamily: 'Poppins', color: Colors.grey, fontSize: 12)),
              Expanded(child: Text(name, style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 12))),
              Text('Rp ${_fmt(sub)}', style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w500)),
            ]));
        }),
        const Divider(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Total', style: TextStyle(
            fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14)),
          Text('Rp ${_fmt(total)}', style: const TextStyle(
            fontFamily: 'Poppins', fontWeight: FontWeight.w800,
            fontSize: 15, color: Color(0xFFE94560))),
        ]),
        if (status != 'paid' && status != 'cancelled') ...[
          const SizedBox(height: 10),
          const Text('💡 Pembayaran di kasir saat pesanan siap.',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.grey)),
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

class _StatusProgress extends StatelessWidget {
  final String status;
  const _StatusProgress({required this.status});

  @override
  Widget build(BuildContext context) {
    const steps = ['new', 'preparing', 'ready', 'served', 'paid'];
    const labels = ['Baru', 'Masak', 'Siap', 'Saji', 'Lunas'];
    final currentIdx = steps.indexOf(status);

    return Row(
      children: List.generate(steps.length, (idx) {
        final isActive = idx <= currentIdx;
        final isLast = idx == steps.length - 1;
        return Expanded(child: Row(children: [
          Expanded(child: Column(children: [
            Container(
              width: 20, height: 20,
              decoration: BoxDecoration(
                color: isActive
                  ? const Color(0xFFE94560)
                  : const Color(0xFFE5E7EB),
                shape: BoxShape.circle),
              child: isActive
                ? const Icon(Icons.check, color: Colors.white, size: 12)
                : null),
            const SizedBox(height: 4),
            Text(labels[idx], style: TextStyle(
              fontFamily: 'Poppins', fontSize: 9,
              color: isActive ? const Color(0xFFE94560) : Colors.grey),
              textAlign: TextAlign.center),
          ])),
          if (!isLast)
            Expanded(child: Container(
              height: 2,
              color: idx < currentIdx
                ? const Color(0xFFE94560)
                : const Color(0xFFE5E7EB))),
        ]));
      }),
    );
  }
}