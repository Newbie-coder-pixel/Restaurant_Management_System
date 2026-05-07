// lib/features/multi_branch/presentation/widgets/transfer_stock_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../services/transfer_stock_service.dart';

class TransferStockDialog extends StatefulWidget {
  final String fromBranchId;
  final String fromBranchName;
  final String requestedBy; // staff id

  const TransferStockDialog({
    super.key,
    required this.fromBranchId,
    required this.fromBranchName,
    required this.requestedBy,
  });

  @override
  State<TransferStockDialog> createState() => _TransferStockDialogState();
}

class _TransferStockDialogState extends State<TransferStockDialog> {
  final _service = TransferStockService(Supabase.instance.client);
  final _qtyCtrl = TextEditingController();

  List<Map<String, dynamic>> _items   = [];
  List<Map<String, dynamic>> _branches = [];

  Map<String, dynamic>? _selectedItem;
  Map<String, dynamic>? _selectedBranch;

  bool _isLoadingItems    = true;
  bool _isLoadingBranches = true;
  bool _isSubmitting      = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final items = await _service.fetchItemsForBranch(widget.fromBranchId);
      if (mounted) setState(() { _items = items; _isLoadingItems = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoadingItems = false);
    }

    try {
      final branches = await _service.fetchOtherBranches(widget.fromBranchId);
      if (mounted) setState(() { _branches = branches; _isLoadingBranches = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoadingBranches = false);
    }
  }

