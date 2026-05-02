// api/notify.js
// Vercel serverless function — kirim FCM push notification ke manager
// Environment variable yang dibutuhkan di Vercel:
//   FIREBASE_SERVICE_ACCOUNT_JSON → paste seluruh isi JSON service account Firebase

import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';

function getFirebaseApp() {
  if (getApps().length > 0) return getApps()[0];
  const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
  return initializeApp({ credential: cert(serviceAccount) });
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  if (!process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
    return res.status(500).json({ error: 'FIREBASE_SERVICE_ACCOUNT_JSON not configured' });
  }

  try {
    const { tokens, title, body, data = {} } = req.body;

    if (!tokens || !Array.isArray(tokens) || tokens.length === 0) {
      return res.status(400).json({ error: 'tokens harus array dan tidak boleh kosong' });
    }
    if (!title || !body) {
      return res.status(400).json({ error: 'title dan body wajib diisi' });
    }

    getFirebaseApp();
    const messaging = getMessaging();

    const message = {
      tokens,
      notification: { title, body },
      data: Object.fromEntries(
        Object.entries(data).map(([k, v]) => [k, String(v)])
      ),
      android: {
        priority: data.type === 'urgent_escalation' ? 'high' : 'normal',
        notification: {
          sound: 'default',
          priority: data.type === 'urgent_escalation' ? 'max' : 'default',
          channelId: 'escalation_channel',
        },
      },
      apns: {
        payload: {
          aps: { sound: 'default', badge: 1 },
        },
      },
    };

    const response = await messaging.sendEachForMulticast(message);

    console.log(`[notify] ${response.successCount} success, ${response.failureCount} failed`);

    return res.status(200).json({
      success: true,
      successCount: response.successCount,
      failureCount: response.failureCount,
    });
  } catch (error) {
    console.error('[notify] Error:', error);
    return res.status(500).json({ error: error.message });
  }
}