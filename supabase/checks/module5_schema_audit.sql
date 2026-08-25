-- NarrateMy — Module 5 schema audit
-- Paste this whole file into Supabase Dashboard → SQL Editor → Run, then
-- paste the results back so they can be checked against
-- supabase/migrations/0001-0003. Read-only — nothing here modifies data.

-- 1) Do the three tables exist, with the right columns/types/defaults?
select table_name, column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name in ('profiles', 'preferences', 'bookmarks')
order by table_name, ordinal_position;

-- 2) Is RLS actually turned ON for all three? (relrowsecurity must be true)
select relname as table_name, relrowsecurity as rls_enabled
from pg_class
where relname in ('profiles', 'preferences', 'bookmarks')
  and relnamespace = 'public'::regnamespace;

-- 3) Which policies exist on each table? (should match 0003_rls_policies.sql:
--    profiles_select_own/profiles_update_own,
--    preferences_select_own/preferences_update_own,
--    bookmarks_select_own/bookmarks_insert_own/bookmarks_delete_own)
select tablename, policyname, cmd, qual
from pg_policies
where schemaname = 'public'
  and tablename in ('profiles', 'preferences', 'bookmarks')
order by tablename, policyname;

-- 4) Do the three RPC functions exist? (resolve_username, record_failed_login,
--    phone_account_status — all should be callable by 'anon')
select routine_name, security_type
from information_schema.routines
where routine_schema = 'public'
  and routine_name in ('resolve_username', 'record_failed_login', 'phone_account_status', 'handle_new_user');

-- 5) Is the auto-provisioning trigger installed on auth.users?
select tgname as trigger_name, tgrelid::regclass as on_table, tgenabled as enabled
from pg_trigger
where tgname = 'on_auth_user_created';

-- 6) Row counts + any orphans — an auth.users row with no matching profile
--    means the trigger didn't fire for that signup (should be zero rows).
select
  (select count(*) from auth.users) as auth_users_count,
  (select count(*) from public.profiles) as profiles_count,
  (select count(*) from public.preferences) as preferences_count,
  (select count(*) from public.bookmarks) as bookmarks_count,
  (select count(*) from auth.users au
     left join public.profiles p on p.id = au.id
     where p.id is null) as auth_users_missing_profile,
  (select count(*) from public.profiles p
     left join public.preferences pr on pr.user_id = p.id
     where pr.user_id is null) as profiles_missing_preferences;

-- 7) A quick look at your actual accounts (username, phone via auth join,
--    lockout state) — useful for spotting leftover scratch/test accounts
--    before you run the testing checklist.
select p.username, au.phone, p.has_password, p.failed_login_attempts,
       p.locked_until, p.preferred_language, p.created_at
from public.profiles p
join auth.users au on au.id = p.id
order by p.created_at desc;
