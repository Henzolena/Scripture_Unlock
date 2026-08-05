create or replace function public.community_dashboard()
returns jsonb
language sql
stable security definer
set search_path to 'public'
as $function$
  select jsonb_build_object(
    'profile', (
      select jsonb_build_object(
        'id', p.id,
        'name', p.name,
        'friend_code', p.friend_code,
        'avatar_path', coalesce(p.avatar_path, '')
      )
      from public.profiles p
      where p.id = auth.uid()
    ),
    'friends', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', fp.id,
        'name', fp.name,
        'friend_code', fp.friend_code,
        'avatar_path', coalesce(fp.avatar_path, ''),
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
        'avatar_path', coalesce(rp.avatar_path, ''),
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
        'avatar_path', coalesce(ap.avatar_path, ''),
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
$function$;

create or replace function public.study_room_members_snapshot(target_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  me uuid := auth.uid();
  my_role text;
  can_manage boolean;
begin
  if me is null then
    raise exception 'Authentication required';
  end if;

  select m.role into my_role
  from public.study_room_members m
  where m.room_id = target_room_id
    and m.user_id = me
    and m.status = 'active';

  if my_role is null then
    raise exception 'You are not a member of this room';
  end if;

  can_manage := my_role in ('owner', 'admin');

  return jsonb_build_object(
    'room_id', target_room_id,
    'my_role', my_role,
    'can_manage_roles', can_manage,
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_id', m.user_id,
        'name', coalesce(p.name, ''),
        'friend_code', coalesce(p.friend_code, ''),
        'avatar_path', coalesce(p.avatar_path, ''),
        'role', m.role,
        'status', m.status,
        'joined_at', m.joined_at,
        'created_at', m.created_at
      ) order by
        case m.role when 'owner' then 0 when 'admin' then 1 when 'leader' then 2 else 3 end,
        coalesce(p.name, '')
      )
      from public.study_room_members m
      left join public.profiles p on p.id = m.user_id
      where m.room_id = target_room_id
        and m.status in ('active', 'invited')
    ), '[]'::jsonb)
  );
end;
$function$;

