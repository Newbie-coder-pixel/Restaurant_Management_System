// lib/features/multi_branch/presentation/transfer_stock_list_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/staff_role.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/widgets/staff_shell.dart';
import '../models/transfer_stock_model.dart';
import '../services/transfer_stock_service.dart';
import 'widgets/transfer_stock_dialog.dart';

class TransferStockListScreen extends ConsumerStatefulWidget {
  const TransferStockListScreen({super.key});

  @override
  ConsumerState<TransferStockListScreen> createState() =>
      _TransferStockListScreenState();
}

class _TransferStockListScreenState
    extends ConsumerState<TransferStockListScreen> {
  final _service = TransferStockService(Supabase.instance.client);

  List<TransferStockModel> _transfers = [];
  bool _isLoading = true;
  TransferStatus? _filterStatus;

  String? _branchId;
  String? _branchName;
  String? _staffId;
  StaffRole? _userRole;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final staff = ref.read(currentStaffProvider);
    if (staff != null && _branchId == null) {
      _branchId   = staff.branchId;
      _staffId    = staff.id;
      _userRole   = staff.role;
      _branchName = staff.fullName; // fallback, will be fetched properly
      _loadBranchName();
      _load();
    }
  }

  Future<void> _loadBranchName() async {
    if (_branchId == null) return;
    try {
      final res = await Supabase.instance.client
          .from('branches')
          .select('name')
          .eq('id', _branchId!)
          .single();
      if (mounted) setState(() => _branchName = res['name'] as String?);
    } catch (_) {}
  }

  Future<void> _load() async {
    if (_branchId == null) return;
    setState(() => _isLoading = true);
    try {
      final data = await _service.fetchTransfers(
        branchId:     _branchId!,
        filterStatus: _filterStatus,
      );
      if (mounted) setState(() { _transfers = data; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _canManage =>
      _userRole == StaffRole.manager || _userRole == StaffRole.superadmin;

  // ── Request transfer (manager/superadmin only) ──────────────────
  Future<void> _openRequestDialog() async {
    if (_branchId == null || _staffId == null) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => TransferStockDialog(
        fromBranchId:   _branchId!,
        fromBranchName: _branchName ?? 'My Branch',
        requestedBy:    _staffId!,
      ),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅ Transfer request sent successfully!'),
        backgroundColor: AppColors.available,
      ));
      _load();
    }
  }

  // ── Approve/confirm receipt (destination branch manager) ────────
  Future<void> _approveTransfer(TransferStockModel transfer) async {
    // Confirm first
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmReceiveDialog(transfer: transfer),
    );
    if (confirm != true || !mounted) return;

    // Find item_id in the destination branch (item with the same name)
    try {
      final today = DateTime.now().toIso8601String().split('T').first;
      final res = await Supabase.instance.client
          .from('inventory_items')
          .select('id')
          .eq('branch_id', _branchId!)
          .eq('name', transfer.itemName ?? '')
          .eq('date', today)
          .maybeSingle();

      final toItemId = res?['id'] as String?;
      if (toItemId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('❌ Item not found in this branch\'s inventory. Make sure the item name matches.'),
          backgroundColor: AppColors.accent,
          duration: Duration(seconds: 5),
        ));
        return;
      }

      await _service.approveTransfer(
        transferId: transfer.id,
        toItemId:   toItemId,
        approvedBy: _staffId!,
        quantity:   transfer.quantity,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Transfer confirmed successfully & stock updated!'),
          backgroundColor: AppColors.available,
        ));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ Failed to confirm: $e'),
          backgroundColor: AppColors.accent,
        ));
      }
    }
  }

  // ── Cancel transfer ────────────────────────────────────────────
  Future<void> _cancelTransfer(TransferStockModel transfer) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel Transfer?',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: Text(
          'The transfer of ${transfer.itemName ?? ''} — '
          '${transfer.quantity.toStringAsFixed(1)} ${transfer.itemUnit ?? ''} '
          'to ${transfer.toBranchName ?? ''} will be cancelled.',
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, Cancel',
              style: TextStyle(fontFamily: 'Poppins'))),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await _service.cancelTransfer(transfer.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Transfer cancelled.'),
          backgroundColor: AppColors.accentOrange,
        ));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ Failed to cancel: $e'),
          backgroundColor: AppColors.accent,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StaffShell(
      pageTitle: 'Stock Transfer',
      activeRoute: AppRoutes.branches,
      topBarActions: [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
          onPressed: _load,
        ),
      ],
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              onPressed: _openRequestDialog,
              backgroundColor: AppColors.accent,
              icon: const Icon(Icons.swap_horiz, color: Colors.white),
              label: const Text('Request Transfer',
                style: TextStyle(
                  color: Colors.white, fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600)),
            )
          : null,
      body: Column(children: [
        _buildFilterChips(),
        const Divider(height: 1, color: AppColors.border),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _transfers.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: _transfers.length,
                      itemBuilder: (_, i) => _buildTransferCard(_transfers[i]),
                    ),
        ),
      ]),
    );
  }

  // ── Filter chips ───────────────────────────────────────────────
  Widget _buildFilterChips() {
    return Container(
      height: 54,
      color: AppColors.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(children: [
          _chip(null, 'All'),
          _chip(TransferStatus.pending,  'Pending'),
          _chip(TransferStatus.received, 'Received'),
          _chip(TransferStatus.cancelled, 'Cancelled'),
        ]),
      ),
    );
  }

  Widget _chip(TransferStatus? status, String label) {
    final selected = _filterStatus == status;
    final color = status == null
        ? AppColors.primary
        : status == TransferStatus.pending
            ? AppColors.accentOrange
            : status == TransferStatus.received
                ? AppColors.available
                : AppColors.textHint;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          setState(() { _filterStatus = status; _isLoading = true; });
          _load();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            border: Border.all(color: selected ? color : AppColors.border),
          ),
          child: Text(label,
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.textSecondary)),
        ),
      ),
    );
  }

  // ── Transfer card ──────────────────────────────────────────────
  Widget _buildTransferCard(TransferStockModel t) {
    final isIncoming = t.toBranchId == _branchId;
    final isPending  = t.status == TransferStatus.pending;
    final isReceived = t.status == TransferStatus.received;

    final statusColor = isPending
        ? AppColors.accentOrange
        : isReceived
            ? AppColors.available
            : AppColors.textHint;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Header: item + status ──────────────────────────
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (isIncoming ? AppColors.available : AppColors.accent)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isIncoming ? Icons.arrow_downward : Icons.arrow_upward,
                  size: 18,
                  color: isIncoming ? AppColors.available : AppColors.accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.itemName ?? '-',
                      style: const TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                        fontSize: 15)),
                    Text(
                      '${t.quantity.toStringAsFixed(1)} ${t.itemUnit ?? ''}',
                      style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 13,
                        color: AppColors.textSecondary)),
                  ],
                ),
              ),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Text(t.status.label,
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 11,
                    fontWeight: FontWeight.w600, color: statusColor)),
              ),
            ]),
            const Divider(height: 20),

            // ── Detail: from → to ──────────────────────────────
            _detailRow(Icons.store_outlined, 'From',  t.fromBranchName ?? '-'),
            _detailRow(Icons.store,          'To',    t.toBranchName   ?? '-'),
            _detailRow(Icons.person_outline, 'Requested by', t.requestedByName ?? '-'),
            _detailRow(Icons.calendar_today_rounded, 'Request date',
                _formatDt(t.createdAt)),

            // ── Receipt details (if already received) ───────────
            if (isReceived) ...[
              const Divider(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.available.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.available.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.verified_rounded,
                        size: 14, color: AppColors.available),
                      SizedBox(width: 6),
                      Text('Proof of Receipt',
                        style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.available)),
                    ]),
                    const SizedBox(height: 8),
                    _detailRow(Icons.person_rounded, 'Received by',
                        t.approvedByName ?? '-'),
                    _detailRow(Icons.access_time_rounded, 'Time received',
                        t.receivedAt != null ? _formatDt(t.receivedAt!) : '-'),
                    _detailRow(Icons.inventory_2_rounded, 'Item',
                        '${t.itemName ?? '-'} — ${t.quantity.toStringAsFixed(1)} ${t.itemUnit ?? ''}'),
                    _detailRow(Icons.swap_horiz, 'From → To',
                        '${t.fromBranchName ?? '-'} → ${t.toBranchName ?? '-'}'),
                  ],
                ),
              ),
            ],

            // ── Actions ────────────────────────────────────────
            if (isPending && _canManage) ...[
              const SizedBox(height: 12),
              Row(children: [
                // Approve button only appears for the DESTINATION branch
                if (isIncoming)
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.available,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _approveTransfer(t),
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Confirm Receipt',
                        style: TextStyle(
                          fontFamily: 'Poppins', fontWeight: FontWeight.w600,
                          fontSize: 13)),
                    ),
                  ),
                // Cancel button only for the SENDING branch
                if (!isIncoming) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        side: const BorderSide(color: AppColors.accent),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _cancelTransfer(t),
                      icon: const Icon(Icons.cancel_outlined, size: 16),
                      label: const Text('Cancel',
                        style: TextStyle(
                          fontFamily: 'Poppins', fontWeight: FontWeight.w600,
                          fontSize: 13)),
                    ),
                  ),
                ],
              ]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: AppColors.textHint),
          const SizedBox(width: 6),
          SizedBox(
            width: 100,
            child: Text(label,
              style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 12,
                color: AppColors.textSecondary)),
          ),
          const Text(': ',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          Expanded(
            child: Text(value,
              style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 12,
                fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  String _formatDt(DateTime dt) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, $h:$m';
  }

  Widget _buildEmptyState() => const Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.swap_horiz, size: 64, color: AppColors.textHint),
      SizedBox(height: 12),
      Text('No stock transfers yet',
        style: TextStyle(
          fontFamily: 'Poppins', fontWeight: FontWeight.w700,
          fontSize: 18, color: AppColors.textSecondary)),
      SizedBox(height: 6),
      Text('Use the "Request Transfer" button to\nsend stock to another branch.',
        textAlign: TextAlign.center,
        style: TextStyle(fontFamily: 'Poppins', color: AppColors.textHint)),
    ]),
  );
}

