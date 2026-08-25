-- NarrateMy — Module 5 (User Profile & Language Management)
-- Migration 2 of 3: SECURITY DEFINER RPCs for username login + lockout.
-- Run AFTER 0001.

-- resolve_username ---------------------------------------------------------
-- Username & Password login has no native Supabase identity to sign in
-- against directly (Supabase Auth keys on email/phone). This RPC is the
-- pre-auth lookup step: given a username, return just enough to attempt
-- signInWithPassword(phone:, password:) client-side — the phone number and
-- whether the account is currently locked. Deliberately returns NOTHING
-- else from profiles (no name, no id) so it can safely be anon-callable
-- without widening profiles' RLS.
--
-- Zero rows back = "account not registered" (UC401 A5 / M4). Returns
-- user_id too — `record_failed_login` needs it, and it must be callable
-- BEFORE the caller is authenticated (the login attempt that needs
-- recording is the one that just failed), so there is no other way for
-- the client to have it at that point.
create or replace function public.resolve_username(p_username text)
returns table(user_id uuid, phone text, locked_until timestamptz)
language sql
security definer
set search_path = public
as $$
  select p.id, au.phone, p.locked_until
  from public.profiles p
  join auth.users au on au.id = p.id
  where p.username = p_username;
$$;

grant execute on function public.resolve_username(text) to anon;

-- record_failed_login -------------------------------------------------------
-- UC401 A7/A8 (REQ_502_17): 5 consecutive failed Username & Password
-- attempts trip a 30-minute lockout. Done as ONE atomic UPDATE...RETURNING
-- (not a read-then-write from Dart) specifically to avoid the race where
-- two near-simultaneous failed attempts both read attempts=4 and neither
-- ever pushes the counter to 5.
create or replace function public.record_failed_login(p_user_id uuid)
returns table(attempts int, locked_until timestamptz)
language sql
security definer
set search_path = public
as $$
  update public.profiles
  set failed_login_attempts = failed_login_attempts + 1,
      locked_until = case
        when failed_login_attempts + 1 >= 5 then now() + interval '30 minutes'
        else locked_until
      end
  where id = p_user_id
  returning failed_login_attempts, locked_until;
$$;

grant execute on function public.record_failed_login(uuid) to anon;

-- phone_account_status ------------------------------------------------------
-- UC403 A1's precondition check ("phone not registered, OR registered but
-- not via Username & Password") needs a phone->profile lookup, which RLS
-- otherwise blocks for an unauthenticated caller. Returns NULL (not a row)
-- when the phone isn't registered at all; otherwise whether that account
-- has a password set.
create or replace function public.phone_account_status(p_phone text)
returns table(user_id uuid, has_password boolean)
language sql
security definer
set search_path = public
as $$
  select p.id, p.has_password
  from public.profiles p
  join auth.users au on au.id = p.id
  where au.phone = p_phone;
$$;

grant execute on function public.phone_account_status(text) to anon;

-- Reset-on-success (REQ_502_18) and reset-on-lockout-expiry (REQ_502_22) do
-- NOT need functions here: reset-on-success is a plain owner-scoped
-- `UPDATE profiles SET failed_login_attempts=0, locked_until=null WHERE
-- id=auth.uid()` issued from the app AFTER a successful signIn (safe, no
-- race, the caller is authenticated by then — see
-- SupabaseAuthRepositoryAdapter.loginWithUsernamePassword). Lockout expiry
-- needs no reset at all: "locked" is just evaluated as
-- `locked_until is not null and locked_until > now()`, which goes false on
-- its own once the 30 minutes pass.
