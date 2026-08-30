-- Shared bookmark support for Nearby, AR, AI Chat, and Itinerary.
--
-- This does NOT create a recommendation_bookmarks table. Run it once against
-- the existing public.places and public.bookmarks tables. It preserves
-- existing itinerary bookmarks and makes item_id optional only when a
-- bookmark is backed by place_id.

begin;

-- Stop safely instead of silently deleting existing duplicate data.
do $$
begin
  if exists (
    select 1
    from public.places
    where place_id is not null
    group by place_id
    having count(*) > 1
  ) then
    raise exception
      'Duplicate places.place_id values exist. Merge those rows before rerunning this script.';
  end if;

  if exists (
    select 1
    from public.bookmarks
    where place_id is not null
    group by user_id, place_id
    having count(*) > 1
  ) then
    raise exception
      'Duplicate bookmark rows exist for the same user and place. Keep one row from each duplicate group, then rerun this script.';
  end if;
end
$$;

alter table public.bookmarks
  alter column item_id drop not null,
  alter column id set default gen_random_uuid(),
  alter column created_at set default now();

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'bookmarks_item_reference_check'
      and conrelid = 'public.bookmarks'::regclass
  ) then
    alter table public.bookmarks
      add constraint bookmarks_item_reference_check
      check (item_id is not null or place_id is not null);
  end if;
end
$$;

create unique index if not exists places_google_place_id_uidx
  on public.places (place_id);

create unique index if not exists bookmarks_user_place_uidx
  on public.bookmarks (user_id, place_id)
  where place_id is not null;

create index if not exists bookmarks_user_id_idx
  on public.bookmarks (user_id);

alter table public.places enable row level security;
alter table public.bookmarks enable row level security;

-- Signed-out users must never create or inspect personal bookmarks.
revoke all on table public.bookmarks from anon;
grant select, insert, delete on table public.bookmarks to authenticated;

-- Place information is shared, but only authenticated users need to create a
-- missing row while bookmarking. Existing guest SELECT access is preserved.
revoke insert, update, delete on table public.places from anon;
grant select, insert, update on table public.places to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'places'
      and policyname = 'Authenticated users can read places'
  ) then
    create policy "Authenticated users can read places"
      on public.places for select
      to authenticated
      using (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'places'
      and policyname = 'Authenticated users can update verified places'
  ) then
    create policy "Authenticated users can update verified places"
      on public.places for update
      to authenticated
      using (true)
      with check (
        place_id is not null
        and btrim(place_id) <> ''
        and name is not null
        and btrim(name) <> ''
        and latitude is not null
        and longitude is not null
        and latitude between -90 and 90
        and longitude between -180 and 180
      );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'places'
      and policyname = 'Authenticated users can create verified places'
  ) then
    create policy "Authenticated users can create verified places"
      on public.places for insert
      to authenticated
      with check (
        place_id is not null
        and btrim(place_id) <> ''
        and btrim(name) <> ''
        and latitude between -90 and 90
        and longitude between -180 and 180
      );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'bookmarks'
      and policyname = 'Users can read their own bookmarks'
  ) then
    create policy "Users can read their own bookmarks"
      on public.bookmarks for select
      to authenticated
      using ((select auth.uid()) = user_id);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'bookmarks'
      and policyname = 'Users can create their own bookmarks'
  ) then
    create policy "Users can create their own bookmarks"
      on public.bookmarks for insert
      to authenticated
      with check ((select auth.uid()) = user_id);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'bookmarks'
      and policyname = 'Users can delete their own bookmarks'
  ) then
    create policy "Users can delete their own bookmarks"
      on public.bookmarks for delete
      to authenticated
      using ((select auth.uid()) = user_id);
  end if;
end
$$;

commit;

-- Optional inspection after the transaction succeeds:
-- select schemaname, tablename, policyname, roles, cmd
-- from pg_policies
-- where schemaname = 'public' and tablename in ('places', 'bookmarks')
-- order by tablename, policyname;
