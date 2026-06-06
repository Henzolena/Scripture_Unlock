drop policy if exists "Public read profile avatars" on storage.objects;

create policy "Public read profile avatars"
on storage.objects
for select
to public
using (
    bucket_id = 'profile-avatars'
    and storage.allow_any_operation(array[
        'object.get_authenticated_info',
        'object.get_authenticated'
    ])
);
