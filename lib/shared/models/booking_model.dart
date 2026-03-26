enum BookingStatus { pending, confirmed, seated, cancelled, noShow, completed }
enum BookingSource { app, website, aiChatbot, phone, walkIn, whatsapp }

class BookingModel {
  final String id;
  final String branchId;
  final String? tableId;
  final String customerName;
  final String? customerPhone;
  final String? customerEmail;
  final int guestCount;
  final DateTime bookingDate;
  final String bookingTime;
  final int durationMinutes;
  final BookingStatus status;
  final BookingSource source;
  final String? specialRequests;
  final String confirmationCode;
  final DateTime createdAt;

  const BookingModel({
    required this.id, required this.branchId, this.tableId,
    required this.customerName, this.customerPhone, this.customerEmail,
    required this.guestCount, required this.bookingDate, required this.bookingTime,
    this.durationMinutes = 90, required this.status, required this.source,
    this.specialRequests, required this.confirmationCode, required this.createdAt,
  });

  static BookingStatus _statusFromString(String s) {
    const map = {
      'pending':   BookingStatus.pending,
      'confirmed': BookingStatus.confirmed,
      'seated':    BookingStatus.seated,
      'cancelled': BookingStatus.cancelled,
      'no_show':   BookingStatus.noShow,
      'noShow':    BookingStatus.noShow,
      'completed': BookingStatus.completed,
    };
    return map[s] ?? BookingStatus.pending;
  }

  static BookingSource _sourceFromString(String s) {
    const map = {
      'app':        BookingSource.app,
      'website':    BookingSource.website,
      'ai_chatbot': BookingSource.aiChatbot,
      'aiChatbot':  BookingSource.aiChatbot,
      'phone':      BookingSource.phone,
      'walk_in':    BookingSource.walkIn,
      'walkIn':     BookingSource.walkIn,
      'whatsapp':   BookingSource.whatsapp,
    };
    return map[s] ?? BookingSource.app;
  }

  factory BookingModel.fromJson(Map<String, dynamic> j) => BookingModel(
    id: j['id'], branchId: j['branch_id'], tableId: j['table_id'],
    customerName: j['customer_name'], customerPhone: j['customer_phone'],
    customerEmail: j['customer_email'], guestCount: j['guest_count'] ?? 1,
    bookingDate: DateTime.parse(j['booking_date']),
    bookingTime: j['booking_time'], durationMinutes: j['duration_minutes'] ?? 90,
    status: _statusFromString(j['status'] ?? 'pending'),
    source: _sourceFromString(j['source'] ?? 'app'),
    specialRequests: j['special_requests'],
    confirmationCode: j['confirmation_code'] ?? '',
    createdAt: DateTime.parse(j['created_at']),
  );
}