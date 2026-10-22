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

-- Correos que pueden ver el panel (un solo usuario administrador).
create table if not exists public.admins (email text primary key);
alter table public.admins enable row level security;

revoke all on public.events, public.admins from anon, authenticated;

-- Registro de un evento (pg_log). Lo llama el navegador con la clave anon.
-- Valida todo, limita a 60 eventos/minuto por visitante y a 3000/minuto en total.
create or replace function public.pg_log(p_kind text, p_game text, p_vid text, p_sid text, p_props jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_kind is null or p_kind not in ('view','room_create','room_join','game_start','game_end','net_fail') then return; end if;
  if p_game is null or p_game not in ('','bomba','tutti','teclazo') then return; end if;
  if p_vid is null or p_vid !~ '^[a-z0-9]{8,24}$' then return; end if;
  if p_sid is null or p_sid !~ '^[a-z0-9]{0,24}$' then return; end if;
  if p_props is null or jsonb_typeof(p_props) <> 'object' or length(p_props::text) > 300 then p_props := '{}'::jsonb; end if;
  if (select count(*) from events where vid = p_vid and ts > now() - interval '1 minute') >= 60 then return; end if;
  if (select count(*) from (select 1 from events where ts > now() - interval '1 minute' limit 3000) x) >= 3000 then return; end if;
  insert into events (kind, game, vid, sid, p) values (p_kind, p_game, p_vid, p_sid, p_props);
end $$;
revoke all on function public.pg_log(text, text, text, text, jsonb) from public;
grant execute on function public.pg_log(text, text, text, text, jsonb) to anon, authenticated;

-- Eventos con las propiedades ya convertidas a tipos seguros.
create or replace function public._ev(a timestamptz, b timestamptz)
returns table (ts timestamptz, kind text, game text, vid text, sid text, solo boolean, n int, dur int, m numeric, dev text, src text)
language sql stable set search_path = public as $$
  select e.ts, e.kind, e.game, e.vid, e.sid,
         coalesce(e.p->>'solo', 'false') = 'true',
         case when e.p->>'n'   ~ '^[0-9]{1,3}$' then (e.p->>'n')::int end,
         case when e.p->>'dur' ~ '^[0-9]{1,6}$' then (e.p->>'dur')::int end,
         case when e.p->>'m'   ~ '^[0-9]{1,6}(\.[0-9]+)?$' then (e.p->>'m')::numeric end,
         case when e.p->>'dev' in ('m','d','t') then e.p->>'dev' end,
         case when e.p->>'src' ~ '^[a-z]{1,12}$' then e.p->>'src' end
  from events e where e.ts >= a and e.ts < b;
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
    'players',  count(distinct vid) filter (where kind = 'game_start'),
    'fails',    count(*) filter (where kind = 'net_fail'),
    'avg_n',    round(avg(n) filter (where kind = 'game_start' and not solo), 1),
    'avg_dur',  round(avg(dur) filter (where kind = 'game_end'))
  ) from public._ev(a, b);
$$;
revoke all on function public._kpis(timestamptz, timestamptz) from public, anon, authenticated;

-- Todo lo que muestra el panel, en una sola llamada. Solo para los correos de la tabla admins.
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
  if lower(coalesce(auth.jwt() ->> 'email', '')) not in (select lower(email) from public.admins) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'days', d,
    'now', (select count(distinct vid) from events where ts > now() - interval '5 minutes'),
    'cur', public._kpis(t0, tn),
    'prev', public._kpis(tp, t0),
    'new', (select count(*) from (select vid from events where kind = 'view' group by vid having min(ts) >= t0) x),
    'prev_new', (select count(*) from (select vid from events where kind = 'view' group by vid having min(ts) >= tp and min(ts) < t0) x),
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
               count(distinct vid) filter (where kind = 'game_start') as players,
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
      select coalesce(jsonb_agg(jsonb_build_object('t', ts, 'k', kind, 'g', game, 'n', n, 'solo', solo) order by ts desc), '[]'::jsonb)
      from (select ts, kind, game, n, solo from public._ev(now() - interval '7 days', tn) where kind <> 'view' order by ts desc limit 14) x
    )
  ) into res;
  return res;
end $$;
revoke all on function public.admin_stats(int) from public, anon;
grant execute on function public.admin_stats(int) to authenticated;
