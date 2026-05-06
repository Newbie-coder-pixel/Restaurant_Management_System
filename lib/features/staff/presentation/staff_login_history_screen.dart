import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/staff_model.dart';
import '../../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────
class LoginHistoryRecord {
  final String id;
  final String staffId;
  final DateTime loggedInAt;

  LoginHistoryRecord({
    required this.id,
    required this.staffId,
    required this.loggedInAt,
  });

  factory LoginHistoryRecord.fromJson(Map<String, dynamic> j) =>
      LoginHistoryRecord(
        id: j['id'] as String,
        staffId: j['staff_id'] as String,
        loggedInAt: DateTime.parse(j['logged_in_at'] as String).toLocal(),
      );
}

// ─────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────
class StaffLoginHistoryScreen extends StatefulWidget {
  final StaffMember staff;

  const StaffLoginHistoryScreen({super.key, required this.staff});

  @override
  State<StaffLoginHistoryScreen> createState() =>
      _StaffLoginHistoryScreenState();
}

class _StaffLoginHistoryScreenState extends State<StaffLoginHistoryScreen> {
  List<LoginHistoryRecord> _records = [];
  bool _isLoading = true;
  String? _error;

  // Tampilkan max 3 bulan terakhir — cukup untuk audit
  static const _limitMonths = 3;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final since = DateTime.now()
          .subtract(const Duration(days: 30 * _limitMonths))
          .toUtc()
          .toIso8601String();

      final res = await Supabase.instance.client
          .from('staff_login_history')
          .select()
          .eq('staff_id', widget.staff.id)
          .gte('logged_in_at', since)
          .order('logged_in_at', ascending: false)
          .limit(100);

      if (mounted) {
        setState(() {
          _records = (res as List)
              .map((e) => LoginHistoryRecord.fromJson(e as Map<String, dynamic>))
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  // ── helpers ────────────────────────────────
  String _formatDate(DateTime dt) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    const days = ['Min', 'Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab'];
    return '${days[dt.weekday % 7]}, ${dt.day} ${months[dt.month]} ${dt.year}';
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
    if (diff.inHours < 24) return '${diff.inHours} jam lalu';
    if (diff.inDays < 7) return '${diff.inDays} hari lalu';
    return _formatDate(dt);
  }

  // Group records by date string
  Map<String, List<LoginHistoryRecord>> get _grouped {
    final map = <String, List<LoginHistoryRecord>>{};
    for (final r in _records) {
      final key = _formatDate(r.loggedInAt);
      map.putIfAbsent(key, () => []).add(r);
    }
    return map;
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'superadmin': return const Color(0xFF9C27B0);
      case 'manager':    return const Color(0xFF2196F3);
      case 'cashier':    return const Color(0xFF4CAF50);
      case 'waiter':     return const Color(0xFFFF9800);
      case 'kitchen':    return const Color(0xFFE94560);
      case 'host':       return const Color(0xFF00BCD4);
      default:           return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleColor = _roleColor(widget.staff.role.name);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Riwayat Login',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Staff info header
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: roleColor.withValues(alpha: 0.15),
                child: Text(
                  widget.staff.fullName.isNotEmpty
                      ? widget.staff.fullName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: roleColor),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.staff.fullName,
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              fontSize: 15)),
                      Text(widget.staff.email,
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: AppColors.textSecondary)),
                    ]),
              ),
              // Total login badge
              if (!_isLoading)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(children: [
                    Text('${_records.length}',
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            color: AppColors.primary)),
                    const Text('login',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10,
                            color: AppColors.textSecondary)),
                  ]),
                ),
            ]),
          ),
          // Subtitle info
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.grey.shade50,
            child: const Text(
              'Menampilkan $_limitMonths bulan terakhir',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: AppColors.textHint),
            ),
          ),
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError()
                    : _records.isEmpty
                        ? _buildEmpty()
                        : _buildList(),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final grouped = _grouped;
    final dateKeys = grouped.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: dateKeys.length,
      itemBuilder: (_, i) {
        final dateLabel = dateKeys[i];
        final dayRecords = grouped[dateLabel]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date header
            Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 4),
              child: Row(children: [
                Container(
                  width: 8, height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(dateLabel,
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppColors.textPrimary)),
                const SizedBox(width: 8),
                Text('(${dayRecords.length}x)',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        color: AppColors.textHint)),
              ]),
            ),
            // Records for this date
            ...dayRecords.map((r) => _buildRecordTile(r)),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _buildRecordTile(LoginHistoryRecord r) {
    final isRecent = DateTime.now().difference(r.loggedInAt).inHours < 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 8, left: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isRecent
              ? AppColors.primary.withValues(alpha: 0.3)
              : Colors.grey.shade200,
        ),
      ),
      child: Row(children: [
        Icon(
          Icons.login_outlined,
          size: 18,
          color: isRecent ? AppColors.primary : AppColors.textHint,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _formatTime(r.loggedInAt),
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: isRecent ? AppColors.primary : AppColors.textPrimary),
          ),
        ),
        Text(
          _relativeTime(r.loggedInAt),
          style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              color: AppColors.textHint),
        ),
        if (isRecent) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('Terbaru',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ]),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_toggle_off_outlined,
              size: 64, color: AppColors.textHint),
          SizedBox(height: 16),
          Text('Belum ada riwayat login',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: AppColors.textSecondary)),
          SizedBox(height: 8),
          Text('Riwayat login akan muncul\nsetelah staff login berikutnya',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: AppColors.textHint)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFE94560), size: 48),
            const SizedBox(height: 12),
            Text('Gagal memuat data:\n$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: AppColors.textSecondary,
                    fontSize: 13)),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: _load,
                child: const Text('Coba Lagi',
                    style: TextStyle(fontFamily: 'Poppins'))),
          ],
        ),
      ),
    );
  }
}