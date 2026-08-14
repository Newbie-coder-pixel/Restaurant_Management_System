// lib/features/table_management/presentation/table_qr_codes_screen.dart
//
// Staff-facing "Table QR Codes" screen: shows every table's current QR code
// (auto-rotates daily at midnight WIB — see qr_token_for_table() /
// validate_qr_token() in supabase/migrations/20260814020000_table_qr_rotation.sql)
// with a per-table "Regenerate" action to force-invalidate a code early, plus
// a "Regenerate all" bulk action and a printable PDF export for the whole
// branch. Pushed from TableScreen's app bar rather than routed through
// GoRouter, since it's a staff-only detail view reachable only from an
// already-access-gated screen.
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/table_model.dart';

class TableQrCodesScreen extends StatefulWidget {
  final String branchId;
  const TableQrCodesScreen({super.key, required this.branchId});

  @override
  State<TableQrCodesScreen> createState() => _TableQrCodesScreenState();
}

class _TableQrCodesScreenState extends State<TableQrCodesScreen> {
  bool _loading = true;
  String? _error;
  String _branchName = '';
  List<TableModel> _tables = [];
  // table_id → today's token
  final Map<String, String> _tokens = {};
  final Set<String> _regenerating = {};
  bool _regeneratingAll = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final branchRes = await Supabase.instance.client
          .from('branches')
          .select('name')
          .eq('id', widget.branchId)
          .maybeSingle();

      final res = await Supabase.instance.client
          .from('restaurant_tables')
          .select()
          .eq('branch_id', widget.branchId)
          .order('table_number');
      final tables = (res as List).map((e) => TableModel.fromJson(e)).toList();

      final tokens = await Future.wait(tables.map((t) async {
        final token = await Supabase.instance.client.rpc(
          'qr_token_for_table',
          params: {'p_table_id': t.id},
        ) as String;
        return MapEntry(t.id, token);
      }));

