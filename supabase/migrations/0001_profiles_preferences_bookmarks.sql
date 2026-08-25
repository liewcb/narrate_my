-- NarrateMy — Module 5 (User Profile & Language Management)
-- Migration 1 of 3: core tables + auto-provisioning trigger.
--
-- Run this in the Supabase SQL Editor (or `supabase db push` if you have
-- the CLI set up), in order, before 0002 and 0003.

-- 1. profiles ----------------------------------------------------------
-- Shared identity table other modules (Recommendation Engine, AR,
-- Itinerary) join against by id. One row per auth.users row.
create table if not exists public.profiles (
  id                  uuid primary key references auth.users(id) on delete cascade,
  username            text unique,              -- null for Google/phone-only accounts (C3: fixed at registration)
  full_name           text,
  bio                 text,                     -- "other personal details" (REQ_503_3)
  avatar_url          text,
  preferred_language  text not null default 'en'
                       check (preferred_language in ('en','zh','ms','es','hi')), -- C2: English/Mandarin/Malay/Spanish/Hindi
  has_password        boolean not null default false,  -- drives "Change Password" UI visibility (C6)
  failed_login_attempts int not null default 0,
  locked_until        timestamptz,              -- REQ_502_17: 30-min lockout after 5 failed attempts
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

comment on table public.profiles is
  'One row per tourist account. Personal Info + Language columns live here so UC402''s independent-atomic-save requirement (REQ_503_11) is structural: a Personal Info save and a Language save are different UPDATE statements against different columns.';

-- 2. preferences ---------------------------------------------------------
-- Separate table (not columns on profiles) so it is structurally
-- impossible for a Personal-Info save to touch staged Preferences edits,
-- and so the Recommendation Engine module can read it without touching
-- profiles' other columns/RLS.
create table if not exists public.preferences (
  user_id                   uuid primary key references public.profiles(id) on delete cascade,
  attraction_interests      text[] not null default '{}',   -- REQ_503_4
  food_cuisine_interests    text[] not null default '{}',   -- REQ_503_8 (distinct from dietary)
  dietary_preferences       text[] not null default '{}',   -- REQ_503_5
  accessibility_preferences text[] not null default '{}',   -- REQ_503_6
  category_exclusions       text[] not null default '{}',   -- REQ_503_7
  updated_at                timestamptz not null default now()
);

-- 3. bookmarks -------------------------------------------------------------
-- Module 5 owns view/remove (REQ_503_21/22). The bookmarked *entity* data
-- (attraction/restaurant details) belongs to the Recommendation Engine
-- module's tables — item_id is a generic FK target, not owned here.
create table if not exists public.bookmarks (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  item_id     uuid not null,
  item_type   text not null default 'attraction',
  created_at  timestamptz not null default now(),
  unique (user_id, item_id)
);

-- 4. auto-provisioning trigger --------------------------------------------
-- The client cannot be trusted to always follow up signUp() with an INSERT
-- (network drop, app killed mid-flow) — without this, a user could exist
-- in auth.users with no matching profiles/preferences row, breaking every
-- owner-scoped RLS read/write on first login. SECURITY DEFINER so it can
-- write to public.profiles/public.preferences regardless of the (not yet
-- fully authenticated) caller's own RLS grants.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id) values (new.id)
    on conflict (id) do nothing;
  insert into public.preferences (user_id) values (new.id)
    on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
