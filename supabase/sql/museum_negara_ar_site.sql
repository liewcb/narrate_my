-- Treat Museum Negara exhibits as experiences inside one physical venue for
-- AR recommendations. The Nearby map still plots every Attraction separately.

begin;

with museum_attractions as (
  select a.attraction_id, m.latitude, m.longitude
  from public."Attraction" a
  join public."Marker" m on m.marker_id = a.marker_id
  where a.attraction_id in (
          'AD013', -- Main Museum Facade
          'AD014', -- Historical Glass Murals
          'AD015', -- Istana Satu
          'AD016', -- Steam Locomotive
          'AD017', -- Historic Fire Engine & Vintage Cars
          'AD020', -- Tin Dredge Bucket
          'AD021'  -- Colonial Cannon Display
        )
     or a.attraction_content ilike '%National Museum of Malaysia%'
     or a.name ilike '%Museum Negara%'
     or a.name ilike '%Muzium Negara%'
     or a.name = 'Main Museum Facade'
), museum_location as (
  select avg(latitude)::numeric as latitude,
         avg(longitude)::numeric as longitude
  from museum_attractions
)
insert into public.ar_sites (
  site_id,
  display_name,
  latitude,
  longitude,
  address,
  category,
  match_aliases,
  match_radius_meters
)
select
  'ARS_MUSEUM_NEGARA',
  'Muzium Negara',
  latitude,
  longitude,
  'Jalan Damansara, Tasik Perdana, 50566 Kuala Lumpur',
  'Museum',
  array[
    'Muzium Negara',
    'National Museum of Malaysia',
    'Main Museum Facade'
  ],
  500
from museum_location
where latitude is not null and longitude is not null
on conflict (site_id) do update
set display_name = excluded.display_name,
    latitude = excluded.latitude,
    longitude = excluded.longitude,
    address = excluded.address,
    category = excluded.category,
    match_aliases = excluded.match_aliases,
    match_radius_meters = excluded.match_radius_meters,
    updated_at = now();

update public."Attraction" a
set site_id = 'ARS_MUSEUM_NEGARA'
where (
       a.attraction_id in (
         'AD013', 'AD014', 'AD015', 'AD016', 'AD017', 'AD020', 'AD021'
       )
    or a.attraction_content ilike '%National Museum of Malaysia%'
    or a.name ilike '%Museum Negara%'
    or a.name ilike '%Muzium Negara%'
    or a.name = 'Main Museum Facade'
  )
  and exists (
    select 1
    from public.ar_sites
    where site_id = 'ARS_MUSEUM_NEGARA'
  );

commit;

-- Verification:
-- select a.attraction_id, a.name, a.marker_id, a.site_id
-- from public."Attraction" a
-- where a.site_id = 'ARS_MUSEUM_NEGARA'
-- order by a.attraction_id;
