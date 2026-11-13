-- pg games · estadísticas propias
-- Ejecutar entero en el SQL Editor del proyecto Supabase de pg games (el nuevo e independiente).
-- Es repetible: se puede volver a ejecutar sin perder datos.

-- Eventos anónimos. Nadie los lee ni escribe directamente desde la API: solo a través de las funciones de abajo.
create table if not exists public.events (
  id   bigint generated always as identity primary key,
  ts   timestamptz not null default now(),
  kind text not null,
  game text not null default '',
  vid  text not null,
  sid  text not null default '',
  p    jsonb not null default '{}'::jsonb
);
create index if not exists events_ts_idx on public.events (ts);
create index if not exists events_vid_ts_idx on public.events (vid, ts);
alter table public.events enable row level security;

-- Alias de cada dispositivo (el nombre que escribe el jugador, máx. 14 caracteres). Sirve para distinguir público real de pruebas.
create table if not exists public.players (
  vid        text primary key,
  name       text not null,
  first_seen timestamptz not null default now(),
  last_seen  timestamptz not null default now()
);
alter table public.players enable row level security;
-- Cada dispositivo es una cuenta: «name» es el primer nombre que escribió y «names», todos los que ha usado por orden.
alter table public.players add column if not exists names jsonb not null default '[]'::jsonb;
with n as (
  select vid, nm, min(ts) as t from (
    select vid, ts, nullif(btrim(regexp_replace(left(coalesce(p ->> 'name', ''), 14), '[[:cntrl:]<>]', '', 'g')), '') as nm
    from public.events where p ? 'name') x
  where nm is not null group by vid, nm
)
update public.players pl set names = s.names, name = s.names ->> 0
from (select vid, jsonb_agg(nm order by t) as names from n group by vid) s
where s.vid = pl.vid and pl.names = '[]'::jsonb;

-- Cuentas con varios dispositivos: «vid» pertenece a la cuenta cuyo dispositivo principal es «main». Solo lo cambia el administrador.
create table if not exists public.merges (vid text primary key, main text not null, ts timestamptz not null default now());
create index if not exists merges_main_idx on public.merges (main);
alter table public.merges enable row level security;
revoke all on public.merges from anon, authenticated;

-- Cuenta de un dispositivo, dispositivos de una cuenta, nombre visible y todos los nombres usados.
create or replace function public._acct(p text) returns text language sql stable set search_path = public as $$
  select coalesce((select main from merges where vid = p), p);
$$;
create or replace function public._members(a text) returns text[] language sql stable set search_path = public as $$
  select array[a] || coalesce((select array_agg(vid order by ts) from merges where main = a), '{}'::text[]);
$$;
create or replace function public._aname(a text) returns text language sql stable set search_path = public as $$
  select pl.name from players pl where pl.vid = any(public._members(a)) order by (pl.vid = a) desc, pl.first_seen limit 1;
$$;
create or replace function public._anames(a text) returns jsonb language sql stable set search_path = public as $$
  select coalesce(jsonb_agg(n order by o), '[]'::jsonb) from (
    select t.n, min(case when pl.vid = a then 0 else 1000 end + t.i) as o
    from players pl, jsonb_array_elements_text(pl.names) with ordinality t(n, i)
    where pl.vid = any(public._members(a)) group by t.n) x;
$$;
revoke all on function public._acct(text), public._members(text), public._aname(text), public._anames(text) from public, anon, authenticated;

-- Dispositivos que el administrador ha ocultado: sus eventos no cuentan en ninguna estadística.
create table if not exists public.hidden_vids (vid text primary key, ts timestamptz not null default now());
alter table public.hidden_vids enable row level security;

-- Correos que pueden ver el panel (un solo usuario administrador).
create table if not exists public.admins (email text primary key);
alter table public.admins enable row level security;

revoke all on public.events, public.players, public.hidden_vids, public.admins from anon, authenticated;

-- ¿Quien llama es administrador?
create or replace function public._is_admin() returns boolean language sql stable security definer set search_path = public as $$
  select lower(coalesce(auth.jwt() ->> 'email', '')) in (select lower(email) from public.admins);
