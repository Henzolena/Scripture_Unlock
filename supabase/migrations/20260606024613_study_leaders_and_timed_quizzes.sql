-- Room leadership, leader-only study content, and timed live quiz sessions.

alter table public.study_room_members
  drop constraint if exists study_room_members_role_check;

alter table public.study_room_members
  add constraint study_room_members_role_check
  check (role = any (array['owner'::text, 'admin'::text, 'leader'::text, 'member'::text]));

alter table public.study_sessions
  add column if not exists quiz_mode text not null default 'leader_led',
  add column if not exists quiz_status text not null default 'setup',
  add column if not exists quiz_started_at timestamptz,
  add column if not exists quiz_ended_at timestamptz,
  add column if not exists quiz_duration_seconds integer not null default 90;

alter table public.study_sessions
  drop constraint if exists study_sessions_quiz_mode_check;

alter table public.study_sessions
  add constraint study_sessions_quiz_mode_check
  check (quiz_mode in ('leader_led', 'timed'));

alter table public.study_sessions
  drop constraint if exists study_sessions_quiz_status_check;

alter table public.study_sessions
  add constraint study_sessions_quiz_status_check
  check (quiz_status in ('setup', 'running', 'ended'));

alter table public.study_sessions
  drop constraint if exists study_sessions_quiz_duration_seconds_check;

alter table public.study_sessions
  add constraint study_sessions_quiz_duration_seconds_check
  check (quiz_duration_seconds between 30 and 600);

