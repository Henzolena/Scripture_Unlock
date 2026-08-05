revoke all on function public.save_study_session_guide(uuid, jsonb, text) from public;
revoke all on function public.save_study_session_guide(uuid, jsonb, text) from anon;
grant execute on function public.save_study_session_guide(uuid, jsonb, text) to authenticated;

revoke all on function public.add_study_session_reaction(uuid, text, text, uuid) from public;
revoke all on function public.add_study_session_reaction(uuid, text, text, uuid) from anon;
grant execute on function public.add_study_session_reaction(uuid, text, text, uuid) to authenticated;

revoke all on function public.study_session_snapshot(uuid) from public;
revoke all on function public.study_session_snapshot(uuid) from anon;
grant execute on function public.study_session_snapshot(uuid) to authenticated;
