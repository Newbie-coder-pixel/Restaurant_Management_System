import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/staff_role.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/widgets/staff_shell.dart';

class _BranchStats {
  final double revenue;
  final int activeOrders;
  final int staffTotal;
  final int staffOnDuty;
  const _BranchStats({
    this.revenue = 0,
    this.activeOrders = 0,
    this.staffTotal = 0,
    this.staffOnDuty = 0,
  });
}

class BranchDashboardScreen extends ConsumerStatefulWidget {
  const BranchDashboardScreen({super.key});
  @override
  ConsumerState<BranchDashboardScreen> createState() => _BranchDashboardState();
}

class _BranchDashboardState extends ConsumerState<BranchDashboardScreen> {
  List<Map<String, dynamic>> _branches = [];
  Map<String, _BranchStats> _stats = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _isAuthorized =>
      ref.read(currentStaffProvider)?.role == StaffRole.superadmin;

  Future<void> _load() async {
    // "Multi-Branch" is a superadmin-only feature (see StaffRole.accessFeatures).
    // Previously this screen would query & render data for ALL branches for any
    // role that managed to reach it (no guard at all) — the router now blocks
    // non-superadmin navigation to /branches, and this is the second layer
    // of defense at the widget level.
    if (!_isAuthorized) {
      setState(() => _isLoading = false);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final res = await Supabase.instance.client
          .from('branches')
          .select(
              'id, name, address, phone, email, is_active, '
              'opening_time, closing_time, latitude, longitude')
          .order('created_at');
      _branches = (res as List).cast<Map<String, dynamic>>();
      await _loadStats();
      if (mounted) setState(() => _isLoading = false);
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Per-branch stat tiles (revenue / active orders / staff on duty) ────
  // Reuses the exact filters already used elsewhere: payments.status='paid'
  // for revenue (reports_provider.dart), the "active" order status list
  // (order_screen.dart), and staff.is_active / attendance for headcount
  // (staff_screen.dart, attendance_clock_service.dart) — just scoped per
  // branch here instead of a single selected branch.
  Future<void> _loadStats() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final tomorrowStart = todayStart.add(const Duration(days: 1));
    final todayStr = todayStart.toIso8601String().split('T').first;
    const activeStatuses = ['new', 'created', 'paid', 'preparing', 'ready', 'served'];
    final client = Supabase.instance.client;

    final entries = await Future.wait(_branches.map((b) async {
      final id = b['id'] as String;
      try {
        final results = await Future.wait([
          client.from('payments').select('amount')
              .eq('status', 'paid').eq('branch_id', id)
              .gte('created_at', todayStart.toIso8601String())
              .lt('created_at', tomorrowStart.toIso8601String()),
          client.from('orders').select('id')
              .eq('branch_id', id).inFilter('status', activeStatuses),
          client.from('staff').select('id')
              .eq('branch_id', id).eq('is_active', true),
          client.from('attendance').select('id')
              .eq('branch_id', id).eq('date', todayStr).eq('status', 'present')
              .filter('clock_out', 'is', null),
        ]);

        final revenue = (results[0] as List).fold<double>(
            0, (sum, r) => sum + ((r as Map)['amount'] as num).toDouble());

        return MapEntry(id, _BranchStats(
          revenue: revenue,
          activeOrders: (results[1] as List).length,
          staffTotal: (results[2] as List).length,
          staffOnDuty: (results[3] as List).length,
        ));
      } catch (_) {
        return MapEntry(id, const _BranchStats());
      }
    }));

    if (mounted) setState(() => _stats = Map.fromEntries(entries));
  }

  String _fmtRupiahCompact(num value) {
    final v = value.toDouble();
    if (v.abs() >= 1000000) return 'Rp ${(v / 1000000).toStringAsFixed(1)}M';
    if (v.abs() >= 1000) return 'Rp ${(v / 1000).toStringAsFixed(0)}K';
    return 'Rp ${v.toStringAsFixed(0)}';
  }

  String _fmtTime(String? t) {
    if (t == null) return '-';
    return t.length >= 5 ? t.substring(0, 5) : t;
  }

  Future<TimeOfDay?> _pickTime(BuildContext ctx, TimeOfDay initial) =>
      showTimePicker(context: ctx, initialTime: initial);

  Future<void> _showBranchDialog({Map<String, dynamic>? branch}) async {
    final isEdit = branch != null;
    final nameCtrl    = TextEditingController(text: branch?['name'] ?? '');
    final addressCtrl = TextEditingController(text: branch?['address'] ?? '');
    final phoneCtrl   = TextEditingController(text: branch?['phone'] ?? '');
    final emailCtrl   = TextEditingController(text: branch?['email'] ?? '');
    final latCtrl     = TextEditingController(
        text: branch?['latitude']?.toString() ?? '');
    final lngCtrl     = TextEditingController(
        text: branch?['longitude']?.toString() ?? '');

    TimeOfDay openTime  = _parseTime(branch?['opening_time'],  const TimeOfDay(hour: 10, minute: 0));
    TimeOfDay closeTime = _parseTime(branch?['closing_time'],  const TimeOfDay(hour: 22, minute: 0));
    bool isActive  = branch?['is_active'] == true;
    bool isLoading = false;
    String? errorMsg;

    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(builder: (ctx, ss) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
        title: Text(isEdit ? 'Edit Branch' : 'Add Branch',
          style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [

            // ── Name ──────────────────────────────────────────────
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Branch Name *',
                prefixIcon: Icon(Icons.store_outlined))),
            const SizedBox(height: 12),

            // ── Address ───────────────────────────────────────────
            TextField(
              controller: addressCtrl,
              decoration: const InputDecoration(
                labelText: 'Address',
                prefixIcon: Icon(Icons.location_on_outlined)),
              maxLines: 2),
            const SizedBox(height: 12),

            // ── Phone ─────────────────────────────────────────────
            TextField(
              controller: phoneCtrl,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                prefixIcon: Icon(Icons.phone_outlined)),
              keyboardType: TextInputType.phone),
            const SizedBox(height: 12),

            // ── Email ─────────────────────────────────────────────
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined)),
              keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 16),

            // ── Coordinates ───────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.iconAccentBlue.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(color: AppColors.iconAccentBlue.withValues(alpha: 0.25))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.my_location, size: 15, color: AppColors.iconAccentBlue),
                    SizedBox(width: 6),
                    Text('Location Coordinates',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppColors.iconAccentBlue)),
                  ]),
                  const SizedBox(height: 4),
                  const Text(
                    'Required for the "Nearest Branch" feature in the customer app.',
                    style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: latCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Latitude',
                          hintText: 'e.g.: -6.2088',
                          prefixIcon: Icon(Icons.expand_less, size: 18),
                          isDense: true),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^-?\d*\.?\d*')),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: lngCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Longitude',
                          hintText: 'e.g.: 106.8456',
                          prefixIcon: Icon(Icons.expand_more, size: 18),
                          isDense: true),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^-?\d*\.?\d*')),
                        ],
                      ),
                    ),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Operating Hours ───────────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Operating Hours',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13,
                    color: AppColors.textPrimary)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _TimePickerButton(
                    label: 'Open',
                    time: openTime,
                    onTap: () async {
                      final t = await _pickTime(ctx, openTime);
                      if (t != null) ss(() => openTime = t);
                    },
                  )),
                  const SizedBox(width: 10),
                  const Text('–',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 10),
                  Expanded(child: _TimePickerButton(
                    label: 'Close',
                    time: closeTime,
                    onTap: () async {
                      final t = await _pickTime(ctx, closeTime);
                      if (t != null) ss(() => closeTime = t);
                    },
                  )),
                ]),
              ]),
            ),
            const SizedBox(height: 12),

            // ── Active Status (edit mode only) ────────────────────
            if (isEdit)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: (isActive ? AppColors.available : AppColors.textHint)
                      .withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  border: Border.all(
                    color: (isActive ? AppColors.available : AppColors.textHint)
                        .withValues(alpha: 0.3))),
                child: Row(children: [
                  Icon(
                    isActive
                        ? Icons.check_circle_outline
                        : Icons.cancel_outlined,
                    size: 18,
                    color: isActive ? AppColors.available : AppColors.textHint),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isActive ? 'Branch Active' : 'Branch Inactive',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isActive
                            ? AppColors.available
                            : AppColors.textHint))),
                  Switch(
                    value: isActive,
                    activeThumbColor: AppColors.available,
                    onChanged: (v) => ss(() => isActive = v)),
                ]),
              ),

            // ── Error ─────────────────────────────────────────────
            if (errorMsg case final msg?) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8)),
                child: Text(msg,
                  style: const TextStyle(
                    color: AppColors.accent, fontSize: 12, fontFamily: 'Poppins'))),
            ],
          ]),
        ),
        actions: [
          TextButton(
            onPressed: isLoading ? null : () => Navigator.pop(ctx),
            child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white),
            onPressed: isLoading ? null : () async {
              if (nameCtrl.text.trim().isEmpty) {
                ss(() => errorMsg = 'Branch name is required.');
                return;
              }
              final openMin  = openTime.hour * 60 + openTime.minute;
              // If closeMin <= openMin, assume it closes the next day (e.g. opens 10:00, closes 01:00)
              final closeMin = closeTime.hour * 60 + closeTime.minute;
              final effectiveCloseMin = closeMin <= openMin ? closeMin + 1440 : closeMin;
              if (effectiveCloseMin == openMin) {
                ss(() => errorMsg = 'Closing time cannot be the same as opening time.');
                return;
              }
              final latStr = latCtrl.text.trim();
              final lngStr = lngCtrl.text.trim();
              final latFilled = latStr.isNotEmpty;
              final lngFilled = lngStr.isNotEmpty;
              if (latFilled != lngFilled) {
                ss(() => errorMsg =
                    'Latitude and Longitude must both be filled in or both left empty.');
                return;
              }
              double? lat, lng;
              if (latFilled) {
                lat = double.tryParse(latStr);
                lng = double.tryParse(lngStr);
                if (lat == null || lng == null) {
                  ss(() => errorMsg = 'Invalid coordinate format.');
                  return;
                }
                if (lat < -90 || lat > 90) {
                  ss(() => errorMsg = 'Latitude must be between -90 and 90.');
                  return;
                }
                if (lng < -180 || lng > 180) {
                  ss(() => errorMsg = 'Longitude must be between -180 and 180.');
                  return;
                }
              }

              ss(() { isLoading = true; errorMsg = null; });
              try {
                final data = {
                  'name':         nameCtrl.text.trim(),
                  'address':      addressCtrl.text.trim().isEmpty ? null : addressCtrl.text.trim(),
                  'phone':        phoneCtrl.text.trim().isEmpty   ? null : phoneCtrl.text.trim(),
                  'email':        emailCtrl.text.trim().isEmpty   ? null : emailCtrl.text.trim(),
                  'latitude':     lat,
                  'longitude':    lng,
                  'is_active':    isActive,
                  'opening_time': '${openTime.hour.toString().padLeft(2, '0')}:${openTime.minute.toString().padLeft(2, '0')}:00',
                  'closing_time': '${closeTime.hour.toString().padLeft(2, '0')}:${closeTime.minute.toString().padLeft(2, '0')}:00',
                };
                if (isEdit) {
                  await Supabase.instance.client
                      .from('branches').update(data).eq('id', branch['id']);
                } else {
                  await Supabase.instance.client.from('branches').insert(data);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                await _load();
              } catch (e) {
                ss(() { isLoading = false; errorMsg = 'Failed to save: $e'; });
              }
            },
            child: isLoading
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(isEdit ? 'Save' : 'Add',
                    style: const TextStyle(fontFamily: 'Poppins')),
          ),
        ],
      )),
    );
  }

  void _navigateToTransferStock() {
    context.go(AppRoutes.transferStock);
  }

  TimeOfDay _parseTime(String? t, TimeOfDay fallback) {
    if (t == null || t.isEmpty) return fallback;
    final parts = t.split(':');
    if (parts.length < 2) return fallback;
    return TimeOfDay(
      hour:   int.tryParse(parts[0]) ?? fallback.hour,
      minute: int.tryParse(parts[1]) ?? fallback.minute);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthorized) {
      return const Scaffold(
        body: Center(
          child: Text('You do not have access to this page.',
            style: TextStyle(fontFamily: 'Poppins')),
        ),
      );
    }

    return StaffShell(
      pageTitle: 'Multi-Branch Overview',
      activeRoute: AppRoutes.branches,
      topBarActions: [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
          onPressed: _load,
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showBranchDialog(),
        backgroundColor: AppColors.accent,
        icon: const Icon(Icons.add_business, color: Colors.white),
        label: const Text('Add Branch',
          style: TextStyle(
            color: Colors.white, fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _branches.isEmpty
              ? const _EmptyBranchesState()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 24),
                      LayoutBuilder(builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        final columns = width >= 1180 ? 3 : (width >= 760 ? 2 : 1);
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _branches.length,
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            crossAxisSpacing: 20,
                            mainAxisSpacing: 20,
                            mainAxisExtent: 322,
                          ),
                          itemBuilder: (_, i) => _BranchCard(
                            branch: _branches[i],
                            stats: _stats[_branches[i]['id']] ?? const _BranchStats(),
                            fmtRupiah: _fmtRupiahCompact,
                            fmtTime: _fmtTime,
                            onEdit: () => _showBranchDialog(branch: _branches[i]),
                            onTransfer: _navigateToTransferStock,
                          ),
                        );
                      }),
                    ],
                  ),
                ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Multi-Branch Overview',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 30,
                  fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              SizedBox(height: 4),
              Text('Real-time status across all locations',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 14, color: AppColors.textSecondary)),
            ],
          ),
        ),
        FilledButton(
          onPressed: _navigateToTransferStock,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm)),
          ),
          child: const Text('TRANSFER STOCK',
            style: TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w800,
              fontSize: 13, letterSpacing: 0.4)),
        ),
      ],
    );
  }
}

