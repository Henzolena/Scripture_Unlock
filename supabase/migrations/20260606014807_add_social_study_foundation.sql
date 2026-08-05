create or replace function public.generate_short_code(prefix text default 'SU')
returns text
language sql
volatile
as $$
  select prefix || '-' || upper(substr(replace(extensions.gen_random_uuid()::text, '-', ''), 1, 6));
$$;

alter table public.profiles
  add column if not exists friend_code text;

update public.profiles
set friend_code = public.generate_short_code('SU')
where friend_code is null or friend_code = '';

create unique index if not exists profiles_friend_code_uidx
  on public.profiles (upper(friend_code));

alter table public.profiles
  alter column friend_code set default public.generate_short_code('SU'),
  alter column friend_code set not null;

create table if not exists public.friend_requests (
  id uuid primary key default extensions.gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  addressee_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'canceled')),
  message text not null default '',
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  check (requester_id <> addressee_id)
);

create unique index if not exists friend_requests_pending_pair_uidx
  on public.friend_requests (requester_id, addressee_id)
  where status = 'pending';

create index if not exists friend_requests_addressee_status_idx
  on public.friend_requests (addressee_id, status, created_at desc);

create index if not exists friend_requests_requester_status_idx
  on public.friend_requests (requester_id, status, created_at desc);

create table if not exists public.friendships (
  user_id uuid not null references public.profiles(id) on delete cascade,
  friend_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id),
  check (user_id <> friend_id)
);

create index if not exists friendships_friend_idx
  on public.friendships (friend_id, user_id);

create table if not exists public.study_rooms (
  id uuid primary key default extensions.gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 80),
  description text not null default '',
  default_pack_id text not null default 'psalms',
  language text not null default 'en',
  invite_code text not null default public.generate_short_code('ROOM'),
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists study_rooms_invite_code_uidx
  on public.study_rooms (upper(invite_code));

create index if not exists study_rooms_owner_idx
  on public.study_rooms (owner_id, updated_at desc);

create table if not exists public.study_room_members (
  room_id uuid not null references public.study_rooms(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'admin', 'member')),
  status text not null default 'active' check (status in ('active', 'invited', 'left', 'removed')),
  invited_by uuid references public.profiles(id) on delete set null,
  joined_at timestamptz,
  last_seen_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (room_id, user_id)
);

create index if not exists study_room_members_user_status_idx
  on public.study_room_members (user_id, status, created_at desc);

