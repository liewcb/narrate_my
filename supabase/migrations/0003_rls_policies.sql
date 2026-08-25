-- NarrateMy — Module 5 (User Profile & Language Management)
-- Migration 3 of 3: Row-Level Security. Run AFTER 0001 and 0002.
--
-- Policy intent, all three tables: owner-only. Nothing in the spec
-- requires cross-tourist visibility of profile/preferences/bookmark data,
-- so there is no broadened SELECT policy anywhere. The pre-auth username
-- lookup and the lockout counter increment deliberately go through the
-- SECURITY DEFINER functions in 0002 instead of a relaxed table policy —
-- that keeps these tables' RLS simple and strictly owner-only even though
-- login itself happens before the caller is "the owner" yet.

alter table public.profiles enable row level security;
alter table public.preferences enable row level security;
alter table public.bookmarks enable row level security;

-- profiles: read/update own row only. No client-side INSERT — rows are
-- created exclusively by the handle_new_user trigger (0001).
create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = id);

create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id);

-- preferences: read/update own row only. (The Recommendation Engine module
-- reads this too, but always in the context of the logged-in tourist
-- computing their own recommendations — owner-only RLS already covers
-- that; it does not need a broadened policy.)
create policy "preferences_select_own" on public.preferences
  for select using (auth.uid() = user_id);

create policy "preferences_update_own" on public.preferences
  for update using (auth.uid() = user_id);

-- bookmarks: full CRUD on own rows only (view + add + remove, REQ_503_21/22).
create policy "bookmarks_select_own" on public.bookmarks
  for select using (auth.uid() = user_id);

create policy "bookmarks_insert_own" on public.bookmarks
  for insert with check (auth.uid() = user_id);

create policy "bookmarks_delete_own" on public.bookmarks
  for delete using (auth.uid() = user_id);
