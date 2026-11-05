-- RepForge : installation complète en un seul copier-coller (SQL Editor Supabase).
-- = migrations/20261105000000_init.sql + seed.sql

-- RepForge — schéma initial
-- Principes :
--   * PK uuid générées côté client (offline-first : la ligne existe en local avant d'exister dans le cloud)
--   * updated_at maintenu par trigger -> sync incrémentale "last-write-wins"
--   * deleted_at = suppression logique (tombstone) pour propager les suppressions entre appareils
--   * RLS : (select auth.uid()) pour évaluer l'uid une seule fois par requête

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------
create type public.load_type as enum ('dumbbell', 'machine', 'assisted', 'bodyweight');
create type public.set_kind as enum ('warmup', 'working');
create type public.biometric_kind as enum ('body_mass', 'height');

-- ---------------------------------------------------------------------------
-- updated_at automatique
-- ---------------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- profiles (1-1 avec auth.users)
-- ---------------------------------------------------------------------------
create table public.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  display_name  text,
  birth_date    date,
  height_cm     numeric(5, 1) check (height_cm between 50 and 260),
  body_mass_kg  numeric(5, 2) check (body_mass_kg between 20 and 400),
  sex           text check (sex in ('male', 'female', 'other')),
  settings      jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create trigger profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();

-- Création automatique du profil à l'inscription (Google / Apple)
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'))
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke execute on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- biometrics_logs (historique poids / taille)
-- ---------------------------------------------------------------------------
create table public.biometrics_logs (
  id           uuid primary key,
  user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  kind         public.biometric_kind not null,
  value        numeric(6, 2) not null check (value > 0),
  measured_at  timestamptz not null,
  source       text not null default 'app' check (source in ('app', 'healthkit')),
  healthkit_uuid uuid,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);

create index biometrics_logs_user_updated_idx on public.biometrics_logs (user_id, updated_at);
create index biometrics_logs_user_kind_date_idx on public.biometrics_logs (user_id, kind, measured_at desc);
create unique index biometrics_logs_hk_uuid_idx on public.biometrics_logs (user_id, healthkit_uuid)
  where healthkit_uuid is not null;

create trigger biometrics_logs_touch before update on public.biometrics_logs
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- workout_templates (programme : global si user_id NULL, sinon personnel)
-- ---------------------------------------------------------------------------
create table public.workout_templates (
  id          uuid primary key,
  user_id     uuid references auth.users (id) on delete cascade,
  sort_order  int not null default 0,
  title       text not null,
  subtitle    text,
  symbol      text,
  exercises   jsonb not null check (jsonb_typeof(exercises) = 'array'),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

create index workout_templates_user_idx on public.workout_templates (user_id, updated_at);

create trigger workout_templates_touch before update on public.workout_templates
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- workout_sessions
-- ---------------------------------------------------------------------------
create table public.workout_sessions (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  template_id       uuid references public.workout_templates (id) on delete set null,
  title             text not null,
  started_at        timestamptz not null,
  ended_at          timestamptz,
  paused_seconds    int not null default 0 check (paused_seconds >= 0),
  notes             text,
  healthkit_workout_uuid uuid,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  check (ended_at is null or ended_at >= started_at)
);

create index workout_sessions_user_updated_idx on public.workout_sessions (user_id, updated_at);
create index workout_sessions_user_started_idx on public.workout_sessions (user_id, started_at desc);
create index workout_sessions_template_idx on public.workout_sessions (template_id);

create trigger workout_sessions_touch before update on public.workout_sessions
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- exercise_sets
-- ---------------------------------------------------------------------------
create table public.exercise_sets (
  id               uuid primary key,
  user_id          uuid not null default auth.uid() references auth.users (id) on delete cascade,
  session_id       uuid not null references public.workout_sessions (id) on delete cascade,
  exercise_key     text not null,
  exercise_name    text not null,
  exercise_order   int not null,
  load_type        public.load_type not null,
  set_index        int not null check (set_index >= 0),
  kind             public.set_kind not null default 'working',
  weight_kg        numeric(6, 2) check (weight_kg >= 0),
  reps             int check (reps between 0 and 999),
  rest_seconds     int not null default 0 check (rest_seconds >= 0),
  completed_at     timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  unique (session_id, exercise_order, set_index)
);

create index exercise_sets_user_updated_idx on public.exercise_sets (user_id, updated_at);
create index exercise_sets_session_idx on public.exercise_sets (session_id);
create index exercise_sets_user_exercise_idx on public.exercise_sets (user_id, exercise_key, completed_at desc)
  where deleted_at is null;

create trigger exercise_sets_touch before update on public.exercise_sets
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.profiles          enable row level security;
alter table public.biometrics_logs   enable row level security;
alter table public.workout_templates enable row level security;
alter table public.workout_sessions  enable row level security;
alter table public.exercise_sets     enable row level security;

-- profiles
create policy "profiles: lecture du sien" on public.profiles
  for select to authenticated using ((select auth.uid()) = id);
create policy "profiles: création du sien" on public.profiles
  for insert to authenticated with check ((select auth.uid()) = id);
create policy "profiles: maj du sien" on public.profiles
  for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

-- biometrics_logs / workout_sessions / exercise_sets : propriétaire uniquement
do $$
declare t text;
begin
  foreach t in array array['biometrics_logs', 'workout_sessions', 'exercise_sets'] loop
    execute format($f$create policy "%1$s: lecture" on public.%1$I for select to authenticated
                     using ((select auth.uid()) = user_id)$f$, t);
    execute format($f$create policy "%1$s: insertion" on public.%1$I for insert to authenticated
                     with check ((select auth.uid()) = user_id)$f$, t);
    execute format($f$create policy "%1$s: maj" on public.%1$I for update to authenticated
                     using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id)$f$, t);
    execute format($f$create policy "%1$s: suppression" on public.%1$I for delete to authenticated
                     using ((select auth.uid()) = user_id)$f$, t);
  end loop;
end;
$$;

-- exercise_sets : la séance parente doit appartenir au même utilisateur
create policy "exercise_sets: séance du propriétaire" on public.exercise_sets
  as restrictive for insert to authenticated
  with check (exists (
    select 1 from public.workout_sessions s
    where s.id = session_id and s.user_id = (select auth.uid())
  ));

-- workout_templates : globaux en lecture, personnels en lecture/écriture
create policy "templates: lecture globaux + perso" on public.workout_templates
  for select to authenticated using (user_id is null or user_id = (select auth.uid()));
create policy "templates: insertion perso" on public.workout_templates
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "templates: maj perso" on public.workout_templates
  for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "templates: suppression perso" on public.workout_templates
  for delete to authenticated using (user_id = (select auth.uid()));

-- Le rôle anon n'a besoin de rien
revoke all on public.profiles, public.biometrics_logs, public.workout_templates,
              public.workout_sessions, public.exercise_sets from anon;

-- ⚠️ Fichier généré par scripts/generate_program.py — ne pas éditer à la main.
-- Templates globaux (user_id NULL) visibles par tous les utilisateurs authentifiés.
insert into public.workout_templates (id, user_id, sort_order, title, subtitle, symbol, exercises)
values
  ('52ec6081-30c8-53bc-bcc8-c60d42e8f83b', null, 1, 'Séance 1', 'Pectoraux & Triceps', 'figure.strengthtraining.traditional', '[{"key": "pec_deck", "name": "Pec Deck", "loadType": "machine", "sets": [{"index": 0, "kind": "warmup", "restSeconds": 90, "targetReps": null}, {"index": 1, "kind": "working", "restSeconds": 90, "targetReps": null}, {"index": 2, "kind": "working", "restSeconds": 180, "targetReps": null}]}, {"key": "chest_press_plate_incline", "name": "Chest press à disque - Incliné/convergente", "loadType": "machine", "sets": [{"index": 0, "kind": "warmup", "restSeconds": 120, "targetReps": null}, {"index": 1, "kind": "working", "restSeconds": 120, "targetReps": null}, {"index": 2, "kind": "working", "restSeconds": 180, "targetReps": null}]}, {"key": "overhead_triceps_cable", "name": "Overhead triceps extension poulie", "loadType": "machine", "sets": [{"index": 0, "kind": "working", "restSeconds": 90, "targetReps": null}, {"index": 1, "kind": "working", "restSeconds": 90, "targetReps": null}, {"index": 2, "kind": "working", "restSeconds": 180, "targetReps": null}]}, {"key": "single_arm_triceps_cable", "name": "Extension triceps unilatérale poulie", "loadType": "machine", "sets": [{"index": 0, "kind": "working", "restSeconds": 90, "targetReps": null}, {"index": 1, "kind": "working", "restSeconds": 90, "targetReps": null}, {"index": 2, "kind": "working", "restSeconds": 0, "targetReps": null}]}]'::jsonb),
  ('d931d5fa-bf78-5afe-860e-39f11b336205', null, 2, 'Séance 2', 'Dos & Biceps', 'figure.climbing', '[{"key": "assisted_pull_up", "name": "Tractions délestées", "loadType": "assisted", "sets": [{"index": 0, "kind": "working", "restSeconds": 120, "targetReps": null}, {"index": 1, "kind": "working", "restSeconds": 120, "targetReps": null}, {"index": 2, "kind": "working", "restSeconds": 180, "targetReps": null}]}, {"key": "seated_cable_row_v", "name": "Rowing horizontal poulie - poignée V", "loadType": "machine", "sets": [{"index": 0, "kind": "working", "restSeconds": 120, "targetReps": null}, {"index": 1, "kind": "working", "restSeconds": 120, "targetReps": null}, {"index": 2, "kind": "working", "restSeconds": 180, "targetReps": null}]}, {"key": "incline_bench_curl", "name": "Curl banc incliné - assis, 2 bras", "loadType": "dumbbell", "sets": [{"index": 0, "kind": "working", "restSeconds": 90, "targetReps": null}, {"index": 1, "kind": "working", "restSeconds": 90, "targetReps": null}, {"index": 2, "kind": "working", "restSeconds": 180, "targetReps": null}]}, {"key": "bench_90_single_curl", "name": "Curl banc à 90° - debout, unilatéral", "loadType": "dumbbell", "sets": [{"index": 0, "kind": "working", "restSeconds": 90, "targetReps": null}, {"index": 1, "kind": "working", "restSeconds": 90, "targetReps": null}, {"index": 2, "kind": "working", "restSeconds": 0, "targetReps": null}]}]'::jsonb),
  ('ef9d32d2-03dd-54df-bd00-977687ec018d', null, 3, 'Séance 3', 'Épaules & Bras', 'figure.arms.open', '[{"key": "machine_shoulder_press", "name": "Développé militaire machine", "loadType": "machine", "sets": [{"index": 0, "kind": "working", "restSeconds": 120, "targetReps": null}, {"index": 1, "kind": "working", "restSeconds": 120, "targetReps": null}, {"index": 2, "kind": "working", "restSeconds": 180, "targetReps": null}]}, {"key": "lateral_raise", "name": "Élévations latérales", "loadType": "dumbbell", "sets": [{"index": 0, "kind": "working", "restSeconds": 90, "targetReps": null}, {"index": 1, "kind": "working", "restSeconds": 90, "targetReps": null}, {"index": 2, "kind": "working", "restSeconds": 180, "targetReps": null}]}, {"key": "reverse_pec_deck", "name": "Reverse Pec Deck", "loadType": "machine", "sets": [{"index": 0, "kind": "working", "restSeconds": 90, "targetReps": null}, {"index": 1, "kind": "working", "restSeconds": 90, "targetReps": null}, {"index": 2, "kind": "working", "restSeconds": 180, "targetReps": null}]}, {"key": "hammer_curl", "name": "Curl marteau", "loadType": "dumbbell", "sets": [{"index": 0, "kind": "working", "restSeconds": 90, "targetReps": null}, {"index": 1, "kind": "working", "restSeconds": 90, "targetReps": null}, {"index": 2, "kind": "working", "restSeconds": 180, "targetReps": null}]}, {"key": "single_arm_triceps_cable", "name": "Extension triceps unilatérale poulie", "loadType": "machine", "sets": [{"index": 0, "kind": "working", "restSeconds": 90, "targetReps": null}, {"index": 1, "kind": "working", "restSeconds": 90, "targetReps": null}, {"index": 2, "kind": "working", "restSeconds": 0, "targetReps": null}]}]'::jsonb),
  ('bd344e2f-4a72-5cec-9e15-679e0267bf0f', null, 4, 'Séance 4', 'Pectoraux, Dos & Avant-bras', 'figure.mixed.cardio', '[{"key": "incline_db_chest_press", "name": "Chest press incliné haltères", "loadType": "dumbbell", "sets": [{"index": 0, "kind": "warmup", "restSeconds": 120, "targetReps": null}, {"index": 1, "kind": "working", "restSeconds": 120, "targetReps": null}, {"index": 2, "kind": "working", "restSeconds": 180, "targetReps": null}]}, {"key": "seated_cable_pull_v", "name": "Tirage horizontal poulie - poignée V", "loadType": "machine", "sets": [{"index": 0, "kind": "working", "restSeconds": 120, "targetReps": null}, {"index": 1, "kind": "working", "restSeconds": 120, "targetReps": null}, {"index": 2, "kind": "working", "restSeconds": 180, "targetReps": null}]}, {"key": "pec_fly", "name": "Pec Fly", "loadType": "machine", "sets": [{"index": 0, "kind": "working", "restSeconds": 90, "targetReps": null}, {"index": 1, "kind": "working", "restSeconds": 90, "targetReps": null}, {"index": 2, "kind": "working", "restSeconds": 180, "targetReps": null}]}, {"key": "converging_row_machine", "name": "Rowing machine convergente", "loadType": "machine", "sets": [{"index": 0, "kind": "working", "restSeconds": 120, "targetReps": null}, {"index": 1, "kind": "working", "restSeconds": 120, "targetReps": null}, {"index": 2, "kind": "working", "restSeconds": 180, "targetReps": null}]}, {"key": "strict_wrist_curl", "name": "Curl avant-bras strict", "loadType": "dumbbell", "sets": [{"index": 0, "kind": "working", "restSeconds": 60, "targetReps": null}, {"index": 1, "kind": "working", "restSeconds": 60, "targetReps": null}, {"index": 2, "kind": "working", "restSeconds": 180, "targetReps": null}]}, {"key": "reverse_curl", "name": "Reverse curl", "loadType": "machine", "sets": [{"index": 0, "kind": "working", "restSeconds": 60, "targetReps": null}, {"index": 1, "kind": "working", "restSeconds": 60, "targetReps": null}, {"index": 2, "kind": "working", "restSeconds": 0, "targetReps": null}]}]'::jsonb)
on conflict (id) do update set
  sort_order = excluded.sort_order, title = excluded.title, subtitle = excluded.subtitle,
  symbol = excluded.symbol, exercises = excluded.exercises, updated_at = now();