// ── Confirm receipt dialog ───────────────────────────────────────────────
class _ConfirmReceiveDialog extends StatelessWidget {
  final TransferStockModel transfer;
  const _ConfirmReceiveDialog({required this.transfer});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.available.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.verified_rounded,
            color: AppColors.available, size: 20)),
        const SizedBox(width: 10),
        const Text('Confirm Receipt',
          style: TextStyle(
            fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Confirm that the following items have been physically received:',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 13)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.available.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.available.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row('Item',    transfer.itemName ?? '-'),
                _row('Quantity',
                  '${transfer.quantity.toStringAsFixed(1)} ${transfer.itemUnit ?? ''}'),
                _row('From',   transfer.fromBranchName ?? '-'),
                _row('Time',  _now()),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'This branch\'s stock will automatically increase after confirmation.',
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 11,
              color: AppColors.textSecondary)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel',
            style: TextStyle(fontFamily: 'Poppins'))),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.available,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10))),
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.check_rounded, size: 16),
          label: const Text('Yes, Received',
            style: TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w700))),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(label,
            style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 12,
              color: AppColors.textSecondary))),
        const Text(': ',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        Expanded(
          child: Text(value,
            style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 12,
              fontWeight: FontWeight.w700))),
      ],
    ),
  );

  String _now() {
    final dt = DateTime.now();
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, $h:$m';
  }
}