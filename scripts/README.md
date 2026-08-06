# Secrets workflow

`Secrets.xcconfig` holds the three keys the app actually reads at runtime
(`SUPABASE_HOST`, `SUPABASE_ANON_KEY`, `GEMINI_API_KEY` — mapped into the bundle
by `Scripture-Unlock-Info.plist`). It is gitignored, which means it is also
unbacked-up: a wiped machine loses it.

These scripts make it **derived** rather than stored, with Bitwarden as the source
of truth.

## One-time setup

Bitwarden's free tier has no equivalent of `op inject`, so this is a small script
rather than native tooling. The tradeoff is worth it: the file stops being
something you have to keep.

```bash
# 1. Create a free account at bitwarden.com, then:
bw login

# 2. Unlock and seed the vault from the file you already have
export BW_SESSION=$(bw unlock --raw)
./scripts/bw-seed-secrets.sh
```

`bw-seed-secrets.sh` refuses to run if the vault item already exists, so it
cannot silently clobber good values.

## Day to day

```bash
export BW_SESSION=$(bw unlock --raw)
./scripts/gen-secrets.sh
```

That rewrites `Secrets.xcconfig` at mode `600`. Once you have verified a
round-trip, the local file is disposable — regenerate it on any machine after
`bw login`.

## Why the scripts are fussy about `//`

xcconfig treats `//` as the start of a comment, so a value of
`https://project.supabase.co` silently truncates to `https:`. That is why the app
stores a bare host and rebuilds the scheme itself. `gen-secrets.sh` hard-fails if
any value contains `//`, rather than writing a config that builds but breaks at
runtime.

## What is *not* covered here

| Secret | Where it lives |
|---|---|
| Apple signing certificate + profile | fastlane match → `Henzolena/ios-certificates` (encrypted) |
| App Store Connect API key | `~/.appstoreconnect/` + the encrypted vault DMG |
| APNs key, Resend key | Supabase Edge Function secrets — **write-only**, cannot be read back |
| Railway variables | Railway; capture with `railway variables --kv` |

The encrypted `ScriptureUnlock-Secrets.dmg` in iCloud Drive is the disaster-recovery
copy of the items that cannot be re-issued.
