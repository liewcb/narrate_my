-- NarrateMy — Module 5 (User Profile & Language Management)
-- Migration 7: Storage bucket + policies for profile pictures. Also an
-- added feature (Foo's request), not in the written spec.
--
-- Run this AFTER 0001–0006. Safe to re-run.

-- Public-read bucket: avatars are shown to the tourist themselves right now
-- (CircleAvatar on the Profile home screen), but a public URL is the
-- simplest thing that works with Flutter's plain `NetworkImage` (no signed-
-- URL refresh logic needed) and nothing in the spec treats a profile
-- picture as sensitive. Writes are still locked down below.
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- Anyone can READ any avatar (see rationale above).
create policy "avatars_public_read" on storage.objects
  for select using (bucket_id = 'avatars');

-- Path convention enforced by these policies: `{user_id}/avatar.<ext>` —
-- `storage.foldername(name)` splits the object path on '/', so
-- `(storage.foldername(name))[1]` is the first path segment (the folder a
-- tourist's avatar lives under). A tourist may only write into their OWN
-- folder, matching every other owner-only policy in this project (0003).
create policy "avatars_owner_insert" on storage.objects
  for insert with check (
    bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "avatars_owner_update" on storage.objects
  for update using (
    bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "avatars_owner_delete" on storage.objects
  for delete using (
    bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]
  );