$$;
revoke all on function public._is_admin() from public, anon, authenticated;

-- Registro de un evento (pg_log). Lo llama el navegador con la clave anon.
-- Valida todo, limita a 60 eventos/minuto por visitante y a 3000/minuto en total.
create or replace function public.pg_log(p_kind text, p_game text, p_vid text, p_sid text, p_props jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_name text;
begin
  if p_kind is null or p_kind not in ('view','room_create','room_join','game_start','game_end','net_fail') then return; end if;
  if p_game is null or p_game not in ('','bomba','tutti','teclazo','pistas') then return; end if;
  if p_vid is null or p_vid !~ '^[a-z0-9]{8,24}$' then return; end if;
  if p_sid is null or p_sid !~ '^[a-z0-9]{0,24}$' then return; end if;
  if p_props is null or jsonb_typeof(p_props) <> 'object' or length(p_props::text) > 500 then p_props := '{}'::jsonb; end if;
  if (select count(*) from events where vid = p_vid and ts > now() - interval '1 minute') >= 60 then return; end if;
  if (select count(*) from (select 1 from events where ts > now() - interval '1 minute' limit 3000) x) >= 3000 then return; end if;
  insert into events (kind, game, vid, sid, p) values (p_kind, p_game, p_vid, p_sid, p_props);
  v_name := nullif(btrim(regexp_replace(left(coalesce(p_props ->> 'name', ''), 14), '[[:cntrl:]<>]', '', 'g')), '');
  if v_name is not null then
    insert into players (vid, name, names) values (p_vid, v_name, jsonb_build_array(v_name))
    on conflict (vid) do update set last_seen = now(),
      names = case when players.names ? v_name or jsonb_array_length(players.names) >= 20 then players.names
                   else players.names || jsonb_build_array(v_name) end;
  end if;
end $$;
revoke all on function public.pg_log(text, text, text, text, jsonb) from public;
grant execute on function public.pg_log(text, text, text, text, jsonb) to anon, authenticated;

-- Eventos con las propiedades ya convertidas a tipos seguros, sin los dispositivos ocultos.
drop function if exists public._ev(timestamptz, timestamptz);
create or replace function public._ev(a timestamptz, b timestamptz)
returns table (ts timestamptz, kind text, game text, vid text, sid text, solo boolean, n int, dur int, m numeric, dev text, src text, name text, names jsonb)
language sql stable set search_path = public as $$
  select e.ts, e.kind, e.game, e.vid, e.sid,
         coalesce(e.p->>'solo', 'false') = 'true',
         case when e.p->>'n'   ~ '^[0-9]{1,3}$' then (e.p->>'n')::int end,
         case when e.p->>'dur' ~ '^[0-9]{1,6}$' then (e.p->>'dur')::int end,
         case when e.p->>'m'   ~ '^[0-9]{1,6}(\.[0-9]+)?$' then (e.p->>'m')::numeric end,
         case when e.p->>'dev' in ('m','d','t') then e.p->>'dev' end,
         case when e.p->>'src' ~ '^[a-z]{1,12}$' then e.p->>'src' end,
         nullif(btrim(regexp_replace(left(coalesce(e.p->>'name', ''), 14), '[[:cntrl:]<>]', '', 'g')), ''),
         case when jsonb_typeof(e.p->'names') = 'array' then e.p->'names' end
  from events e
  where e.ts >= a and e.ts < b and e.vid not in (select h.vid from hidden_vids h);
$$;
revoke all on function public._ev(timestamptz, timestamptz) from public, anon, authenticated;

create or replace function public._kpis(a timestamptz, b timestamptz)
returns jsonb language sql stable set search_path = public as $$
  select jsonb_build_object(
    'visitors', count(distinct vid) filter (where kind = 'view'),
    'views',    count(*) filter (where kind = 'view'),
    'sessions', count(distinct sid) filter (where kind = 'view' and sid <> ''),
    'rooms',    count(*) filter (where kind = 'room_create'),
    'joins',    count(*) filter (where kind = 'room_join'),
    'started',  count(*) filter (where kind = 'game_start'),
    'finished', count(*) filter (where kind = 'game_end'),
    'solo',     count(*) filter (where kind = 'game_start' and solo),
    'players',  count(distinct vid) filter (where kind in ('game_start', 'room_join')),
    'fails',    count(*) filter (where kind = 'net_fail'),
    'avg_n',    round(avg(n) filter (where kind = 'game_start' and not solo), 1),
    'avg_dur',  round(avg(dur) filter (where kind = 'game_end'))
  ) from public._ev(a, b);
$$;
revoke all on function public._kpis(timestamptz, timestamptz) from public, anon, authenticated;

-- Todo lo que muestra el panel (menos la lista de jugadores), en una sola llamada. Solo para los correos de la tabla admins.
create or replace function public.admin_stats(p_days int default 30)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  tz    constant text := 'Europe/Madrid';
  d     int  := greatest(1, least(coalesce(p_days, 30), 365));
  today date := (now() at time zone tz)::date;
  t0    timestamptz := ((today - (d - 1))::timestamp) at time zone tz;
  tp    timestamptz := ((today - (2 * d - 1))::timestamp) at time zone tz;
  tn    timestamptz := now() + interval '1 minute';
  res   jsonb;
begin
  if not public._is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;

  select jsonb_build_object(
    'days', d,
    'now', (select count(distinct vid) from events where ts > now() - interval '5 minutes' and vid not in (select vid from hidden_vids)),
    'cur', public._kpis(t0, tn),
    'prev', public._kpis(tp, t0),
    'new', (select count(*) from (select vid from events where kind = 'view' and vid not in (select vid from hidden_vids) group by vid having min(ts) >= t0) x),
    'prev_new', (select count(*) from (select vid from events where kind = 'view' and vid not in (select vid from hidden_vids) group by vid having min(ts) >= tp and min(ts) < t0) x),
    'hidden', (select count(*) from hidden_vids),
    'daily', (
      select coalesce(jsonb_agg(jsonb_build_object('d', to_char(s.day, 'YYYY-MM-DD'), 'v', coalesce(x.v, 0), 'pv', coalesce(x.pv, 0), 'g', coalesce(x.g, 0)) order by s.day), '[]'::jsonb)
      from generate_series(today - (d - 1), today, interval '1 day') as s(day)
      left join (
        select (ts at time zone tz)::date as day,
               count(distinct vid) filter (where kind = 'view') as v,
               count(*) filter (where kind = 'view') as pv,
               count(*) filter (where kind = 'game_start') as g
        from public._ev(t0, tn) group by 1
      ) x on x.day = s.day::date
    ),
    'games', (
      select jsonb_agg(jsonb_build_object(
        'game', gm.g, 'views', coalesce(s.views, 0), 'rooms', coalesce(s.rooms, 0), 'joins', coalesce(s.joins, 0),
        'started', coalesce(s.started, 0), 'finished', coalesce(s.finished, 0), 'solo', coalesce(s.solo, 0),
        'players', coalesce(s.players, 0), 'avg_n', s.avg_n, 'avg_dur', s.avg_dur, 'avg_m', s.avg_m, 'best_m', s.best_m
      ) order by gm.o)
      from (values ('bomba', 1), ('tutti', 2), ('teclazo', 3), ('pistas', 4)) as gm(g, o)
      left join (
        select game,
               count(*) filter (where kind = 'view') as views,
               count(*) filter (where kind = 'room_create') as rooms,
               count(*) filter (where kind = 'room_join') as joins,
               count(*) filter (where kind = 'game_start') as started,
               count(*) filter (where kind = 'game_end') as finished,
               count(*) filter (where kind = 'game_start' and solo) as solo,
               count(distinct vid) filter (where kind in ('game_start', 'room_join')) as players,
               round(avg(n) filter (where kind = 'game_start' and not solo), 1) as avg_n,
               round(avg(dur) filter (where kind = 'game_end')) as avg_dur,
               round(avg(m) filter (where kind = 'game_end'), 1) as avg_m,
               max(m) filter (where kind = 'game_end') as best_m
        from public._ev(t0, tn) where game <> '' group by game
      ) s on s.game = gm.g
    ),
    'heat', (
      select coalesce(jsonb_agg(jsonb_build_object('w', w, 'h', h, 'n', c)), '[]'::jsonb)
      from (select extract(isodow from ts at time zone tz)::int as w, extract(hour from ts at time zone tz)::int as h, count(*) as c
            from public._ev(t0, tn) where kind = 'view' group by 1, 2) x
    ),
    'sizes', (
      select coalesce(jsonb_agg(jsonb_build_object('n', n, 'c', c) order by n), '[]'::jsonb)
      from (select n, count(*) as c from public._ev(t0, tn) where kind = 'game_start' and not solo and n is not null group by n) x
    ),
    'devices', (
      select coalesce(jsonb_agg(jsonb_build_object('k', dev, 'n', c) order by c desc), '[]'::jsonb)
      from (select dev, count(*) as c from public._ev(t0, tn) where kind = 'view' and dev is not null group by dev) x
    ),
    'sources', (
      select coalesce(jsonb_agg(jsonb_build_object('k', src, 'n', c) order by c desc), '[]'::jsonb)
      from (select src, count(*) as c from public._ev(t0, tn) where kind = 'view' and src is not null group by src order by c desc limit 8) x
    ),
    'recent', (
      select coalesce(jsonb_agg(jsonb_build_object('t', ts, 'k', kind, 'g', game, 'n', n, 'solo', solo, 'name', name, 'names', names) order by ts desc), '[]'::jsonb)
      from (select e.ts, e.kind, e.game, e.n, e.solo, coalesce(pl.name, e.name) as name, e.names
            from public._ev(now() - interval '7 days', tn) e left join merges mg on mg.vid = e.vid left join players pl on pl.vid = coalesce(mg.main, e.vid)
            where e.kind <> 'view' order by e.ts desc limit 30) x
    )
  ) into res;
  return res;
end $$;
revoke all on function public.admin_stats(int) from public, anon;
grant execute on function public.admin_stats(int) to authenticated;



-- Resumen de cada partida (jugadores, puntos, respuestas o palabras). Lo envía quien crea la partida al terminarla.
create table if not exists public.game_logs (
  id   bigint generated always as identity primary key,
  ts   timestamptz not null default now(),
  game text not null,
  vid  text not null,
  solo boolean not null default false,
  d    jsonb not null
);
create index if not exists game_logs_vid_ts_idx on public.game_logs (vid, ts);
create index if not exists game_logs_d_idx on public.game_logs using gin (d jsonb_path_ops);
alter table public.game_logs enable row level security;
revoke all on public.game_logs from anon, authenticated;

create or replace function public.pg_game(p_game text, p_vid text, p_detail jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_game is null or p_game not in ('bomba', 'tutti', 'teclazo', 'pistas') then return; end if;
  if p_vid is null or p_vid !~ '^[a-z0-9]{8,24}$' then return; end if;
  if p_detail is null or jsonb_typeof(p_detail) <> 'object' or jsonb_typeof(p_detail -> 'pl') <> 'array' then return; end if;
  if jsonb_array_length(p_detail -> 'pl') not between 1 and 8 or length(p_detail::text) > 64000 then return; end if;
  if jsonb_typeof(p_detail -> 'solo') is distinct from 'boolean' then return; end if;
  if (select count(*) from game_logs where vid = p_vid and ts > now() - interval '1 minute') >= 10 then return; end if;
  if (select count(*) from (select 1 from game_logs where ts > now() - interval '1 minute' limit 600) x) >= 600 then return; end if;
  insert into game_logs (game, vid, solo, d) values (p_game, p_vid, (p_detail ->> 'solo')::boolean, p_detail);
exception when others then return;
end $$;
revoke all on function public.pg_game(text, text, jsonb) from public;
grant execute on function public.pg_game(text, text, jsonb) to anon, authenticated;

create or replace function public.admin_players(p_days int default 90)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  tz constant text := 'Europe/Madrid';
  d  int := greatest(1, least(coalesce(p_days, 90), 365));
  t0 timestamptz := (((now() at time zone tz)::date - (d - 1))::timestamp) at time zone tz;
  res jsonb;
begin
  if not public._is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(to_jsonb(r) order by r.last desc), '[]'::jsonb) into res
  from (
    select x.a as vid, public._aname(x.a) as name, public._anames(x.a) as names, cardinality(x.ms) as devs,
           exists (select 1 from hidden_vids h where h.vid = any(x.ms)) as hidden,
           least((select min(first_seen) from players where vid = any(x.ms)), (select min(e.ts) from events e where e.vid = any(x.ms))) as first,
           greatest((select max(last_seen) from players where vid = any(x.ms)), (select max(e.ts) from events e where e.vid = any(x.ms))) as last,
           (select count(*) from events e where e.vid = any(x.ms) and e.kind = 'game_start' and e.ts >= t0) as hosted,
           (select count(*) from events e where e.vid = any(x.ms) and e.kind = 'room_join' and e.ts >= t0) as joined,
           (select count(*) from events e where e.vid = any(x.ms) and e.kind = 'view' and e.ts >= t0) as visits,
           (select count(*) from game_logs g where g.vid = any(x.ms) or exists (select 1 from jsonb_array_elements(g.d -> 'pl') y where y ->> 'pv' = any(x.ms))) as played,
           (select coalesce(jsonb_agg(distinct e.game), '[]'::jsonb) from events e where e.vid = any(x.ms) and e.game <> '' and e.kind in ('game_start', 'room_join', 'room_create') and e.ts >= t0) as games,
           (select coalesce(jsonb_agg(distinct e.p ->> 'dev'), '[]'::jsonb) from events e where e.vid = any(x.ms) and e.kind = 'view' and e.p ->> 'dev' in ('m', 'd', 't')) as dev
    from (select a, public._members(a) as ms from (
            select distinct public._acct(vid) as a from (
              select vid from players where last_seen >= t0
              union
              select distinct vid from events where kind in ('game_start', 'room_join', 'room_create') and ts >= t0
            ) v) y) x
  ) r;
  return res;
end $$;
revoke all on function public.admin_players(int) from public, anon;
grant execute on function public.admin_players(int) to authenticated;

create or replace function public.admin_hide(p_vid text, p_hide boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public._is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_vid is null or p_vid !~ '^[a-z0-9]{8,24}$' then return; end if;
  if p_hide then insert into hidden_vids (vid) select unnest(public._members(public._acct(p_vid))) on conflict do nothing;
  else delete from hidden_vids where vid = any(public._members(public._acct(p_vid))); end if;
end $$;
revoke all on function public.admin_hide(text, boolean) from public, anon;
grant execute on function public.admin_hide(text, boolean) to authenticated;

create or replace function public.admin_player_games(p_vid text, p_limit int default 40)
returns jsonb language plpgsql security definer set search_path = public as $$
declare res jsonb; ms text[];
begin
  if not public._is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_vid is null or p_vid !~ '^[a-z0-9]{8,24}$' then return '[]'::jsonb; end if;
  ms := public._members(public._acct(p_vid));
  select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'ts', g.ts, 'game', g.game, 'host', g.vid = any(ms), 'solo', g.solo, 'd', g.d) order by g.ts desc), '[]'::jsonb) into res
  from (select * from game_logs gl
        where gl.vid = any(ms) or exists (select 1 from jsonb_array_elements(gl.d -> 'pl') y where y ->> 'pv' = any(ms))
        order by ts desc limit greatest(1, least(coalesce(p_limit, 40), 300))) g;
  return res;