create table if not exists public.study_sessions (
  id uuid primary key default extensions.gen_random_uuid(),
  room_id uuid not null references public.study_rooms(id) on delete cascade,
  host_id uuid not null references public.profiles(id) on delete cascade,
  title text not null default 'Bible study',
  book text not null default '',
  book_name text not null default '',
  chapter integer not null default 1,
  verse_start integer,
  verse_end integer,
  language text not null default 'en',
  phase text not null default 'read' check (phase in ('read', 'reflect', 'discuss', 'quiz', 'pray', 'recap')),
  status text not null default 'active' check (status in ('active', 'ended')),
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists study_sessions_room_status_idx
  on public.study_sessions (room_id, status, started_at desc);

create table if not exists public.study_session_messages (
  id uuid primary key default extensions.gen_random_uuid(),
  session_id uuid not null references public.study_sessions(id) on delete cascade,
  room_id uuid not null references public.study_rooms(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null default 'chat' check (kind in ('chat', 'system', 'prayer', 'prompt')),
  body text not null check (char_length(trim(body)) between 1 and 2000),
  verse_ref text,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists study_session_messages_session_idx
  on public.study_session_messages (session_id, created_at desc);

create table if not exists public.study_session_notes (
  id uuid primary key default extensions.gen_random_uuid(),
  session_id uuid not null references public.study_sessions(id) on delete cascade,
  room_id uuid not null references public.study_rooms(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  verse_ref text,
  body text not null check (char_length(trim(body)) between 1 and 4000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists study_session_notes_session_idx
  on public.study_session_notes (session_id, created_at desc);

create table if not exists public.study_session_reactions (
  id uuid primary key default extensions.gen_random_uuid(),
  session_id uuid not null references public.study_sessions(id) on delete cascade,
  room_id uuid not null references public.study_rooms(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  target_type text not null default 'session' check (target_type in ('session', 'message', 'note', 'verse')),
  target_id uuid,
  reaction text not null check (reaction in ('amen', 'insightful', 'praying', 'question', 'heart')),
  created_at timestamptz not null default now()
);

create index if not exists study_session_reactions_session_idx
  on public.study_session_reactions (session_id, created_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_study_rooms_updated_at on public.study_rooms;
create trigger set_study_rooms_updated_at
before update on public.study_rooms
for each row execute function public.set_updated_at();

drop trigger if exists set_study_sessions_updated_at on public.study_sessions;
create trigger set_study_sessions_updated_at
before update on public.study_sessions
for each row execute function public.set_updated_at();

drop trigger if exists set_study_session_notes_updated_at on public.study_session_notes;
create trigger set_study_session_notes_updated_at
before update on public.study_session_notes
for each row execute function public.set_updated_at();

create or replace function public.is_room_member(target_room_id uuid, target_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.study_room_members m
    where m.room_id = target_room_id
      and m.user_id = target_user_id
      and m.status = 'active'
  );
$$;

create or replace function public.is_room_visible(target_room_id uuid, target_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.study_room_members m
    where m.room_id = target_room_id
      and m.user_id = target_user_id
      and m.status in ('active', 'invited')
  );
$$;

create or replace function public.is_room_manager(target_room_id uuid, target_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.study_room_members m
    where m.room_id = target_room_id
      and m.user_id = target_user_id
      and m.status = 'active'
      and m.role in ('owner', 'admin')
  );
$$;

create or replace function public.is_session_member(target_session_id uuid, target_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.study_sessions s
    join public.study_room_members m on m.room_id = s.room_id
    where s.id = target_session_id
      and m.user_id = target_user_id
      and m.status = 'active'
  );
$$;

create or replace function public.can_access_realtime_topic(topic text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  room_text text;
  session_text text;
begin
  room_text := substring(topic from '^study-room:([0-9a-fA-F-]{36})$');
  if room_text is not null then
    return public.is_room_member(room_text::uuid, auth.uid());
  end if;

  session_text := substring(topic from '^study-session:([0-9a-fA-F-]{36})$');
  if session_text is not null then
    return public.is_session_member(session_text::uuid, auth.uid());
  end if;

  return false;
exception when invalid_text_representation then
  return false;
end;
$$;

alter table public.friend_requests enable row level security;
alter table public.friendships enable row level security;
alter table public.study_rooms enable row level security;
alter table public.study_room_members enable row level security;
alter table public.study_sessions enable row level security;
alter table public.study_session_messages enable row level security;
alter table public.study_session_notes enable row level security;
alter table public.study_session_reactions enable row level security;

create policy "Friend requests visible to participants"
  on public.friend_requests for select to authenticated
  using (auth.uid() in (requester_id, addressee_id));

create policy "Users create own friend requests"
  on public.friend_requests for insert to authenticated
  with check (auth.uid() = requester_id and requester_id <> addressee_id);

create policy "Participants update own friend requests"
  on public.friend_requests for update to authenticated
  using (auth.uid() in (requester_id, addressee_id))
  with check (auth.uid() in (requester_id, addressee_id));

create policy "Users read own friendships"
  on public.friendships for select to authenticated
  using (auth.uid() = user_id);

create policy "Users remove own friendships"
  on public.friendships for delete to authenticated
  using (auth.uid() = user_id);

create policy "Study rooms visible to members"
  on public.study_rooms for select to authenticated
  using (public.is_room_visible(id, auth.uid()));

create policy "Users create owned study rooms"
  on public.study_rooms for insert to authenticated
  with check (auth.uid() = owner_id);

create policy "Room managers update rooms"
  on public.study_rooms for update to authenticated
  using (public.is_room_manager(id, auth.uid()))
  with check (public.is_room_manager(id, auth.uid()));

create policy "Room members visible to room"
  on public.study_room_members for select to authenticated
  using (public.is_room_visible(room_id, auth.uid()));

create policy "Room managers add members"
  on public.study_room_members for insert to authenticated
  with check (public.is_room_manager(room_id, auth.uid()) or user_id = auth.uid());

create policy "Members update own membership"
  on public.study_room_members for update to authenticated
  using (user_id = auth.uid() or public.is_room_manager(room_id, auth.uid()))
  with check (user_id = auth.uid() or public.is_room_manager(room_id, auth.uid()));

create policy "Study sessions visible to room members"
  on public.study_sessions for select to authenticated
  using (public.is_room_visible(room_id, auth.uid()));

create policy "Room members create study sessions"
  on public.study_sessions for insert to authenticated
  with check (host_id = auth.uid() and public.is_room_member(room_id, auth.uid()));

create policy "Room managers or hosts update study sessions"
  on public.study_sessions for update to authenticated
  using (host_id = auth.uid() or public.is_room_manager(room_id, auth.uid()))
  with check (host_id = auth.uid() or public.is_room_manager(room_id, auth.uid()));

create policy "Messages visible to room members"
  on public.study_session_messages for select to authenticated
  using (public.is_room_visible(room_id, auth.uid()));

create policy "Room members create messages"
  on public.study_session_messages for insert to authenticated
  with check (user_id = auth.uid() and public.is_room_member(room_id, auth.uid()) and public.is_session_member(session_id, auth.uid()));

create policy "Users soft update own messages"
  on public.study_session_messages for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "Notes visible to room members"
  on public.study_session_notes for select to authenticated
  using (public.is_room_visible(room_id, auth.uid()));

create policy "Room members create notes"
  on public.study_session_notes for insert to authenticated
  with check (user_id = auth.uid() and public.is_room_member(room_id, auth.uid()) and public.is_session_member(session_id, auth.uid()));

create policy "Users update own notes"
  on public.study_session_notes for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "Reactions visible to room members"
  on public.study_session_reactions for select to authenticated
  using (public.is_room_visible(room_id, auth.uid()));

create policy "Room members create reactions"
  on public.study_session_reactions for insert to authenticated
  with check (user_id = auth.uid() and public.is_room_member(room_id, auth.uid()) and public.is_session_member(session_id, auth.uid()));

create policy "Users remove own reactions"
  on public.study_session_reactions for delete to authenticated
  using (user_id = auth.uid());

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'profiles' and policyname = 'Profiles visible to social graph'
  ) then
    create policy "Profiles visible to social graph"
      on public.profiles for select to authenticated
      using (
        id = auth.uid()
        or exists (select 1 from public.friendships f where f.user_id = auth.uid() and f.friend_id = profiles.id)
        or exists (select 1 from public.friend_requests fr where fr.status = 'pending' and auth.uid() in (fr.requester_id, fr.addressee_id) and profiles.id in (fr.requester_id, fr.addressee_id))
        or exists (
          select 1
          from public.study_room_members mine
          join public.study_room_members theirs on theirs.room_id = mine.room_id
          where mine.user_id = auth.uid()
            and mine.status in ('active', 'invited')
            and theirs.user_id = profiles.id
            and theirs.status in ('active', 'invited')
        )
      );
  end if;
end $$;

create or replace function public.community_dashboard()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'profile', (
      select jsonb_build_object('id', p.id, 'name', p.name, 'friend_code', p.friend_code)
      from public.profiles p
      where p.id = auth.uid()
    ),
    'friends', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', fp.id,
        'name', fp.name,
        'friend_code', fp.friend_code,
        'created_at', f.created_at
      ) order by f.created_at desc)
      from public.friendships f
      join public.profiles fp on fp.id = f.friend_id
      where f.user_id = auth.uid()
    ), '[]'::jsonb),
    'incoming_requests', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', fr.id,
        'user_id', rp.id,
        'name', rp.name,
        'friend_code', rp.friend_code,
        'message', fr.message,
        'created_at', fr.created_at
      ) order by fr.created_at desc)
      from public.friend_requests fr
      join public.profiles rp on rp.id = fr.requester_id
      where fr.addressee_id = auth.uid() and fr.status = 'pending'
    ), '[]'::jsonb),
    'outgoing_requests', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', fr.id,
        'user_id', ap.id,
        'name', ap.name,
        'friend_code', ap.friend_code,
        'message', fr.message,
        'created_at', fr.created_at
      ) order by fr.created_at desc)
      from public.friend_requests fr
      join public.profiles ap on ap.id = fr.addressee_id
      where fr.requester_id = auth.uid() and fr.status = 'pending'
    ), '[]'::jsonb),
    'rooms', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id,
        'name', r.name,
        'description', r.description,
        'default_pack_id', r.default_pack_id,
        'language', r.language,
        'invite_code', r.invite_code,
        'owner_id', r.owner_id,
        'role', m.role,
        'member_status', m.status,
        'member_count', (select count(*) from public.study_room_members cm where cm.room_id = r.id and cm.status = 'active'),
        'active_session_id', (select s.id from public.study_sessions s where s.room_id = r.id and s.status = 'active' order by s.started_at desc limit 1),
        'updated_at', r.updated_at,
        'created_at', r.created_at
      ) order by r.updated_at desc)
      from public.study_room_members m
      join public.study_rooms r on r.id = m.room_id
      where m.user_id = auth.uid() and m.status in ('active', 'invited') and r.archived_at is null
    ), '[]'::jsonb)
  );
