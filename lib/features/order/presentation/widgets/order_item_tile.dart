import 'package:flutter/material.dart';
import '../../../../shared/models/order_model.dart';
import '../../../../core/theme/app_theme.dart';

class OrderItemTile extends StatelessWidget {
  final OrderItem item;
  const OrderItemTile({super.key, required this.item});

  Color _statusColor(OrderItemStatus s) {
    switch (s) {
      case OrderItemStatus.pending:   return AppColors.reserved;
      case OrderItemStatus.preparing: return AppColors.orderPreparing;
      case OrderItemStatus.ready:     return AppColors.orderReady;
      case OrderItemStatus.served:    return AppColors.available;
      case OrderItemStatus.cancelled: return AppColors.textHint;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(item.status);
    return ListTile(
      dense: true,
      leading: Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6)),
        child: Center(child: Text('${item.quantity}',
          style: TextStyle(
            fontFamily: 'Poppins', fontWeight: FontWeight.w700,
            fontSize: 13, color: color))),
      ),
      title: Text(item.menuItemName,
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
      subtitle: item.specialRequests != null
          ? Text('⚡ ${item.specialRequests}',
              style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 11, color: AppColors.reserved))
          : null,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('Rp ${item.subtotal.toStringAsFixed(0)}',
            style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6)),
            child: Text(item.status.name,
              style: TextStyle(
                fontFamily: 'Poppins', fontSize: 10,
                fontWeight: FontWeight.w600, color: color)),
          ),
        ],
      ),
    );
  }
}