-- Run this once in Supabase Dashboard > SQL Editor before deploying the
-- updated recommend-nearby Edge Function.

create table if not exists public.nearby_recommendation_cache (
  cache_key text primary key,
  latitude_bucket numeric(7, 2) not null,
  longitude_bucket numeric(7, 2) not null,
  radius_km numeric(6, 2) not null,
  preference_hash text not null,
  prompt_version text not null,
  recommendations jsonb not null,
  model_name text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  constraint nearby_recommendation_cache_array
    check (jsonb_typeof(recommendations) = 'array')
);

create index if not exists nearby_recommendation_cache_expires_at_idx
  on public.nearby_recommendation_cache (expires_at);

alter table public.nearby_recommendation_cache enable row level security;

-- Flutter never accesses this table directly. Keeping it private prevents a
-- user from reading another preference group's cached response or poisoning
-- the shared cache. The Edge Function's service-role client is the only
-- caller and bypasses RLS after receiving the explicit table grant.
revoke all on table public.nearby_recommendation_cache
  from anon, authenticated;
grant select, insert, update, delete
  on table public.nearby_recommendation_cache
  to service_role;

-- A conservative app-side budget prevents a test session with many unique
-- location/preference combinations from exhausting the provider quota.
create table if not exists public.nearby_recommendation_ai_usage (
  id bigint generated always as identity primary key,
  cache_key text not null,
  model_name text not null,
  attempted_at timestamptz not null default now()
);

create index if not exists nearby_recommendation_ai_usage_attempted_at_idx
  on public.nearby_recommendation_ai_usage (attempted_at);

alter table public.nearby_recommendation_ai_usage enable row level security;
revoke all on table public.nearby_recommendation_ai_usage
  from anon, authenticated;
grant select, insert, delete
  on table public.nearby_recommendation_ai_usage
  to service_role;
grant usage, select
  on sequence public.nearby_recommendation_ai_usage_id_seq
  to service_role;
