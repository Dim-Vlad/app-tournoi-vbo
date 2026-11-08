-- =====================================================================
--  Tournoi VBO — Schéma initial Supabase (PostgreSQL)
--  Volley-Ball Ollioulais — app de gestion de tournois de volley
--
--  Modèle de comptes :
--    • Admin           : crée et gère tout (role = 'admin')
--    • Référent gymnase : suit tous les tournois, saisit les matchs sur
--                         place (role = 'referent', créé par l'admin avec
--                         e-mail + mot de passe)
--    • Capitaine        : AUCUN compte. Rejoint un tournoi via son code
--                         (join_code) et saisit ses scores via des
--                         fonctions RPC sécurisées (voir plus bas).
--
--  À appliquer dans l'éditeur SQL Supabase, ou via `supabase db push`.
-- =====================================================================

create extension if not exists "pgcrypto";   -- gen_random_uuid()

-- ---------------------------------------------------------------------
--  Types énumérés
-- ---------------------------------------------------------------------
do $$ begin
  create type user_role         as enum ('admin', 'referent');
exception when duplicate_object then null; end $$;

do $$ begin
  create type tournament_status as enum ('draft', 'live', 'closed');
exception when duplicate_object then null; end $$;

do $$ begin
  create type match_status      as enum ('todo', 'pending', 'live', 'valid');
exception when duplicate_object then null; end $$;

do $$ begin
  create type phase_type        as enum ('brassage', 'principal', 'consolante', 'finales');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------
--  profiles : 1 ligne par utilisateur authentifié (admin ou référent)
--  Liée à auth.users ; alimentée automatiquement par un trigger.
-- ---------------------------------------------------------------------
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  role        user_role   not null default 'referent',
  full_name   text        not null default '',
  email       text,
  status      text        not null default 'active' check (status in ('active', 'suspended')),
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
--  tournaments
--  config jsonb = tout le paramétrage (poules, teamsPerPool, sets, timed,
--  setMinutes, pointsPerSet, twoPointGap, scheduleMode, finalStart,
--  phaseConsolante, splitPhase2ByGym, …) — souple pour suivre l'app.
-- ---------------------------------------------------------------------
create table if not exists public.tournaments (
  id           uuid primary key default gen_random_uuid(),
  created_by   uuid references public.profiles(id) on delete set null,
  name         text not null,
  event_date   date,
  place        text,
  status       tournament_status not null default 'draft',
  archived     boolean not null default false,
  join_code    text unique,
  live_phase   phase_type not null default 'brassage',
  config       jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now(),
  launched_at  timestamptz,
  closed_at    timestamptz
);
create index if not exists idx_tournaments_status on public.tournaments(status) where archived = false;

-- ---------------------------------------------------------------------
--  gyms (gymnases d'un tournoi)
-- ---------------------------------------------------------------------
create table if not exists public.gyms (
  id            uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  name          text not null,
  position      int  not null default 0
);
create index if not exists idx_gyms_tournament on public.gyms(tournament_id);

-- ---------------------------------------------------------------------
--  teams (équipes)
-- ---------------------------------------------------------------------
create table if not exists public.teams (
  id            uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  name          text not null,
  level         int,
  created_at    timestamptz not null default now()
);
create index if not exists idx_teams_tournament on public.teams(tournament_id);

-- ---------------------------------------------------------------------
--  pools (poules) — une poule appartient à une phase et un gymnase/terrain
-- ---------------------------------------------------------------------
create table if not exists public.pools (
  id            uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  letter        text not null,
  phase         phase_type not null default 'brassage',
  gym_id        uuid references public.gyms(id) on delete set null,
  court         int
);
create index if not exists idx_pools_tournament on public.pools(tournament_id);

-- ---------------------------------------------------------------------
--  pool_teams : appartenance équipe ↔ poule (+ seed de départ)
-- ---------------------------------------------------------------------
create table if not exists public.pool_teams (
  id       uuid primary key default gen_random_uuid(),
  pool_id  uuid not null references public.pools(id) on delete cascade,
  team_id  uuid not null references public.teams(id) on delete cascade,
  seed     int,
  unique (pool_id, team_id)
);

-- ---------------------------------------------------------------------
--  matches
--  score_a / score_b = score en sets gagnés ; sets = détail jsonb
--  ex. [{"a":25,"b":18},{"a":23,"b":25},{"a":15,"b":12}]
-- ---------------------------------------------------------------------
create table if not exists public.matches (
  id             uuid primary key default gen_random_uuid(),
  tournament_id  uuid not null references public.tournaments(id) on delete cascade,
  pool_id        uuid references public.pools(id) on delete set null,
  phase          phase_type not null default 'brassage',
  round          int,
  scheduled_time text,
  gym_id         uuid references public.gyms(id) on delete set null,
  court          int,
  team_a         uuid references public.teams(id) on delete set null,
  team_b         uuid references public.teams(id) on delete set null,
  referee_team   uuid references public.teams(id) on delete set null,
  status         match_status not null default 'todo',
  score_a        int,
  score_b        int,
  sets           jsonb,
  validated_at   timestamptz,
  created_at     timestamptz not null default now()
);
create index if not exists idx_matches_tournament on public.matches(tournament_id);
create index if not exists idx_matches_status     on public.matches(tournament_id, status);

-- ---------------------------------------------------------------------
--  score_entries : double saisie par les capitaines (validation croisée)
--  1 saisie par (match, équipe qui saisit). Quand les 2 saisies
--  concordent, le match passe en 'valid' (voir submit_score()).
-- ---------------------------------------------------------------------
create table if not exists public.score_entries (
  id         uuid primary key default gen_random_uuid(),
  match_id   uuid not null references public.matches(id) on delete cascade,
  team_id    uuid not null references public.teams(id)   on delete cascade,
  score_a    int  not null,
  score_b    int  not null,
  sets       jsonb,
  created_at timestamptz not null default now(),
  unique (match_id, team_id)
);

-- =====================================================================
--  Fonctions utilitaires de rôle (SECURITY DEFINER → pas de récursion RLS)
-- =====================================================================
create or replace function public.current_role()
returns user_role language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid();
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin' and status = 'active'
  );
