import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Origin allowed via the ALLOWED_ORIGINS env var (comma-separated).
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
    // Use the service role key — can create a user without logging out the existing session
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    // ── Verify the caller ────────────────────────────────────────────────
    // BEFORE this fix, this function NEVER checked who was calling it
    // — the role & branchId from the body were trusted as-is, so any staff
    // role (even with a valid JWT but role waiter/cashier) could create a
    // new account with the superadmin role. Now the caller MUST be an active
    // staff member with role superadmin/manager, and a manager cannot create
    // superadmin accounts or create staff in another branch.
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
        JSON.stringify({ error: 'Invalid session, please log in again.' }),
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
        JSON.stringify({ error: 'Your account does not have access to create new staff.' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    if (callerStaff.role !== 'superadmin' && callerStaff.role !== 'manager') {
      return new Response(
        JSON.stringify({ error: 'Only managers/superadmins can create new staff.' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const { email, password, fullName, phone, role, branchId } = await req.json()

    // Validate input
    if (!email || !password || !fullName || !role || !branchId) {
      return new Response(
        JSON.stringify({ error: 'Incomplete data.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    // A manager can only create staff in their own branch, and cannot grant superadmin.
    if (callerStaff.role === 'manager') {
      if (role === 'superadmin') {
        return new Response(
          JSON.stringify({ error: 'Managers cannot create superadmin accounts.' }),
          { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        )
      }
      if (branchId !== callerStaff.branch_id) {
        return new Response(
          JSON.stringify({ error: 'Managers can only create staff in their own branch.' }),
          { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        )
      }
    }

    // Step 1: Create the auth user using the Admin API (doesn't disturb the logged-in session)
    const { data: authData, error: authError } = await supabaseAdmin.auth.admin.createUser({
      email,
      password,
      email_confirm: true, // confirmed immediately, no email verification needed
    })

    if (authError) {
      return new Response(
        JSON.stringify({ error: authError.message }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const userId = authData.user.id

    // Step 2: Insert into the staff table
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
      // If inserting staff fails, delete the auth user that was already created
      await supabaseAdmin.auth.admin.deleteUser(userId)
      return new Response(
        JSON.stringify({ error: 'Failed to save staff data: ' + staffError.message }),
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