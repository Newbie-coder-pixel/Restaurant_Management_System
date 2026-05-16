import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../core/models/staff_role.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/widgets/app_drawer.dart';

// Model sederhana untuk branch
class _Branch {
  final String id;
  final String name;
  const _Branch({required this.id, required this.name});
}

class RestaurantClosureScreen extends ConsumerStatefulWidget {
  const RestaurantClosureScreen({super.key});

  @override
  ConsumerState<RestaurantClosureScreen> createState() =>
      _RestaurantClosureScreenState();
}

class _RestaurantClosureScreenState
    extends ConsumerState<RestaurantClosureScreen> {
  // Branch aktif yang sedang ditampilkan
  String? _selectedBranchId;
  String _selectedBranchName = '';

  // Daftar cabang (hanya diisi untuk Super Admin)
  List<_Branch> _branches = [];
  bool _isSuperAdmin = false;

  bool _isLoading = true;
  bool _isSaving = false;

  DateTime _focusedDay = DateTime.now();
  Map<String, Map<String, dynamic>> _closures = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final staff = ref.read(currentStaffProvider);
    if (staff != null && _selectedBranchId == null) {
      _isSuperAdmin = staff.role == StaffRole.superadmin;

      if (_isSuperAdmin) {
        // Super Admin: load semua branch dulu, lalu pilih pertama
        _loadBranches();
      } else {
        // Staff biasa: langsung pakai branch sendiri
        _selectedBranchId = staff.branchId;
        _selectedBranchName = 'Cabang Anda';
        _loadClosures();
      }
    }
  }

  /// Load semua branch dari Supabase (hanya Super Admin)
  Future<void> _loadBranches() async {
    setState(() => _isLoading = true);
    try {
      final res = await Supabase.instance.client
          .from('branches')
          .select('id, name')
          .eq('is_active', true)
          .order('name');

      final list = (res as List)
          .cast<Map<String, dynamic>>()
          .map((e) => _Branch(id: e['id'], name: e['name']))
          .toList();

      if (mounted) {
        setState(() {
          _branches = list;
          if (list.isNotEmpty) {
            _selectedBranchId = list.first.id;
            _selectedBranchName = list.first.name;
          }
        });
        await _loadClosures();
      }
    } catch (e) {
      debugPrint('error load branches: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadClosures() async {
    if (_selectedBranchId == null) return;
    setState(() => _isLoading = true);
    try {
      final res = await Supabase.instance.client
          .from('restaurant_closures')
          .select()
          .eq('branch_id', _selectedBranchId!)
          .order('closure_date');

      final map = <String, Map<String, dynamic>>{};
      for (final row in (res as List).cast<Map<String, dynamic>>()) {
        final date = row['closure_date'] as String;
        map[date] = row;
      }

      if (mounted) {
        setState(() {
          _closures = map;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('error load closures: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Dipanggil saat Super Admin ganti branch dari dropdown
  void _onBranchChanged(_Branch branch) {
    if (_selectedBranchId == branch.id) return;
    setState(() {
      _selectedBranchId = branch.id;
      _selectedBranchName = branch.name;
      _closures = {};
      _focusedDay = DateTime.now();
    });
    _loadClosures();
  }

  Future<void> _toggleClosure(DateTime day) async {
    if (_selectedBranchId == null) return;
    final dateStr = _fmtDate(day);

    final today = DateTime.now();
    final todayStr = _fmtDate(today);
    if (dateStr.compareTo(todayStr) < 0) {
      _showSnack('Tidak bisa mengubah tanggal yang sudah lewat', Colors.orange);
      return;
    }

    if (_closures.containsKey(dateStr)) {
      await _removeClosure(dateStr);
    } else {
      await _addClosure(day, dateStr);
    }
  }

  Future<void> _addClosure(DateTime day, String dateStr) async {
    final bookings = await Supabase.instance.client
        .from('bookings')
        .select('id')
        .eq('branch_id', _selectedBranchId!)
        .eq('booking_date', dateStr)
        .inFilter('status', ['pending', 'confirmed', 'seated']).limit(1);

    if ((bookings as List).isNotEmpty) {
      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Ada Booking Aktif',
              style: TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          content: Text(
            'Tanggal ${_fmtDisplayDate(day)} masih ada booking aktif.\n\n'
            'Apakah tetap ingin menutup restoran di tanggal ini?',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:
                  const Text('Batal', style: TextStyle(fontFamily: 'Poppins')),
            ),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Tetap Tutup',
                  style:
                      TextStyle(fontFamily: 'Poppins', color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    if (!mounted) return;
    final reason = await _showReasonDialog(day);
    if (reason == null) return;

    setState(() => _isSaving = true);
    try {
      final staff = ref.read(currentStaffProvider);
      await Supabase.instance.client.from('restaurant_closures').insert({
        'branch_id': _selectedBranchId,
        'closure_date': dateStr,
        'reason': reason.isEmpty ? null : reason,
        'created_by': staff?.id,
      });
      await _loadClosures();
      _showSnack('✅ ${_fmtDisplayDate(day)} ditandai sebagai hari tutup',
          const Color(0xFF4CAF50));
    } catch (e) {
      _showSnack('Gagal simpan: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _removeClosure(String dateStr) async {
    setState(() => _isSaving = true);
    try {
      await Supabase.instance.client
          .from('restaurant_closures')
          .delete()
          .eq('branch_id', _selectedBranchId!)
          .eq('closure_date', dateStr);
      await _loadClosures();
      _showSnack(
          '✅ Tanggal tutup dihapus — restoran kembali buka', AppColors.available);
    } catch (e) {
      _showSnack('Gagal hapus: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<String?> _showReasonDialog(DateTime day) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.store_rounded, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Tutup ${_fmtDisplayDate(day)}',
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 16)),
          ),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Alasan tutup (opsional):',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13)),
          const SizedBox(height: 10),
          TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Contoh: Hari Raya, Renovasi, Private Event...',
              hintStyle:
                  const TextStyle(fontFamily: 'Poppins', fontSize: 12),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child:
                const Text('Batal', style: TextStyle(fontFamily: 'Poppins')),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Simpan',
                style:
                    TextStyle(fontFamily: 'Poppins', color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  String _fmtDisplayDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  List<MapEntry<String, Map<String, dynamic>>> get _upcomingClosures {
    final todayStr = _fmtDate(DateTime.now());
    return _closures.entries
        .where((e) => e.key.compareTo(todayStr) >= 0)
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
  }

  // ─────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Hari Tutup Restoran'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadClosures,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadClosures,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Branch selector (Super Admin only) ──
                  if (_isSuperAdmin) ...[
                    _buildBranchSelector(),
                    const SizedBox(height: 12),
                  ],
                  _buildInfoBanner(),
                  const SizedBox(height: 16),
                  _buildCalendar(),
                  const SizedBox(height: 20),
                  _buildUpcomingList(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // BRANCH SELECTOR (Super Admin only)
  // ─────────────────────────────────────────────────────────────

  Widget _buildBranchSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.store_mall_directory_rounded,
                color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pilih Cabang',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedBranchId,
                    isExpanded: true,
                    isDense: true,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    items: _branches
                        .map((b) => DropdownMenuItem(
                              value: b.id,
                              child: Text(b.name,
                                  style: const TextStyle(
                                      fontFamily: 'Poppins', fontSize: 14)),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val == null) return;
                      final branch =
                          _branches.firstWhere((b) => b.id == val);
                      _onBranchChanged(branch);
                    },
                  ),
                ),
              ],
            ),
          ),
          // Badge jumlah hari tutup cabang ini
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _upcomingClosures.isEmpty
                  ? AppColors.available.withValues(alpha: 0.15)
                  : AppColors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_upcomingClosures.length} tutup',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _upcomingClosures.isEmpty
                    ? AppColors.available
                    : AppColors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // INFO BANNER
  // ─────────────────────────────────────────────────────────────

  Widget _buildInfoBanner() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.touch_app_rounded,
                color: AppColors.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _isSuperAdmin
                    ? 'Pilih cabang di atas, lalu ketuk tanggal untuk menandai/membatalkan hari tutup. '
                        'Perubahan hanya berlaku untuk cabang yang dipilih.'
                    : 'Ketuk tanggal di kalender untuk menandai/membatalkan hari tutup restoran. '
                        'Booking baru tidak bisa dibuat di tanggal yang ditandai tutup.',
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: AppColors.primary),
              ),
            ),
          ],
        ),
      );

  // ─────────────────────────────────────────────────────────────
  // CALENDAR
  // ─────────────────────────────────────────────────────────────

  Widget _buildCalendar() => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 2)),
          ],
        ),
        child: TableCalendar(
          firstDay: DateTime.now().subtract(const Duration(days: 1)),
          lastDay: DateTime.now().add(const Duration(days: 365)),
          focusedDay: _focusedDay,
          onDaySelected: (selected, focused) {
            setState(() => _focusedDay = focused);
            _toggleClosure(selected);
          },
          onPageChanged: (focused) =>
              setState(() => _focusedDay = focused),
          calendarBuilders: CalendarBuilders(
            defaultBuilder: (ctx, day, focusedDay) {
              final isWeekend = day.weekday == DateTime.saturday ||
                  day.weekday == DateTime.sunday;
              return _dayCell(day, isWeekend: isWeekend);
            },
            todayBuilder: (ctx, day, focusedDay) =>
                _dayCell(day, isToday: true),
            outsideBuilder: (ctx, day, focusedDay) =>
                _dayCell(day, isOutside: true),
          ),
          calendarStyle: const CalendarStyle(
            outsideDaysVisible: true,
          ),
          headerStyle: const HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
            titleTextStyle: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 16),
          ),
        ),
      );

  Widget _dayCell(
    DateTime day, {
    bool isWeekend = false,
    bool isToday = false,
    bool isOutside = false,
  }) {
    final dateStr = _fmtDate(day);
    final isClosed = _closures.containsKey(dateStr);

    Color bgColor = Colors.transparent;
    Color textColor = isOutside
        ? Colors.black26
        : isWeekend
            ? AppColors.accent.withValues(alpha: 0.8)
            : AppColors.textPrimary;
    FontWeight fontWeight = FontWeight.normal;

    if (isClosed) {
      bgColor = AppColors.accent.withValues(alpha: 0.15);
      textColor = AppColors.accent;
      fontWeight = FontWeight.w700;
    }
    if (isToday && !isClosed) {
      bgColor = AppColors.primary.withValues(alpha: 0.12);
      textColor = AppColors.primary;
      fontWeight = FontWeight.w700;
    }

    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: isClosed
            ? Border.all(color: AppColors.accent.withValues(alpha: 0.5))
            : isToday
                ? Border.all(
                    color: AppColors.primary.withValues(alpha: 0.4))
                : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('${day.day}',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: fontWeight,
                  color: textColor)),
          if (isClosed)
            Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // UPCOMING LIST
  // ─────────────────────────────────────────────────────────────

  Widget _buildUpcomingList() {
    final upcoming = _upcomingClosures;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.event_busy_rounded,
            color: AppColors.accent, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Jadwal Tutup${_isSuperAdmin ? ' — $_selectedBranchName' : ''} (${upcoming.length})',
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 15),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      if (upcoming.isEmpty)
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: const Center(
            child: Column(children: [
              Icon(Icons.store_rounded, size: 40, color: AppColors.textHint),
              SizedBox(height: 8),
              Text('Belum ada jadwal tutup',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      color: AppColors.textSecondary)),
            ]),
          ),
        )
      else
        ...upcoming.map((e) {
          final dateStr = e.key;
          final row = e.value;
          final reason = row['reason'] as String?;
          final parts = dateStr.split('-');
          final dt = DateTime(int.parse(parts[0]), int.parse(parts[1]),
              int.parse(parts[2]));
          final dayName = _dayName(dt.weekday);
          final isToday = dateStr == _fmtDate(DateTime.now());

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2)),
              ],
            ),
            child: ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.event_busy_rounded,
                    color: AppColors.accent, size: 22),
              ),
              title: Row(children: [
                Text('$dayName, ${dt.day}/${dt.month}/${dt.year}',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                if (isToday) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('Hari ini',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ]),
              subtitle: Text(
                reason ?? 'Tanpa keterangan',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: reason != null
                        ? AppColors.textSecondary
                        : AppColors.textHint,
                    fontStyle: reason == null
                        ? FontStyle.italic
                        : FontStyle.normal),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.accent, size: 20),
                tooltip: 'Hapus hari tutup',
                onPressed: () => _removeClosure(dateStr),
              ),
            ),
          );
        }),
    ]);
  }

  String _dayName(int weekday) {
    const days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
    return days[weekday - 1];
  }
}