$$;

create or replace function public.send_friend_request_by_code(target_code text, request_message text default '')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  target uuid;
  request_row public.friend_requests;
begin
  if me is null then
    raise exception 'Authentication required';
  end if;

  select id into target
  from public.profiles
  where upper(friend_code) = upper(trim(target_code))
  limit 1;

  if target is null then
    raise exception 'Friend code not found';
  end if;

  if target = me then
    raise exception 'You cannot add yourself';
  end if;

  if exists (select 1 from public.friendships where user_id = me and friend_id = target) then
    return jsonb_build_object('status', 'already_friends');
  end if;

  if exists (select 1 from public.friend_requests where requester_id = target and addressee_id = me and status = 'pending') then
    select * into request_row
    from public.friend_requests
    where requester_id = target and addressee_id = me and status = 'pending'
    order by created_at desc
    limit 1;

    update public.friend_requests
    set status = 'accepted', responded_at = now()
    where id = request_row.id;

    insert into public.friendships(user_id, friend_id) values (me, target) on conflict do nothing;
    insert into public.friendships(user_id, friend_id) values (target, me) on conflict do nothing;

    return jsonb_build_object('status', 'accepted_existing_request', 'request_id', request_row.id);
  end if;

  insert into public.friend_requests(requester_id, addressee_id, message)
  values (me, target, coalesce(request_message, ''))
  on conflict (requester_id, addressee_id) where status = 'pending'
  do update set message = excluded.message, created_at = now()
  returning * into request_row;

  return jsonb_build_object('status', 'pending', 'request_id', request_row.id);
