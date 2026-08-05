-- One reaction per user per target, with second tap toggling it off.
-- Also stores an LLM-prepared study guide with every live study session.

alter table public.study_sessions
  add column if not exists guide jsonb not null default '{}'::jsonb,
  add column if not exists guide_status text not null default 'pending',
  add column if not exists guide_generated_at timestamptz;

alter table public.study_sessions
  drop constraint if exists study_sessions_guide_status_check;

alter table public.study_sessions
  add constraint study_sessions_guide_status_check
  check (guide_status in ('pending', 'ready', 'failed'));

-- Remove duplicate historical reactions before adding uniqueness.
with ranked as (
  select id,
         row_number() over (
           partition by session_id, user_id, target_type, target_id, reaction
           order by created_at asc, id asc
         ) as rn
  from public.study_session_reactions
)
delete from public.study_session_reactions r
using ranked d
where r.id = d.id
  and d.rn > 1;

create unique index if not exists study_session_reactions_unique_target_idx
  on public.study_session_reactions(session_id, user_id, target_type, target_id, reaction)
  where target_id is not null;

create unique index if not exists study_session_reactions_unique_session_idx
  on public.study_session_reactions(session_id, user_id, target_type, reaction)
  where target_id is null;

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
as $function$
declare
  me uuid := auth.uid();
  session_row public.study_sessions;
  existing_row public.study_session_reactions;
  reaction_row public.study_session_reactions;
  resolved_target text := coalesce(target_kind, 'session');
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

  if resolved_target not in ('session', 'message', 'note', 'verse') then
    raise exception 'Unsupported reaction target';
  end if;

  select * into existing_row
  from public.study_session_reactions
  where session_id = target_session_id
    and user_id = me
    and target_type = resolved_target
    and target_id is not distinct from target_uuid
    and reaction = reaction_name
  limit 1;

  if found then
    delete from public.study_session_reactions
    where id = existing_row.id
    returning * into reaction_row;

    perform realtime.send(
      jsonb_build_object(
        'entity', 'reaction_removed',
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

    return jsonb_build_object('id', reaction_row.id, 'action', 'removed');
  end if;

  insert into public.study_session_reactions(session_id, room_id, user_id, target_type, target_id, reaction)
  values (target_session_id, session_row.room_id, me, resolved_target, target_uuid, reaction_name)
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

  return jsonb_build_object('id', reaction_row.id, 'action', 'added', 'created_at', reaction_row.created_at);
end;
$function$;

create or replace function public.save_study_session_guide(
  target_session_id uuid,
  guide_payload jsonb,
  next_status text default 'ready'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  me uuid := auth.uid();
  session_row public.study_sessions;
  resolved_status text := coalesce(next_status, 'ready');
begin
  if me is null then
    raise exception 'Authentication required';
  end if;

  if resolved_status not in ('ready', 'failed') then
    raise exception 'Unsupported guide status';
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

  update public.study_sessions
  set guide = case when resolved_status = 'ready' then coalesce(guide_payload, '{}'::jsonb) else '{}'::jsonb end,
      guide_status = resolved_status,
      guide_generated_at = case when resolved_status = 'ready' then now() else guide_generated_at end,
      updated_at = now()
  where id = target_session_id
  returning * into session_row;

  perform realtime.send(
    jsonb_build_object(
      'entity', 'guide',
      'session_id', session_row.id,
      'guide_status', session_row.guide_status,
      'guide_generated_at', session_row.guide_generated_at,
      'updated_at', session_row.updated_at
    ),
    'session_changed',
    'study-session:' || target_session_id::text,
    true
  );

  return jsonb_build_object(
    'id', session_row.id,
    'guide_status', session_row.guide_status,
    'guide_generated_at', session_row.guide_generated_at
  );
end;
$function$;

create or replace function public.study_session_snapshot(target_session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
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
      'ended_at', session_row.ended_at,
      'guide_status', session_row.guide_status,
      'guide_generated_at', session_row.guide_generated_at,
      'guide', case
        when session_row.guide_status = 'ready' and session_row.guide <> '{}'::jsonb then session_row.guide
        else null
      end
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
        and r.target_type = 'session'
        and r.target_id is null
    ), '[]'::jsonb)
  );
end;
$function$;

grant execute on function public.add_study_session_reaction(uuid, text, text, uuid) to authenticated;
grant execute on function public.save_study_session_guide(uuid, jsonb, text) to authenticated;
grant execute on function public.study_session_snapshot(uuid) to authenticated;
