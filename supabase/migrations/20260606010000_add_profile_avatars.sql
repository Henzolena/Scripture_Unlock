alter table public.profiles
    add column if not exists avatar_path text not null default '',
    add column if not exists avatar_updated_at timestamp with time zone;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'profile-avatars',
    'profile-avatars',
    true,
    5242880,
    array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set
    public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

do $$
begin
    if not exists (
        select 1 from pg_policies
        where schemaname = 'storage'
          and tablename = 'objects'
          and policyname = 'Public read profile avatars'
    ) then
        create policy "Public read profile avatars"
        on storage.objects
        for select
        to public
        using (bucket_id = 'profile-avatars');
    end if;

    if not exists (
        select 1 from pg_policies
        where schemaname = 'storage'
          and tablename = 'objects'
          and policyname = 'Users upload own profile avatars'
    ) then
        create policy "Users upload own profile avatars"
        on storage.objects
        for insert
        to authenticated
        with check (
            bucket_id = 'profile-avatars'
            and (storage.foldername(name))[1] = (select auth.uid()::text)
            and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'webp')
        );
    end if;

    if not exists (
        select 1 from pg_policies
        where schemaname = 'storage'
          and tablename = 'objects'
          and policyname = 'Users update own profile avatars'
    ) then
        create policy "Users update own profile avatars"
        on storage.objects
        for update
        to authenticated
        using (
            bucket_id = 'profile-avatars'
            and (storage.foldername(name))[1] = (select auth.uid()::text)
        )
        with check (
            bucket_id = 'profile-avatars'
            and (storage.foldername(name))[1] = (select auth.uid()::text)
            and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'webp')
        );
    end if;

    if not exists (
        select 1 from pg_policies
        where schemaname = 'storage'
          and tablename = 'objects'
          and policyname = 'Users delete own profile avatars'
    ) then
        create policy "Users delete own profile avatars"
        on storage.objects
        for delete
        to authenticated
        using (
            bucket_id = 'profile-avatars'
            and (storage.foldername(name))[1] = (select auth.uid()::text)
        );
    end if;
end $$;
