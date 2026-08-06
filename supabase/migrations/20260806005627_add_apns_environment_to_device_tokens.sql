-- A single APNS_PRODUCTION flag cannot route pushes correctly, because APNs
-- device tokens are environment-specific: a debug build registers with the
-- sandbox gateway, a TestFlight or App Store build with production. Both kinds
-- coexist in this table (the developer runs Xcode builds while testers use
-- TestFlight), so one global flag always breaks whichever half it does not
-- match — silently, since APNs just answers BadDeviceToken.
--
-- Record the environment per token and let send-push pick the gateway per row.
--
-- Default 'production': tokens already stored came from TestFlight installs
-- (three testers, all INSTALLED), so production is the correct assumption for
-- existing rows. The client now sends the value explicitly.

alter table public.device_tokens
  add column if not exists environment text not null default 'production';

alter table public.device_tokens
  drop constraint if exists device_tokens_environment_check;

alter table public.device_tokens
  add constraint device_tokens_environment_check
  check (environment in ('sandbox', 'production'));

-- The same physical device yields different tokens per environment, so
-- uniqueness must include it.
create unique index if not exists device_tokens_user_token_env_idx
  on public.device_tokens (user_id, token, environment);

comment on column public.device_tokens.environment is
  'APNs gateway this token is valid for: sandbox (debug builds) or production (TestFlight/App Store).';