end;
$$;

create or replace function public.respond_friend_request(request_id uuid, accept boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  request_row public.friend_requests;
begin
  if me is null then
    raise exception 'Authentication required';
  end if;

  select * into request_row
  from public.friend_requests
  where id = request_id and addressee_id = me and status = 'pending'
  for update;

  if request_row.id is null then
    raise exception 'Friend request not found';
  end if;

  if accept then
    update public.friend_requests
    set status = 'accepted', responded_at = now()
    where id = request_id;

    insert into public.friendships(user_id, friend_id) values (request_row.addressee_id, request_row.requester_id) on conflict do nothing;
    insert into public.friendships(user_id, friend_id) values (request_row.requester_id, request_row.addressee_id) on conflict do nothing;

    return jsonb_build_object('status', 'accepted');
  end if;

  update public.friend_requests
  set status = 'declined', responded_at = now()
  where id = request_id;

  return jsonb_build_object('status', 'declined');
end;
$$;

create or replace function public.create_study_room(room_name text, room_description text default '', default_pack text default 'psalms', room_language text default 'en')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  room_row public.study_rooms;
begin
  if me is null then
    raise exception 'Authentication required';
  end if;

  insert into public.study_rooms(owner_id, name, description, default_pack_id, language)
  values (me, trim(room_name), coalesce(room_description, ''), coalesce(default_pack, 'psalms'), coalesce(room_language, 'en'))
  returning * into room_row;

  insert into public.study_room_members(room_id, user_id, role, status, joined_at)
  values (room_row.id, me, 'owner', 'active', now())
  on conflict (room_id, user_id) do update set role = 'owner', status = 'active', joined_at = coalesce(public.study_room_members.joined_at, now());

  return jsonb_build_object('id', room_row.id, 'invite_code', room_row.invite_code, 'name', room_row.name);
end;
$$;

create or replace function public.join_study_room_by_code(target_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  room_row public.study_rooms;
begin
  if me is null then
    raise exception 'Authentication required';
  end if;

  select * into room_row
  from public.study_rooms
  where upper(invite_code) = upper(trim(target_code)) and archived_at is null
  limit 1;

  if room_row.id is null then
    raise exception 'Study room not found';
  end if;

  insert into public.study_room_members(room_id, user_id, role, status, joined_at)
  values (room_row.id, me, 'member', 'active', now())
  on conflict (room_id, user_id)
  do update set status = 'active', joined_at = coalesce(public.study_room_members.joined_at, now());

  return jsonb_build_object('id', room_row.id, 'name', room_row.name);
end;
$$;

create or replace function public.invite_friend_to_room(target_room_id uuid, target_friend_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Authentication required';
  end if;

  if not public.is_room_manager(target_room_id, me) then
    raise exception 'Only room managers can invite friends';
  end if;

  if not exists (select 1 from public.friendships where user_id = me and friend_id = target_friend_id) then
    raise exception 'You can only invite accepted friends';
  end if;

  insert into public.study_room_members(room_id, user_id, role, status, invited_by)
  values (target_room_id, target_friend_id, 'member', 'invited', me)
  on conflict (room_id, user_id)
  do update set status = case when public.study_room_members.status = 'removed' then 'invited' else public.study_room_members.status end,
                invited_by = me;

  return jsonb_build_object('status', 'invited');
end;
$$;

create or replace function public.create_study_session(target_room_id uuid, session_title text default 'Bible study', target_book text default '', target_book_name text default '', target_chapter integer default 1, target_verse_start integer default null, target_verse_end integer default null, target_language text default 'en')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  session_row public.study_sessions;
begin
  if me is null then
    raise exception 'Authentication required';
  end if;

  if not public.is_room_member(target_room_id, me) then
    raise exception 'You are not a member of this room';
  end if;

  insert into public.study_sessions(room_id, host_id, title, book, book_name, chapter, verse_start, verse_end, language)
  values (target_room_id, me, coalesce(session_title, 'Bible study'), coalesce(target_book, ''), coalesce(target_book_name, ''), coalesce(target_chapter, 1), target_verse_start, target_verse_end, coalesce(target_language, 'en'))
  returning * into session_row;

  return jsonb_build_object('id', session_row.id, 'room_id', session_row.room_id, 'phase', session_row.phase, 'status', session_row.status);
end;
$$;

grant execute on function public.community_dashboard() to authenticated;
grant execute on function public.send_friend_request_by_code(text, text) to authenticated;
grant execute on function public.respond_friend_request(uuid, boolean) to authenticated;
grant execute on function public.create_study_room(text, text, text, text) to authenticated;
grant execute on function public.join_study_room_by_code(text) to authenticated;
grant execute on function public.invite_friend_to_room(uuid, uuid) to authenticated;
grant execute on function public.create_study_session(uuid, text, text, text, integer, integer, integer, text) to authenticated;

alter table realtime.messages enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'realtime' and tablename = 'messages' and policyname = 'Study members can receive realtime events'
  ) then
    create policy "Study members can receive realtime events"
      on realtime.messages for select to authenticated
      using (realtime.messages.extension in ('broadcast', 'presence') and public.can_access_realtime_topic(realtime.topic()));
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'realtime' and tablename = 'messages' and policyname = 'Study members can send realtime events'
  ) then
    create policy "Study members can send realtime events"
      on realtime.messages for insert to authenticated
      with check (realtime.messages.extension in ('broadcast', 'presence') and public.can_access_realtime_topic(realtime.topic()));
  end if;
end $$;
