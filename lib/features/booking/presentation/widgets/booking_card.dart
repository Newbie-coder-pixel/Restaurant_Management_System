import 'package:flutter/material.dart';
import '../../../../shared/models/booking_model.dart';
import '../../../../core/theme/app_theme.dart';

class BookingCard extends StatelessWidget {
  final BookingModel booking;
  final Color statusColor;
  final void Function(BookingStatus) onStatusChange;

  const BookingCard({
    super.key,
    required this.booking,
    required this.statusColor,
    required this.onStatusChange,
  });

  String _sourceIcon(BookingSource s) {
    switch (s) {
      case BookingSource.app:        return '📱';
      case BookingSource.website:    return '🌐';
      case BookingSource.aiChatbot:  return '🤖';
      case BookingSource.phone:      return '📞';
      case BookingSource.walkIn:     return '🚶';
      case BookingSource.whatsapp:   return '💬';
    }
  }

  // ✅ Method yang hilang — inilah penyebab error
  String _sourceLabel(BookingSource s) {
    switch (s) {
      case BookingSource.app:        return 'App';
      case BookingSource.website:    return 'Website';
      case BookingSource.aiChatbot:  return 'AI Chatbot';
      case BookingSource.phone:      return 'Telepon';
      case BookingSource.walkIn:     return 'Walk-in';
      case BookingSource.whatsapp:   return 'WhatsApp';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              child: Text(booking.customerName[0].toUpperCase(),
                style: const TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                  color: AppColors.primary)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(booking.customerName,
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
              Text('${booking.guestCount} orang • ${_sourceIcon(booking.source)} ${_sourceLabel(booking.source)}',
                style: AppTextStyles.caption),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: statusColor),
              ),
              child: Text(booking.status.name,
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 11,
                  fontWeight: FontWeight.w600, color: statusColor)),
            ),
          ]),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(children: [
            _infoChip(Icons.access_time, booking.bookingTime),
            const SizedBox(width: 12),
            _infoChip(Icons.timer_outlined, '${booking.durationMinutes} mnt'),
            if (booking.customerPhone != null) ...[
              const SizedBox(width: 12),
              _infoChip(Icons.phone_outlined, booking.customerPhone!),
            ],
          ]),
          if (booking.specialRequests != null &&
              booking.specialRequests!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.notes_outlined, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Expanded(child: Text(booking.specialRequests!, style: AppTextStyles.caption)),
            ]),
          ],
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (booking.status == BookingStatus.pending)
              _actionBtn('Konfirmasi', AppColors.available, BookingStatus.confirmed),
            if (booking.status == BookingStatus.confirmed)
              _actionBtn('Dudukkan', AppColors.primary, BookingStatus.seated),
            if (booking.status == BookingStatus.pending ||
                booking.status == BookingStatus.confirmed) ...[
              const SizedBox(width: 8),
              _actionBtn('Batalkan', AppColors.accent, BookingStatus.cancelled),
            ],
            if (booking.status == BookingStatus.seated)
              _actionBtn('Selesai', AppColors.primary, BookingStatus.completed),
          ]),
        ]),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) => Row(children: [
    Icon(icon, size: 14, color: AppColors.textSecondary),
    const SizedBox(width: 4),
    Text(label, style: AppTextStyles.caption),
  ]);

  Widget _actionBtn(String label, Color color, BookingStatus status) =>
    ElevatedButton(
      onPressed: () => onStatusChange(status),
      style: ElevatedButton.styleFrom(
        backgroundColor: color, foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(
          fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
}