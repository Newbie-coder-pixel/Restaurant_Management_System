import 'package:flutter/material.dart';
import '../../../../shared/models/order_model.dart';
import '../../../../core/theme/app_theme.dart';

class OrderItemTile extends StatelessWidget {
  final OrderItem item;
  const OrderItemTile({super.key, required this.item});

  Color _statusColor(OrderItemStatus s) {
    switch (s) {
      case OrderItemStatus.pending:   return const Color(0xFF7C3AED);
      case OrderItemStatus.preparing: return AppColors.orderPreparing;
      case OrderItemStatus.ready:     return AppColors.orderReady;
      case OrderItemStatus.served:    return AppColors.available;
      case OrderItemStatus.cancelled: return AppColors.textHint;
    }
  }

  String _statusLabel(OrderItemStatus s) {
    switch (s) {
      case OrderItemStatus.pending:   return 'Antri';
      case OrderItemStatus.preparing: return 'Dimasak';
      case OrderItemStatus.ready:     return 'Siap';
      case OrderItemStatus.served:    return 'Tersaji';
      case OrderItemStatus.cancelled: return 'Batal';
    }
  }

  IconData _statusIcon(OrderItemStatus s) {
    switch (s) {
      case OrderItemStatus.pending:   return Icons.hourglass_top_outlined;
      case OrderItemStatus.preparing: return Icons.outdoor_grill_outlined;
      case OrderItemStatus.ready:     return Icons.dining_outlined;
      case OrderItemStatus.served:    return Icons.check_circle_outline;
      case OrderItemStatus.cancelled: return Icons.cancel_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(item.status);
    final hasNotes = item.specialRequests != null && item.specialRequests!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Qty badge
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8)),
          child: Center(child: Text('${item.quantity}',
            style: TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w800,
              fontSize: 13, color: color)))),

        const SizedBox(width: 10),

        // Name + notes
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.menuItemName,
              style: const TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
            if (hasNotes) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3))),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.edit_note, size: 12, color: Colors.amber),
                  const SizedBox(width: 4),
                  Flexible(child: Text(item.specialRequests!,
                    style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 11,
                      color: Colors.amber, fontWeight: FontWeight.w500))),
                ])),
            ],
          ],
        )),

        const SizedBox(width: 10),

        // Price + status
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('Rp ${item.subtotal.toStringAsFixed(0)}',
            style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withValues(alpha: 0.3))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_statusIcon(item.status), size: 10, color: color),
              const SizedBox(width: 3),
              Text(_statusLabel(item.status),
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 10,
                  fontWeight: FontWeight.w700, color: color)),
            ])),
        ]),
      ]),
    );
  }
}