$$;

create or replace function public.is_staff()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and status = 'active'
  );
$$;

-- ---------------------------------------------------------------------
--  Trigger : création automatique du profil à l'inscription d'un user.
--  Le rôle et le nom sont lus depuis user_metadata (fournis par l'admin
--  lors de la création du compte référent via l'API admin Supabase).
-- ---------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, full_name, role, status)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce((new.raw_user_meta_data->>'role')::user_role, 'referent'),
    'active'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- =====================================================================
--  Row-Level Security
-- =====================================================================
alter table public.profiles      enable row level security;
alter table public.tournaments   enable row level security;
alter table public.gyms          enable row level security;
alter table public.teams         enable row level security;
alter table public.pools         enable row level security;
alter table public.pool_teams    enable row level security;
alter table public.matches       enable row level security;
alter table public.score_entries enable row level security;

-- ---- profiles -------------------------------------------------------
create policy "profiles: lecture (soi-même ou admin)"
  on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_admin());

create policy "profiles: l'admin gère tout"
  on public.profiles for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy "profiles: mise à jour de son propre nom"
  on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- ---- tournaments ----------------------------------------------------
create policy "tournaments: admin accès total"
  on public.tournaments for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy "tournaments: référent lecture seule"
  on public.tournaments for select to authenticated
  using (public.current_role() = 'referent');

-- ---- helper : accès staff en lecture + écriture match pour le staff --
--  Les tables de contenu (gyms/teams/pools/pool_teams/matches/
--  score_entries) : admin = tout ; référent = lecture de tout + mise à
--  jour des matchs (saisie sur place). On factorise par table ci-dessous.

-- gyms
create policy "gyms: admin tout"     on public.gyms for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy "gyms: staff lecture"  on public.gyms for select to authenticated
  using (public.is_staff());

-- teams
create policy "teams: admin tout"    on public.teams for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy "teams: staff lecture" on public.teams for select to authenticated
  using (public.is_staff());

-- pools
create policy "pools: admin tout"    on public.pools for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy "pools: staff lecture" on public.pools for select to authenticated
  using (public.is_staff());

-- pool_teams
create policy "pool_teams: admin tout"    on public.pool_teams for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy "pool_teams: staff lecture" on public.pool_teams for select to authenticated
  using (public.is_staff());

-- matches : admin tout ; référent lecture + update (saisie des scores)
create policy "matches: admin tout"       on public.matches for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy "matches: staff lecture"    on public.matches for select to authenticated
  using (public.is_staff());
create policy "matches: référent saisie"  on public.matches for update to authenticated
  using (public.current_role() = 'referent')
  with check (public.current_role() = 'referent');

-- score_entries : admin + référent (lecture/écriture). Les capitaines
-- passent par la RPC submit_score (SECURITY DEFINER), pas par la table.
create policy "score_entries: staff tout" on public.score_entries for all to authenticated
  using (public.is_staff()) with check (public.is_staff());

-- =====================================================================
--  RPC CAPITAINES (anon) — aucune table n'est exposée directement.
--  Toutes ces fonctions valident le join_code côté serveur.
-- =====================================================================

