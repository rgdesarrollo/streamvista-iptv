const { onRequest } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const crypto = require('crypto');
const cors = require('cors')({ origin: true });
const express = require('express');

admin.initializeApp();
const db = admin.firestore();
const app = express();
app.use(express.json({ limit: '16kb' }));
app.use((req, res, next) => cors(req, res, next));

const devices = db.collection('pairedDevices');
const pinHash = (deviceId, pin) => crypto.createHash('sha256').update(`${deviceId}:${pin}`).digest('hex');
const validDevice = (id) => /^SV-[A-F0-9]{24}$/.test(id);
const validPin = (pin) => /^\d{6}$/.test(pin);

app.post('/register', async (req, res) => {
  const { deviceId, pin } = req.body || {};
  if (!validDevice(deviceId) || !validPin(pin)) return res.status(400).json({ error: 'Invalid device ID or PIN.' });
  await devices.doc(deviceId).set({
    pinHash: pinHash(deviceId, pin),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  res.status(204).end();
});

app.post('/provision', async (req, res) => {
  try {
    const { deviceId, pin, sourceType, server, username, password, userAgent } = req.body || {};
    if (!validDevice(deviceId) || !validPin(pin) || !['xtream', 'm3u'].includes(sourceType) || !/^https?:\/\//i.test(server || '')) {
      return res.status(400).json({ error: 'Check the device ID, PIN and source URL.' });
    }
    if (sourceType === 'xtream' && (!username || !password)) return res.status(400).json({ error: 'Xtream username and password are required.' });
    const ref = devices.doc(deviceId);
    const device = await ref.get();
    if (!device.exists) return res.status(404).json({ error: 'Device not found or pairing PIN has expired.' });
    if (device.data().pinHash !== pinHash(deviceId, pin)) return res.status(404).json({ error: 'Device not found or PIN has expired.' });
    await ref.update({
      pendingConfig: { sourceType, server, username: username || null, password: password || null, userAgent: userAgent || null, createdAt: Date.now() },
      expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 10 * 60 * 1000),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    res.status(201).json({ ok: true });
  } catch (error) { res.status(400).json({ error: error.message || 'Check the playlist details.' }); }
});

app.get('/config', async (req, res) => {
  const { deviceId, pin } = req.query;
  if (!validDevice(deviceId) || !validPin(pin)) return res.status(400).json({ error: 'Invalid pairing data.' });
  const ref = devices.doc(deviceId);
  const result = await db.runTransaction(async (transaction) => {
    const device = await transaction.get(ref);
    const data = device.data();
    if (!device.exists || data.pinHash !== pinHash(deviceId, pin)) return { status: 404 };
    if (!data.pendingConfig || !data.expiresAt || data.expiresAt.toMillis() < Date.now()) {
      if (data.pendingConfig) transaction.update(ref, { pendingConfig: admin.firestore.FieldValue.delete() });
      return { status: 204 };
    }
    transaction.update(ref, { pendingConfig: admin.firestore.FieldValue.delete(), deliveredAt: admin.firestore.FieldValue.serverTimestamp() });
    return { status: 200, config: data.pendingConfig };
  });
  if (result.status === 200) return res.json(result.config);
  res.status(result.status).end();
});

exports.pairing = onRequest({ region: 'us-central1', cors: true }, app);
