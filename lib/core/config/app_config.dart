// lib/core/config/app_config.dart
// ⚠️  Replace these values with your actual Supabase credentials
// Get them from: https://supabase.com → Project Settings → API

class AppConfig {
  // ── Supabase ──────────────────────────────────────────────
  static const String supabaseUrl = 'https://pppxzbddfoeajwngbwdo.supabase.co';

  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBwcHh6YmRkZm9lYWp3bmdid2RvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI4NTU5MjYsImV4cCI6MjA4ODQzMTkyNn0.gqsmLAgEBix5DqLyxxevYO0JTD48t4ikv8MYDWfqe7o';

  // ── Groq API Proxy (via Vercel) ───────────────────────────
  // API Key TIDAK disimpan di sini — sudah aman di Vercel Environment Variables
  // Proxy endpoint: /api/chat (Vercel Function)
  // JANGAN tambahkan groqApiKey di sini lagi!


  // ── Midtrans Payment Gateway ───────────────────────────────
  // Client key AMAN disimpan di Flutter (memang didesain public, bukan rahasia)
  // Server key JANGAN PERNAH ditaruh di sini — hanya boleh di Supabase
  // Edge Function Secrets (lihat supabase_midtrans_migration.sql bagian 6)
  //
  // Ambil client key di:
  //   Sandbox    → https://dashboard.sandbox.midtrans.com → Settings → Access Keys
  //   Production → https://dashboard.midtrans.com → Settings → Access Keys
  //
  // ⚠️  GANTI nilai di bawah ini dengan client key asli kamu
  static const String midtransClientKeySandbox =
      'Mid-client-f78f7e7Tgcr_gavX';
  static const String midtransClientKeyProduction =
    'Mid-client-JETr7K-VE_xT2luw'; // ← isi ini, yang kamu dapat tadi

  // Ganti ke `true` HANYA kalau sudah siap go-live dengan akun production
  static const bool midtransIsProduction = false;

  static String get midtransClientKey => midtransIsProduction
      ? midtransClientKeyProduction
      : midtransClientKeySandbox;


  // ── App Settings ──────────────────────────────────────────
  static const String appName = 'RestaurantOS';
  static const String appVersion = '1.0.0';

  // ── Order Number Prefix (per branch code) ─────────────────
  static const String defaultOrderPrefix = 'A';

  // ── Tax Rate ──────────────────────────────────────────────
  static const double defaultTaxRate = 0.11;
}