-- Rejoindre un tournoi avec son code → infos publiques si le tournoi est live.
create or replace function public.join_tournament(p_code text)
returns table (id uuid, name text, status tournament_status, live_phase phase_type, config jsonb)
language sql stable security definer set search_path = public as $$
  select t.id, t.name, t.status, t.live_phase, t.config
  from public.tournaments t
  where upper(t.join_code) = upper(p_code)
    and t.status = 'live'
    and t.archived = false;
$$;

-- Liste des équipes d'un tournoi (pour que le capitaine choisisse la sienne).
create or replace function public.tournament_teams(p_code text)
returns table (team_id uuid, team_name text, pool_letter text)
language sql stable security definer set search_path = public as $$
  select tm.id, tm.name, p.letter
  from public.tournaments t
  join public.teams tm on tm.tournament_id = t.id
  left join public.pool_teams pt on pt.team_id = tm.id
  left join public.pools p on p.id = pt.pool_id
  where upper(t.join_code) = upper(p_code) and t.status = 'live'
  order by p.letter nulls last, tm.name;
$$;

-- Matchs d'une équipe (joués / à venir), code requis.
create or replace function public.team_matches(p_code text, p_team_id uuid)
returns setof public.matches
language sql stable security definer set search_path = public as $$
  select m.*
  from public.tournaments t
  join public.matches m on m.tournament_id = t.id
  where upper(t.join_code) = upper(p_code)
    and t.status = 'live'
    and (m.team_a = p_team_id or m.team_b = p_team_id)
  order by m.round, m.scheduled_time;
$$;

-- Saisie d'un score par un capitaine. Valide le code + l'appartenance de
-- l'équipe, enregistre la saisie, et valide le match si les deux équipes
-- ont saisi le même résultat.
create or replace function public.submit_score(
  p_code    text,
  p_match_id uuid,
  p_team_id  uuid,
  p_score_a  int,
  p_score_b  int,
  p_sets     jsonb default null
) returns public.matches
language plpgsql security definer set search_path = public as $$
declare
  v_tournament uuid;
  v_match      public.matches;
  v_entries    int;
  v_agree      int;
begin
  -- 1. Le code correspond à un tournoi live ?
  select id into v_tournament
  from public.tournaments
  where upper(join_code) = upper(p_code) and status = 'live' and archived = false;
  if v_tournament is null then
    raise exception 'Code de tournoi invalide ou tournoi non actif';
  end if;

  -- 2. Le match appartient bien à ce tournoi et l'équipe y participe ?
  select * into v_match from public.matches
  where id = p_match_id and tournament_id = v_tournament;
  if v_match.id is null then
    raise exception 'Match introuvable pour ce tournoi';
  end if;
  if p_team_id <> v_match.team_a and p_team_id <> v_match.team_b then
    raise exception 'Cette équipe ne joue pas ce match';
  end if;
  if v_match.status = 'valid' then
    return v_match;  -- déjà validé, on ne rejoue pas la saisie
  end if;

  -- 3. Enregistre / met à jour la saisie de cette équipe.
  insert into public.score_entries (match_id, team_id, score_a, score_b, sets)
  values (p_match_id, p_team_id, p_score_a, p_score_b, p_sets)
  on conflict (match_id, team_id)
  do update set score_a = excluded.score_a,
                score_b = excluded.score_b,
                sets    = excluded.sets,
                created_at = now();

  -- 4. Combien de saisies, et concordent-elles ?
  select count(*),
         count(*) filter (where score_a = p_score_a and score_b = p_score_b)
    into v_entries, v_agree
  from public.score_entries where match_id = p_match_id;

  if v_entries >= 2 and v_agree >= 2 then
    -- Les deux capitaines sont d'accord → match validé.
    update public.matches
      set status = 'valid', score_a = p_score_a, score_b = p_score_b,
          sets = p_sets, validated_at = now()
      where id = p_match_id
      returning * into v_match;
  else
    -- En attente de l'autre équipe, ou désaccord → l'organisation tranche.
    update public.matches
      set status = 'pending'
      where id = p_match_id and status <> 'valid'
      returning * into v_match;
  end if;

  return v_match;
end;
$$;

-- Les capitaines utilisent la clé anon : on leur ouvre UNIQUEMENT ces RPC.
grant execute on function public.join_tournament(text)                              to anon, authenticated;
grant execute on function public.tournament_teams(text)                             to anon, authenticated;
grant execute on function public.team_matches(text, uuid)                           to anon, authenticated;
grant execute on function public.submit_score(text, uuid, uuid, int, int, jsonb)    to anon, authenticated;

-- =====================================================================
--  Temps réel : diffuser les changements de matchs/poules/équipes.
-- =====================================================================
do $$ begin
  alter publication supabase_realtime add table public.matches;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.pools;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.teams;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.tournaments;
exception when duplicate_object then null; end $$;

-- =====================================================================
--  Fin de la migration 0001
-- =====================================================================
