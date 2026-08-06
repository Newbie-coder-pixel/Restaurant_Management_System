// lib/features/chatbot/services/report_export_service.dart

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum ReportPeriod { daily, weekly, monthly, custom }

enum ReportFormat { pdf, csv }

class ReportExportService {
  // ── Fetch data for the given period ─────────────────────────────────
  static Future<Map<String, dynamic>> fetchReportData({
    required String? branchId,
    required ReportPeriod period,
    DateTime? customStart,
    DateTime? customEnd,
  }) async {
    final sb = Supabase.instance.client;
    final now = DateTime.now().toLocal();

    // IMPORTANT: date bounds are built from LOCAL time (WIB) and must be
    // converted with .toUtc() before being sent as a filter to Postgres —
    // a string without an offset is read by Postgres as UTC, not WIB, so
    // the "today/this week/this month" window could shift by ±7 hours from
    // the actual local bound. The upper bound is always "tomorrow at 00:00
    // local" and is used as an exclusive upper bound (`.lt`), not
    // `23:59:59` which could miss data in the last second of the day.
    DateTime localMidnight(DateTime d) => DateTime(d.year, d.month, d.day);
    String isoUtc(DateTime local) => local.toUtc().toIso8601String();
    String dateOnly(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    late DateTime startLocal;
    late DateTime endLocalExclusive;
    late String periodLabel;

    switch (period) {
      case ReportPeriod.daily:
        startLocal = localMidnight(now);
        endLocalExclusive = localMidnight(now).add(const Duration(days: 1));
        periodLabel = 'Daily — ${_formatDate(now)}';
        break;
      case ReportPeriod.weekly:
        final weekStartLocal =
            localMidnight(now.subtract(Duration(days: now.weekday - 1)));
        startLocal = weekStartLocal;
        endLocalExclusive = localMidnight(now).add(const Duration(days: 1));
        periodLabel =
            'Weekly — ${_formatDate(weekStartLocal)} to ${_formatDate(now)}';
        break;
      case ReportPeriod.monthly:
        startLocal = DateTime(now.year, now.month, 1);
        endLocalExclusive = localMidnight(now).add(const Duration(days: 1));
        periodLabel = 'Monthly — ${_bulanIndo(now.month)} ${now.year}';
        break;
      case ReportPeriod.custom:
        final start = customStart!;
        final endInclusive = customEnd!;
        startLocal = localMidnight(start);
        endLocalExclusive = localMidnight(endInclusive).add(const Duration(days: 1));
        periodLabel = start.year == endInclusive.year &&
                start.month == endInclusive.month &&
                start.day == endInclusive.day
            ? 'Custom — ${_formatDate(start)}'
            : 'Custom — ${_formatDate(start)} to ${_formatDate(endInclusive)}';
        break;
    }

    final startDate = isoUtc(startLocal);
    final endDate = isoUtc(endLocalExclusive);
    final startDateOnly = dateOnly(startLocal);
    final endDateOnly = dateOnly(endLocalExclusive);

    // Orders
    var qOrders = sb
        .from('orders')
        .select('total_amount, status, payment_status, order_type, payment_method, created_at, customer_name')
        .gte('created_at', startDate)
        .lt('created_at', endDate);
    if (branchId != null) qOrders = qOrders.eq('branch_id', branchId);
    final orders = (await qOrders as List).cast<Map<String, dynamic>>();

    // Orders that are paid have status 'paid' (see the OrderStatus enum in
    // order_model.dart) — 'completed' is a BOOKING status, not an order one.
    // This filter used to incorrectly use 'completed', so revenue/average
    // order value/payment breakdown/top menu in the report were always 0
    // even though transactions kept coming in.
    //
    // Also include payment_status == 'paid' directly: orders paid up front
    // (customer app) never get `status` set to 'paid' by the webhook — that
    // column tracks kitchen progress, not money (see
    // supabase/functions/midtrans-webhook/index.ts) — so status alone would
    // permanently exclude every customer-app order from this report.
    final completed = orders
        .where((o) => o['status'] == 'paid' || o['payment_status'] == 'paid')
        .toList();
    final cancelled = orders.where((o) => o['status'] == 'cancelled').length;
    final totalRevenue = completed.fold<double>(
        0, (s, o) => s + ((o['total_amount'] as num?)?.toDouble() ?? 0));
    final avgOrder =
        completed.isEmpty ? 0.0 : totalRevenue / completed.length;

    // Payment breakdown
    final Map<String, double> paymentMap = {};
    for (final o in completed) {
      final method = (o['payment_method'] as String?) ?? 'Other';
      paymentMap[method] =
          (paymentMap[method] ?? 0) + ((o['total_amount'] as num?)?.toDouble() ?? 0);
    }

    // Top menu items
    var qItems = sb
        .from('order_items')
        .select('menu_item_name, quantity, unit_price, orders!inner(status, payment_status, created_at, branch_id)')
        .gte('orders.created_at', startDate)
        .lt('orders.created_at', endDate)
        // Same "completed" definition as `completed` above.
        .or('status.eq.paid,payment_status.eq.paid', referencedTable: 'orders');
    if (branchId != null) qItems = qItems.eq('orders.branch_id', branchId);
    final items = (await qItems as List).cast<Map<String, dynamic>>();

    final Map<String, Map<String, dynamic>> menuMap = {};
    for (final item in items) {
      final name = (item['menu_item_name'] as String?) ?? 'Unknown';
      final qty = (item['quantity'] as num?)?.toInt() ?? 1;
      final price = (item['unit_price'] as num?)?.toDouble() ?? 0;
      menuMap[name] ??= {'qty': 0, 'revenue': 0.0};
      menuMap[name]!['qty'] = (menuMap[name]!['qty'] as int) + qty;
      menuMap[name]!['revenue'] =
          (menuMap[name]!['revenue'] as double) + (price * qty);
    }
    final topMenu = (menuMap.entries.toList()
          ..sort((a, b) =>
              (b.value['qty'] as int).compareTo(a.value['qty'] as int)))
        .take(10)
        .map((e) => {
              'name': e.key,
              'qty': e.value['qty'],
              'revenue': e.value['revenue'],
            })
        .toList();

    // Bookings — booking_date is a DATE column (no timezone), so use
    // startDateOnly/endDateOnly (LOCAL calendar date), not a substring of
    // startDate/endDate which are now already converted to UTC above.
    var qBooking = sb
        .from('bookings')
        .select('status, guest_count')
        .gte('booking_date', startDateOnly)
        .lt('booking_date', endDateOnly);
    if (branchId != null) qBooking = qBooking.eq('branch_id', branchId);
    final bookings = (await qBooking as List).cast<Map<String, dynamic>>();

    return {
      'period': periodLabel,
      'generated_at': _formatDate(now),
      'orders': {
        'total': orders.length,
        'completed': completed.length,
        'cancelled': cancelled,
        'revenue': totalRevenue,
        'avg_order': avgOrder,
        'payment_breakdown': paymentMap,
      },
      'top_menu': topMenu,
      'bookings': {
        'total': bookings.length,
        'confirmed':
            bookings.where((b) => b['status'] == 'confirmed').length,
        'cancelled':
            bookings.where((b) => b['status'] == 'cancelled').length,
        'no_show':
            bookings.where((b) => b['status'] == 'no_show').length,
        'total_guests': bookings.fold<int>(
            0, (s, b) => s + ((b['guest_count'] as num?)?.toInt() ?? 0)),
      },
    };
  }

  // ── Generate PDF ──────────────────────────────────────────────────
  static Future<Uint8List> generatePdf({
    required Map<String, dynamic> data,
    required String branchName,
  }) async {
    final pdf = pw.Document();
    final orders = data['orders'] as Map<String, dynamic>;
    final bookings = data['bookings'] as Map<String, dynamic>;
    final topMenu = data['top_menu'] as List;
    final paymentBreakdown =
        orders['payment_breakdown'] as Map<String, double>;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'ANALYTICS REPORT',
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      branchName,
                      style: const pw.TextStyle(
                        fontSize: 12,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      data['period'] as String,
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue800,
                      ),
                    ),
                    pw.Text(
                      'Generated: ${data['generated_at']}',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.Divider(color: PdfColors.grey400),
            pw.SizedBox(height: 8),
          ],
        ),
        build: (ctx) => [
          // ── KPI Summary ──────────────────────────────────────────
          pw.Text(
            'Order Summary',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              _pdfKpiBox('Total Orders', '${orders['total']}'),
              pw.SizedBox(width: 8),
              _pdfKpiBox('Completed', '${orders['completed']}'),
              pw.SizedBox(width: 8),
              _pdfKpiBox('Cancelled', '${orders['cancelled']}'),
              pw.SizedBox(width: 8),
              _pdfKpiBox(
                'Revenue',
                'Rp ${_fmtNum(orders['revenue'] as double)}',
              ),
              pw.SizedBox(width: 8),
              _pdfKpiBox(
                'Average Order',
                'Rp ${_fmtNum(orders['avg_order'] as double)}',
              ),
            ],
          ),
          pw.SizedBox(height: 20),

