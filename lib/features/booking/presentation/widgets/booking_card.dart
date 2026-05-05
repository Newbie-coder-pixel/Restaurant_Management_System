import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../shared/models/booking_model.dart';
import '../../../../core/theme/app_theme.dart';

class BookingCard extends StatelessWidget {
  final BookingModel booking;
  final Map<String, dynamic>? tableData;
  final Color statusColor;
  final void Function(BookingStatus) onStatusChange;
  /// Dipanggil khusus untuk pembatalan — membuka dialog catatan dulu.
  /// Menerima [notes] yang diisi staff, lalu caller update status + simpan notes.
  final void Function(String notes) onCancel;
  final VoidCallback? onEdit;

  const BookingCard({
    super.key,
    required this.booking,
    this.tableData,
    required this.statusColor,
    required this.onStatusChange,
    required this.onCancel,
    this.onEdit,
  });

  String _sourceIcon(BookingSource s) {
    switch (s) {
      case BookingSource.app:       return '📱';
      case BookingSource.website:   return '🌐';
      case BookingSource.aiChatbot: return '🤖';
      case BookingSource.phone:     return '📞';
      case BookingSource.walkIn:    return '🚶';
      case BookingSource.whatsapp:  return '💬';
    }
  }

  String _sourceLabel(BookingSource s) {
    switch (s) {
      case BookingSource.app:       return 'App';
      case BookingSource.website:   return 'Website';
      case BookingSource.aiChatbot: return 'AI Chatbot';
      case BookingSource.phone:     return 'Telepon';
      case BookingSource.walkIn:    return 'Walk-in';
      case BookingSource.whatsapp:  return 'WhatsApp';
    }
  }

