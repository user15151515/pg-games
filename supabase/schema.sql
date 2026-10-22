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
  if p_game is null or p_game not in ('','bomba','tutti','teclazo') then return; end if;
  if p_vid is null or p_vid !~ '^[a-z0-9]{8,24}$' then return; end if;
  if p_sid is null or p_sid !~ '^[a-z0-9]{0,24}$' then return; end if;
  if p_props is null or jsonb_typeof(p_props) <> 'object' or length(p_props::text) > 500 then p_props := '{}'::jsonb; end if;
  if (select count(*) from events where vid = p_vid and ts > now() - interval '1 minute') >= 60 then return; end if;
  if (select count(*) from (select 1 from events where ts > now() - interval '1 minute' limit 3000) x) >= 3000 then return; end if;
  insert into events (kind, game, vid, sid, p) values (p_kind, p_game, p_vid, p_sid, p_props);
  v_name := nullif(btrim(regexp_replace(left(coalesce(p_props ->> 'name', ''), 14), '[[:cntrl:]<>]', '', 'g')), '');
  if v_name is not null then
    insert into players (vid, name) values (p_vid, v_name)
    on conflict (vid) do update set name = excluded.name, last_seen = now();
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
      from (values ('bomba', 1), ('tutti', 2), ('teclazo', 3)) as gm(g, o)
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
      from (select ts, kind, game, n, solo, name, names from public._ev(now() - interval '7 days', tn) where kind <> 'view' order by ts desc limit 30) x
    )
  ) into res;
  return res;
end $$;
revoke all on function public.admin_stats(int) from public, anon;
grant execute on function public.admin_stats(int) to authenticated;

-- Lista de jugadores con su actividad, incluidos los ocultos y los que juegan sin escribir nombre.
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
    select v.vid, pl.name, (h.vid is not null) as hidden,
           coalesce(pl.first_seen, (select min(e.ts) from events e where e.vid = v.vid)) as first,
           greatest(pl.last_seen, (select max(e.ts) from events e where e.vid = v.vid)) as last,
           (select count(*) from events e where e.vid = v.vid and e.kind = 'game_start' and e.ts >= t0) as hosted,
           (select count(*) from events e where e.vid = v.vid and e.kind = 'room_join' and e.ts >= t0) as joined,
           (select count(*) from events e where e.vid = v.vid and e.kind = 'view' and e.ts >= t0) as visits,
           (select coalesce(jsonb_agg(distinct e.game), '[]'::jsonb) from events e where e.vid = v.vid and e.game <> '' and e.kind in ('game_start', 'room_join', 'room_create') and e.ts >= t0) as games,
           (select e.p ->> 'dev' from events e where e.vid = v.vid and e.kind = 'view' and e.p ? 'dev' order by e.ts desc limit 1) as dev
    from (
      select vid from players where last_seen >= t0
      union
      select distinct vid from events where kind in ('game_start', 'room_join', 'room_create') and ts >= t0
    ) v
    left join players pl on pl.vid = v.vid
    left join hidden_vids h on h.vid = v.vid
    order by 5 desc limit 300
  ) r;
  return res;
end $$;
revoke all on function public.admin_players(int) from public, anon;
grant execute on function public.admin_players(int) to authenticated;

-- Ocultar o mostrar un dispositivo (sus eventos dejan de contar en todas las estadísticas).
create or replace function public.admin_hide(p_vid text, p_hide boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public._is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_vid is null or p_vid !~ '^[a-z0-9]{8,24}$' then return; end if;
  if p_hide then insert into hidden_vids (vid) values (p_vid) on conflict do nothing;
  else delete from hidden_vids where vid = p_vid; end if;
end $$;
revoke all on function public.admin_hide(text, boolean) from public, anon;
grant execute on function public.admin_hide(text, boolean) to authenticated;
