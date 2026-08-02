import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// Edge Function: notify-staff
// Called from Flutter after a booking has been successfully saved to the DB
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
  // WhatsApp number of the staff/owner to be notified — set in Supabase Edge Function Secrets
  // Key: STAFF_WA_NUMBER, Value: 628xxxxxxxxx (no + and no spaces)
  const staffPhone  = Deno.env.get('STAFF_WA_NUMBER');

  if (!staffPhone) {
    return new Response(
      JSON.stringify({ error: 'STAFF_WA_NUMBER secret has not been set in Supabase' }),
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
    return new Response(JSON.stringify({ error: 'booking_id is required' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Fetch booking details
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
      JSON.stringify({ error: 'Booking not found', id: body.booking_id }),
      { status: 404, headers: { 'Content-Type': 'application/json' } }
    );
  }

  const b = bookings[0];
  const tableNumber = b.restaurant_tables?.table_number ?? '-';
  const floorLevel  = b.restaurant_tables?.floor_level  ?? '-';
  const branchName  = b.branches?.name                  ?? '-';
  const time        = b.booking_time?.substring(0, 5)   ?? '-';
  const dpText      = b.deposit_amount > 0
    ? `💰 Deposit: Rp ${Number(b.deposit_amount).toLocaleString('id-ID')}`
    : `💰 Deposit: None`;

  // Format the date using Indonesian locale
  const dateObj   = new Date(b.booking_date);
  const dateIndo  = dateObj.toLocaleDateString('id-ID', {
    weekday: 'long', day: 'numeric', month: 'long', year: 'numeric',
  });

  const specialReq = b.special_requests
    ? `\n📋 Note: ${b.special_requests}`
    : '';

  const message =
`🔔 *New Booking Received!*

📍 *${branchName}*
👤 ${b.customer_name}
📞 ${b.customer_phone ?? '-'}
👥 ${b.guest_count} guests
📅 ${dateIndo}
⏰ ${time} WIB
🪑 Table ${tableNumber} (Floor ${floorLevel})
${dpText}${specialReq}

Status: *${b.status?.toUpperCase()}*
Code: ${b.confirmation_code ?? '-'}

_Please confirm promptly if needed._`;

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
      message: 'WhatsApp notification sent to staff',
      booking_id: body.booking_id,
      staff_phone: staffPhone,
      fonnte_response: waJson,
    }),
    { status: 200, headers: { 'Content-Type': 'application/json' } }
  );
});