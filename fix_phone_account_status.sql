-- Fix for: "the number is waiting for verification in supabase, the
-- number also can be login" / "register到一半退出, 手機號碼顯示register
-- 但實際沒有register" (8 Sep).
--
-- ROOT CAUSE: signInWithOtp(phone:, shouldCreateUser: true) creates the
-- real auth.users row the MOMENT the OTP is sent, not when it's verified.
-- If the tourist backs out before entering the OTP, that row is left
-- behind, unconfirmed (phone_confirmed_at IS NULL) -- and the
-- handle_new_user trigger fires on insert regardless of confirmation, so
-- a matching profiles row exists too. This is already-documented cleanup
-- debt (see module5-testing-checklist.md's Phase 12: "including
-- unconfirmed rows left by failed registrations -- the provisioning
-- trigger fires on insert, so those are expected").
--
-- The bug: phone_account_status() -- the one RPC used by registration's
-- duplicate-phone check, login's account-exists check, password-reset's
-- account-exists check, and Personal Info's phone-change duplicate check
-- -- treats that abandoned, unconfirmed row as a real, completed
-- registration. That's why the same phone number can't be re-registered
-- (still "already registered") AND can be logged into via OTP (the login
-- flow's OTP entry becomes that row's first-ever verification, silently
-- completing an abandoned registration -- REQ_501_26 explicitly requires
-- the opposite: "the system shall discard all unverified registration
-- data if the tourist cancels the registration process before the
-- account is created").
--
-- THE FIX: only count a phone as belonging to a real account once it has
-- actually been OTP-confirmed.
--
-- Run this once in the Supabase SQL Editor. It's a full replacement of
-- the function (CREATE OR REPLACE), matching the exact contract the app
-- already calls it with (p_phone in; user_id + has_password out) -- see
-- lib/model/data_sources/remote/auth_remote_data_source.dart's
-- phoneAccountStatus().

create or replace function public.phone_account_status(p_phone text)
returns table (user_id uuid, has_password boolean)
language sql
security definer
set search_path = public, auth
as $$
  select u.id as user_id,
         coalesce(p.has_password, false) as has_password
  from auth.users u
  left join public.profiles p on p.id = u.id
  where u.phone = p_phone
    and u.phone_confirmed_at is not null  -- the actual fix
  limit 1;
$$;

grant execute on function public.phone_account_status(text) to anon, authenticated;

-- OPTIONAL cleanup, run once after the function fix above: your testing
-- checklist's Phase 12 already calls for deleting "unconfirmed rows left
-- by failed registrations" by hand. Numbers already blocked by an
-- existing ghost row (like 0122222222) will STILL be blocked until that
-- row is actually deleted -- the function fix only stops NEW ghost rows
-- from causing this, it doesn't retroactively un-block old ones. To find
-- them:
--
--   select id, phone, phone_confirmed_at, created_at
--   from auth.users
--   where phone_confirmed_at is null
--   order by created_at desc;
--
-- Delete a specific one (via the dashboard's Authentication -> Users ->
-- delete, or, once you've confirmed the id from the query above):
--
--   delete from auth.users where id = '<uuid from the query above>';
