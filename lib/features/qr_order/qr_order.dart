// lib/features/qr_order/qr_order.dart
// Barrel export for the entire qr_order feature

export 'models/qr_order_model.dart';
// MenuItem exists in qr_cart_provider and is re-exported by qr_menu_provider.
// Hidden from qr_cart_provider here so it doesn't become ambiguous.
export 'providers/qr_cart_provider.dart' hide MenuItem;
export 'providers/qr_menu_provider.dart'; // exposes MenuItem + QrMenuState + qrMenuProvider
export 'data/qr_order_repository.dart';
export 'presentation/qr_menu_screen.dart';
export 'presentation/qr_cart_screen.dart';
export 'presentation/qr_payment_screen.dart';
export 'presentation/qr_order_tracker_screen.dart';