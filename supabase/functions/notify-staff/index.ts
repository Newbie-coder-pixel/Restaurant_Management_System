import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// Edge Function: notify-staff
// Dipanggil dari Flutter setelah booking berhasil disimpan ke DB
// Method: POST
// Body: { booking_id: string }

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceKey  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const fonnteToken = Deno.env.get('FONNTE_TOKEN')!;
  // Nomor WA staff/owner yang mau dinotif — set di Supabase Edge Function Secrets
  // Key: STAFF_WA_NUMBER, Value: 628xxxxxxxxx (tanpa + tanpa spasi)
  const staffPhone  = Deno.env.get('STAFF_WA_NUMBER');

  if (!staffPhone) {
    return new Response(
      JSON.stringify({ error: 'STAFF_WA_NUMBER secret belum di-set di Supabase' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }

  let body: { booking_id?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid JSON body' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  if (!body.booking_id) {
    return new Response(JSON.stringify({ error: 'booking_id wajib diisi' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Ambil detail booking
  const bookingRes = await fetch(
    `${supabaseUrl}/rest/v1/bookings?id=eq.${body.booking_id}&select=*,restaurant_tables(table_number,floor_level),branches(name)&limit=1`,
    {
      headers: {
        'apikey': serviceKey,
        'Authorization': `Bearer ${serviceKey}`,
      },
    }
  );

  const bookings = await bookingRes.json();

  if (!Array.isArray(bookings) || bookings.length === 0) {
    return new Response(
      JSON.stringify({ error: 'Booking tidak ditemukan', id: body.booking_id }),
      { status: 404, headers: { 'Content-Type': 'application/json' } }
    );
  }

  const b = bookings[0];
  const tableNumber = b.restaurant_tables?.table_number ?? '-';
  const floorLevel  = b.restaurant_tables?.floor_level  ?? '-';
  const branchName  = b.branches?.name                  ?? '-';
  const time        = b.booking_time?.substring(0, 5)   ?? '-';
  const dpText      = b.deposit_amount > 0
    ? `💰 DP: Rp ${Number(b.deposit_amount).toLocaleString('id-ID')}`
    : `💰 DP: Tidak ada`;

  // Format tanggal ke Indonesia
  const dateObj   = new Date(b.booking_date);
  const dateIndo  = dateObj.toLocaleDateString('id-ID', {
    weekday: 'long', day: 'numeric', month: 'long', year: 'numeric',
  });

  const specialReq = b.special_requests
    ? `\n📋 Catatan: ${b.special_requests}`
    : '';

  const message =
`🔔 *Booking Baru Masuk!*

📍 *${branchName}*
👤 ${b.customer_name}
📞 ${b.customer_phone ?? '-'}
👥 ${b.guest_count} orang
📅 ${dateIndo}
⏰ ${time} WIB
🪑 Meja ${tableNumber} (Lantai ${floorLevel})
${dpText}${specialReq}

Status: *${b.status?.toUpperCase()}*
Kode: ${b.confirmation_code ?? '-'}

_Segera konfirmasi jika diperlukan._`;

  const waRes = await fetch('https://api.fonnte.com/send', {
    method: 'POST',
    headers: {
      'Authorization': fonnteToken,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({
      target: staffPhone,
      message,
      countryCode: '62',
    }),
  });

  const waJson = await waRes.json();

  return new Response(
    JSON.stringify({
      message: 'Notif WA terkirim ke staff',
      booking_id: body.booking_id,
      staff_phone: staffPhone,
      fonnte_response: waJson,
    }),
    { status: 200, headers: { 'Content-Type': 'application/json' } }
  );
});