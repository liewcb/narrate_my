-- Parent locations for displaying existing AR experiences on the Nearby map.
--
-- Safe for the existing AR module:
--   * Marker and Attraction rows are not deleted or renamed.
--   * Attraction.site_id is nullable, so existing records and queries work.
--   * The mobile client receives read-only access to active AR sites.
--   * Attractions left with site_id = null are still shown by Nearby as
--     standalone AR markers; grouping can therefore happen later.

begin;

create table if not exists public.ar_sites (
  site_id varchar primary key,
  display_name varchar not null,
  latitude numeric not null check (latitude between -90 and 90),
  longitude numeric not null check (longitude between -180 and 180),
  address text,
  category varchar,
  google_place_ids text[] not null default '{}',
  match_aliases text[] not null default '{}',
  match_radius_meters integer not null default 150
    check (match_radius_meters between 10 and 2000),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public."Attraction"
  add column if not exists site_id varchar;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'attraction_ar_site_fk'
      and conrelid = 'public."Attraction"'::regclass
  ) then
    alter table public."Attraction"
      add constraint attraction_ar_site_fk
      foreign key (site_id)
      references public.ar_sites(site_id)
      on delete set null;
  end if;
end
$$;

create index if not exists attraction_site_id_idx
  on public."Attraction" (site_id);

create index if not exists ar_sites_location_idx
  on public.ar_sites (latitude, longitude)
  where is_active;

alter table public.ar_sites enable row level security;

revoke all on table public.ar_sites from anon, authenticated;
grant select on table public.ar_sites to anon, authenticated;
grant all on table public.ar_sites to service_role;

drop policy if exists "Anyone can read active AR sites" on public.ar_sites;
create policy "Anyone can read active AR sites"
  on public.ar_sites for select
  to anon, authenticated
  using (is_active = true);

-- Initial parent groups derived from the existing Marker coordinates.
-- Replace/add aliases and Google Place IDs in Table Editor after running.
with klcc_location as (
  select avg(m.latitude)::numeric as latitude,
         avg(m.longitude)::numeric as longitude
  from public."Attraction" a
  join public."Marker" m on m.marker_id = a.marker_id
  where a.attraction_id in ('AD001', 'AD002', 'AD003', 'AD007')
)
insert into public.ar_sites (
  site_id,
  display_name,
  latitude,
  longitude,
  category,
  match_aliases,
  match_radius_meters
)
select
  'ARS_KLCC_TOWERS',
  'Petronas Twin Towers',
  latitude,
  longitude,
  'Landmark',
  array[
    'Petronas Twin Towers',
    'KLCC Skybridge',
    'Tower 1',
    'Tower 2',
    'Observation Deck'
  ],
  220
from klcc_location
where latitude is not null and longitude is not null
on conflict (site_id) do update
set latitude = excluded.latitude,
    longitude = excluded.longitude,
    match_aliases = excluded.match_aliases,
    updated_at = now();

with tarumt_location as (
  select avg(m.latitude)::numeric as latitude,
         avg(m.longitude)::numeric as longitude
  from public."Attraction" a
  join public."Marker" m on m.marker_id = a.marker_id
  where a.attraction_id in ('AD004', 'AD005', 'AD006')
)
insert into public.ar_sites (
  site_id,
  display_name,
  latitude,
  longitude,
  category,
  match_aliases,
  match_radius_meters
)
select
  'ARS_TARUMT_KL',
  'TAR UMT Kuala Lumpur Campus',
  latitude,
  longitude,
  'Campus',
  array[
    'TAR UMT',
    'Tunku Abdul Rahman University of Management and Technology',
    'TAR UMT Arena',
    'TAR UMT Block B',
    'Bangunan Tun Tan Siew Sin'
  ],
  500
from tarumt_location
where latitude is not null and longitude is not null
on conflict (site_id) do update
set latitude = excluded.latitude,
    longitude = excluded.longitude,
    match_aliases = excluded.match_aliases,
    updated_at = now();

update public."Attraction"
set site_id = 'ARS_KLCC_TOWERS'
where attraction_id in ('AD001', 'AD002', 'AD003', 'AD007')
  and exists (
    select 1 from public.ar_sites where site_id = 'ARS_KLCC_TOWERS'
  );

update public."Attraction"
set site_id = 'ARS_TARUMT_KL'
where attraction_id in ('AD004', 'AD005', 'AD006')
  and exists (
    select 1 from public.ar_sites where site_id = 'ARS_TARUMT_KL'
  );

commit;

-- After running, fill google_place_ids from Google Places where possible.
-- Example (replace the value with the verified ID used by your app):
-- update public.ar_sites
-- set google_place_ids = array['VERIFIED_GOOGLE_PLACE_ID'], updated_at = now()
-- where site_id = 'ARS_KLCC_TOWERS';

-- Verification queries:
-- select * from public.ar_sites order by display_name;
-- select attraction_id, name, marker_id, site_id
-- from public."Attraction"
-- order by attraction_id;
--
-- Optional grouping audit. Rows returned here remain visible as standalone
-- Nearby AR markers until a parent site is assigned:
-- select attraction_id, name, marker_id
-- from public."Attraction"
-- where site_id is null
-- order by attraction_id;
