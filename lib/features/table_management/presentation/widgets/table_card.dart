import 'package:flutter/material.dart';
import '../../../../shared/models/table_model.dart';
import '../../../../core/theme/app_theme.dart';

class TableCard extends StatelessWidget {
  final TableModel table;
  final void Function(TableStatus) onStatusChange;

  const TableCard({super.key, required this.table, required this.onStatusChange});

  void _showMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _StatusBottomSheet(table: table, onStatusChange: onStatusChange),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = table.status.color;
    return GestureDetector(
      onTap: () => _showMenu(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.15),
              blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          _buildTableIcon(),
          const SizedBox(height: 8),
          Text('Meja ${table.tableNumber}',
            style: TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w700,
              fontSize: 15, color: color)),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.person_outline, size: 12, color: AppColors.textSecondary),
            const SizedBox(width: 3),
            Text('${table.capacity} orang',
              style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
          ]),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(12)),
            child: Text(table.status.label,
              style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 10,
                fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        ]),
      ),
    );
  }

  Widget _buildTableIcon() {
    final color = table.status.color;
    switch (table.shape) {
      case TableShape.round:
        return Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.2),
            border: Border.all(color: color, width: 2)),
          child: Icon(Icons.table_restaurant, color: color, size: 22),
        );
      case TableShape.rectangle:
        return Container(
          width: 54, height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: color.withValues(alpha: 0.2),
            border: Border.all(color: color, width: 2)),
          child: Icon(Icons.table_restaurant, color: color, size: 20),
        );
      case TableShape.square:
        return Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: color.withValues(alpha: 0.2),
            border: Border.all(color: color, width: 2)),
          child: Icon(Icons.table_restaurant, color: color, size: 22),
        );
    }
  }
}

class _StatusBottomSheet extends StatelessWidget {
  final TableModel table;
  final void Function(TableStatus) onStatusChange;
  const _StatusBottomSheet({required this.table, required this.onStatusChange});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Meja ${table.tableNumber}', style: AppTextStyles.heading3),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: table.status.color, borderRadius: BorderRadius.circular(12)),
            child: Text(table.status.label,
              style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 12,
                fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        ]),
        const SizedBox(height: 8),
        Text('Kapasitas: ${table.capacity} orang', style: AppTextStyles.bodySecondary),
        const SizedBox(height: 20),
        const Text('Ubah Status:',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 12),
        ...TableStatus.values.where((s) => s != table.status).map((s) => ListTile(
          leading: CircleAvatar(backgroundColor: s.color, radius: 8),
          title: Text(s.label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 14)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.pop(context);
            onStatusChange(s);
          },
        )),
      ]),
    );
  }
}