          // ── Payment Breakdown ────────────────────────────────────
          if (paymentBreakdown.isNotEmpty) ...[
            pw.Text(
              'Payment Breakdown',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(2),
              },
              children: [
                pw.TableRow(
                  decoration:
                      const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _pdfCell('Payment Method', isHeader: true),
                    _pdfCell('Total Revenue', isHeader: true),
                  ],
                ),
                ...paymentBreakdown.entries.map(
                  (e) => pw.TableRow(children: [
                    _pdfCell(e.key),
                    _pdfCell('Rp ${_fmtNum(e.value)}'),
                  ]),
                ),
              ],
            ),
            pw.SizedBox(height: 20),
          ],

          // ── Top Menu ─────────────────────────────────────────────
          pw.Text(
            'Best-Selling Menu Items (Top 10)',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            columnWidths: {
              0: const pw.FixedColumnWidth(32),
              1: const pw.FlexColumnWidth(4),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FlexColumnWidth(3),
            },
            children: [
              pw.TableRow(
                decoration:
                    const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _pdfCell('#', isHeader: true),
                  _pdfCell('Menu Item', isHeader: true),
                  _pdfCell('Sold', isHeader: true),
                  _pdfCell('Revenue', isHeader: true),
                ],
              ),
              ...topMenu.asMap().entries.map(
                (e) => pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: e.key.isEven ? PdfColors.white : PdfColors.grey50,
                  ),
                  children: [
                    _pdfCell('${e.key + 1}'),
                    _pdfCell(e.value['name'] as String),
                    _pdfCell('${e.value['qty']}x'),
                    _pdfCell('Rp ${_fmtNum(e.value['revenue'] as double)}'),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 20),

          // ── Bookings ─────────────────────────────────────────────
          pw.Text(
            'Booking Summary',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              _pdfKpiBox('Total Bookings', '${bookings['total']}'),
              pw.SizedBox(width: 8),
              _pdfKpiBox('Confirmed', '${bookings['confirmed']}'),
              pw.SizedBox(width: 8),
              _pdfKpiBox('Cancelled', '${bookings['cancelled']}'),
              pw.SizedBox(width: 8),
              _pdfKpiBox('No Show', '${bookings['no_show']}'),
              pw.SizedBox(width: 8),
              _pdfKpiBox('Total Guests', '${bookings['total_guests']}'),
            ],
          ),
          pw.SizedBox(height: 24),
          pw.Center(
            child: pw.Text(
              'This report was generated automatically by Resto Analytics AI',
              style: const pw.TextStyle(
                fontSize: 9,
                color: PdfColors.grey500,
              ),
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  // ── Generate CSV ──────────────────────────────────────────────────
  static String generateCsv({
    required Map<String, dynamic> data,
    required String branchName,
  }) {
    final orders = data['orders'] as Map<String, dynamic>;
    final bookings = data['bookings'] as Map<String, dynamic>;
    final topMenu = data['top_menu'] as List;
    final paymentBreakdown =
        orders['payment_breakdown'] as Map<String, double>;

    final buf = StringBuffer();

    // Header info
    buf.writeln('RESTAURANT ANALYTICS REPORT');
    buf.writeln('Branch,$branchName');
    buf.writeln('Period,${data['period']}');
    buf.writeln('Generated,${data['generated_at']}');
    buf.writeln();

    // Order summary
    buf.writeln('=== ORDER SUMMARY ===');
    buf.writeln('Metric,Value');
    buf.writeln('Total Orders,${orders['total']}');
    buf.writeln('Completed Orders,${orders['completed']}');
    buf.writeln('Cancelled Orders,${orders['cancelled']}');
    buf.writeln('Total Revenue,Rp ${_fmtNum(orders['revenue'] as double)}');
    buf.writeln(
        'Average Order Value,Rp ${_fmtNum(orders['avg_order'] as double)}');
    buf.writeln();

    // Payment breakdown
    buf.writeln('=== PAYMENT BREAKDOWN ===');
    buf.writeln('Method,Revenue');
    for (final e in paymentBreakdown.entries) {
      buf.writeln('${e.key},Rp ${_fmtNum(e.value)}');
    }
    buf.writeln();

    // Top menu
    buf.writeln('=== BEST-SELLING MENU ITEMS ===');
    buf.writeln('Ranking,Menu Item,Sold,Revenue');
    for (int i = 0; i < topMenu.length; i++) {
      final m = topMenu[i];
      buf.writeln(
          '${i + 1},${m['name']},${m['qty']},Rp ${_fmtNum(m['revenue'] as double)}');
    }
    buf.writeln();

    // Bookings
    buf.writeln('=== BOOKING SUMMARY ===');
    buf.writeln('Metric,Value');
    buf.writeln('Total Bookings,${bookings['total']}');
    buf.writeln('Confirmed,${bookings['confirmed']}');
    buf.writeln('Cancelled,${bookings['cancelled']}');
    buf.writeln('No Show,${bookings['no_show']}');
    buf.writeln('Total Guests,${bookings['total_guests']}');

    return buf.toString();
  }

  // ── Helpers ───────────────────────────────────────────────────────
  static pw.Widget _pdfKpiBox(String label, String value) =>
      pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            color: PdfColors.grey50,
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                value,
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue900,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                label,
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          ),
        ),
      );

  static pw.Widget _pdfCell(String text, {bool isHeader = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight:
                isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );

  static String _fmtNum(double v) {
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  static String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')} ${_bulanIndo(d.month)} ${d.year}';

  static String _bulanIndo(int bulan) {
    const list = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return list[bulan];
  }
}

// ── Export Bottom Sheet ───────────────────────────────────────────────
class ReportExportSheet extends StatefulWidget {
  final String? branchId;
  final String branchName;

  /// Pre-fills the Custom period, when the staff already asked the AI
  /// chatbot for a report over a specific date range earlier in the
  /// conversation. Null when they opened export without naming a range —
  /// the sheet then behaves exactly as before (Daily/Weekly/Monthly only).
  final DateTime? initialCustomStart;
  final DateTime? initialCustomEnd;

  const ReportExportSheet({
    super.key,
    required this.branchId,
    required this.branchName,
    this.initialCustomStart,
    this.initialCustomEnd,
  });

  @override
  State<ReportExportSheet> createState() => _ReportExportSheetState();
}

class _ReportExportSheetState extends State<ReportExportSheet> {
  late ReportPeriod _period;
  ReportFormat _format = ReportFormat.pdf;
  bool _isLoading = false;
  String? _errorMsg;

  bool get _hasCustomRange =>
      widget.initialCustomStart != null && widget.initialCustomEnd != null;

  @override
  void initState() {
    super.initState();
    _period = _hasCustomRange ? ReportPeriod.custom : ReportPeriod.daily;
  }

  Future<void> _export() async {
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      final data = await ReportExportService.fetchReportData(
        branchId: widget.branchId,
        period: _period,
        customStart: widget.initialCustomStart,
        customEnd: widget.initialCustomEnd,
      );

      if (_format == ReportFormat.pdf) {
        final pdfBytes = await ReportExportService.generatePdf(
          data: data,
          branchName: widget.branchName,
        );
        await Printing.sharePdf(
          bytes: pdfBytes,
          filename:
              'report_${_periodFileName()}_${widget.branchName.replaceAll(' ', '_')}.pdf',
        );
      } else {
        // CSV — share as a text file via the printing share sheet
        final csv = ReportExportService.generateCsv(
          data: data,
          branchName: widget.branchName,
        );
        final csvBytes = Uint8List.fromList(csv.codeUnits);
        await Printing.sharePdf(
          bytes: csvBytes,
          filename:
              'report_${_periodFileName()}_${widget.branchName.replaceAll(' ', '_')}.csv',
        );
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _errorMsg = 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _periodFileName() {
    switch (_period) {
      case ReportPeriod.daily:
        return 'daily';
      case ReportPeriod.weekly:
        return 'weekly';
      case ReportPeriod.monthly:
        return 'monthly';
      case ReportPeriod.custom:
        return 'custom';
    }
  }

  String _formatShortDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          const Text(
            '📊 Export Report',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.branchName,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 20),

          // Period
          const Text(
            'Period',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _periodChip(ReportPeriod.daily, '📅 Daily'),
              const SizedBox(width: 8),
              _periodChip(ReportPeriod.weekly, '📆 Weekly'),
              const SizedBox(width: 8),
              _periodChip(ReportPeriod.monthly, '🗓️ Monthly'),
              if (_hasCustomRange) ...[
                const SizedBox(width: 8),
                _periodChip(ReportPeriod.custom, '✨ Custom'),
              ],
            ],
          ),
          if (_hasCustomRange && _period == ReportPeriod.custom) ...[
            const SizedBox(height: 8),
            Text(
              'From your chat: ${_formatShortDate(widget.initialCustomStart!)} '
              '– ${_formatShortDate(widget.initialCustomEnd!)}',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                color: Colors.grey[600],
              ),
            ),
          ],
          const SizedBox(height: 20),

          // Format
          const Text(
            'Format',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _formatCard(
                ReportFormat.pdf,
                Icons.picture_as_pdf_rounded,
                'PDF',
                'Ready to print & share',
                Colors.red,
              ),
              const SizedBox(width: 12),
              _formatCard(
                ReportFormat.csv,
                Icons.table_chart_rounded,
                'CSV',
                'Open in Excel / Sheets',
                Colors.green,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Error
          if (_errorMsg != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _errorMsg!,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: Colors.red,
                ),
              ),
            ),

          // Export button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _export,
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download_rounded, size: 18),
              label: Text(
                _isLoading ? 'Generating report...' : 'Export Now',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A2E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _periodChip(ReportPeriod period, String label) {
    final isSelected = _period == period;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _period = period),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF1A1A2E)
                : Colors.grey[100],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF1A1A2E)
                  : Colors.grey[300]!,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : Colors.grey[700],
            ),
          ),
        ),
      ),
    );
  }

  Widget _formatCard(
    ReportFormat format,
    IconData icon,
    String title,
    String subtitle,
    Color color,
  ) {
    final isSelected = _format == format;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _format = format),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: 0.08)
                : Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : Colors.grey[300]!,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  color: isSelected ? color : Colors.grey, size: 24),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? color : Colors.grey[700],
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}