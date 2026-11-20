// Ranking público (top 5) de Bomba, Teclazo y Pistas: añade el botón «Ranking» en la portada del juego
// y muestra el mejor resultado de cada jugador, o de cada pareja en Pistas (función pg_top del proyecto Supabase de pg games).
(() => {
  const URL = 'https://acsrnjowxvjamiybsjkx.supabase.co';
  const KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFjc3Juam93eHZqYW1peWJzamt4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI2MTU3MzMsImV4cCI6MjEwODE5MTczM30.PeKiaUjeBjdpK0B-zziQNjUfluIfmuuajZMj0Mb_Pzw';
  const game = (location.pathname.match(/\/(bomba|teclazo|pistas)(\/|$)/) || [])[1];
  const solo = document.getElementById('btnSolo') || document.querySelector('#homeCreate .cta');
  if (!game || !solo) return;
  const en = () => document.documentElement.lang === 'en';
  const unit = () => game === 'pistas' ? 'puntos' : game === 'teclazo' ? (document.documentElement.lang === 'en' ? 'wpm' : 'ppm') : (document.documentElement.lang === 'en' ? 'words' : 'palabras');
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
  ov.innerHTML = '<div class="rankcard" role="dialog" aria-modal="true" aria-label="Ranking"><div class="rankhd"><b class="display">Ranking</b><span class="rku"></span></div><div class="rktabs" hidden><button type="button" data-s="0"></button><button type="button" data-s="1"></button></div><ol class="ranklist"></ol></div>';
  document.body.appendChild(ov);
  const list = ov.querySelector('.ranklist');
  // Bomba: ranking separado de sala e individual (en sala cada uno hace menos palabras)
  const tabs = ov.querySelector('.rktabs');
  const split = game === 'bomba';
  let tab = '0';
  if (split) { tabs.hidden = false; try { tab = localStorage.getItem('pg_rank_tab_' + game) === '1' ? '1' : '0'; } catch (e) {} }
  const paintTabs = () => tabs.querySelectorAll('button').forEach(b => {
    b.textContent = b.dataset.s === '1' ? (en() ? 'Solo' : 'Individual') : (en() ? 'Room' : 'Sala');
    b.classList.toggle('on', b.dataset.s === tab);
  });
  tabs.onclick = e => {
    const b = e.target.closest('button'); if (!b || b.dataset.s === tab) return;
    tab = b.dataset.s; try { localStorage.setItem('pg_rank_tab_' + game, tab); } catch (e) {}
    paintTabs(); load();
  };

  const cache = {}, at = {};
  const paint = data => {
    const me = (() => { try { return (localStorage.getItem('jt_name') || '').trim().toLowerCase(); } catch (e) { return ''; } })();
    // en Pistas el nombre es el equipo: «A|B|C» → «A, B y C»
    const names = n => String(n).split('|').filter(Boolean);
    const join = a => a.length < 2 ? (a[0] || '') : a.slice(0, -1).join(', ') + (en() ? ' & ' : ' y ') + a[a.length - 1];
    const rows = [];
    for (let i = 0; i < 5; i++) {
      const r = data && data[i];
      rows.push(r ? `<li${me && names(r.n).some(x => x.trim().toLowerCase() === me) ? ' class="me"' : ''}><i>${i + 1}</i><span>${esc(join(names(r.n)))}</span><b>${r.v}</b></li>`
                  : `<li class="nil"><i>${i + 1}</i><span>${data ? '—' : ''}</span><b></b></li>`);
    }
    list.innerHTML = rows.join('');
  };
  const load = async () => {
    const k = split ? tab : 'all';
    if (cache[k] && Date.now() - at[k] < 60000) { paint(cache[k]); return; }
    paint(null);
    const body = { p_game: game }; if (split) body.p_solo = tab === '1';
    let d;
    try {
      const r = await fetch(URL + '/rest/v1/rpc/pg_top', { method: 'POST', headers: { 'content-type': 'application/json', apikey: KEY, authorization: 'Bearer ' + KEY }, body: JSON.stringify(body) });
      d = await r.json();
    } catch (e) { d = null; }
    if ((split ? tab : 'all') !== k) return;   // se ha cambiado de pestaña mientras cargaba
    if (!Array.isArray(d)) { paint([]); return; }
    cache[k] = d; at[k] = Date.now(); paint(d);
  };
  const close = () => { ov.hidden = true; document.removeEventListener('keydown', key); };
  const key = e => { if (e.key === 'Escape') close(); };
  row.querySelector('button').onclick = () => {
    dot.hidden = true; try { localStorage.setItem(SEEN, '1'); } catch (e) {}
    ov.querySelector('.rku').textContent = unit(); if (split) paintTabs();
    ov.hidden = false; document.addEventListener('keydown', key); load();
  };
  ov.onclick = e => { if (e.target === ov) close(); };
})();
