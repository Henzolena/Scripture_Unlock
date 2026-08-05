-- get_friends_leaderboard trusted its requesting_user_id argument and never
-- compared it to auth.uid(). Being SECURITY DEFINER it also bypasses RLS, so
-- any caller could pass an arbitrary UUID and read that user's friend list,
-- display names, friend codes and streak stats.
--
-- It was also reachable unauthenticated: CREATE FUNCTION grants EXECUTE to
-- PUBLIC by default, and the original migration only added a grant to
-- `authenticated` without revoking PUBLIC.
--
-- The signature is kept so the iOS client needs no change — LeaderboardView
-- already sends session.user.id, which now must equal auth.uid().

create or replace function public.get_friends_leaderboard(requesting_user_id uuid)
returns table (
  user_id        uuid,
  name           text,
  avatar_path    text,
  friend_code    text,
  total_correct  bigint,
  total_sessions bigint
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if requesting_user_id is distinct from auth.uid() then
    raise exception 'You may only request your own leaderboard';
  end if;

  return query
  with friend_ids as (
    select friend_id as fid from friendships where friendships.user_id = requesting_user_id
    union
    select requesting_user_id as fid
  ),
  agg as (
    select
      se.user_id,
      count(distinct se.date) filter (where se.dismissed_at is not null) as total_sessions,
      coalesce(sum(se.questions_correct), 0)                             as total_correct
    from streak_entries se
    where se.user_id in (select fid from friend_ids)
    group by se.user_id
  )
  select
    p.id,
    p.name,
    p.avatar_path,
    p.friend_code,
    coalesce(a.total_correct,  0),
    coalesce(a.total_sessions, 0)
  from profiles p
  left join agg a on a.user_id = p.id
  where p.id in (select fid from friend_ids)
  order by coalesce(a.total_correct, 0) desc;
end;
$$;

revoke execute on function public.get_friends_leaderboard(uuid) from public;
revoke execute on function public.get_friends_leaderboard(uuid) from anon;
grant  execute on function public.get_friends_leaderboard(uuid) to authenticated;
