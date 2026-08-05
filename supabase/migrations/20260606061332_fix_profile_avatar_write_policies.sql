drop policy if exists "Users upload own profile avatars" on storage.objects;
drop policy if exists "Users update own profile avatars" on storage.objects;
drop policy if exists "Users delete own profile avatars" on storage.objects;

create policy "Users upload own profile avatars"
on storage.objects
for insert
to authenticated
with check (
    bucket_id = 'profile-avatars'
    and (
        owner_id = (select auth.uid()::text)
        or (storage.foldername(name))[1] = (select auth.uid()::text)
    )
    and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'webp')
);

create policy "Users update own profile avatars"
on storage.objects
for update
to authenticated
using (
    bucket_id = 'profile-avatars'
    and (
        owner_id = (select auth.uid()::text)
        or (storage.foldername(name))[1] = (select auth.uid()::text)
    )
)
with check (
    bucket_id = 'profile-avatars'
    and (
        owner_id = (select auth.uid()::text)
        or (storage.foldername(name))[1] = (select auth.uid()::text)
    )
    and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'webp')
);

create policy "Users delete own profile avatars"
on storage.objects
for delete
to authenticated
using (
    bucket_id = 'profile-avatars'
    and (
        owner_id = (select auth.uid()::text)
        or (storage.foldername(name))[1] = (select auth.uid()::text)
    )
);
