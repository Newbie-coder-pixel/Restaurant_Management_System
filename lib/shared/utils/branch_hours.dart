// Whether a branch is currently within its operating hours.
//
// This is a UX-convenience check ONLY (it trusts the device's local clock,
// which a customer fully controls) — it exists so the QR menu screen can
// show a friendly "we're closed" state instead of a raw error. The
// authoritative, unbypassable gate lives server-side in Postgres:
// enforce_branch_open_for_order_insert / ..._for_order_item_insert
// (see supabase/migrations/20260804000000_enforce_branch_hours_on_orders.sql),
// which evaluates Asia/Jakarta server time and rejects the insert outright.
bool isBranchOpen({
  required String? openingTime,
  required String? closingTime,
  DateTime? now,
}) {
  if (openingTime == null || closingTime == null) return true;
  try {
    final n = now ?? DateTime.now();
    final openMin = _minutesOf(openingTime);
    final closeMin = _minutesOf(closingTime);
    final nowMin = n.hour * 60 + n.minute;
    // Overnight window, e.g. 10:00–01:00.
    if (closeMin < openMin) return nowMin >= openMin || nowMin < closeMin;
    return nowMin >= openMin && nowMin < closeMin;
  } catch (_) {
    return true;
  }
}

int _minutesOf(String hhmm) {
  final parts = hhmm.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

/// "08:00" from "08:00:00" or "08:00" — for display only.
String formatHhMm(String? raw) {
  if (raw == null) return '?';
  final parts = raw.split(':');
  if (parts.length < 2) return raw;
  return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
}
