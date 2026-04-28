import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../shared/models/table_model.dart';
import '../../../../core/theme/app_theme.dart';

class TableCard extends StatelessWidget {
  final TableModel table;
  final void Function(TableStatus) onStatusChange;

  const TableCard({super.key, required this.table, required this.onStatusChange});

  void _showMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _StatusBottomSheet(table: table, onStatusChange: onStatusChange),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = table.status.color;
    final isCleaning = table.status == TableStatus.cleaning;

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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
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
            if (isCleaning) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _confirmCleaningDone(context),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4CAF50).withValues(alpha: 0.35),
                        blurRadius: 6, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, size: 12, color: Colors.white),
                      SizedBox(width: 4),
                      Text('Siap Dipakai',
                        style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 10,
                          fontWeight: FontWeight.w700, color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _confirmCleaningDone(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.cleaning_services_rounded,
              color: Color(0xFF4CAF50), size: 20)),
          const SizedBox(width: 10),
          const Text('Meja Siap?',
            style: TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
        ]),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 13,
              color: AppColors.textPrimary, height: 1.5),
            children: [
              const TextSpan(text: 'Tandai '),
              TextSpan(
                text: 'Meja ${table.tableNumber}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
              const TextSpan(text: ' sebagai '),
              const TextSpan(
                text: 'Tersedia',
                style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF4CAF50))),
              const TextSpan(text: '?\n\nPastikan meja sudah bersih dan siap untuk tamu berikutnya.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Belum',
              style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary))),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              onStatusChange(TableStatus.available);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            icon: const Icon(Icons.check_rounded, size: 16),
            label: const Text('Ya, Siap!',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700))),
        ],
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

// ── Model sederhana untuk data booking ──────────────────────────
class _BookingDetail {
  final String customerName;
  final String? customerPhone;
  final String? customerEmail;
  final String bookingDate;
  final String bookingTime;
  final int guestCount;
  final int durationMinutes;
  final String? specialRequests;
  final String? confirmationCode;
  final String status;

  const _BookingDetail({
    required this.customerName,
    this.customerPhone,
    this.customerEmail,
    required this.bookingDate,
    required this.bookingTime,
    required this.guestCount,
    required this.durationMinutes,
    this.specialRequests,
    this.confirmationCode,
    required this.status,
  });

  factory _BookingDetail.fromJson(Map<String, dynamic> j) => _BookingDetail(
    customerName: j['customer_name'] ?? '-',
    customerPhone: j['customer_phone'],
    customerEmail: j['customer_email'],
    bookingDate: j['booking_date'] ?? '-',
    bookingTime: (j['booking_time'] as String? ?? '-').substring(0, 5), // HH:mm
    guestCount: j['guest_count'] ?? 1,
    durationMinutes: j['duration_minutes'] ?? 90,
    specialRequests: j['special_requests'],
    confirmationCode: j['confirmation_code'],
    status: j['status'] ?? '-',
  );
}

// ── Model sederhana untuk data order ────────────────────────────
class _OrderDetail {
  final String orderNumber;
  final String? customerName;
  final String? customerPhone;
  final String status;
  final String paymentStatus;
  final String? paymentMethod;
  final double subtotal;
  final double discountAmount;
  final double taxAmount;
  final double totalAmount;
  final String? notes;
  final DateTime createdAt;
  final List<dynamic> items;

  const _OrderDetail({
    required this.orderNumber,
    this.customerName,
    this.customerPhone,
    required this.status,
    required this.paymentStatus,
    this.paymentMethod,
    required this.subtotal,
    required this.discountAmount,
    required this.taxAmount,
    required this.totalAmount,
    this.notes,
    required this.createdAt,
    required this.items,
  });

  factory _OrderDetail.fromJson(Map<String, dynamic> j) => _OrderDetail(
    orderNumber: j['order_number'] ?? '-',
    customerName: j['customer_name'],
    customerPhone: j['customer_phone'],
    status: j['status'] ?? '-',
    paymentStatus: j['payment_status'] ?? 'unpaid',
    paymentMethod: j['payment_method'],
    subtotal: (j['subtotal'] ?? 0).toDouble(),
    discountAmount: (j['discount_amount'] ?? 0).toDouble(),
    taxAmount: (j['tax_amount'] ?? 0).toDouble(),
    totalAmount: (j['total_amount'] ?? 0).toDouble(),
    notes: j['notes'],
    createdAt: DateTime.tryParse(j['created_at'] ?? '') ?? DateTime.now(),
    items: j['items'] ?? [],
  );
}

// ── Bottom sheet utama ───────────────────────────────────────────
class _StatusBottomSheet extends StatefulWidget {
  final TableModel table;
  final void Function(TableStatus) onStatusChange;
  const _StatusBottomSheet({required this.table, required this.onStatusChange});

