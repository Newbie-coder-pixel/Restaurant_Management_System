import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../shared/models/booking_model.dart';
import '../../../../core/theme/app_theme.dart';

class BookingCard extends StatelessWidget {
  final BookingModel booking;
  final Map<String, dynamic>? tableData;
  final Color statusColor;
  final void Function(BookingStatus) onStatusChange;
  final VoidCallback? onEdit;
  final Future<void> Function()? onMarkDpPaid;
  final Map<String, dynamic>? rawData;

  const BookingCard({
    super.key,
    required this.booking,
    this.tableData,
    required this.statusColor,
    required this.onStatusChange,
    this.onEdit,
    this.onMarkDpPaid,
    this.rawData,
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
      case BookingStatus.pending:   return 'Menunggu';
      case BookingStatus.confirmed: return 'Konfirmasi';
      case BookingStatus.seated:    return 'Sudah Duduk';
      case BookingStatus.cancelled: return 'Dibatalkan';
      case BookingStatus.noShow:    return 'Tidak Hadir';
      case BookingStatus.completed: return 'Selesai';
    }
  }

  String _formatRupiah(int amount) {
    final str = amount.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write('.');
      buffer.write(str[i]);
    }
    return 'Rp ${buffer.toString()}';
  }

  @override
  Widget build(BuildContext context) {
    final tableNum      = tableData?['table_number']?.toString();
    final tableCapacity = tableData?['capacity']?.toString();
    final tableFloor    = tableData?['floor_level']?.toString();
    final isFinished    = booking.status == BookingStatus.cancelled ||
        booking.status == BookingStatus.noShow ||
        booking.status == BookingStatus.completed;

    // ── Baca data DP dari rawData ──
    final depositAmount  = rawData?['deposit_amount'] as int? ?? 0;
    final depositStatus  = rawData?['deposit_status'] as String? ?? 'not_required';
    final dpPerOrang     = rawData?['dp_per_orang'] as int? ?? 0;
    final depositNotes   = rawData?['deposit_notes'] as String?;
    final depositPaidAt  = rawData?['deposit_paid_at'] as String?;
    final hasDeposit     = depositAmount > 0;
    final isDpPaid       = depositStatus == 'paid' || depositStatus == 'applied';
    final isDpPending    = depositStatus == 'pending';
    final isDpUploaded   = depositStatus == 'uploaded'; // bukti sudah diupload, menunggu konfirmasi staff

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

          // ── Info row: waktu, durasi, HP ─────────────────
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
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3))),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.notes_outlined, size: 14, color: Colors.orange),
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

          // ── Section DP ──────────────────────────────────
          if (hasDeposit) ...[
            const SizedBox(height: 10),
            _buildDpSection(
              context,
              depositAmount,
              depositStatus,
              dpPerOrang,
              depositNotes,
              depositPaidAt,
              isDpPaid,
              isDpPending,
              isDpUploaded,
              isFinished,
            ),
          ],

          const SizedBox(height: 12),

          // ── Action buttons ──────────────────────────────
          if (!isFinished)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: _buildActions(),
            ),
        ]),
      ),
    );
  }

  Widget _buildDpSection(
    BuildContext context,
    int depositAmount,
    String depositStatus,
    int dpPerOrang,
    String? depositNotes,
    String? depositPaidAt,
    bool isDpPaid,
    bool isDpPending,
    bool isDpUploaded,
    bool isFinished,
  ) {
    // ── Tentukan warna berdasarkan status ──
    final Color bgColor;
    final Color borderColor;
    final Color iconColor;
    final Color labelColor;
    final IconData statusIcon;
    final String statusText;

    if (isDpPaid) {
      bgColor     = const Color(0xFFE8F5E9);
      borderColor = const Color(0xFF4CAF50);
      iconColor   = const Color(0xFF2E7D32);
      labelColor  = const Color(0xFF2E7D32);
      statusIcon  = Icons.check_circle_outline;
      statusText  = 'DP Sudah Lunas';
    } else if (isDpUploaded) {
      // State baru: bukti sudah diupload, menunggu konfirmasi staff
      bgColor     = const Color(0xFFE3F2FD);
      borderColor = const Color(0xFF1976D2);
      iconColor   = const Color(0xFF1565C0);
      labelColor  = const Color(0xFF1565C0);
      statusIcon  = Icons.hourglass_top_outlined;
      statusText  = 'Bukti Dikirim — Menunggu Konfirmasi';
    } else {
      bgColor     = const Color(0xFFFFF8E1);
      borderColor = const Color(0xFFFFB300);
      iconColor   = const Color(0xFFE65100);
      labelColor  = const Color(0xFFE65100);
      statusIcon  = Icons.payments_outlined;
      statusText  = 'DP Belum Dibayar';
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Baris atas: icon + label + nominal ──
          Row(children: [
            Icon(statusIcon, size: 15, color: iconColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                statusText,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: labelColor),
              ),
            ),
            Text(
              _formatRupiah(depositAmount),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: labelColor),
            ),
          ]),

          // ── Rincian per orang ──
          if (dpPerOrang > 0) ...[
            const SizedBox(height: 2),
            Text(
              '${_formatRupiah(dpPerOrang)} × ${depositAmount ~/ dpPerOrang} orang',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                color: labelColor.withValues(alpha: 0.7)),
            ),
          ],

          // ── Waktu konfirmasi (jika sudah lunas) ──
          if (isDpPaid && depositPaidAt != null) ...[
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.schedule, size: 12, color: labelColor.withValues(alpha: 0.6)),
              const SizedBox(width: 4),
              Text(
                'Dikonfirmasi: ${_formatDateTime(depositPaidAt)}',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: labelColor.withValues(alpha: 0.7)),
              ),
            ]),
          ],

          // ── Catatan DP dari staff ──
          if (depositNotes != null && depositNotes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.sticky_note_2_outlined, size: 12, color: labelColor),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      depositNotes,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        color: labelColor),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Badge: bukti sudah dikirim customer ──
          if (isDpUploaded) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF1976D2).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                    color: const Color(0xFF1976D2).withValues(alpha: 0.3)),
              ),
              child: const Row(children: [
                Icon(Icons.info_outline, size: 13, color: Color(0xFF1565C0)),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Customer sudah mengirim bukti transfer. Periksa dan konfirmasi pembayaran.',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: Color(0xFF1565C0)),
                  ),
                ),
              ]),
            ),
          ],

          // ── Tombol "Tandai DP Lunas" — muncul saat pending ATAU uploaded ──
          if ((isDpPending || isDpUploaded) && !isFinished && onMarkDpPaid != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _confirmMarkDpPaid(context, isDpUploaded),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDpUploaded
                      ? const Color(0xFF1976D2)
                      : const Color(0xFFE65100),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
                icon: Icon(
                  isDpUploaded ? Icons.verified_outlined : Icons.check,
                  size: 14,
                ),
                label: Text(isDpUploaded
                    ? 'Konfirmasi Bukti & Tandai Lunas'
                    : 'Tandai DP Sudah Dibayar'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDateTime(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      const months = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
        'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
      ];
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '${dt.day} ${months[dt.month]} ${dt.year}, $h:$m';
    } catch (_) {
      return raw;
    }
  }

  // Dialog konfirmasi sebelum tandai DP lunas
  Future<void> _confirmMarkDpPaid(BuildContext context, bool hasProof) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(
            hasProof ? Icons.verified_outlined : Icons.payments_outlined,
            color: hasProof ? const Color(0xFF1976D2) : const Color(0xFF4CAF50),
            size: 22,
          ),
          const SizedBox(width: 8),
          const Text('Konfirmasi DP',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        ]),
        content: Text(
          hasProof
              ? 'Bukti transfer dari ${booking.customerName} sudah diterima.\n\n'
                'Konfirmasi dan tandai DP sebagai lunas?'
              : 'Tandai DP dari ${booking.customerName} sebagai sudah dibayar?\n\n'
                'Pastikan pembayaran sudah diterima secara fisik.',
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal',
                style: TextStyle(fontFamily: 'Poppins'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: hasProof
                  ? const Color(0xFF1976D2)
                  : const Color(0xFF4CAF50),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              hasProof ? 'Ya, Konfirmasi' : 'Ya, Sudah Dibayar',
              style: const TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed == true && onMarkDpPaid != null) {
      await onMarkDpPaid!();
    }
  }

  List<Widget> _buildActions() {
    final buttons = <Widget>[];
    switch (booking.status) {
      case BookingStatus.pending:
        buttons.add(_actionBtn(
            'Konfirmasi', AppColors.available, BookingStatus.confirmed));
        buttons.add(const SizedBox(width: 6));
        buttons.add(
            _actionBtn('Batalkan', AppColors.accent, BookingStatus.cancelled));
        break;
      case BookingStatus.confirmed:
        buttons.add(
            _actionBtn('Dudukkan', AppColors.primary, BookingStatus.seated));
        buttons.add(const SizedBox(width: 6));
        buttons.add(_actionBtn(
            'Tidak Hadir', Colors.orange, BookingStatus.noShow,
            icon: Icons.person_off_outlined));
        buttons.add(const SizedBox(width: 6));
        buttons.add(
            _actionBtn('Batalkan', AppColors.accent, BookingStatus.cancelled));
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: icon != null ? Icon(icon, size: 14) : const SizedBox.shrink(),
        label: Text(label),
      );
}