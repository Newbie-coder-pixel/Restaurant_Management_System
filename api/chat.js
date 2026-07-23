// Origin diizinkan via env var ALLOWED_ORIGINS (comma-separated), diset di
// Vercel project settings — mis. "https://staff-app.vercel.app,https://customer-app.vercel.app".
// Sebelumnya "*" mengizinkan situs manapun memicu proxy ini dari browser
// pengunjung dan menghabiskan kuota GROQ_API_KEY project ini.
function resolveAllowedOrigin(req) {
  const allowed = (process.env.ALLOWED_ORIGINS || '')
    .split(',').map((s) => s.trim()).filter(Boolean);
  const origin = req.headers.origin;
  if (allowed.length === 0 || !origin) return null;
  return allowed.includes(origin) ? origin : null;
}

export default async function handler(req, res) {
  const allowedOrigin = resolveAllowedOrigin(req);
  if (allowedOrigin) res.setHeader('Access-Control-Allow-Origin', allowedOrigin);
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const groqApiKey = process.env.GROQ_API_KEY;
  if (!groqApiKey) {
    return res.status(500).json({ error: 'GROQ_API_KEY not configured' });
  }

  // Validasi bentuk body minimal supaya endpoint ini tidak jadi proxy generik
  // ke Groq API untuk payload apapun (batasi cost/abuse).
  const messages = req.body?.messages;
  if (!Array.isArray(messages) || messages.length === 0 || messages.length > 50) {
    return res.status(400).json({ error: 'Invalid messages payload' });
  }

  try {
    const response = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${groqApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(req.body),
    });

    const data = await response.json();
    res.status(response.status).json(data);
  } catch (error) {
    res.status(500).json({ error: 'Failed to reach Groq API' });
  }
}