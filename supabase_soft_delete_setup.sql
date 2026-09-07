-- ============================================================================
-- Soft delete for Delete Account (UC402, "not in the written spec")
-- Added 2 Sep at Foo's request, replacing the old hard-delete RPC
-- (delete_own_account, from 0006_delete_account_and_dob.sql) with a
-- deactivate-now / purge-later pattern. Run this whole file once in your
-- Supabase project's SQL Editor (Database → SQL Editor → New query → paste
-- → Run). No supabase/migrations/ folder exists in this repo, so this isn't
-- wired into a migration history — just run it directly, same as every
-- other schema change so far this project.
-- ============================================================================

-- 1. New columns on profiles -------------------------------------------------
alter table public.profiles
  add column if not exists is_active boolean not null default true,
  add column if not exists deleted_at timestamptz;

-- 2. Soft delete: deactivates the caller's own account instead of removing
--    the row. Called from the app by AuthRemoteDataSource.deleteOwnAccount()
--    (lib/model/data_sources/remote/auth_remote_data_source.dart).
create or replace function public.soft_delete_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.profiles
  set is_active = false,
      deleted_at = now()
  where id = auth.uid();
end;
$$;

grant execute on function public.soft_delete_own_account() to authenticated;

-- 3. Reactivate: undoes a soft delete. Called automatically by the app
--    right after every successful login (password, phone OTP, or Google —
--    see AuthRemoteDataSource.reactivateOwnAccount() and its call sites in
--    profile_adapter.dart). Harmless no-op if the account is already
--    active, so every login path calls it unconditionally.
create or replace function public.reactivate_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.profiles
  set is_active = true,
      deleted_at = null
  where id = auth.uid();
end;
$$;

grant execute on function public.reactivate_own_account() to authenticated;

-- 4. OPTIONAL — permanent purge after the 30-day grace period. Deleting
--    from auth.users cascades to profiles (and preferences/bookmarks, if
--    their foreign keys are ON DELETE CASCADE — check 0001's table
--    definitions if unsure). The app never calls this directly; it's meant
--    to run on a schedule.
create or replace function public.purge_expired_deleted_accounts()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from auth.users
  where id in (
    select id from public.profiles
    where is_active = false
      and deleted_at is not null
      and deleted_at < now() - interval '30 days'
  );
end;
$$;

-- 5. OPTIONAL — schedule the purge to run daily at 03:00 UTC. Requires the
--    pg_cron extension (Database → Extensions in the Supabase dashboard —
--    enable "pg_cron" first). If you'd rather not enable an extension for
--    a class project, just skip this and run
--    `select public.purge_expired_deleted_accounts();` by hand every so
--    often before your demo/submission — nothing breaks if it's never run,
--    accounts just stay soft-deleted indefinitely instead of being purged.
--
-- select cron.schedule(
--   'purge-deleted-accounts',
--   '0 3 * * *',
--   'select public.purge_expired_deleted_accounts();'
-- );
