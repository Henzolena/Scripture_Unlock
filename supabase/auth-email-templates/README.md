# Supabase Auth Email Templates

These templates match the Scripture Unlock app palette:

- Midnight: `#0F172A`
- Surface: `#1F2937`
- Pastoral gold: `#C9A961`
- Pale gold: `#E5C684`
- Sky blue: `#93C5FD`

## Hosted Supabase Setup

Open the Scripture Unlock project in Supabase:

https://supabase.com/dashboard/project/bpqauxqpibaosnbvhito/auth/templates

Update both authentication templates:

1. **Confirm signup**
   - Subject: `{{ .Token }} is your Scripture Unlock verification code`
   - Body: copy `confirm-signup.html`

2. **Magic Link / OTP**
   - Subject: `{{ .Token }} is your Scripture Unlock sign-in code`
   - Body: copy `magic-link-otp.html`

Both templates intentionally use `{{ .Token }}` instead of `{{ .ConfirmationURL }}` so Supabase sends a verification code rather than a confirmation link.