      if (!mounted) return;
      setState(() {
        _branchName = branchRes?['name'] as String? ?? 'Branch';
        _tables = tables;
        _tokens
          ..clear()
          ..addEntries(tokens);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load table QR codes: $e';
        _loading = false;
      });
    }
  }

  String _urlFor(String tableId) =>
      '${AppConfig.qrAppUrl}/qr/$tableId?t=${_tokens[tableId]}';

  Future<void> _regenerate(TableModel table) async {
    final confirmed = await _confirmRegenerate(count: 1);
    if (confirmed != true || !mounted) return;

    setState(() => _regenerating.add(table.id));
    try {
      final newToken = await Supabase.instance.client.rpc(
        'regenerate_qr_token',
        params: {'p_table_id': table.id},
      ) as String;
      if (!mounted) return;
      setState(() => _tokens[table.id] = newToken);
      _snack('Table ${table.tableNumber}\'s QR code was regenerated. '
          'The old code no longer works.');
    } catch (e) {
      if (mounted) _snack('Failed to regenerate: $e', isError: true);
    } finally {
      if (mounted) setState(() => _regenerating.remove(table.id));
    }
  }

  Future<void> _regenerateAll() async {
    if (_tables.isEmpty) return;
    final confirmed = await _confirmRegenerate(count: _tables.length);
    if (confirmed != true || !mounted) return;

    setState(() => _regeneratingAll = true);
    try {
      final results = await Future.wait(_tables.map((t) async {
        final token = await Supabase.instance.client.rpc(
          'regenerate_qr_token',
          params: {'p_table_id': t.id},
        ) as String;
        return MapEntry(t.id, token);
      }));
      if (!mounted) return;
      setState(() => _tokens.addEntries(results));
      _snack('Regenerated QR codes for all ${_tables.length} tables.');
    } catch (e) {
      if (mounted) _snack('Failed to regenerate all: $e', isError: true);
    } finally {
      if (mounted) setState(() => _regeneratingAll = false);
    }
  }

  Future<bool?> _confirmRegenerate({required int count}) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
          title: Text(count == 1 ? 'Regenerate this QR code?' : 'Regenerate all $count QR codes?'),
          content: Text(
            count == 1
                ? 'The current code on this table will stop working immediately, '
                  'even for guests already looking at it. Reprint/redisplay the '
                  'new code before removing the old one.'
                : 'Every table\'s current code will stop working immediately. '
                  'Make sure you can reprint/redisplay all of them before '
                  'confirming.',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Regenerate'),
            ),
          ],
        ),
      );

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
        backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _exportPdf() async {
    if (_tables.isEmpty) return;
    try {
      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          header: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('TABLE QR CODES',
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Text(_branchName,
                  style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
              pw.SizedBox(height: 4),
              pw.Text(
                'Generated ${DateTime.now().toLocal().toString().substring(0, 16)} — '
                'each code refreshes automatically the next day.',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
              ),
              pw.Divider(color: PdfColors.grey400),
              pw.SizedBox(height: 8),
            ],
          ),
          build: (ctx) => [
            pw.Wrap(
              spacing: 16,
              runSpacing: 16,
              children: _tables.map((t) {
                return pw.Container(
                  width: 150,
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                  ),
                  child: pw.Column(
                    children: [
                      pw.BarcodeWidget(
                        barcode: pw.Barcode.qrCode(),
                        data: _urlFor(t.id),
                        width: 120,
                        height: 120,
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text('Table ${t.tableNumber}',
                          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                      pw.Text('${t.capacity} seats',
                          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      );

      final bytes = await pdf.save();
      await Printing.sharePdf(
        bytes: Uint8List.fromList(bytes),
        filename:
            'table_qr_codes_${_branchName.replaceAll(' ', '_')}.pdf',
      );
    } catch (e) {
      if (mounted) _snack('Failed to export PDF: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: Text('Table QR Codes — $_branchName',
            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
        actions: [
          IconButton(
            tooltip: 'Regenerate all',
            icon: _regeneratingAll
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                : const Icon(Icons.refresh_rounded),
            onPressed: (_regeneratingAll || _tables.isEmpty) ? null : _regenerateAll,
          ),
          IconButton(
            tooltip: 'Export PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _tables.isEmpty ? null : _exportPdf,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(fontFamily: 'Poppins')),
                      const SizedBox(height: 12),
                      TextButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : _tables.isEmpty
                  ? const Center(
                      child: Text('No tables in this branch yet.',
                          style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: Column(
                        children: [
                          Container(
                            width: double.infinity,
                            color: AppColors.surfaceVariant,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            child: const Text(
                              'Every code refreshes automatically at midnight (WIB), so a '
                              'code scanned yesterday no longer works today. Use Regenerate '
                              'to invalidate a code immediately (e.g. if it was shared publicly).',
                              style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                                  color: AppColors.textSecondary, height: 1.4),
                            ),
                          ),
                          Expanded(
                            child: GridView.builder(
                              padding: const EdgeInsets.all(20),
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 220,
                                mainAxisSpacing: 16,
                                crossAxisSpacing: 16,
                                childAspectRatio: 0.78,
                              ),
                              itemCount: _tables.length,
                              itemBuilder: (context, i) => _TableQrCard(
                                table: _tables[i],
                                url: _urlFor(_tables[i].id),
                                regenerating: _regenerating.contains(_tables[i].id),
                                onRegenerate: () => _regenerate(_tables[i]),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
    );
  }
}

class _TableQrCard extends StatelessWidget {
  final TableModel table;
  final String url;
  final bool regenerating;
  final VoidCallback onRegenerate;

  const _TableQrCard({
    required this.table,
    required this.url,
    required this.regenerating,
    required this.onRegenerate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: QrImageView(data: url, version: QrVersions.auto, gapless: false),
            ),
          ),
          const SizedBox(height: 10),
          Text('Table ${table.tableNumber}',
              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14)),
          Text('${table.capacity} seats',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 32,
            child: OutlinedButton.icon(
              onPressed: regenerating ? null : onRegenerate,
              icon: regenerating
                  ? const SizedBox(
                      width: 12, height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                  : const Icon(Icons.refresh_rounded, size: 14),
              label: const Text('Regenerate',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: const BorderSide(color: AppColors.accent),
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