create or replace function public.study_session_snapshot(target_session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  me uuid := auth.uid();
  session_row public.study_sessions;
  room_row public.study_rooms;
  reaction_counts jsonb;
  my_role text;
  can_lead boolean;
  can_manage_roles boolean;
  reveal_answers boolean;
  visible_guide jsonb;
  question_count integer;
  quiz_my_answers jsonb;
  quiz_results jsonb;
  quiz_question_stats jsonb;
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

  select m.role into my_role
  from public.study_room_members m
  where m.room_id = session_row.room_id
    and m.user_id = me
    and m.status = 'active';

  can_lead := coalesce(my_role in ('owner', 'admin', 'leader'), false);
  can_manage_roles := coalesce(my_role in ('owner', 'admin'), false);
  reveal_answers := can_lead or (session_row.quiz_mode = 'timed' and session_row.quiz_status = 'ended');
  question_count := coalesce(jsonb_array_length(coalesce(session_row.guide #> '{quiz,questions}', '[]'::jsonb)), 0);

  visible_guide := case
    when session_row.guide_status = 'ready' and session_row.guide <> '{}'::jsonb then public.visible_study_session_guide(session_row.guide, reveal_answers)
    else null
  end;

  select coalesce(jsonb_object_agg(reaction, total), '{}'::jsonb)
  into reaction_counts
  from (
    select reaction, count(*)::int as total
    from public.study_session_reactions
    where session_id = target_session_id
    group by reaction
  ) totals;

  select coalesce(jsonb_agg(jsonb_build_object(
    'question_index', a.question_index,
    'selected_index', a.selected_index,
    'is_correct', case when reveal_answers then a.is_correct else null end,
    'answered_at', a.answered_at
  ) order by a.question_index), '[]'::jsonb)
  into quiz_my_answers
  from public.study_session_quiz_answers a
  where a.session_id = target_session_id
    and a.user_id = me;

  if can_lead or session_row.quiz_status = 'ended' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'user_id', scores.user_id,
      'user_name', scores.user_name,
      'avatar_path', scores.avatar_path,
      'answered', scores.answered,
      'correct', scores.correct,
      'total', question_count,
      'is_complete', scores.answered >= question_count and question_count > 0
    ) order by scores.correct desc, scores.answered desc, scores.user_name), '[]'::jsonb)
    into quiz_results
    from (
      select m.user_id,
             coalesce(nullif(p.name, ''), 'Friend') as user_name,
             coalesce(p.avatar_path, '') as avatar_path,
             count(a.question_index)::int as answered,
             coalesce(sum(case when a.is_correct then 1 else 0 end), 0)::int as correct
      from public.study_room_members m
      left join public.profiles p on p.id = m.user_id
      left join public.study_session_quiz_answers a on a.session_id = target_session_id and a.user_id = m.user_id
      where m.room_id = session_row.room_id
        and m.status = 'active'
      group by m.user_id, p.name, p.avatar_path
    ) scores;

    select coalesce(jsonb_agg(jsonb_build_object(
      'question_index', stats.question_index,
      'answer_counts', stats.answer_counts,
      'correct_index', case when reveal_answers then stats.correct_index else null end
    ) order by stats.question_index), '[]'::jsonb)
    into quiz_question_stats
    from (
      select gs.i as question_index,
             jsonb_build_array(
               count(a.*) filter (where a.selected_index = 0),
               count(a.*) filter (where a.selected_index = 1),
               count(a.*) filter (where a.selected_index = 2),
               count(a.*) filter (where a.selected_index = 3)
             ) as answer_counts,
             nullif(session_row.guide->'quiz'->'questions'->gs.i->>'answer_index', '')::integer as correct_index
      from generate_series(0, question_count - 1) as gs(i)
      left join public.study_session_quiz_answers a on a.session_id = target_session_id and a.question_index = gs.i
      group by gs.i
    ) stats;
  else
    quiz_results := '[]'::jsonb;
    quiz_question_stats := '[]'::jsonb;
  end if;

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
      'guide', visible_guide,
      'quiz_mode', session_row.quiz_mode,
      'quiz_status', session_row.quiz_status,
      'quiz_started_at', session_row.quiz_started_at,
      'quiz_ended_at', session_row.quiz_ended_at,
      'quiz_duration_seconds', session_row.quiz_duration_seconds
    ),
    'room', jsonb_build_object(
      'id', room_row.id,
      'name', room_row.name,
      'description', room_row.description,
      'default_pack_id', room_row.default_pack_id,
      'language', room_row.language,
      'invite_code', room_row.invite_code,
      'my_role', my_role,
      'can_lead', can_lead,
      'can_manage_roles', can_manage_roles
    ),
    'messages', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id,
        'session_id', m.session_id,
        'room_id', m.room_id,
        'user_id', m.user_id,
        'user_name', coalesce(p.name, ''),
        'avatar_path', coalesce(p.avatar_path, ''),
        'kind', m.kind,
        'body', m.body,
        'verse_ref', m.verse_ref,
        'created_at', m.created_at
      ) order by m.created_at asc)
      from public.study_session_messages m
      left join public.profiles p on p.id = m.user_id
      where m.session_id = target_session_id
        and m.deleted_at is null
    ), '[]'::jsonb),
    'notes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', n.id,
        'session_id', n.session_id,
        'room_id', n.room_id,
        'user_id', n.user_id,
        'user_name', coalesce(p.name, ''),
        'avatar_path', coalesce(p.avatar_path, ''),
        'verse_ref', n.verse_ref,
        'body', n.body,
        'created_at', n.created_at,
        'updated_at', n.updated_at
      ) order by n.created_at desc)
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
    ), '[]'::jsonb),
    'quiz', jsonb_build_object(
      'my_answers', quiz_my_answers,
      'results', quiz_results,
      'question_stats', quiz_question_stats,
      'question_count', question_count
    )
  );
end;
$function$;
