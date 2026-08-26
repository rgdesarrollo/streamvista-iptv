import { initializeApp } from 'https://www.gstatic.com/firebasejs/10.14.1/firebase-app.js';
import { createUserWithEmailAndPassword, getAuth, signInWithEmailAndPassword, signOut } from 'https://www.gstatic.com/firebasejs/10.14.1/firebase-auth.js';

const config = window.STREAMVISTA_FIREBASE;
const api = window.STREAMVISTA_PAIRING_API?.replace(/\/$/, '');
const $ = (id) => document.getElementById(id);
const firebaseConfigured = Boolean(
  config?.apiKey && config?.projectId && config?.appId &&
  !Object.values(config).some((value) => `${value}`.includes('REPLACE_ME')),
);
const auth = firebaseConfigured ? getAuth(initializeApp(config)) : null;

function requireFirebase(statusId) {
  if (auth) return true;
  $(statusId).textContent = 'Firebase aún no está configurado. Añade el objeto firebaseConfig real en firebase-config.js.';
  return false;
}

function openProvisioning() {
  $('login-form').classList.add('hidden');
  $('register-form').classList.add('hidden');
  $('provision-form').classList.remove('hidden');
}

$('show-register').addEventListener('click', () => {
  $('login-form').classList.add('hidden'); $('register-form').classList.remove('hidden');
});
$('show-login').addEventListener('click', () => {
  $('register-form').classList.add('hidden'); $('login-form').classList.remove('hidden');
});

$('source-type').addEventListener('change', () => {
  $('xtream-fields').classList.toggle('hidden', $('source-type').value !== 'xtream');
});

$('login-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  if (!requireFirebase('login-status')) return;
  try {
    await signInWithEmailAndPassword(auth, $('email').value.trim(), $('password').value);
    openProvisioning();
  } catch (_) { $('login-status').textContent = 'No se pudo iniciar sesión. Revisa tu correo y contraseña.'; }
});

$('register-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  if (!requireFirebase('register-status')) return;
  try {
    await createUserWithEmailAndPassword(auth, $('register-email').value.trim(), $('register-password').value);
    openProvisioning();
  } catch (error) { $('register-status').textContent = error.message; }
});

$('sign-out').addEventListener('click', async () => {
  if (!auth) return;
  await signOut(auth); $('provision-form').classList.add('hidden'); $('login-form').classList.remove('hidden');
});

$('provision-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  if (!requireFirebase('provision-status')) return;
  if (!api || api.includes('REPLACE_ME')) { $('provision-status').textContent = 'Set STREAMVISTA_PAIRING_API before deploying.'; return; }
  const sourceType = $('source-type').value;
  const payload = {
    deviceId: $('device-id').value.trim(), pin: $('pin').value.trim(), sourceType,
    server: $('server').value.trim(), username: sourceType === 'xtream' ? $('username').value.trim() : null,
    password: sourceType === 'xtream' ? $('source-password').value : null,
    userAgent: $('user-agent').value.trim() || null,
  };
  try {
    const token = await auth.currentUser.getIdToken();
    const response = await fetch(`${api}/provision`, { method:'POST', headers:{ 'Content-Type':'application/json', Authorization:`Bearer ${token}` }, body:JSON.stringify(payload) });
    if (!response.ok) throw new Error((await response.json()).error || 'Unable to send configuration');
    $('provision-status').textContent = 'Configuration sent. It is deleted after the device receives it.';
  } catch (error) { $('provision-status').textContent = error.message; }
});

if (!firebaseConfigured) {
  $('login-status').textContent = 'Antes de crear una cuenta, configura Firebase para este portal.';
}
