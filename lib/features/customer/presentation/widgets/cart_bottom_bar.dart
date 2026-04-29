import 'package:flutter/material.dart';
import '../../../customer/providers/cart_provider.dart';

class CartBottomBar extends StatelessWidget {
  final CartState cart;
  final VoidCallback onCheckout;
  final bool show;
  const CartBottomBar({super.key, required this.cart, required this.onCheckout, this.show = true});

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();
    return Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
    decoration: BoxDecoration(
      color: const Color(0xFF1A1A2E),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      boxShadow: [BoxShadow(
        color: Colors.black.withValues(alpha: 0.15),
        blurRadius: 20, offset: const Offset(0, -4))]),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFE94560),
          borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.shopping_cart_outlined, color: Colors.white, size: 18),
          const SizedBox(width: 4),
          Text('${cart.itemCount}',
            style: const TextStyle(fontFamily: 'Poppins',
              color: Colors.white, fontWeight: FontWeight.w700)),
        ])),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Rp ${_fmt(cart.subtotal)}',
          style: const TextStyle(fontFamily: 'Poppins',
            color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
        Text('${cart.itemCount} item • +PPN 11%',
          style: const TextStyle(fontFamily: 'Poppins',
            color: Colors.white54, fontSize: 11)),
      ])),
      ElevatedButton(
        onPressed: onCheckout,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFE94560),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        child: const Text('Checkout →',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700))),
    ]));

  }

  String _fmt(double v) {
    final s = v.toStringAsFixed(0);
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write('.');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }
}