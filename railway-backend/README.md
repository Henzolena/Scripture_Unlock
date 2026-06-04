# Railway Backend Additions — Verse of the Day Audio

## What's in this folder

| File | Purpose |
|------|---------|
| `votd_audio_router.py` | FastAPI router for VOTD audio generation |

## How to wire it into the existing backend

1. Copy `votd_audio_router.py` into your Railway backend repo.
2. In your main `app.py` / `main.py`, add:
   ```python
   from votd_audio_router import router as votd_router
   app.include_router(votd_router)
   ```

## Required dependencies (add to requirements.txt)
```
google-generativeai>=0.8.0
mistralai>=1.0.0
pydub>=0.25.1
httpx>=0.27.0
```

## Required system package (add to Dockerfile or nixpacks.toml)
```
# Dockerfile
RUN apt-get install -y ffmpeg

# nixpacks.toml
[phases.setup]
aptPkgs = ["ffmpeg"]
```

## Required Railway environment variables
Set these in the Railway dashboard → your service → Variables:

| Variable | Value |
|----------|-------|
| `SUPABASE_URL` | `https://bpqauxqpibaosnbvhito.supabase.co` |
| `SUPABASE_SERVICE_KEY` | Your Supabase `service_role` key (Settings → API) |
| `VOTD_ADMIN_KEY` | Any secret string you choose (protects the generate endpoint) |
| `GEMINI_API_KEY` | Already set ✅ |
| `MISTRAL_API_KEY` | Already set ✅ |

## How to trigger audio generation

### Manual (one-off)
```bash
curl -X POST https://ethiopian-bible-api-production.up.railway.app/api/v1/votd/generate-audio \
  -H "X-Admin-Key: YOUR_VOTD_ADMIN_KEY"
```

### Daily cron (Railway Cron Job)
Create a Railway Cron Job service in the same project:
- Schedule: `0 4 * * *`  (4 AM UTC — before most users wake up)
- Command:
  ```bash
  curl -X POST https://ethiopian-bible-api-production.up.railway.app/api/v1/votd/generate-audio \
    -H "X-Admin-Key: $VOTD_ADMIN_KEY"
  ```

## Check today's verse + audio status (no auth)
```bash
curl https://ethiopian-bible-api-production.up.railway.app/api/v1/votd/today
```

## Architecture summary
```
Railway cron (4 AM UTC)
  └─ POST /api/v1/votd/generate-audio
       ├─ GET /en/votd                    → verse text (from own API)
       ├─ Mistral small                   → 180-word devotional script
       ├─ Gemini 2.5 Flash TTS            → WAV audio bytes
       ├─ pydub                           → MP3 conversion
       ├─ Supabase Storage verse-audio/   → {date}.mp3 uploaded
       └─ Supabase verse_of_the_day       → audio_url + status = "ready"

iOS app (user opens HomeView)
  ├─ EthiopianBibleService.verseOfTheDay() → verse text from Railway
  ├─ VerseOfDayService.fetchSupabaseRow()  → audio_url from Supabase
  └─ VersOfDayAudioPlayer.load(url:)       → streams MP3 on play tap
```
