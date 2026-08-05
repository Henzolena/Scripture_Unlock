create or replace function public.study_session_snapshot(target_session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  session_row public.study_sessions;
  room_row public.study_rooms;
  reaction_counts jsonb;
begin
  if me is null then
    raise exception 'Authentication required';
  end if;

  select * into session_row
  from public.study_sessions
  where id = target_session_id;

  if not found then
    raise exception 'Study session not found';
  end if;

  if not public.is_session_member(target_session_id, me) then
    raise exception 'You are not a member of this session';
  end if;

  select * into room_row
  from public.study_rooms
  where id = session_row.room_id;

  select coalesce(jsonb_object_agg(reaction, total), '{}'::jsonb)
  into reaction_counts
  from (
    select reaction, count(*)::int as total
    from public.study_session_reactions
    where session_id = target_session_id
    group by reaction
  ) totals;

  return jsonb_build_object(
    'session', jsonb_build_object(
      'id', session_row.id,
      'room_id', session_row.room_id,
      'host_id', session_row.host_id,
      'title', session_row.title,
      'book', session_row.book,
      'book_name', session_row.book_name,
      'chapter', session_row.chapter,
      'verse_start', session_row.verse_start,
      'verse_end', session_row.verse_end,
      'language', session_row.language,
      'phase', session_row.phase,
      'status', session_row.status,
      'started_at', session_row.started_at,
      'ended_at', session_row.ended_at
    ),
    'room', jsonb_build_object(
      'id', room_row.id,
      'name', room_row.name,
      'description', room_row.description,
      'default_pack_id', room_row.default_pack_id,
      'language', room_row.language,
      'invite_code', room_row.invite_code
    ),
    'messages', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', m.id,
          'session_id', m.session_id,
          'room_id', m.room_id,
          'user_id', m.user_id,
          'user_name', coalesce(p.name, ''),
          'kind', m.kind,
          'body', m.body,
          'verse_ref', m.verse_ref,
          'created_at', m.created_at
        ) order by m.created_at asc
      )
      from public.study_session_messages m
      left join public.profiles p on p.id = m.user_id
      where m.session_id = target_session_id
        and m.deleted_at is null
    ), '[]'::jsonb),
    'notes', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', n.id,
          'session_id', n.session_id,
          'room_id', n.room_id,
          'user_id', n.user_id,
          'user_name', coalesce(p.name, ''),
          'verse_ref', n.verse_ref,
          'body', n.body,
          'created_at', n.created_at,
          'updated_at', n.updated_at
        ) order by n.created_at desc
      )
      from public.study_session_notes n
      left join public.profiles p on p.id = n.user_id
      where n.session_id = target_session_id
        and n.deleted_at is null
    ), '[]'::jsonb),
    'reaction_counts', reaction_counts,
    'my_reactions', coalesce((
      select jsonb_agg(distinct r.reaction)
      from public.study_session_reactions r
      where r.session_id = target_session_id
        and r.user_id = me
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.post_study_session_message(
  target_session_id uuid,
  message_body text,
  message_kind text default 'chat',
  message_verse_ref text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  session_row public.study_sessions;
  message_row public.study_session_messages;
  actor_name text;
begin
  if me is null then
    raise exception 'Authentication required';
  end if;

  select * into session_row
  from public.study_sessions
  where id = target_session_id
    and status = 'active';

  if not found then
    raise exception 'Active study session not found';
  end if;

  if not public.is_session_member(target_session_id, me) then
    raise exception 'You are not a member of this session';
  end if;

  if coalesce(message_kind, 'chat') not in ('chat', 'prayer', 'prompt') then
    raise exception 'Unsupported message type';
  end if;

  insert into public.study_session_messages(session_id, room_id, user_id, kind, body, verse_ref)
  values (
    target_session_id,
    session_row.room_id,
    me,
    coalesce(message_kind, 'chat'),
    trim(message_body),
    nullif(trim(coalesce(message_verse_ref, '')), '')
  )
  returning * into message_row;

  select coalesce(name, '') into actor_name
  from public.profiles
  where id = me;

  perform realtime.send(
    jsonb_build_object(
      'entity', 'message',
      'id', message_row.id,
      'session_id', message_row.session_id,
      'room_id', message_row.room_id,
      'user_id', message_row.user_id,
      'user_name', coalesce(actor_name, ''),
      'kind', message_row.kind,
      'body', message_row.body,
      'verse_ref', message_row.verse_ref,
      'created_at', message_row.created_at
    ),
    'session_changed',
    'study-session:' || target_session_id::text,
    true
  );

  return jsonb_build_object('id', message_row.id, 'created_at', message_row.created_at);
end;
$$;

create or replace function public.post_study_session_note(
  target_session_id uuid,
  note_body text,
  note_verse_ref text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  session_row public.study_sessions;
  note_row public.study_session_notes;
  actor_name text;
begin
  if me is null then
    raise exception 'Authentication required';
  end if;

  select * into session_row
  from public.study_sessions
  where id = target_session_id
    and status = 'active';

  if not found then
    raise exception 'Active study session not found';
  end if;

  if not public.is_session_member(target_session_id, me) then
    raise exception 'You are not a member of this session';
  end if;

  insert into public.study_session_notes(session_id, room_id, user_id, verse_ref, body)
  values (
    target_session_id,
    session_row.room_id,
    me,
    nullif(trim(coalesce(note_verse_ref, '')), ''),
    trim(note_body)
  )
  returning * into note_row;

  select coalesce(name, '') into actor_name
  from public.profiles
  where id = me;

  perform realtime.send(
    jsonb_build_object(
      'entity', 'note',
      'id', note_row.id,
      'session_id', note_row.session_id,
      'room_id', note_row.room_id,
      'user_id', note_row.user_id,
      'user_name', coalesce(actor_name, ''),
      'verse_ref', note_row.verse_ref,
      'body', note_row.body,
      'created_at', note_row.created_at,
      'updated_at', note_row.updated_at
    ),
    'session_changed',
    'study-session:' || target_session_id::text,
    true
  );

  return jsonb_build_object('id', note_row.id, 'created_at', note_row.created_at);
end;
$$;

create or replace function public.add_study_session_reaction(
  target_session_id uuid,
  reaction_name text,
  target_kind text default 'session',
  target_uuid uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  session_row public.study_sessions;
  reaction_row public.study_session_reactions;
begin
  if me is null then
    raise exception 'Authentication required';
  end if;

  select * into session_row
  from public.study_sessions
  where id = target_session_id
    and status = 'active';

  if not found then
    raise exception 'Active study session not found';
  end if;

  if not public.is_session_member(target_session_id, me) then
    raise exception 'You are not a member of this session';
  end if;

  if reaction_name not in ('amen', 'insightful', 'praying', 'question', 'heart') then
    raise exception 'Unsupported reaction';
  end if;

  if coalesce(target_kind, 'session') not in ('session', 'message', 'note', 'verse') then
    raise exception 'Unsupported reaction target';
  end if;

  insert into public.study_session_reactions(session_id, room_id, user_id, target_type, target_id, reaction)
  values (target_session_id, session_row.room_id, me, coalesce(target_kind, 'session'), target_uuid, reaction_name)
  returning * into reaction_row;

  perform realtime.send(
    jsonb_build_object(
      'entity', 'reaction',
      'id', reaction_row.id,
      'session_id', reaction_row.session_id,
      'room_id', reaction_row.room_id,
      'user_id', reaction_row.user_id,
      'target_type', reaction_row.target_type,
      'target_id', reaction_row.target_id,
      'reaction', reaction_row.reaction,
      'created_at', reaction_row.created_at
    ),
    'session_changed',
    'study-session:' || target_session_id::text,
    true
  );

  return jsonb_build_object('id', reaction_row.id, 'created_at', reaction_row.created_at);
end;
$$;

create or replace function public.advance_study_session_phase(
  target_session_id uuid,
  next_phase text
)
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

  select * into session_row
  from public.study_sessions
  where id = target_session_id
    and status = 'active';

  if not found then
    raise exception 'Active study session not found';
  end if;

  if not public.is_room_manager(session_row.room_id, me) then
    raise exception 'Only the room owner or an admin can guide the session';
  end if;

  if next_phase not in ('read', 'reflect', 'discuss', 'quiz', 'pray', 'recap') then
    raise exception 'Unsupported session phase';
  end if;

  update public.study_sessions
  set phase = next_phase,
      updated_at = now()
  where id = target_session_id
  returning * into session_row;

  perform realtime.send(
    jsonb_build_object(
      'entity', 'phase',
      'session_id', session_row.id,
      'phase', session_row.phase,
      'updated_at', session_row.updated_at
    ),
    'session_changed',
    'study-session:' || target_session_id::text,
    true
  );

  return jsonb_build_object('id', session_row.id, 'phase', session_row.phase);
end;
$$;

create or replace function public.end_study_session(target_session_id uuid)
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

  select * into session_row
  from public.study_sessions
  where id = target_session_id;

  if not found then
    raise exception 'Study session not found';
  end if;

  if not public.is_room_manager(session_row.room_id, me) then
    raise exception 'Only the room owner or an admin can end the session';
  end if;

  update public.study_sessions
  set status = 'ended',
      ended_at = now(),
      updated_at = now()
  where id = target_session_id
  returning * into session_row;

  perform realtime.send(
    jsonb_build_object(
      'entity', 'ended',
      'session_id', session_row.id,
      'status', session_row.status,
      'ended_at', session_row.ended_at
    ),
    'session_changed',
    'study-session:' || target_session_id::text,
    true
  );

  return jsonb_build_object('id', session_row.id, 'status', session_row.status);
end;
$$;

revoke all on function public.study_session_snapshot(uuid) from public, anon;
revoke all on function public.post_study_session_message(uuid, text, text, text) from public, anon;
revoke all on function public.post_study_session_note(uuid, text, text) from public, anon;
revoke all on function public.add_study_session_reaction(uuid, text, text, uuid) from public, anon;
revoke all on function public.advance_study_session_phase(uuid, text) from public, anon;
revoke all on function public.end_study_session(uuid) from public, anon;

grant execute on function public.study_session_snapshot(uuid) to authenticated;
grant execute on function public.post_study_session_message(uuid, text, text, text) to authenticated;
grant execute on function public.post_study_session_note(uuid, text, text) to authenticated;
grant execute on function public.add_study_session_reaction(uuid, text, text, uuid) to authenticated;
grant execute on function public.advance_study_session_phase(uuid, text) to authenticated;
grant execute on function public.end_study_session(uuid) to authenticated;
