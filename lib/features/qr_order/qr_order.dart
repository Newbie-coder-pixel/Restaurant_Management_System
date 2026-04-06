// lib/features/qr_order/qr_order.dart
// Barrel export untuk seluruh feature qr_order

export 'models/qr_order_model.dart';
// MenuItem ada di qr_cart_provider dan di-re-export oleh qr_menu_provider.
// Hide dari qr_cart_provider di sini supaya tidak ambiguous.
export 'providers/qr_cart_provider.dart' hide MenuItem;
export 'providers/qr_menu_provider.dart'; // exposes MenuItem + QrMenuState + qrMenuProvider
export 'data/qr_order_repository.dart';
export 'presentation/qr_menu_screen.dart';
export 'presentation/qr_cart_screen.dart';
export 'presentation/qr_payment_screen.dart';
export 'presentation/qr_order_tracker_screen.dart';