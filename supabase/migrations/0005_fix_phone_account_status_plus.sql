-- NarrateMy — Module 5 (User Profile & Language Management)
-- Migration 5: fix phone_account_status's "+" mismatch (login bug).
--
-- ROOT CAUSE (confirmed against Supabase Auth's own docs/source): GoTrue
-- strips the leading "+" before storing a phone number in auth.users.phone
-- — a user who registers with "+60123456789" ends up with
-- auth.users.phone = '60123456789' (no plus). But `phone_account_status`
-- below compared `au.phone = p_phone` using the app's E.164 string
-- straight from PhoneField (which DOES include the leading "+", e.g.
-- '+60123456789'). '60123456789' <> '+60123456789', so this RPC always
-- returned zero rows for a real, already-registered phone number. That
-- one broken comparison explains BOTH bugs reported at once, since both
-- paths call this same function:
--   1. Login via phone OTP (`sendPhoneLoginOtp`) always saw "no rows" and
--      threw AccountNotFoundFailure — a real account could never log back
--      in.
--   2. Registering again with the SAME phone (`sendPhoneRegistrationOtp`)
--      also saw "no rows", so the app's own duplicate-account check never
--      fired — the OTP was just resent (Supabase itself matched the
--      existing user internally, since ITS OWN comparison already strips
--      the "+"), giving the appearance that "register" was the only path
--      that "worked" for a phone that was actually already registered.
--
-- This also silently affected `sendPasswordResetOtp` (UC403 A1) and
-- `sendPhoneChangeOtp` (UC402 A9) — both call phone_account_status too.
--
-- Fix: normalize inside the function (strip a leading "+" from the input
-- before comparing) rather than in every Dart call site — one place, and
-- correct no matter what format a future caller passes.
create or replace function public.phone_account_status(p_phone text)
returns table(user_id uuid, has_password boolean)
language sql
security definer
set search_path = public
as $$
  select p.id, p.has_password
  from public.profiles p
  join auth.users au on au.id = p.id
  where au.phone = ltrim(p_phone, '+');
$$;

grant execute on function public.phone_account_status(text) to anon;
