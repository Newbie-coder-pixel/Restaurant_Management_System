// lib/features/payment/services/pdf_tab_opener_stub.dart
// Non-web (Android/iOS/desktop): there's no browser tab to open the PDF in,
// so fall back to the platform's native print/share sheet.
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

Future<void> openPdfInNewTab(Uint8List bytes, String fileName) {
  return Printing.layoutPdf(
    onLayout: (_) async => bytes,
    name: fileName,
    format: PdfPageFormat.roll80,
  );
}
