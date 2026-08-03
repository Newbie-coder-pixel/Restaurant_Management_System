// lib/features/payment/services/receipt_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Generates & prints a PDF receipt for a paid order.
// Layout follows the 80mm thermal paper width (PdfPageFormat.roll80), with a
// promotional QR block for the customer app at the bottom, separate from the
// price breakdown — so it isn't mistaken for part of the amount due.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../shared/models/order_model.dart';
import '../models/midtrans_model.dart';

// Conditional import:
//   • Web    → pdf_tab_opener_web.dart  (opens the PDF in a new tab)
//   • Mobile → pdf_tab_opener_stub.dart (native print/share sheet)
import 'pdf_tab_opener_stub.dart'
    if (dart.library.js_interop) 'pdf_tab_opener_web.dart';

final _currency = NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp ',
  decimalDigits: 0,
);

class ReceiptService {
  /// Fetches the branch data + the current payment method from Supabase, builds
  /// the receipt PDF, then opens it in a new browser tab (web) or the native
  /// print/share sheet (mobile/desktop).
  static Future<void> printReceipt({
    required OrderModel order,
    String? cashierName,
  }) async {
    final sb = Supabase.instance.client;

    Map<String, dynamic>? branch;
    try {
      branch = await sb
          .from('branches')
          .select('name, address, phone')
          .eq('id', order.branchId)
          .maybeSingle();
    } catch (_) {
      branch = null; // The receipt still prints without branch details if this fails
    }

    String? paymentMethod;
    try {
      final row = await sb
          .from('orders')
          .select('payment_method')
          .eq('id', order.id)
          .maybeSingle();
      paymentMethod = row?['payment_method'] as String?;
    } catch (_) {
      paymentMethod = null;
    }

    final pdf = await _buildDocument(
      order: order,
      branchName: branch?['name'] as String? ?? AppConfig.appName,
      branchAddress: branch?['address'] as String?,
      branchPhone: branch?['phone'] as String?,
      paymentMethod: paymentMethod,
      cashierName: cashierName,
    );

    final bytes = await pdf.save();
    await openPdfInNewTab(bytes, 'Receipt-${order.orderNumber}');
  }

  static Future<pw.Document> _buildDocument({
    required OrderModel order,
    required String branchName,
    String? branchAddress,
    String? branchPhone,
    String? paymentMethod,
    String? cashierName,
  }) async {
    final pdf = pw.Document();
    const dashed = pw.BoxDecoration(
      border: pw.Border(
        top: pw.BorderSide(
          color: PdfColors.grey600,
          width: 0.75,
          style: pw.BorderStyle.dashed,
        ),
      ),
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80.copyWith(
          marginLeft: 14,
          marginRight: 14,
          marginTop: 14,
          marginBottom: 14,
        ),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // ── Branch header ──────────────────────────────────────
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(branchName,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                          fontSize: 13, fontWeight: pw.FontWeight.bold)),
                  if (branchAddress != null && branchAddress.isNotEmpty)
                    pw.Text(branchAddress,
                        textAlign: pw.TextAlign.center,
                        style: const pw.TextStyle(
                            fontSize: 8, color: PdfColors.grey700)),
                  if (branchPhone != null && branchPhone.isNotEmpty)
                    pw.Text(branchPhone,
                        textAlign: pw.TextAlign.center,
                        style: const pw.TextStyle(
                            fontSize: 8, color: PdfColors.grey700)),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Divider(thickness: 0.75, color: PdfColors.black),

              // ── Order meta ──────────────────────────────────────────
              _metaRow('Order No.', order.orderNumber),
              if (order.tableNumber != null)
                _metaRow('Table', order.tableNumber!),
              _metaRow('Date', _formatDate(order.createdAt)),
              if (cashierName != null) _metaRow('Cashier', cashierName),

              pw.SizedBox(height: 4),
              pw.Divider(thickness: 0.5, color: PdfColors.grey600),

              // ── Items ──────────────────────────────────────────────
              ...order.items.map((item) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        pw.Row(
                          mainAxisAlignment:
                              pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Expanded(
                              child: pw.Text(item.menuItemName,
                                  style: pw.TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: pw.FontWeight.bold)),
                            ),
                            pw.Text(_fmtRp(item.subtotal),
                                style: const pw.TextStyle(fontSize: 9.5)),
                          ],
                        ),
                        pw.Text(
                            '${item.quantity} x ${_fmtRp(item.unitPrice)}',
                            style: const pw.TextStyle(
                                fontSize: 8, color: PdfColors.grey700)),
                      ],
                    ),
                  )),

              pw.SizedBox(height: 4),
              pw.Divider(thickness: 0.5, color: PdfColors.grey600),

              // ── Totals ──────────────────────────────────────────────
              _totalRow('Subtotal', order.subtotal),
              _totalRow('PB1 (10%)', order.pb1Amount),
              _totalRow('Service (3%)', order.serviceChargeAmount),
              if (order.discountAmount > 0)
                _totalRow('Discount', -order.discountAmount),
              if (order.overtimeCharge > 0)
                _totalRow('Extra Dining Time',
                    order.overtimeCharge.toDouble()),
              pw.SizedBox(height: 3),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TOTAL',
                      style: pw.TextStyle(
                          fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  pw.Text(_fmtRp(order.totalAmountWithOvertime),
                      style: pw.TextStyle(
                          fontSize: 12, fontWeight: pw.FontWeight.bold)),
                ],
              ),

              pw.SizedBox(height: 6),
              pw.Text(
                paymentMethod != null
                    ? 'Paid - ${MidtransPaymentMethod.label(paymentMethod)}'
                    : 'Paid',
                style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
              ),
              pw.SizedBox(height: 6),
              pw.Center(
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 12, vertical: 3),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.blue900, width: 1.2),
                    borderRadius: pw.BorderRadius.circular(2),
                  ),
                  child: pw.Text('PAID',
                      style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue900,
                          letterSpacing: 1.5)),
                ),
              ),

              // ── Customer app promo block (separate from the fiscal receipt) ──
              pw.SizedBox(height: 10),
              pw.Container(decoration: dashed, padding: const pw.EdgeInsets.only(top: 10)),
              pw.Center(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text('Order online & book a table next time?',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                            fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    pw.Text(
                        'Scan to check order history, book a table, chat with AI',
                        textAlign: pw.TextAlign.center,
                        style: const pw.TextStyle(
                            fontSize: 7.5, color: PdfColors.grey700)),
                    pw.SizedBox(height: 8),
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: AppConfig.customerAppUrl,
                      width: 70,
                      height: 70,
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      AppConfig.customerAppUrl
                          .replaceFirst('https://', '')
                          .replaceFirst('http://', ''),
                      style: pw.TextStyle(
                          fontSize: 8, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.Text('Thank you!',
                    style: const pw.TextStyle(
                        fontSize: 8, color: PdfColors.grey700)),
              ),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  static pw.Widget _metaRow(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label,
                style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
            pw.Text(value, style: const pw.TextStyle(fontSize: 8.5)),
          ],
        ),
      );

  static pw.Widget _totalRow(String label, double amount) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
            pw.Text(amount < 0 ? '- ${_fmtRp(amount.abs())}' : _fmtRp(amount),
                style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
      );

  static String _fmtRp(double amount) => _currency.format(amount);

  static String _formatDate(DateTime d) =>
      DateFormat('dd/MM/yy HH:mm').format(d);
}