  @override
  State<_StatusBottomSheet> createState() => _StatusBottomSheetState();
}

class _StatusBottomSheetState extends State<_StatusBottomSheet> {
  _BookingDetail? _booking;
  _OrderDetail? _order;
  bool _loadingBooking = false;
  bool _loadingOrder = false;

  @override
  void initState() {
    super.initState();
    if (widget.table.status == TableStatus.reserved) {
      _fetchBooking();
    } else if (widget.table.status == TableStatus.occupied) {
      _fetchOrder();
    }
  }

  Future<void> _fetchOrder() async {
    setState(() => _loadingOrder = true);
    try {
      final res = await Supabase.instance.client
          .from('orders')
          .select()
          .eq('table_id', widget.table.id)
          .inFilter('status', ['created', 'confirmed', 'preparing', 'ready', 'served'])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _order = res != null ? _OrderDetail.fromJson(res) : null;
          _loadingOrder = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingOrder = false);
    }
  }

  Future<void> _fetchBooking() async {
    setState(() => _loadingBooking = true);
    try {
      // Ambil booking yang masih aktif (confirmed/pending) untuk meja ini, hari ini
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final res = await Supabase.instance.client
          .from('bookings')
          .select()
          .eq('table_id', widget.table.id)
          .gte('booking_date', today)
          .inFilter('status', ['pending', 'confirmed'])
          .order('booking_date')
          .order('booking_time')
          .limit(1)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _booking = res != null ? _BookingDetail.fromJson(res) : null;
          _loadingBooking = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingBooking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final table = widget.table;
    final color = table.status.color;

    return Padding(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────
          Row(children: [
            Text('Meja ${table.tableNumber}', style: AppTextStyles.heading3),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(12)),
              child: Text(table.status.label,
                style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 12,
                  fontWeight: FontWeight.w600, color: Colors.white)),
            ),
          ]),
          const SizedBox(height: 4),
          Text('Kapasitas: ${table.capacity} orang', style: AppTextStyles.bodySecondary),

          // ── Detail Reservasi ─────────────────────────────────
          if (table.status == TableStatus.reserved) ...[
            const SizedBox(height: 16),
            _buildReservationSection(color),
          ],

          // ── Detail Order / Terisi ─────────────────────────────
          if (table.status == TableStatus.occupied) ...[
            const SizedBox(height: 16),
            _buildOrderSection(color),
          ],

          // ── Ubah Status ──────────────────────────────────────
          const SizedBox(height: 20),
          const Text('Ubah Status:',
            style: TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 12),
          ...TableStatus.values.where((s) => s != table.status).map((s) => ListTile(
            leading: CircleAvatar(backgroundColor: s.color, radius: 8),
            title: Text(s.label,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 14)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.pop(context);
              widget.onStatusChange(s);
            },
          )),
        ],
      ),
    );
  }

  Widget _buildOrderSection(Color color) {
    if (_loadingOrder) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: const Center(
          child: SizedBox(
            height: 20, width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_order == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Icon(Icons.info_outline, color: color, size: 18),
          const SizedBox(width: 8),
          const Text('Tidak ada data order aktif',
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary)),
        ]),
      );
    }

    final o = _order!;
    final payColor = o.paymentStatus == 'paid'
        ? const Color(0xFF4CAF50)
        : const Color(0xFFE94560);
    final payLabel = o.paymentStatus == 'paid' ? 'Lunas' : 'Belum Bayar';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Judul seksi ──
          Row(children: [
            Icon(Icons.receipt_long_rounded, color: color, size: 16),
            const SizedBox(width: 6),
            Text('Detail Order',
              style: TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                fontSize: 13, color: color)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('#${o.orderNumber}',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 10,
                  fontWeight: FontWeight.w600, color: color)),
            ),
          ]),
          const SizedBox(height: 12),

          // ── Info customer ──
          if (o.customerName != null && o.customerName!.isNotEmpty)
            _detailRow(Icons.person_rounded, 'Customer', o.customerName!),
          if (o.customerPhone != null && o.customerPhone!.isNotEmpty)
            _detailRow(Icons.phone_rounded, 'No. HP', o.customerPhone!),

          // ── Waktu order ──
          _detailRow(Icons.access_time_rounded, 'Masuk',
            '${o.createdAt.hour.toString().padLeft(2, '0')}:${o.createdAt.minute.toString().padLeft(2, '0')}'),

          const Divider(height: 16),

          // ── Items (maks 3 item) ──
          if (o.items.isNotEmpty) ...[
            Row(children: [
              const Icon(Icons.fastfood_rounded, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text('Item (${o.items.length})',
                style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
            ]),
            const SizedBox(height: 6),
            ...o.items.take(3).map((item) {
              final name = item['name'] ?? item['menu_name'] ?? '-';
              final qty = item['quantity'] ?? item['qty'] ?? 1;
              final price = (item['price'] ?? item['unit_price'] ?? 0).toDouble();
              return Padding(
                padding: const EdgeInsets.only(left: 22, bottom: 4),
                child: Row(children: [
                  Expanded(
                    child: Text('$qty× $name',
                      style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 12,
                        color: AppColors.textPrimary)),
                  ),
                  Text(_formatCurrency(price * qty),
                    style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 12,
                      fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                ]),
              );
            }),
            if (o.items.length > 3)
              Padding(
                padding: const EdgeInsets.only(left: 22),
                child: Text('+ ${o.items.length - 3} item lainnya',
                  style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 11,
                    color: AppColors.textHint)),
              ),
            const Divider(height: 16),
          ],

          // ── Total & payment ──
          if (o.discountAmount > 0)
            _detailRow(Icons.discount_rounded, 'Diskon',
              '- ${_formatCurrency(o.discountAmount)}'),
          if (o.taxAmount > 0)
            _detailRow(Icons.percent_rounded, 'Pajak',
              _formatCurrency(o.taxAmount)),
          _detailRow(Icons.payments_rounded, 'Total',
            _formatCurrency(o.totalAmount)),

          const SizedBox(height: 8),

          // ── Status pembayaran badge ──
          Row(children: [
            const SizedBox(width: 22),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: payColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: payColor.withValues(alpha: 0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  o.paymentStatus == 'paid'
                    ? Icons.check_circle_rounded
                    : Icons.pending_rounded,
                  size: 12, color: payColor),
                const SizedBox(width: 4),
                Text(payLabel,
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 11,
                    fontWeight: FontWeight.w600, color: payColor)),
              ]),
            ),
            if (o.paymentMethod != null) ...[
              const SizedBox(width: 8),
              Text('via ${o.paymentMethod}',
                style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 11,
                  color: AppColors.textHint)),
            ],
          ]),

          // ── Notes ──
          if (o.notes != null && o.notes!.isNotEmpty) ...[
            const Divider(height: 16),
            _detailRow(Icons.note_rounded, 'Catatan', o.notes!),
          ],
        ],
      ),
    );
  }

  String _formatCurrency(double amount) {
    final formatted = amount.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
    return 'Rp $formatted';
  }

  Widget _buildReservationSection(Color color) {
    if (_loadingBooking) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: const Center(
          child: SizedBox(
            height: 20, width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_booking == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Icon(Icons.info_outline, color: color, size: 18),
          const SizedBox(width: 8),
          const Text('Tidak ada data reservasi aktif',
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary)),
        ]),
      );
    }

    final b = _booking!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Judul seksi ──
          Row(children: [
            Icon(Icons.event_seat_rounded, color: color, size: 16),
            const SizedBox(width: 6),
            Text('Detail Reservasi',
              style: TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                fontSize: 13, color: color)),
            if (b.confirmationCode != null) ...[
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('#${b.confirmationCode}',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 10,
                    fontWeight: FontWeight.w600, color: color)),
              ),
            ],
          ]),
          const SizedBox(height: 12),

          // ── Nama customer ──
          _detailRow(Icons.person_rounded, 'Nama', b.customerName),
          if (b.customerPhone != null)
            _detailRow(Icons.phone_rounded, 'No. HP', b.customerPhone!),
          if (b.customerEmail != null)
            _detailRow(Icons.email_rounded, 'Email', b.customerEmail!),

          const Divider(height: 16),

          // ── Waktu & tamu ──
          _detailRow(Icons.calendar_today_rounded, 'Tanggal', _formatDate(b.bookingDate)),
          _detailRow(Icons.access_time_rounded, 'Jam', '${b.bookingTime} (${b.durationMinutes} menit)'),
          _detailRow(Icons.people_rounded, 'Jumlah Tamu', '${b.guestCount} orang'),

          // ── Special request ──
          if (b.specialRequests != null && b.specialRequests!.isNotEmpty) ...[
            const Divider(height: 16),
            _detailRow(Icons.note_rounded, 'Catatan', b.specialRequests!),
          ],
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(label,
              style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
          ),
          const Text(': ',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          Expanded(
            child: Text(value,
              style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 12,
                fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  /// Format "2025-04-28" → "Senin, 28 Apr 2025"
  String _formatDate(String raw) {
    try {
      final dt = DateTime.parse(raw);
      const days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
      const months = ['Jan','Feb','Mar','Apr','Mei','Jun','Jul','Agu','Sep','Okt','Nov','Des'];
      return '${days[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return raw;
    }
  }
}