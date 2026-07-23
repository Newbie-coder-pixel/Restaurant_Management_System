import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Origin diizinkan lewat env var ALLOWED_ORIGINS (comma-separated).
function resolveAllowedOrigin(req: Request): string {
  const allowed = (Deno.env.get('ALLOWED_ORIGINS') ?? '')
    .split(',').map((s) => s.trim()).filter(Boolean)
  const origin = req.headers.get('origin') ?? ''
  return allowed.includes(origin) ? origin : ''
}

serve(async (req) => {
  const corsHeaders = {
    'Access-Control-Allow-Origin': resolveAllowedOrigin(req),
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  }

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Pakai service role key — bisa create user tanpa logout session yang ada
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    // ── Verifikasi pemanggil ────────────────────────────────────────────────
    // SEBELUM fix ini, function ini TIDAK PERNAH mengecek siapa yang memanggil
    // — role & branchId dari body dipercaya mentah-mentah, jadi staff role
    // apa pun (bahkan kalau JWT-nya valid tapi rolenya waiter/kasir) bisa
    // membuat akun baru ber-role superadmin. Sekarang caller WAJIB staff aktif
    // dengan role superadmin/manager, dan manager tidak boleh membuat akun
    // superadmin atau membuat staff di cabang lain.
    const authHeader = req.headers.get('authorization') ?? ''
    const callerJwt = authHeader.replace(/^Bearer\s+/i, '')
    if (!callerJwt) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const { data: callerAuth, error: callerAuthError } = await supabaseAdmin.auth.getUser(callerJwt)
    if (callerAuthError || !callerAuth?.user) {
      return new Response(
        JSON.stringify({ error: 'Sesi tidak valid, silakan login ulang.' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const { data: callerStaff, error: callerStaffError } = await supabaseAdmin
      .from('staff')
      .select('role, branch_id, is_active')
      .eq('user_id', callerAuth.user.id)
      .maybeSingle()

    if (callerStaffError || !callerStaff || !callerStaff.is_active) {
      return new Response(
        JSON.stringify({ error: 'Akun Anda tidak memiliki akses untuk membuat staff baru.' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    if (callerStaff.role !== 'superadmin' && callerStaff.role !== 'manager') {
      return new Response(
        JSON.stringify({ error: 'Hanya manager/superadmin yang boleh membuat staff baru.' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const { email, password, fullName, phone, role, branchId } = await req.json()

    // Validasi input
    if (!email || !password || !fullName || !role || !branchId) {
      return new Response(
        JSON.stringify({ error: 'Data tidak lengkap.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    // Manager cuma boleh buat staff di cabang sendiri, dan tidak boleh grant superadmin.
    if (callerStaff.role === 'manager') {
      if (role === 'superadmin') {
        return new Response(
          JSON.stringify({ error: 'Manager tidak boleh membuat akun superadmin.' }),
          { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        )
      }
      if (branchId !== callerStaff.branch_id) {
        return new Response(
          JSON.stringify({ error: 'Manager hanya boleh membuat staff di cabang sendiri.' }),
          { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        )
      }
    }

    // Step 1: Buat auth user pakai Admin API (tidak ganggu sesi yang login)
    const { data: authData, error: authError } = await supabaseAdmin.auth.admin.createUser({
      email,
      password,
      email_confirm: true, // langsung confirmed, tidak perlu verifikasi email
    })

    if (authError) {
      return new Response(
        JSON.stringify({ error: authError.message }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const userId = authData.user.id

    // Step 2: Insert ke tabel staff
    const { error: staffError } = await supabaseAdmin.from('staff').insert({
      user_id: userId,
      branch_id: branchId,
      full_name: fullName,
      email,
      phone: phone || null,
      role,
      is_active: true,
    })

    if (staffError) {
      // Kalau insert staff gagal, hapus auth user yang sudah terbuat
      await supabaseAdmin.auth.admin.deleteUser(userId)
      return new Response(
        JSON.stringify({ error: 'Gagal simpan data staff: ' + staffError.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    return new Response(
      JSON.stringify({ success: true }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )

  } catch (e) {
    return new Response(
      JSON.stringify({ error: 'Server error: ' + e.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }
})