// Ranking público (top 5) de Bomba y Teclazo: añade el botón «Ranking» bajo «Individual» en la portada del juego
// y muestra el mejor resultado de cada jugador (función pg_top del proyecto Supabase de pg games).
(() => {
  const URL = 'https://acsrnjowxvjamiybsjkx.supabase.co';
  const KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFjc3Juam93eHZqYW1peWJzamt4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI2MTU3MzMsImV4cCI6MjEwODE5MTczM30.PeKiaUjeBjdpK0B-zziQNjUfluIfmuuajZMj0Mb_Pzw';
  const game = (location.pathname.match(/\/(bomba|teclazo)(\/|$)/) || [])[1];
  const solo = document.getElementById('btnSolo');
  if (!game || !solo) return;
  const unit = () => game === 'teclazo' ? (document.documentElement.lang === 'en' ? 'wpm' : 'ppm') : (document.documentElement.lang === 'en' ? 'words' : 'palabras');
  const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);

  const row = document.createElement('div');
  row.className = 'subrow';
  row.innerHTML = '<button type="button" class="rankbtn"><svg viewBox="0 0 26 22" aria-hidden="true"><path d="M9.5 3.5h7v17h-7zM2.5 9.5h7v11h-7zM16.5 12.5h7v8h-7z" fill="currentColor" stroke="#17140f" stroke-width="2.4" stroke-linejoin="round"/></svg>Ranking<i class="rkdot" hidden></i></button>';
  solo.after(row);
  // burbuja de novedad hasta que se abre por primera vez en este dispositivo
  const SEEN = 'pg_rank_seen_' + game;
  const dot = row.querySelector('.rkdot');
  try { dot.hidden = localStorage.getItem(SEEN) === '1'; } catch (e) {}

  const ov = document.createElement('div');
  ov.className = 'rankov'; ov.hidden = true;
  ov.innerHTML = '<div class="rankcard" role="dialog" aria-modal="true" aria-label="Ranking"><div class="rankhd"><b class="display">Ranking</b><span class="rku"></span></div><ol class="ranklist"></ol></div>';
  document.body.appendChild(ov);
  const list = ov.querySelector('.ranklist');

  let cache = null, at = 0;
  const paint = data => {
    const me = (() => { try { return (localStorage.getItem('jt_name') || '').trim().toLowerCase(); } catch (e) { return ''; } })();
    const rows = [];
    for (let i = 0; i < 5; i++) {
      const r = data && data[i];
      rows.push(r ? `<li${r.n.trim().toLowerCase() === me ? ' class="me"' : ''}><i>${i + 1}</i><span>${esc(r.n)}</span><b>${r.v}</b></li>`
                  : `<li class="nil"><i>${i + 1}</i><span>${data ? '—' : ''}</span><b></b></li>`);
    }
    list.innerHTML = rows.join('');
  };
  const load = async () => {
    if (cache && Date.now() - at < 60000) { paint(cache); return; }
    paint(null);
    try {
      const r = await fetch(URL + '/rest/v1/rpc/pg_top', { method: 'POST', headers: { 'content-type': 'application/json', apikey: KEY, authorization: 'Bearer ' + KEY }, body: JSON.stringify({ p_game: game }) });
      const d = await r.json();
      cache = Array.isArray(d) ? d : []; at = Date.now();
    } catch (e) { cache = null; paint([]); return; }
    paint(cache);
  };
  const close = () => { ov.hidden = true; document.removeEventListener('keydown', key); };
  const key = e => { if (e.key === 'Escape') close(); };
  row.querySelector('button').onclick = () => {
    dot.hidden = true; try { localStorage.setItem(SEEN, '1'); } catch (e) {}
    ov.querySelector('.rku').textContent = unit();
    ov.hidden = false; document.addEventListener('keydown', key); load();
  };
  ov.onclick = e => { if (e.target === ov) close(); };
})();
