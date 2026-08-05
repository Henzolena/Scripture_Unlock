create or replace function public.finish_study_session_quiz(
  target_session_id uuid,
  actor_id uuid,
  require_leader boolean default true,
  require_timer_elapsed boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  session_row public.study_sessions;
  question_count integer;
  summary text;
  timer_elapsed boolean;
begin
  if actor_id is null then
    raise exception 'Authentication required';
  end if;

  select * into session_row
  from public.study_sessions
  where id = target_session_id
    and status = 'active'
  for update;

  if not found then
    raise exception 'Active study session not found';
  end if;

  if require_leader then
    if not public.is_room_leader(session_row.room_id, actor_id) then
      raise exception 'Only a study leader can end the quiz';
    end if;
  elsif not public.is_session_member(target_session_id, actor_id) then
    raise exception 'You are not a member of this session';
  end if;

  if session_row.quiz_mode <> 'timed' then
    raise exception 'The current quiz is not timed';
  end if;

  if session_row.quiz_status = 'ended' then
    return jsonb_build_object(
      'id', session_row.id,
      'quiz_status', session_row.quiz_status,
      'quiz_ended_at', session_row.quiz_ended_at,
      'status', 'already_ended'
    );
  end if;

  if session_row.quiz_status <> 'running' then
    raise exception 'The timed quiz is not running';
  end if;

  if require_timer_elapsed then
    timer_elapsed := session_row.quiz_started_at is not null
      and now() >= session_row.quiz_started_at + (session_row.quiz_duration_seconds || ' seconds')::interval;

    if not timer_elapsed then
      raise exception 'The quiz timer is still running';
    end if;
  end if;

  question_count := coalesce(jsonb_array_length(coalesce(session_row.guide #> '{quiz,questions}', '[]'::jsonb)), 0);

  update public.study_sessions
  set quiz_status = 'ended',
      quiz_ended_at = coalesce(quiz_ended_at, now()),
      updated_at = now()
  where id = target_session_id
  returning * into session_row;

  select coalesce(
    'Quiz complete: ' || string_agg(
      format('%s %s/%s', coalesce(nullif(p.name, ''), 'Friend'), scores.correct_count, greatest(question_count, 1)),
      ', '
      order by scores.correct_count desc, coalesce(p.name, '')
    ),
    'Quiz complete.'
  )
  into summary
  from public.study_room_members m
  left join public.profiles p on p.id = m.user_id
  left join lateral (
    select coalesce(sum(case when a.is_correct then 1 else 0 end), 0)::int as correct_count
    from public.study_session_quiz_answers a
    where a.session_id = target_session_id
      and a.user_id = m.user_id
  ) scores on true
  where m.room_id = session_row.room_id
    and m.status = 'active';

  insert into public.study_session_messages(session_id, room_id, user_id, kind, body, verse_ref)
  values (target_session_id, session_row.room_id, actor_id, 'system', left(summary, 2000), null);

  perform realtime.send(
    jsonb_build_object('entity', 'quiz_ended', 'session_id', session_row.id, 'quiz_ended_at', session_row.quiz_ended_at),
    'session_changed',
    'study-session:' || target_session_id::text,
    true
  );

  return jsonb_build_object(
    'id', session_row.id,
    'quiz_status', session_row.quiz_status,
    'quiz_ended_at', session_row.quiz_ended_at,
    'status', 'ended'
  );
end;
$function$;

create or replace function public.end_study_session_quiz(target_session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  me uuid := auth.uid();
begin
  return public.finish_study_session_quiz(target_session_id, me, true, false);
end;
$function$;

create or replace function public.submit_study_session_quiz_answer(
  target_session_id uuid,
  question_number integer,
  selected_number integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  me uuid := auth.uid();
  session_row public.study_sessions;
  question_count integer;
  correct_index integer;
  is_answer_correct boolean;
begin
  if me is null then
    raise exception 'Authentication required';
  end if;

  if selected_number < 0 or selected_number > 3 then
    raise exception 'Selected answer must be between 0 and 3';
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

  if session_row.quiz_mode <> 'timed' or session_row.quiz_status <> 'running' then
    raise exception 'The timed quiz is not running';
  end if;

  if session_row.quiz_started_at is null
     or now() >= session_row.quiz_started_at + (session_row.quiz_duration_seconds || ' seconds')::interval then
    return public.finish_study_session_quiz(target_session_id, me, false, true);
  end if;

  question_count := coalesce(jsonb_array_length(coalesce(session_row.guide #> '{quiz,questions}', '[]'::jsonb)), 0);
  if question_number < 0 or question_number >= question_count then
    raise exception 'Quiz question not found';
  end if;

  correct_index := nullif(session_row.guide->'quiz'->'questions'->question_number->>'answer_index', '')::integer;
  if correct_index is null then
    raise exception 'Quiz answer key is missing';
  end if;

  is_answer_correct := selected_number = correct_index;

  insert into public.study_session_quiz_answers(session_id, room_id, user_id, question_index, selected_index, is_correct, answered_at)
  values (target_session_id, session_row.room_id, me, question_number, selected_number, is_answer_correct, now())
  on conflict (session_id, user_id, question_index)
  do update set selected_index = excluded.selected_index,
                is_correct = excluded.is_correct,
                answered_at = now();

  perform realtime.send(
    jsonb_build_object('entity', 'quiz_answer', 'session_id', target_session_id, 'user_id', me, 'question_index', question_number),
    'session_changed',
    'study-session:' || target_session_id::text,
    true
  );

  return jsonb_build_object('question_index', question_number, 'selected_index', selected_number);
end;
$function$;

revoke all on function public.finish_study_session_quiz(uuid, uuid, boolean, boolean) from public, anon, authenticated;
revoke all on function public.end_study_session_quiz(uuid) from public, anon;
grant execute on function public.end_study_session_quiz(uuid) to authenticated;
revoke all on function public.submit_study_session_quiz_answer(uuid, integer, integer) from public, anon;
grant execute on function public.submit_study_session_quiz_answer(uuid, integer, integer) to authenticated;
