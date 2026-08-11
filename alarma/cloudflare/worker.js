/**
 * Puerta de entrada opcional:  PC  ->  Worker  ->  ntfy  ->  Pixel (Tasker)
 *
 * Aporta lo que el plan gratuito de ntfy no tiene: un token con ACL de verdad,
 * validacion del payload y una URL propia. El topic de ntfy y el token de Tasker
 * viven aqui como secretos, no en el PC.
 *
 * Secretos a definir (panel de Cloudflare -> Variables and Secrets):
 *   ALARMA_TOKEN  secreto que el PC manda en la cabecera Authorization
 *   NTFY_TOPIC    nombre del topic de ntfy (sin la URL)
 *   TASKER_TOKEN  secreto que Tasker verifica dentro del JSON
 */
export default {
  async fetch(request, env) {
    if (request.method !== 'POST') {
      return new Response('Method Not Allowed\n', { status: 405 });
    }

    const auth = request.headers.get('Authorization') || '';
    if (!auth.startsWith('Bearer ') || !equal(auth.slice(7), env.ALARMA_TOKEN)) {
      return new Response('Unauthorized\n', { status: 401 });
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return new Response('JSON invalido\n', { status: 400 });
    }

    const { hour, minute, date } = body;
    if (!Number.isInteger(hour) || hour < 0 || hour > 23) {
      return new Response('hour invalido\n', { status: 400 });
    }
    if (!Number.isInteger(minute) || minute < 0 || minute > 59) {
      return new Response('minute invalido\n', { status: 400 });
    }
    if (typeof date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
      return new Response('date invalido\n', { status: 400 });
    }

    // El token que recibimos del PC se descarta: el que viaja a Tasker es el nuestro.
    const res = await fetch(`https://ntfy.sh/${env.NTFY_TOPIC}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Priority': 'high' },
      body: JSON.stringify({ token: env.TASKER_TOKEN, hour, minute, date }),
    });

    if (!res.ok) {
      return new Response(`ntfy respondio ${res.status}\n`, { status: 502 });
    }
    return new Response('ok\n');
  },
};

/** Comparacion en tiempo constante, para no filtrar el token caracter a caracter. */
function equal(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
