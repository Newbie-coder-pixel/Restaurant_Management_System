// api/notify.js
// Vercel serverless function — kirim FCM push notification
// Tanpa firebase-admin package — pakai FCM HTTP v1 API + Google OAuth2 langsung
//
// Environment variable yang dibutuhkan di Vercel:
//   FIREBASE_SERVICE_ACCOUNT_JSON → paste seluruh isi JSON service account Firebase

// ── Generate JWT untuk Google OAuth2 (tanpa library) ─────────────────────────
function base64urlEncode(str) {
  return btoa(str)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

function base64urlEncodeUint8(bytes) {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return base64urlEncode(binary);
}

async function getAccessToken(serviceAccount) {
  const now = Math.floor(Date.now() / 1000);

  // JWT Header
  const header = base64urlEncode(JSON.stringify({
    alg: 'RS256',
    typ: 'JWT',
  }));

  // JWT Payload
  const payload = base64urlEncode(JSON.stringify({
    iss: serviceAccount.client_email,
    sub: serviceAccount.client_email,
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
  }));

  const signingInput = `${header}.${payload}`;

  // Import private key
  const pemKey = serviceAccount.private_key;
  const pemBody = pemKey
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '');

  const binaryKey = Uint8Array.from(atob(pemBody), c => c.charCodeAt(0));

  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    binaryKey,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  );

  // Sign JWT
  const encoder = new TextEncoder();
  const signatureBuffer = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    encoder.encode(signingInput)
  );

  const signature = base64urlEncodeUint8(new Uint8Array(signatureBuffer));
  const jwt = `${signingInput}.${signature}`;

  // Exchange JWT untuk access token
  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });

  if (!tokenRes.ok) {
    const err = await tokenRes.text();
    throw new Error(`OAuth2 token error: ${err}`);
  }

  const tokenData = await tokenRes.json();
  return tokenData.access_token;
}

// ── Kirim ke satu token via FCM HTTP v1 ──────────────────────────────────────
async function sendToToken(accessToken, projectId, token, title, body, data, androidPriority) {
  const message = {
    message: {
      token,
      notification: { title, body },
      data: Object.fromEntries(
        Object.entries(data).map(([k, v]) => [k, String(v)])
      ),
      android: {
        priority: androidPriority,
        notification: {
          sound: 'default',
          channel_id: 'escalation_channel',
        },
      },
      apns: {
        payload: {
          aps: { sound: 'default', badge: 1 },
        },
      },
    },
  };

  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(message),
    }
  );

  return res.ok;
}

// Origin diizinkan via env var ALLOWED_ORIGINS (comma-separated) di Vercel
// project settings. Sebelumnya "*" mengizinkan situs manapun memicu push FCM
// ke token perangkat manapun yang dikirim di body request.
function resolveAllowedOrigin(req) {
  const allowed = (process.env.ALLOWED_ORIGINS || '')
    .split(',').map((s) => s.trim()).filter(Boolean);
  const origin = req.headers.origin;
  if (allowed.length === 0 || !origin) return null;
  return allowed.includes(origin) ? origin : null;
}

// ── Main handler ──────────────────────────────────────────────────────────────
export default async function handler(req, res) {
  const allowedOrigin = resolveAllowedOrigin(req);
  if (allowedOrigin) res.setHeader('Access-Control-Allow-Origin', allowedOrigin);
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  if (!process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
    return res.status(500).json({ error: 'FIREBASE_SERVICE_ACCOUNT_JSON not configured' });
  }

  // Validasi input — termasuk batas jumlah token per request supaya satu
  // panggilan (dipicu langsung dari browser customer, lihat
  // sentiment_escalation_service.dart) tidak bisa dipakai untuk fan-out push
  // notification ke jumlah device tak terbatas dalam satu request.
  const { tokens, title, body, data = {} } = req.body || {};

  if (!tokens || !Array.isArray(tokens) || tokens.length === 0) {
    return res.status(400).json({ error: 'tokens harus array dan tidak boleh kosong' });
  }
  if (tokens.length > 50 || !tokens.every((t) => typeof t === 'string' && t.length < 4096)) {
    return res.status(400).json({ error: 'tokens tidak valid' });
  }
  if (!title || !body || typeof title !== 'string' || typeof body !== 'string' ||
      title.length > 200 || body.length > 1000) {
    return res.status(400).json({ error: 'title dan body wajib diisi dan dalam batas panjang' });
  }

  try {
    // Parse service account
    const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
    const projectId = serviceAccount.project_id;

    if (!projectId) {
      return res.status(500).json({ error: 'project_id tidak ditemukan di service account' });
    }

    // Ambil OAuth2 access token
    const accessToken = await getAccessToken(serviceAccount);

    // Kirim ke setiap token (simulasi sendEachForMulticast)
    const androidPriority = data.type === 'urgent_escalation' ? 'HIGH' : 'NORMAL';

    const results = await Promise.allSettled(
      tokens.map(token =>
        sendToToken(accessToken, projectId, token, title, body, data, androidPriority)
      )
    );

    const successCount = results.filter(r => r.status === 'fulfilled' && r.value === true).length;
    const failureCount = results.length - successCount;

    console.log(`[notify] ${successCount} success, ${failureCount} failed`);

    return res.status(200).json({
      success: true,
      successCount,
      failureCount,
    });

  } catch (error) {
    console.error('[notify] Error:', error.message);
    return res.status(500).json({ error: error.message });
  }
}