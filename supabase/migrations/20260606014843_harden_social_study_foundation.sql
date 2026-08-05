create or replace function public.generate_short_code(prefix text default 'SU')
returns text
language sql
volatile
set search_path = public, extensions
as $$
  select prefix || '-' || upper(substr(replace(extensions.gen_random_uuid()::text, '-', ''), 1, 6));
$$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

revoke execute on function public.can_access_realtime_topic(text) from public, anon;
revoke execute on function public.community_dashboard() from public, anon;
revoke execute on function public.create_study_room(text, text, text, text) from public, anon;
revoke execute on function public.create_study_session(uuid, text, text, text, integer, integer, integer, text) from public, anon;
revoke execute on function public.invite_friend_to_room(uuid, uuid) from public, anon;
revoke execute on function public.is_room_manager(uuid, uuid) from public, anon;
revoke execute on function public.is_room_member(uuid, uuid) from public, anon;
revoke execute on function public.is_room_visible(uuid, uuid) from public, anon;
revoke execute on function public.is_session_member(uuid, uuid) from public, anon;
revoke execute on function public.join_study_room_by_code(text) from public, anon;
revoke execute on function public.respond_friend_request(uuid, boolean) from public, anon;
revoke execute on function public.send_friend_request_by_code(text, text) from public, anon;
revoke execute on function public.generate_short_code(text) from public, anon;
revoke execute on function public.set_updated_at() from public, anon;
revoke execute on function public.handle_new_user() from public, anon;

grant execute on function public.community_dashboard() to authenticated;
grant execute on function public.create_study_room(text, text, text, text) to authenticated;
grant execute on function public.create_study_session(uuid, text, text, text, integer, integer, integer, text) to authenticated;
grant execute on function public.invite_friend_to_room(uuid, uuid) to authenticated;
grant execute on function public.join_study_room_by_code(text) to authenticated;
grant execute on function public.respond_friend_request(uuid, boolean) to authenticated;
grant execute on function public.send_friend_request_by_code(text, text) to authenticated;
grant execute on function public.can_access_realtime_topic(text) to authenticated;
grant execute on function public.is_room_manager(uuid, uuid) to authenticated;
grant execute on function public.is_room_member(uuid, uuid) to authenticated;
grant execute on function public.is_room_visible(uuid, uuid) to authenticated;
grant execute on function public.is_session_member(uuid, uuid) to authenticated;

create index if not exists study_room_members_invited_by_idx on public.study_room_members (invited_by);
create index if not exists study_session_messages_room_idx on public.study_session_messages (room_id);
create index if not exists study_session_messages_user_idx on public.study_session_messages (user_id);
create index if not exists study_session_notes_room_idx on public.study_session_notes (room_id);
create index if not exists study_session_notes_user_idx on public.study_session_notes (user_id);
create index if not exists study_session_reactions_room_idx on public.study_session_reactions (room_id);
create index if not exists study_session_reactions_user_idx on public.study_session_reactions (user_id);
create index if not exists study_sessions_host_idx on public.study_sessions (host_id);