  Future<void> _submit() async {
    // Validasi
    if (_selectedItem == null) {
      setState(() => _errorMsg = 'Pilih item yang akan ditransfer.');
      return;
    }
    if (_selectedBranch == null) {
      setState(() => _errorMsg = 'Pilih cabang tujuan.');
      return;
    }
    final qty = double.tryParse(_qtyCtrl.text.trim());
    if (qty == null || qty <= 0) {
      setState(() => _errorMsg = 'Masukkan jumlah yang valid.');
      return;
    }

    // Cek stok tersedia
    final availableStock = (_selectedItem!['current_stock'] as num?)?.toDouble() ?? 0.0;
    if (qty > availableStock) {
      setState(() => _errorMsg =
          'Jumlah melebihi stok tersedia (${availableStock.toStringAsFixed(1)} ${_selectedItem!['unit'] ?? ''}).');
      return;
    }

    setState(() { _isSubmitting = true; _errorMsg = null; });

    try {
      await _service.requestTransfer(
        fromBranchId: widget.fromBranchId,
        toBranchId:   _selectedBranch!['id'] as String,
        itemId:       _selectedItem!['id'] as String,
        quantity:     qty,
        requestedBy:  widget.requestedBy,
      );
      if (mounted) {
        Navigator.pop(context, true); // true = berhasil
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMsg = 'Gagal mengirim request: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = _isLoadingItems || _isLoadingBranches;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.swap_horiz, color: AppColors.accent, size: 20),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text('Request Transfer Stok',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
        ),
      ]),
      content: SizedBox(
        width: 400,
        child: isLoading
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // ── Info cabang asal ──────────────────────────
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.store, size: 16, color: AppColors.primary),
                        const SizedBox(width: 8),
                        const Text('Dari: ',
                          style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 12,
                            color: AppColors.textSecondary)),
                        Text(widget.fromBranchName,
                          style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 12,
                            fontWeight: FontWeight.w700)),
                      ]),
                    ),
                    const SizedBox(height: 16),

                    // ── Pilih Item ────────────────────────────────
                    const Text('Item yang Ditransfer *',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 12,
                        fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    _items.isEmpty
                        ? _emptyHint('Belum ada item inventory hari ini.')
                        : DropdownButtonFormField<Map<String, dynamic>>(
                            initialValue: _selectedItem,
                            isExpanded: true,
                            decoration: _inputDecoration('Pilih item...', Icons.inventory_2_outlined),
                            items: _items.map((item) {
                              final stock = (item['current_stock'] as num?)?.toDouble() ?? 0.0;
                              return DropdownMenuItem(
                                value: item,
                                child: Row(children: [
                                  Expanded(
                                    child: Text(item['name'] ?? '',
                                      style: const TextStyle(
                                        fontFamily: 'Poppins', fontSize: 13)),
                                  ),
                                  Text('${stock.toStringAsFixed(1)} ${item['unit'] ?? ''}',
                                    style: TextStyle(
                                      fontFamily: 'Poppins', fontSize: 11,
                                      color: stock <= 0
                                          ? Colors.red
                                          : AppColors.textSecondary)),
                                ]),
                              );
                            }).toList(),
                            onChanged: (val) => setState(() {
                              _selectedItem = val;
                              _errorMsg = null;
                            }),
                          ),
                    const SizedBox(height: 14),

                    // ── Pilih Branch Tujuan ───────────────────────
                    const Text('Cabang Tujuan *',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 12,
                        fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    _branches.isEmpty
                        ? _emptyHint('Tidak ada cabang lain yang aktif.')
                        : DropdownButtonFormField<Map<String, dynamic>>(
                            initialValue: _selectedBranch,
                            isExpanded: true,
                            decoration: _inputDecoration('Pilih cabang tujuan...', Icons.store_outlined),
                            items: _branches.map((b) => DropdownMenuItem(
                              value: b,
                              child: Text(b['name'] ?? '',
                                style: const TextStyle(
                                  fontFamily: 'Poppins', fontSize: 13)),
                            )).toList(),
                            onChanged: (val) => setState(() {
                              _selectedBranch = val;
                              _errorMsg = null;
                            }),
                          ),
                    const SizedBox(height: 14),

                    // ── Jumlah ────────────────────────────────────
                    const Text('Jumlah *',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 12,
                        fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _qtyCtrl,
                      decoration: _inputDecoration(
                        'Masukkan jumlah...',
                        Icons.numbers,
                        suffix: _selectedItem != null
                            ? Text(_selectedItem!['unit'] ?? '',
                                style: const TextStyle(
                                  fontFamily: 'Poppins', fontSize: 13,
                                  color: AppColors.textSecondary))
                            : null,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                      ],
                      onChanged: (_) => setState(() => _errorMsg = null),
                    ),

                    // ── Info stok tersedia ────────────────────────
                    if (_selectedItem != null) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        const Icon(Icons.info_outline, size: 13, color: AppColors.textHint),
                        const SizedBox(width: 4),
                        Text(
                          'Stok tersedia: ${((_selectedItem!['current_stock'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(1)} ${_selectedItem!['unit'] ?? ''}',
                          style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 11,
                            color: AppColors.textHint)),
                      ]),
                    ],

                    // ── Error ─────────────────────────────────────
                    if (_errorMsg != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(children: [
                          const Icon(Icons.error_outline, size: 16, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_errorMsg!,
                              style: const TextStyle(
                                fontFamily: 'Poppins', fontSize: 12, color: Colors.red)),
                          ),
                        ]),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Batal',
            style: TextStyle(fontFamily: 'Poppins')),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: (_isSubmitting || isLoading) ? null : _submit,
          icon: _isSubmitting
              ? const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.send_rounded, size: 16),
          label: Text(_isSubmitting ? 'Mengirim...' : 'Kirim Request',
            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textHint),
      prefixIcon: Icon(icon, size: 18),
      suffixIcon: suffix != null ? Padding(
        padding: const EdgeInsets.only(right: 12),
        child: suffix,
      ) : null,
      suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      isDense: true,
    );
  }

  Widget _emptyHint(String msg) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.orange.shade50,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.orange.shade200),
    ),
    child: Row(children: [
      Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange.shade700),
      const SizedBox(width: 8),
      Expanded(
        child: Text(msg,
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: 12,
            color: Colors.orange.shade800)),
      ),
    ]),
  );
}