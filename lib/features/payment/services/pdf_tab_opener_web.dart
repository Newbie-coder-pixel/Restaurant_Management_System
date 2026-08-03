// lib/features/payment/services/pdf_tab_opener_web.dart
// ─────────────────────────────────────────────────────────────────────────────
// WEB implementation: opens the receipt PDF directly in a new browser tab via
// the browser's native PDF viewer, instead of Printing.layoutPdf's print
// dialog. Clicking Receipt should just show the receipt — printing or saving
// it is then the browser viewer's own toolbar action, not something forced
// on the customer/cashier immediately.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

Future<void> openPdfInNewTab(Uint8List bytes, String fileName) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/pdf'),
  );
  final url = web.URL.createObjectURL(blob);
  web.window.open(url, '_blank');
  // The new tab has its own reference to the blob once loaded, so the object
  // URL can be revoked shortly after without breaking the view there — this
  // just stops it from leaking memory across a long cashier/KDS shift where
  // many receipts get opened.
  Timer(const Duration(seconds: 60), () => web.URL.revokeObjectURL(url));
}