create table if not exists public.study_session_quiz_answers (
  session_id uuid not null references public.study_sessions(id) on delete cascade,
  room_id uuid not null references public.study_rooms(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  question_index integer not null check (question_index >= 0),
  selected_index integer not null check (selected_index between 0 and 3),
  is_correct boolean not null default false,
  answered_at timestamptz not null default now(),
  primary key (session_id, user_id, question_index)
);

alter table public.study_session_quiz_answers enable row level security;

create index if not exists study_session_quiz_answers_session_idx
  on public.study_session_quiz_answers(session_id);

create index if not exists study_session_quiz_answers_user_idx
  on public.study_session_quiz_answers(user_id);

create or replace function public.is_room_manager(target_room_id uuid, target_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $function$
  select exists (
    select 1
    from public.study_room_members m
    where m.room_id = target_room_id
      and m.user_id = target_user_id
      and m.status = 'active'
      and m.role in ('owner', 'admin')
  );
$function$;

create or replace function public.is_room_leader(target_room_id uuid, target_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $function$
  select exists (
    select 1
    from public.study_room_members m
    where m.room_id = target_room_id
      and m.user_id = target_user_id
      and m.status = 'active'
      and m.role in ('owner', 'admin', 'leader')
  );
$function$;

create or replace function public.visible_study_session_guide(guide_payload jsonb, reveal_answers boolean)
returns jsonb
language plpgsql
stable
set search_path = public
as $function$
declare
  redacted_questions jsonb;
begin
  if guide_payload is null or guide_payload = '{}'::jsonb then
    return null;
  end if;

  if reveal_answers then
    return guide_payload;
  end if;

  select coalesce(
    jsonb_agg(
      (question_value - 'answer_index' - 'explanation') || jsonb_build_object('answer_index', -1, 'explanation', '')
      order by ordinal_value
    ),
    '[]'::jsonb
  )
  into redacted_questions
  from jsonb_array_elements(coalesce(guide_payload #> '{quiz,questions}', '[]'::jsonb))
       with ordinality as q(question_value, ordinal_value);

  return jsonb_set(
    jsonb_set(guide_payload, '{discuss,leader_notes}', '[]'::jsonb, true),
    '{quiz,questions}',
    redacted_questions,
    true
  );
end;
$function$;

create or replace function public.study_room_members_snapshot(target_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
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

create or replace function public.set_study_room_member_role(
  target_room_id uuid,
  target_user_id uuid,
  next_role text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  me uuid := auth.uid();
  actor_role text;
  target_role text;
begin
  if me is null then
    raise exception 'Authentication required';
  end if;

  if next_role not in ('admin', 'leader', 'member') then
    raise exception 'Unsupported room role';
  end if;

  select role into actor_role
  from public.study_room_members
  where room_id = target_room_id
    and user_id = me
    and status = 'active';

  if actor_role not in ('owner', 'admin') then
    raise exception 'Only room owners or admins can update roles';
  end if;

  select role into target_role
  from public.study_room_members
  where room_id = target_room_id
    and user_id = target_user_id
    and status = 'active';

  if target_role is null then
    raise exception 'Active room member not found';
  end if;

  if target_role = 'owner' then
    raise exception 'The room owner role cannot be changed';
  end if;

  if actor_role = 'admin' and next_role = 'admin' then
    raise exception 'Only the room owner can assign admins';
  end if;

  if actor_role = 'admin' and target_role = 'admin' then
    raise exception 'Only the room owner can change admins';
  end if;

  update public.study_room_members
  set role = next_role
  where room_id = target_room_id
    and user_id = target_user_id
  returning role into target_role;

  return jsonb_build_object('user_id', target_user_id, 'role', target_role);
end;
$function$;

create or replace function public.create_study_session(
  target_room_id uuid,
  session_title text default 'Bible study',
  target_book text default '',
  target_book_name text default '',
  target_chapter integer default 1,
  target_verse_start integer default null,
  target_verse_end integer default null,
  target_language text default 'en'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  me uuid := auth.uid();
  session_row public.study_sessions;
begin
  if me is null then
    raise exception 'Authentication required';
  end if;

  if not public.is_room_leader(target_room_id, me) then
    raise exception 'Only a room leader can start a guided study session';
  end if;

  insert into public.study_sessions(room_id, host_id, title, book, book_name, chapter, verse_start, verse_end, language)
  values (target_room_id, me, coalesce(session_title, 'Bible study'), coalesce(target_book, ''), coalesce(target_book_name, ''), coalesce(target_chapter, 1), target_verse_start, target_verse_end, coalesce(target_language, 'en'))
  returning * into session_row;

  return jsonb_build_object('id', session_row.id, 'room_id', session_row.room_id, 'phase', session_row.phase, 'status', session_row.status);
end;
$function$;

create or replace function public.configure_study_session_quiz(
  target_session_id uuid,
  next_mode text,
  duration_seconds integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  me uuid := auth.uid();
  session_row public.study_sessions;
  resolved_duration integer := coalesce(duration_seconds, 90);
begin
  if me is null then
    raise exception 'Authentication required';
  end if;

  if next_mode not in ('leader_led', 'timed') then
    raise exception 'Unsupported quiz mode';
  end if;

  if resolved_duration < 30 or resolved_duration > 600 then
    raise exception 'Quiz duration must be between 30 seconds and 10 minutes';
  end if;

  select * into session_row
  from public.study_sessions
  where id = target_session_id
    and status = 'active';

  if not found then
    raise exception 'Active study session not found';
  end if;

  if not public.is_room_leader(session_row.room_id, me) then
    raise exception 'Only a study leader can configure the quiz';
  end if;

  delete from public.study_session_quiz_answers where session_id = target_session_id;

  update public.study_sessions
  set quiz_mode = next_mode,
      quiz_status = 'setup',
      quiz_started_at = null,
      quiz_ended_at = null,
      quiz_duration_seconds = resolved_duration,
      updated_at = now()
  where id = target_session_id
  returning * into session_row;

  perform realtime.send(
    jsonb_build_object('entity', 'quiz_configured', 'session_id', session_row.id, 'quiz_mode', session_row.quiz_mode, 'quiz_duration_seconds', session_row.quiz_duration_seconds),
    'session_changed',
    'study-session:' || target_session_id::text,
    true
  );

  return jsonb_build_object('id', session_row.id, 'quiz_mode', session_row.quiz_mode, 'quiz_status', session_row.quiz_status, 'quiz_duration_seconds', session_row.quiz_duration_seconds);
end;
$function$;

create or replace function public.start_study_session_quiz(
  target_session_id uuid,
  duration_seconds integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  me uuid := auth.uid();
  session_row public.study_sessions;
  resolved_duration integer;
  question_count integer;
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

  if not public.is_room_leader(session_row.room_id, me) then
    raise exception 'Only a study leader can start the timed quiz';
  end if;

  question_count := coalesce(jsonb_array_length(coalesce(session_row.guide #> '{quiz,questions}', '[]'::jsonb)), 0);
  if question_count = 0 then
    raise exception 'The study guide has no quiz questions yet';
  end if;

  resolved_duration := coalesce(duration_seconds, session_row.quiz_duration_seconds, 90);
  if resolved_duration < 30 or resolved_duration > 600 then
    raise exception 'Quiz duration must be between 30 seconds and 10 minutes';
  end if;

  delete from public.study_session_quiz_answers where session_id = target_session_id;

  update public.study_sessions
  set phase = 'quiz',
      quiz_mode = 'timed',
      quiz_status = 'running',
      quiz_started_at = now(),
      quiz_ended_at = null,
      quiz_duration_seconds = resolved_duration,
      updated_at = now()
  where id = target_session_id
  returning * into session_row;

  perform realtime.send(
    jsonb_build_object('entity', 'quiz_started', 'session_id', session_row.id, 'quiz_started_at', session_row.quiz_started_at, 'quiz_duration_seconds', session_row.quiz_duration_seconds),
    'session_changed',
    'study-session:' || target_session_id::text,
    true
  );

  return jsonb_build_object('id', session_row.id, 'quiz_status', session_row.quiz_status, 'quiz_started_at', session_row.quiz_started_at, 'quiz_duration_seconds', session_row.quiz_duration_seconds);
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

  if session_row.quiz_started_at is null or now() > session_row.quiz_started_at + (session_row.quiz_duration_seconds || ' seconds')::interval then
    update public.study_sessions
    set quiz_status = 'ended',
        quiz_ended_at = coalesce(quiz_ended_at, now()),
        updated_at = now()
    where id = target_session_id;

    perform realtime.send(
      jsonb_build_object('entity', 'quiz_ended', 'session_id', target_session_id),
      'session_changed',
      'study-session:' || target_session_id::text,
      true
    );

    raise exception 'The quiz timer has ended';
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

create or replace function public.end_study_session_quiz(target_session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  me uuid := auth.uid();
  session_row public.study_sessions;
  question_count integer;
  summary text;
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

  if not public.is_room_leader(session_row.room_id, me) then
    raise exception 'Only a study leader can end the quiz';
  end if;

  question_count := coalesce(jsonb_array_length(coalesce(session_row.guide #> '{quiz,questions}', '[]'::jsonb)), 0);

  update public.study_sessions
  set quiz_status = 'ended',
      quiz_ended_at = now(),
      updated_at = now()
  where id = target_session_id
  returning * into session_row;

  select coalesce(
    'Quiz complete: ' || string_agg(format('%s %s/%s', coalesce(nullif(p.name, ''), 'Friend'), scores.correct_count, greatest(question_count, 1)), ', ' order by scores.correct_count desc, coalesce(p.name, '')),
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
  values (target_session_id, session_row.room_id, me, 'system', left(summary, 2000), null);

  perform realtime.send(
    jsonb_build_object('entity', 'quiz_ended', 'session_id', session_row.id, 'quiz_ended_at', session_row.quiz_ended_at),
    'session_changed',
    'study-session:' || target_session_id::text,
    true
  );

  return jsonb_build_object('id', session_row.id, 'quiz_status', session_row.quiz_status, 'quiz_ended_at', session_row.quiz_ended_at);
end;
$function$;

create or replace function public.advance_study_session_phase(target_session_id uuid, next_phase text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
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

  if not public.is_room_leader(session_row.room_id, me) then
    raise exception 'Only a study leader can guide the session';
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
    jsonb_build_object('entity', 'phase', 'session_id', session_row.id, 'phase', session_row.phase, 'updated_at', session_row.updated_at),
    'session_changed',
    'study-session:' || target_session_id::text,
    true
  );

  return jsonb_build_object('id', session_row.id, 'phase', session_row.phase);
end;
$function$;

create or replace function public.end_study_session(target_session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
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

  if not public.is_room_leader(session_row.room_id, me) then
    raise exception 'Only a study leader can end the session';
  end if;

  update public.study_sessions
  set status = 'ended',
      ended_at = now(),
      updated_at = now()
  where id = target_session_id
  returning * into session_row;

  perform realtime.send(
    jsonb_build_object('entity', 'ended', 'session_id', session_row.id, 'status', session_row.status, 'ended_at', session_row.ended_at),
    'session_changed',
    'study-session:' || target_session_id::text,
    true
  );

  return jsonb_build_object('id', session_row.id, 'status', session_row.status);
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

  if not public.is_room_leader(session_row.room_id, me) then
    raise exception 'Only a study leader can prepare the session guide';
  end if;

  update public.study_sessions
  set guide = case when resolved_status = 'ready' then coalesce(guide_payload, '{}'::jsonb) else '{}'::jsonb end,
      guide_status = resolved_status,
      guide_generated_at = case when resolved_status = 'ready' then now() else guide_generated_at end,
      updated_at = now()
  where id = target_session_id
  returning * into session_row;

  perform realtime.send(
    jsonb_build_object('entity', 'guide', 'session_id', session_row.id, 'guide_status', session_row.guide_status, 'guide_generated_at', session_row.guide_generated_at, 'updated_at', session_row.updated_at),
    'session_changed',
    'study-session:' || target_session_id::text,
    true
  );

  return jsonb_build_object('id', session_row.id, 'guide_status', session_row.guide_status, 'guide_generated_at', session_row.guide_generated_at);
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
      'answered', scores.answered,
      'correct', scores.correct,
      'total', question_count,
      'is_complete', scores.answered >= question_count and question_count > 0
    ) order by scores.correct desc, scores.answered desc, scores.user_name), '[]'::jsonb)
    into quiz_results
    from (
      select m.user_id,
             coalesce(nullif(p.name, ''), 'Friend') as user_name,
             count(a.question_index)::int as answered,
             coalesce(sum(case when a.is_correct then 1 else 0 end), 0)::int as correct
      from public.study_room_members m
      left join public.profiles p on p.id = m.user_id
      left join public.study_session_quiz_answers a on a.session_id = target_session_id and a.user_id = m.user_id
      where m.room_id = session_row.room_id
        and m.status = 'active'
      group by m.user_id, p.name
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

revoke all on function public.study_room_members_snapshot(uuid) from public, anon;
revoke all on function public.set_study_room_member_role(uuid, uuid, text) from public, anon;
revoke all on function public.configure_study_session_quiz(uuid, text, integer) from public, anon;
revoke all on function public.start_study_session_quiz(uuid, integer) from public, anon;
revoke all on function public.submit_study_session_quiz_answer(uuid, integer, integer) from public, anon;
revoke all on function public.end_study_session_quiz(uuid) from public, anon;

grant execute on function public.study_room_members_snapshot(uuid) to authenticated;
grant execute on function public.set_study_room_member_role(uuid, uuid, text) to authenticated;
grant execute on function public.configure_study_session_quiz(uuid, text, integer) to authenticated;
grant execute on function public.start_study_session_quiz(uuid, integer) to authenticated;
grant execute on function public.submit_study_session_quiz_answer(uuid, integer, integer) to authenticated;
grant execute on function public.end_study_session_quiz(uuid) to authenticated;
