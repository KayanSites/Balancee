-- ============================================================
--  Body Composition, Training & Nutrition Tracker
--  Supabase schema — multi-user, RLS on every table.
--  Paste into Supabase → SQL Editor → Run.
-- ============================================================

-- ---------- 1. PROFILES ----------
create table public.profiles (
  id                       uuid primary key references auth.users(id) on delete cascade,
  full_name                text,
  birth_date               date,
  height_cm                numeric(5,1),
  sex                      text check (sex in ('female','male','unspecified')),
  activity_level           text check (activity_level in ('sedentary','light','moderate','active','very_active')),
  goal_weight_kg           numeric(5,2),

  -- كل الأهداف دي اختيارية (nullable).
  -- لو فاضية، التطبيق بيعدّ اللي داخل بس من غير ما يقارن بحاجة.
  target_calories          integer,
  target_protein_g         integer,
  target_carbs_g           integer,
  target_fat_g             integer,
  target_workouts_per_week integer check (target_workouts_per_week between 1 and 7),

  locale                   text default 'ar' check (locale in ('ar','en')),
  created_at               timestamptz default now(),
  updated_at               timestamptz default now()
);

-- ---------- 2. SCANS (InBody) ----------
create table public.scans (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references auth.users(id) on delete cascade,
  measured_at         date not null,
  weight_kg           numeric(5,2) not null,
  skeletal_muscle_kg  numeric(5,2),   -- ↑ مرغوب
  body_fat_kg         numeric(5,2),   -- ↓ مرغوب
  body_fat_pct        numeric(4,1),   -- ↓ مرغوب
  total_body_water_l  numeric(5,2),   -- ↑ مرغوب
  bmi                 numeric(4,1),
  bmr                 integer,
  inbody_score        integer check (inbody_score between 0 and 100),
  visceral_fat_level  integer,
  sheet_url           text,
  notes               text,
  created_at          timestamptz default now(),
  unique (user_id, measured_at)
);
create index scans_user_date_idx on public.scans (user_id, measured_at desc);

-- ---------- 3. MEALS ----------
create table public.meals (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  logged_on   date not null,
  slot        text not null check (slot in ('breakfast','lunch','dinner','snack')),
  name        text not null,
  portion     text,            -- نص حر: "١٠٠ جم"، "طبق"، "٢ بيضة"
  calories    integer,
  protein_g   numeric(5,1),
  carbs_g     numeric(5,1),
  fat_g       numeric(5,1),
  created_at  timestamptz default now()
);
create index meals_user_date_idx on public.meals (user_id, logged_on desc);

-- ---------- 4. WORKOUTS ----------
-- ممكن يبقى مجرد "نزلت الجيم" (تسجيل حضور)، أو تمرين مفصّل بتماريه.
create table public.workouts (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  logged_on    date not null,
  kind         text check (kind in ('push','pull','legs','upper','lower','full','cardio','other')),
  duration_min integer,
  notes        text,
  created_at   timestamptz default now(),
  unique (user_id, logged_on)   -- نزول واحد في اليوم
);
create index workouts_user_date_idx on public.workouts (user_id, logged_on desc);

-- ---------- 5. EXERCISE SETS ----------
create table public.exercise_sets (
  id            uuid primary key default gen_random_uuid(),
  workout_id    uuid not null references public.workouts(id) on delete cascade,
  user_id       uuid not null references auth.users(id) on delete cascade,
  exercise_name text not null,
  set_number    integer not null default 1,
  reps          integer,
  weight_kg     numeric(6,2),
  created_at    timestamptz default now()
);
create index sets_workout_idx       on public.exercise_sets (workout_id);
create index sets_user_exercise_idx on public.exercise_sets (user_id, exercise_name);


-- ============================================================
--  ROW LEVEL SECURITY — من غير الجزء ده أي حد يشوف بيانات أي حد
-- ============================================================
alter table public.profiles      enable row level security;
alter table public.scans         enable row level security;
alter table public.meals         enable row level security;
alter table public.workouts      enable row level security;
alter table public.exercise_sets enable row level security;

create policy "own profile read"   on public.profiles for select using (auth.uid() = id);
create policy "own profile insert" on public.profiles for insert with check (auth.uid() = id);
create policy "own profile update" on public.profiles for update using (auth.uid() = id);

create policy "own scans"    on public.scans         for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own meals"    on public.meals         for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own workouts" on public.workouts      for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own sets"     on public.exercise_sets for all using (auth.uid() = user_id) with check (auth.uid() = user_id);


-- ============================================================
--  بروفايل تلقائي عند التسجيل
-- ============================================================
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', ''));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
