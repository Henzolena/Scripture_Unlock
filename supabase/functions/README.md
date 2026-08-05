# Edge Functions

| Function | Purpose | Secrets used |
|---|---|---|
| `send-push` | Signs an APNs ES256 JWT and delivers a push to a user's `device_tokens` rows. Called by the app at `/functions/v1/send-push`. | `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_BUNDLE_ID`, `APNS_PRODUCTION` |
| `accountability-email` | Emails an accountability partner a streak/accuracy summary via Resend. | `RESEND_API_KEY`, `RESEND_FROM_EMAIL` |

Both were recovered from the deployed ESZIP bundles (version 7) — they had
never been committed. Secrets are set in the Supabase dashboard, not here.

`APNS_PRODUCTION` is compared against the string `'true'`. It must match the
app's `aps-environment` entitlement, or delivery fails silently.

Deploy: `supabase functions deploy <slug> --project-ref bpqauxqpibaosnbvhito`
