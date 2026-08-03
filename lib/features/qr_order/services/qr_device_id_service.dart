import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Identifies the browser/device that started a QR order, so a table's active
/// order can be "owned" by whichever device created it (see
/// supabase/migrations/20260803010000_qr_order_device_id.sql). The id is a
/// random UUID persisted in local storage (SharedPreferences — backed by
/// browser localStorage on web) the first time it's read, and reused after
/// that for as long as the storage isn't cleared.
class QrDeviceIdService {
  static const _prefsKey = 'qr_device_id';
  static const _uuid = Uuid();

  static String? _cached;

  static Future<String> getDeviceId() async {
    if (_cached != null) return _cached!;

    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_prefsKey);
    if (id == null || id.isEmpty) {
      id = _uuid.v4();
      await prefs.setString(_prefsKey, id);
    }
    _cached = id;
    return id;
  }
}
