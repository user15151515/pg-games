// Estadísticas propias y anónimas de pg games (proyecto Supabase de pg games, sin terceros).
// Guarda un identificador aleatorio en este navegador y eventos sueltos: visita, sala creada o unida,
// partida empezada o terminada y fallos de conexión. No lee nombres, palabras ni textos de los jugadores.
// Se desactiva con «No rastrear» del navegador, en localhost, en el navegador del administrador y en los dispositivos abiertos con ?notrack=1.
(() => {
  const URL = 'https://acsrnjowxvjamiybsjkx.supabase.co';
  const KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFjc3Juam93eHZqYW1peWJzamt4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI2MTU3MzMsImV4cCI6MjEwODE5MTczM30.PeKiaUjeBjdpK0B-zziQNjUfluIfmuuajZMj0Mb_Pzw';
  const noop = { ev() {}, start() {}, end() {} };
  // Para ignorar un dispositivo: abrir la web una vez con ?notrack=1 (y ?notrack=0 para volver a contar).
  try { const q = new URLSearchParams(location.search).get('notrack'); if (q === '1') localStorage.setItem('pg_notrack', '1'); else if (q === '0') localStorage.removeItem('pg_notrack'); } catch (e) {}
  let off = /^(localhost|127\.|\[::1\])/.test(location.hostname) || navigator.doNotTrack === '1' || navigator.globalPrivacyControl === true;
  try { if (localStorage.getItem('pg_notrack') === '1') off = true; } catch (e) {}
  if (off) { window.PGT = noop; return; }

  const game = (location.pathname.match(/\/(bomba|tutti|teclazo)(\/|$)/) || [])[1] || '';
  const rnd = n => { const a = 'abcdefghijklmnopqrstuvwxyz0123456789'; let s = ''; for (let i = 0; i < n; i++) s += a[Math.random() * a.length | 0]; return s; };
  let vid = '';
  try { vid = localStorage.getItem('pg_vid') || ''; if (!/^[a-z0-9]{8,24}$/.test(vid)) { vid = rnd(16); localStorage.setItem('pg_vid', vid); } } catch (e) { vid = rnd(16); }
  let sid = '', first = false;
  try { sid = sessionStorage.getItem('pg_sid') || ''; if (!/^[a-z0-9]{6,24}$/.test(sid)) { sid = rnd(12); sessionStorage.setItem('pg_sid', sid); first = true; } } catch (e) { sid = rnd(12); first = true; }

  const send = (kind, props) => {
    try {
      fetch(URL + '/rest/v1/rpc/pg_log', {
        method: 'POST', keepalive: true,
        headers: { 'content-type': 'application/json', apikey: KEY, authorization: 'Bearer ' + KEY },
        body: JSON.stringify({ p_kind: kind, p_game: game, p_vid: vid, p_sid: sid, p_props: props || {} })
      }).catch(() => {});
    } catch (e) {}
  };
  const source = () => {
    let h = ''; try { h = new URL(document.referrer).hostname.replace(/^www\./, ''); } catch (e) {}
    const s = (new URLSearchParams(location.search).get('utm_source') || h).toLowerCase();
    if (!s || h === location.hostname) return 'directo';
    for (const [k, v] of [['whatsapp', 'whatsapp'], ['wa.me', 'whatsapp'], ['telegram', 'telegram'], ['t.me', 'telegram'], ['instagram', 'instagram'], ['facebook', 'facebook'], ['tiktok', 'tiktok'], ['google', 'google'], ['bing', 'bing'], ['duckduckgo', 'duckduckgo'], ['twitter', 'x'], ['t.co', 'x'], ['x.com', 'x'], ['reddit', 'reddit'], ['discord', 'discord'], ['youtube', 'youtube']]) if (s.includes(k)) return v;
    return 'otros';
  };
  const coarse = window.matchMedia && matchMedia('(pointer:coarse)').matches;
  const dev = coarse ? (Math.min(screen.width, screen.height) < 700 ? 'm' : 't') : 'd';

  let t0 = 0;
  window.PGT = {
    ev: send,
    start(n, solo) { t0 = Date.now(); send('game_start', { n, solo: !!solo }); },
    end(n, solo, m) {
      if (!t0) return;
      const dur = Math.round((Date.now() - t0) / 1000); t0 = 0;
      send('game_end', Object.assign({ n, solo: !!solo, dur }, m != null && isFinite(m) ? { m } : {}));
    }
  };
  send('view', first ? { dev, src: source() } : { dev });
})();
