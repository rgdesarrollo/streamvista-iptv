const api = window.STREAMVISTA_PAIRING_API?.replace(/\/$/, '');
const $ = (id) => document.getElementById(id);

$('source-type').addEventListener('change', () => {
  $('xtream-fields').classList.toggle('hidden', $('source-type').value !== 'xtream');
});

$('provision-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  if (!api || api.includes('REPLACE_ME')) {
    $('provision-status').textContent = 'El portal aún no está configurado. Añade STREAMVISTA_PAIRING_API antes de publicarlo.';
    return;
  }
  const sourceType = $('source-type').value;
  const payload = {
    deviceId: $('device-id').value.trim().toUpperCase(), pin: $('pin').value.trim(), sourceType,
    server: $('server').value.trim(),
    username: sourceType === 'xtream' ? $('username').value.trim() : null,
    password: sourceType === 'xtream' ? $('source-password').value : null,
    userAgent: $('user-agent').value.trim() || null,
  };
  try {
    const response = await fetch(`${api}/provision`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
    if (!response.ok) throw new Error((await response.json()).error || 'No se pudo enviar la configuración.');
    $('provision-status').textContent = 'Lista enviada. StreamVista la recibirá en unos segundos.';
  } catch (error) { $('provision-status').textContent = error.message; }
});