end $$;
revoke all on function public.admin_player_games(text, int) from public, anon;
grant execute on function public.admin_player_games(text, int) to authenticated;

create or replace function public.admin_activity(p_days int default 7)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  tz constant text := 'Europe/Madrid';
  d  int := greatest(1, least(coalesce(p_days, 7), 365));
  t0 timestamptz := (((now() at time zone tz)::date - (d - 1))::timestamp) at time zone tz;
  res jsonb;
begin
  if not public._is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  select jsonb_build_object(
    'events', (
      select coalesce(jsonb_agg(jsonb_build_object('t', e.ts, 'k', e.kind, 'g', e.game, 'v', e.vid,
               'nm', coalesce(pl.name, pv.name, nullif(e.p ->> 'name', '')), 'room', e.p ->> 'room',
               'n', case when e.p ->> 'n' ~ '^[0-9]{1,3}$' then (e.p ->> 'n')::int end,
               'solo', coalesce(e.p ->> 'solo', 'false') = 'true') order by e.ts), '[]'::jsonb)
      from (select * from events where ts >= t0 and kind in ('room_create', 'room_join', 'game_start', 'game_end')
              order by ts desc limit 3000) e
      left join merges mg on mg.vid = e.vid
      left join players pl on pl.vid = coalesce(mg.main, e.vid)
      left join players pv on pv.vid = e.vid
    ),
    'logs', (
      select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'ts', g.ts, 'game', g.game, 'v', g.vid, 'solo', g.solo, 'room', g.d ->> 'room', 'd', g.d) order by g.ts), '[]'::jsonb)
      from (select * from game_logs where ts >= t0 order by ts desc limit 400) g
    ),
    'hidden', (select coalesce(jsonb_agg(vid), '[]'::jsonb) from hidden_vids)
  ) into res;
  return res;
