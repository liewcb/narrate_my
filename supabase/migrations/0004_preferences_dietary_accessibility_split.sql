-- NarrateMy — Module 5 (User Profile & Language Management)
-- Migration 4 of 4 (REPLACES an earlier 0004_preferences_travel_pace.sql —
-- delete that file if you still have it; travel pace was confirmed to
-- belong to Module 3's itinerary request form, not a Module 5 profile
-- preference, so it's not part of this migration).
--
-- Splits REQ_503_5 ("dietary preferences AND restrictions") into two real
-- columns instead of one flat list.
--
-- NOTE: an earlier version of this migration also added a free-text
-- `accessibility_notes` column for an "other accessibility needs" field —
-- that field was tried and explicitly rejected (a catch-all text box
-- doesn't behave like the rest of the toggles). REQ_503_6 is covered
-- entirely by `accessibility_preferences`' fixed 4-option list instead
-- (Wheelchair Accessible / Mobility Assistance / Visual Assistance /
-- Hearing Assistance — see `preference_options.dart`). If you already ran
-- the earlier version of this file against your Supabase project, run this
-- cleanup once: `alter table public.preferences drop column if exists
-- accessibility_notes;`
--
-- Run this AFTER 0001-0003 (Supabase SQL Editor, paste-and-run, or
-- `supabase db push`). Safe to re-run — `if not exists` throughout.

alter table public.preferences
  add column if not exists dietary_restrictions text[] not null default '{}';

comment on column public.preferences.dietary_restrictions is
  'Hard dietary restrictions/allergies (e.g. Nut Allergy, Gluten-Free) — kept separate from dietary_preferences (a lifestyle choice like Vegetarian/Halal) so the two are never rendered as one flat list.';

-- Cleanup, ONLY if you already ran the old 0004_preferences_travel_pace.sql
-- before this one replaced it — safe to skip otherwise:
-- alter table public.preferences drop column if exists travel_pace;