// ─── Branch card ──────────────────────────────────────────────────────────

class _BranchCard extends StatelessWidget {
  final Map<String, dynamic> branch;
  final _BranchStats stats;
  final String Function(num) fmtRupiah;
  final String Function(String?) fmtTime;
  final VoidCallback onEdit;
  final VoidCallback onTransfer;

  const _BranchCard({
    required this.branch,
    required this.stats,
    required this.fmtRupiah,
    required this.fmtTime,
    required this.onEdit,
    required this.onTransfer,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = branch['is_active'] == true;
    final address = branch['address'] as String?;
    final openStr  = fmtTime(branch['opening_time']);
    final closeStr = fmtTime(branch['closing_time']);
    final name = branch['name'] as String? ?? '';
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Banner ────────────────────────────────────────────
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            color: (isActive ? AppColors.primary : AppColors.textHint)
                .withValues(alpha: 0.08),
            child: Row(
              children: [
                Container(
                  width: 40, height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: (isActive ? AppColors.primary : AppColors.textHint)
                        .withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Text(initial,
                    style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w800,
                      color: isActive ? AppColors.primary : AppColors.textHint)),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    border: Border.all(
                      color: isActive ? AppColors.primary : AppColors.textHint),
                  ),
                  child: Text(isActive ? 'OPEN' : 'CLOSED',
                    style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: isActive ? AppColors.primary : AppColors.textHint)),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(branch['name'] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 18,
                    fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                const SizedBox(height: 3),
                Text(
                  (address == null || address.isEmpty) ? 'No address on file' : address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.access_time_rounded, size: 12, color: AppColors.textHint),
                  const SizedBox(width: 4),
                  Text('$openStr – $closeStr WIB',
                    style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 11, color: AppColors.textHint)),
                ]),
              ],
            ),
          ),

          const Divider(height: 1, color: AppColors.border),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              children: [
                _statRow("Today's Revenue", fmtRupiah(stats.revenue)),
                const SizedBox(height: 8),
                _statRow('Active Orders', '${stats.activeOrders}'),
                const SizedBox(height: 8),
                _statRow('Staff Count', '${stats.staffOnDuty} / ${stats.staffTotal}'),
              ],
            ),
          ),

          const Spacer(),
          const Divider(height: 1, color: AppColors.border),

          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: onTransfer,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: const RoundedRectangleBorder(),
                  ),
                  label: const Text('Transfer',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
              Container(width: 1, height: 24, color: AppColors.border),
              Expanded(
                child: TextButton.icon(
                  onPressed: onEdit,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: const RoundedRectangleBorder(),
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
          style: const TextStyle(
            fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
        Text(value,
          style: const TextStyle(
            fontFamily: 'Poppins', fontSize: 14,
            fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
      ],
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────

class _EmptyBranchesState extends StatelessWidget {
  const _EmptyBranchesState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96, height: 96,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.store_outlined, size: 48, color: AppColors.primary),
          ),
          const SizedBox(height: 20),
          const Text('No branches yet',
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 18,
              fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          const Text('Use "Add Branch" to register your first location.',
            style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

// ─── Time Picker Button ───────────────────────────────────────────────────

class _TimePickerButton extends StatelessWidget {
  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;
  const _TimePickerButton({
    required this.label,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4))),
        child: Column(children: [
          Text(label,
            style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text('$h:$m',
            style: const TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16,
              color: AppColors.textPrimary)),
        ]),
      ),
    );
  }
}
