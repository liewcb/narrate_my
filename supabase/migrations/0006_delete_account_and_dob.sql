-- NarrateMy — Module 5 (User Profile & Language Management)
-- Migration 6: two app-level features requested by Foo that are NOT in the
-- written FR/UC spec (flagged here explicitly so it's clear these are
-- scope additions, not requirements you missed):
--
--   1. Self-service account deletion (CRUD completeness for Manage Profile
--      — UC402 already has full CRUD on Bookmarks via A22, but no Delete on
--      the account itself).
--   2. A mandatory `date_of_birth` column, to support a new non-skippable
--      "tell us your name + DOB" step right after registration.
--
-- Run this AFTER 0001–0005 (Supabase SQL Editor, paste-and-run, or
-- `supabase db push`). Safe to re-run.

-- 1. date_of_birth column --------------------------------------------------
alter table public.profiles
  add column if not exists date_of_birth date;

comment on column public.profiles.date_of_birth is
  'Captured once, immediately after registration (any method — phone/username/Google), via a new non-skippable onboarding step. Not part of REQ_503_3''s editable Personal Info fields in the written spec — this is an added requirement, so it deliberately is NOT exposed on the Personal Info edit screen; it is set exactly once.';

-- 2. delete_own_account() ---------------------------------------------------
-- SECURITY DEFINER so it can DELETE from auth.users, which a normal
-- `authenticated`-role client can never do directly (there is no client-
-- side Supabase Auth API for self-deletion — only the service-role Admin
-- API, which must never ship inside the Flutter app). This function is
-- created by the role running this migration (normally `postgres` in the
-- Supabase SQL Editor), so it executes with THAT role's privileges,
-- including the ability to delete auth.users rows. `auth.uid()` inside the
-- function body still resolves to the CALLING tourist's own id (Supabase
-- sets this from the request's JWT regardless of the function owner), so a
-- tourist can only ever delete their own account, never someone else's.
--
-- Deleting the auth.users row cascades to public.profiles (0001:
-- `references auth.users(id) on delete cascade`), which in turn cascades
-- to public.preferences and public.bookmarks (0001: `references
-- public.profiles(id) on delete cascade`) — one DELETE removes everything
-- belonging to this tourist, nothing left behind.
create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from auth.users where id = auth.uid();
end;
$$;

-- Only a logged-in tourist may call this, and only on themselves — see the
-- auth.uid() note above.
grant execute on function public.delete_own_account() to authenticated;