  String _statusLabel(BookingStatus s) {
    switch (s) {
      case BookingStatus.pending:    return 'Menunggu';
      case BookingStatus.confirmed:  return 'Konfirmasi';
      case BookingStatus.seated:     return 'Sudah Duduk';
      case BookingStatus.cancelled:  return 'Dibatalkan';
      case BookingStatus.noShow:     return 'Tidak Hadir';
      case BookingStatus.completed:  return 'Selesai';
      case BookingStatus.waitlisted: return 'Waitlist';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tableNum      = tableData?['table_number']?.toString();
    final tableCapacity = tableData?['capacity']?.toString();
    final tableFloor    = tableData?['floor_level']?.toString();
    final isFinished    = booking.status == BookingStatus.cancelled ||
        booking.status == BookingStatus.noShow ||
        booking.status == BookingStatus.completed;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Header: nama + status ───────────────────────
          Row(children: [
            CircleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              child: Text(booking.customerName[0].toUpperCase(),
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(booking.customerName,
                      style: AppTextStyles.body
                          .copyWith(fontWeight: FontWeight.w600)),
                  Text(
                      '${booking.guestCount} orang • '
                      '${_sourceIcon(booking.source)} ${_sourceLabel(booking.source)}',
                      style: AppTextStyles.caption),
                ],
              ),
            ),
            if (!isFinished && onEdit != null)
              IconButton(
                icon: const Icon(Icons.edit_outlined,
                    size: 18, color: AppColors.textSecondary),
                tooltip: 'Edit booking',
                onPressed: onEdit,
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: statusColor),
              ),
              child: Text(_statusLabel(booking.status),
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: statusColor)),
            ),
          ]),

          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // ── Info row: waktu, durasi, HP, email ──────────
          Wrap(
            spacing: 12, runSpacing: 6,
            children: [
              _infoChip(Icons.access_time, booking.bookingTime.length >= 5
                  ? booking.bookingTime.substring(0, 5)
                  : booking.bookingTime),
              _infoChip(Icons.timer_outlined, '${booking.durationMinutes} mnt'),
              if (booking.customerPhone != null)
                _infoChip(Icons.phone_outlined, booking.customerPhone!),
              if (booking.customerEmail != null)
                _infoChip(Icons.email_outlined, booking.customerEmail!),
            ],
          ),

          // ── Indikator waitlist tanpa meja ───────────────
          if (booking.status == BookingStatus.waitlisted && tableNum == null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF3E5F5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF7B1FA2).withValues(alpha: 0.4)),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.hourglass_empty_outlined,
                    size: 13, color: Color(0xFF7B1FA2)),
                SizedBox(width: 6),
                Text('Menunggu slot meja tersedia',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF7B1FA2))),
              ]),
            ),
          ],

          // ── Info meja ───────────────────────────────────
          if (tableNum != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.table_restaurant_outlined,
                    size: 14, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                    'Meja $tableNum'
                    '${tableCapacity != null ? ' • Kapasitas $tableCapacity org' : ''}'
                    '${tableFloor != null ? ' • Lt. $tableFloor' : ''}',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.primary)),
              ]),
            ),
          ],

          // ── Kode konfirmasi ─────────────────────────────
          if (booking.confirmationCode.isNotEmpty) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () {
                Clipboard.setData(
                    ClipboardData(text: booking.confirmationCode));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Kode konfirmasi disalin'),
                    duration: Duration(seconds: 1)));
              },
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.confirmation_number_outlined,
                    size: 13, color: AppColors.textHint),
                const SizedBox(width: 4),
                Text('# ${booking.confirmationCode}',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        color: AppColors.textHint)),
                const SizedBox(width: 4),
                const Icon(Icons.copy, size: 11, color: AppColors.textHint),
              ]),
            ),
          ],

          // ── Special requests ────────────────────────────
          if (booking.specialRequests != null &&
              booking.specialRequests!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: Colors.orange.withValues(alpha: 0.3))),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.notes_outlined,
                      size: 14, color: Colors.orange),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(booking.specialRequests!,
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: Colors.deepOrange))),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),

          // ── Action buttons ──────────────────────────────
          if (!isFinished)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: _buildActions(context),
            ),
        ]),
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    final buttons = <Widget>[];
    switch (booking.status) {
      case BookingStatus.waitlisted:
        buttons.add(_actionBtn(
            'Promote ke Pending', const Color(0xFF7B1FA2), BookingStatus.pending,
            icon: Icons.arrow_upward_outlined));
        buttons.add(const SizedBox(width: 6));
        buttons.add(_cancelBtn(context));
        break;
      case BookingStatus.pending:
        buttons.add(_actionBtn(
            'Konfirmasi', AppColors.available, BookingStatus.confirmed));
        buttons.add(const SizedBox(width: 6));
        buttons.add(_cancelBtn(context));
        break;
      case BookingStatus.confirmed:
        buttons.add(
            _actionBtn('Dudukkan', AppColors.primary, BookingStatus.seated));
        buttons.add(const SizedBox(width: 6));
        buttons.add(_cancelBtn(context));
        break;
      case BookingStatus.seated:
        buttons.add(
            _actionBtn('Selesai', AppColors.primary, BookingStatus.completed,
                icon: Icons.check_circle_outline));
        break;
      default:
        break;
    }
    return buttons;
  }

  /// Tombol "Batalkan" yang membuka dialog catatan sebelum konfirmasi
  Widget _cancelBtn(BuildContext context) => ElevatedButton.icon(
        onPressed: () => _showCancelDialog(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: const SizedBox.shrink(),
        label: const Text('Batalkan'),
      );

  Future<void> _showCancelDialog(BuildContext context) async {
    final notesCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.cancel_outlined, color: Color(0xFFE94560), size: 20),
          SizedBox(width: 8),
          Text('Batalkan Reservasi',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            'Anda akan membatalkan reservasi atas nama '
            '${booking.customerName}.',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: notesCtrl,
            maxLines: 3,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Alasan pembatalan *',
              labelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
              hintText: 'Contoh: Tamu tidak hadir, pembatalan mendadak...',
              hintStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: Colors.black38),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Kembali',
                style: TextStyle(fontFamily: 'Poppins', color: Colors.black54)),
          ),
          StatefulBuilder(
            builder: (ctx2, setLocal) => ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE94560),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                if (notesCtrl.text.trim().isEmpty) {
                  // Shake hint — highlight field
                  setLocal(() {});
                  ScaffoldMessenger.of(ctx2).showSnackBar(const SnackBar(
                    content: Text('Alasan pembatalan wajib diisi'),
                    backgroundColor: Colors.orange,
                    duration: Duration(seconds: 2),
                  ));
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Konfirmasi Batal',
                  style: TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      onCancel(notesCtrl.text.trim());
    }
    notesCtrl.dispose();
  }

  Widget _infoChip(IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(label, style: AppTextStyles.caption),
        ],
      );

  Widget _actionBtn(String label, Color color, BookingStatus status,
          {IconData? icon}) =>
      ElevatedButton.icon(
        onPressed: () => onStatusChange(status),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              fontWeight: FontWeight.w600),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: icon != null ? Icon(icon, size: 14) : const SizedBox.shrink(),
        label: Text(label),
      );
}