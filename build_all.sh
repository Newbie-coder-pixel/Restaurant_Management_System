#!/bin/bash

# ─────────────────────────────────────────────────────────────────────────────
# build_all.sh
# Jalankan dari root project: bash build_all.sh
# Output: build/staff | build/customer | build/qr
# ─────────────────────────────────────────────────────────────────────────────

set -e  # Stop kalau ada error

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Flutter Multi-Mode Build Script"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── vercel.json mini untuk tiap folder build (CORS + SPA rewrite + functions) ──
write_vercel_json() {
  cat > "$1/vercel.json" << 'EOF'
{
  "functions": {
    "api/*.js": { "runtime": "nodejs18.x" }
  },
  "rewrites": [
    { "source": "/((?!api).*)", "destination": "/index.html" }
  ]
}
EOF
}

# ── 1. Staff App ──────────────────────────────────────────────────────────────
echo ""
echo "▶ [1/3] Building STAFF app..."
flutter build web \
  --dart-define=APP_MODE=staff \
  --release

# Pindahkan hasil build ke folder staff
rm -rf build/staff
cp -r build/web build/staff
cp -r api build/staff/api
write_vercel_json build/staff
echo "✓ Staff build selesai → build/staff (+ api/ + vercel.json ikut)"

# ── 2. Customer App ───────────────────────────────────────────────────────────
echo ""
echo "▶ [2/3] Building CUSTOMER app..."
flutter build web \
  --dart-define=APP_MODE=customer \
  --release

rm -rf build/customer
cp -r build/web build/customer
cp -r api build/customer/api
write_vercel_json build/customer
echo "✓ Customer build selesai → build/customer (+ api/ + vercel.json ikut)"

# ── 3. QR App ─────────────────────────────────────────────────────────────────
echo ""
echo "▶ [3/3] Building QR app..."
flutter build web \
  --dart-define=APP_MODE=qr \
  --release

rm -rf build/qr
cp -r build/web build/qr
cp -r api build/qr/api
write_vercel_json build/qr
echo "✓ QR build selesai → build/qr (+ api/ + vercel.json ikut)"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Semua build selesai!"
echo ""
echo "  Folder output:"
echo "  • build/staff    → deploy ke Vercel project STAFF"
echo "  • build/customer → deploy ke Vercel project CUSTOMER"
echo "  • build/qr       → deploy ke Vercel project QR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"