end $$;
revoke all on function public.admin_activity(int) from public, anon;
grant execute on function public.admin_activity(int) to authenticated;

create or replace function public.admin_player(p_vid text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  tz constant text := 'Europe/Madrid';
  a  text;
  ms text[];
  res jsonb;
begin
  if not public._is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_vid is null or p_vid !~ '^[a-z0-9]{8,24}$' then return null; end if;
  a := public._acct(p_vid); ms := public._members(a);
  select jsonb_build_object(
    'vid', a, 'vids', to_jsonb(ms), 'name', public._aname(a), 'names', public._anames(a),
    'hidden', exists (select 1 from hidden_vids where vid = any(ms)),
    'first', least((select min(first_seen) from players where vid = any(ms)), (select min(ts) from events where vid = any(ms))),
    'last', greatest((select max(last_seen) from players where vid = any(ms)), (select max(ts) from events where vid = any(ms))),
    'visits', (select count(*) from events where vid = any(ms) and kind = 'view'),
    'days', (select count(distinct (ts at time zone tz)::date) from events where vid = any(ms)),
    'devices', (
      select jsonb_agg(jsonb_build_object('v', m.v, 'main', m.v = a, 'nm', pl.name, 'names', coalesce(pl.names, '[]'::jsonb),
               'dev', (select e.p ->> 'dev' from events e where e.vid = m.v and e.kind = 'view' and e.p ? 'dev' order by e.ts desc limit 1),
               'first', least(pl.first_seen, (select min(ts) from events where vid = m.v)),
               'last', greatest(pl.last_seen, (select max(ts) from events where vid = m.v)),
               'visits', (select count(*) from events where vid = m.v and kind = 'view'),
               'hidden', exists (select 1 from hidden_vids where vid = m.v)) order by m.o)
      from unnest(ms) with ordinality m(v, o) left join players pl on pl.vid = m.v
    ),
    'mates', (
      select coalesce(jsonb_agg(jsonb_build_object('v', m.pv, 'nm', coalesce(public._aname(m.pv), m.nm), 'n', m.n, 't', m.t,
               'hidden', exists (select 1 from hidden_vids h where h.vid = any(public._members(m.pv)))) order by m.n desc, m.t desc), '[]'::jsonb)
      from (select public._acct(x ->> 'pv') as pv, max(x ->> 'nm') as nm, count(distinct g.id) as n, max(g.ts) as t
            from game_logs g, jsonb_array_elements(g.d -> 'pl') x
            where exists (select 1 from jsonb_array_elements(g.d -> 'pl') y where y ->> 'pv' = any(ms))
              and x ->> 'pv' ~ '^[a-z0-9]{8,24}$' and not (x ->> 'pv' = any(ms))
            group by 1 order by 3 desc, 4 desc limit 60) m
    ),
    'rooms', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'room', r.room, 'g', r.game, 't', r.t, 'own', r.own,
               'games', (select count(*) from game_logs gl where gl.game = r.game and gl.d ->> 'room' = r.room and (gl.ts at time zone tz)::date = r.dy),
               'ppl', (select coalesce(jsonb_agg(jsonb_build_object('v', q.a, 'nm', coalesce(public._aname(q.a), q.nm)) order by q.t), '[]'::jsonb)
                       from (select public._acct(e.vid) as a, max(e.p ->> 'name') as nm, min(e.ts) as t
                             from events e
                             where e.game = r.game and e.p ->> 'room' = r.room and (e.ts at time zone tz)::date = r.dy
                               and not (e.vid = any(ms)) and e.kind in ('room_create', 'room_join', 'game_start', 'game_end')
                             group by 1) q)
             ) order by r.t desc), '[]'::jsonb)
      from (select e.p ->> 'room' as room, e.game, (e.ts at time zone tz)::date as dy, min(e.ts) as t, bool_or(e.kind = 'room_create') as own
            from events e
            where e.vid = any(ms) and e.kind in ('room_create', 'room_join', 'game_start', 'game_end') and e.p ->> 'room' ~ '^[A-Z]{4}$'
            group by 1, 2, 3 order by 4 desc limit 80) r
    )
  ) into res;
  return res;
