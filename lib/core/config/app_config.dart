// lib/core/config/app_config.dart
// ⚠️  Replace these values with your actual Supabase credentials
// Get them from: https://supabase.com → Project Settings → API

class AppConfig {
  // ── Supabase ──────────────────────────────────────────────
  static const String supabaseUrl = 'https://pppxzbddfoeajwngbwdo.supabase.co';

  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBwcHh6YmRkZm9lYWp3bmdid2RvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI4NTU5MjYsImV4cCI6MjA4ODQzMTkyNn0.gqsmLAgEBix5DqLyxxevYO0JTD48t4ikv8MYDWfqe7o';

  // ── Groq API Proxy (via Vercel) ───────────────────────────
  // API Key is NOT stored here — already kept safe in Vercel Environment Variables
  // Proxy endpoint: /api/chat (Vercel Function)
  // DO NOT add groqApiKey here again!


  // ── Midtrans Payment Gateway ───────────────────────────────
  // Client key is SAFE to store in Flutter (it's designed to be public, not secret)
  // Server key must NEVER be placed here — only allowed in Supabase
  // Edge Function Secrets (see supabase_midtrans_migration.sql section 6)
  //
  // Get the client key at:
  //   Sandbox    → https://dashboard.sandbox.midtrans.com → Settings → Access Keys
  //   Production → https://dashboard.midtrans.com → Settings → Access Keys
  //
  // ⚠️  REPLACE the value below with your actual client key
  static const String midtransClientKeySandbox =
      'Mid-client-f78f7e7Tgcr_gavX';
  static const String midtransClientKeyProduction =
    'Mid-client-JETr7K-VE_xT2luw'; // ✅ Production client key

  // 🧪 SANDBOX MODE ACTIVE (temporary — no NPWP yet for production access)
  // To switch back to production later: change the line below back to `true`,
  // and make sure MIDTRANS_SERVER_KEY in Supabase Edge Function Secrets is
  // set to the PRODUCTION server key (not sandbox).
  static const bool midtransIsProduction = false; // production: true | sandbox: false

  static String get midtransClientKey => midtransIsProduction
      ? midtransClientKeyProduction
      : midtransClientKeySandbox;


  // ── App Settings ──────────────────────────────────────────
  static const String appName = 'RestaurantOS';
  static const String appVersion = '1.0.0';

  // ── Public web app domains (Vercel deployments) ───────────
  // Used as the base URL for /api/* proxy calls from native builds
  // (which don't have an origin like web does), and for promotional QR codes on receipts.
  static const String staffAppUrl = 'https://restaurant-staff-topaz.vercel.app';
  static const String customerAppUrl = 'https://restaurant-customer-two.vercel.app';
  // Only matters for native builds of APP_MODE=qr (kIsWeb builds use the
  // relative '/api/chat' path instead and never read this).
  static const String qrAppUrl = 'https://restaurant-qr-code-ten.vercel.app';

  // ── Order Number Prefix (per branch code) ─────────────────
  static const String defaultOrderPrefix = 'A';

  // ── Tax Rate ──────────────────────────────────────────────
  static const double defaultTaxRate = 0.11;
}