end $$;
revoke all on function public.admin_player(text) from public, anon;
grant execute on function public.admin_player(text) to authenticated;

-- Cambiar a mano el nombre que se ve de una cuenta (solo en el panel). Vacío = volver al primer nombre que escribió.
create or replace function public.admin_rename(p_vid text, p_name text)
returns text language plpgsql security definer set search_path = public as $$
declare
  v text := nullif(btrim(regexp_replace(left(coalesce(p_name, ''), 24), '[[:cntrl:]<>]', '', 'g')), '');
  a text;
begin
  if not public._is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_vid is null or p_vid !~ '^[a-z0-9]{8,24}$' then return null; end if;
  a := public._acct(p_vid);
  if v is null then
    update players set name = coalesce(names ->> 0, name) where vid = a returning name into v;
    return v;
  end if;
  insert into players (vid, name, first_seen, last_seen)
  values (a, v, coalesce((select min(ts) from events where vid = a), now()), coalesce((select max(ts) from events where vid = a), now()))
  on conflict (vid) do update set name = excluded.name;
  return v;
end $$;
revoke all on function public.admin_rename(text, text) from public, anon;
grant execute on function public.admin_rename(text, text) to authenticated;

-- Unir la cuenta de p_other a la de p_main (misma persona en varios dispositivos). Se queda el nombre de p_main.
create or replace function public.admin_merge(p_main text, p_other text)
returns text language plpgsql security definer set search_path = public as $$
declare a text; b text;
begin
  if not public._is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_main !~ '^[a-z0-9]{8,24}$' or p_other !~ '^[a-z0-9]{8,24}$' then return null; end if;
  a := public._acct(p_main); b := public._acct(p_other);
  if a = b then return a; end if;
  update merges set main = a where main = b;
  insert into merges (vid, main) values (b, a) on conflict (vid) do update set main = excluded.main, ts = now();
  return a;
end $$;
revoke all on function public.admin_merge(text, text) from public, anon;
grant execute on function public.admin_merge(text, text) to authenticated;

-- Separar un dispositivo de su cuenta. Si es el principal, el siguiente dispositivo pasa a ser el principal de los demás.
create or replace function public.admin_unmerge(p_vid text)
returns void language plpgsql security definer set search_path = public as $$
declare nm text;
begin
  if not public._is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_vid is null or p_vid !~ '^[a-z0-9]{8,24}$' then return; end if;
  if exists (select 1 from merges where vid = p_vid) then delete from merges where vid = p_vid; return; end if;
  select vid into nm from merges where main = p_vid order by ts limit 1;
  if nm is null then return; end if;
  delete from merges where vid = nm;
  update merges set main = nm where main = p_vid;
end $$;
revoke all on function public.admin_unmerge(text) from public, anon;
grant execute on function public.admin_unmerge(text) to authenticated;
