"""
Verse of the Day — Audio Generation Router
===========================================

Generates a ~60-second Gemini TTS devotional for today's verse.

Flow
----
  1.  Fetch today's verse from this service's own /votd endpoint.
  2.  Mistral writes a 180-200 word biblical devotional script.
  3.  Gemini TTS (gemini-2.5-flash-preview-tts) converts the script to WAV audio.
  4.  WAV → MP3 via pydub (requires ffmpeg installed in Railway container).
  5.  MP3 uploaded to Supabase Storage bucket "verse-audio".
  6.  Supabase verse_of_the_day row updated with audio_url + status = "ready".

Required Railway env vars (add via Railway dashboard)
------------------------------------------------------
  SUPABASE_URL          https://bpqauxqpibaosnbvhito.supabase.co
  SUPABASE_SERVICE_KEY  <your service_role key>
  VOTD_ADMIN_KEY        <a secret string you choose — used to protect the endpoint>
  GEMINI_API_KEY        already set
  MISTRAL_API_KEY       already set

Wire-up (in your main FastAPI app)
-----------------------------------
  from votd_audio_router import router as votd_router
  app.include_router(votd_router)

Dependencies to add to requirements.txt
-----------------------------------------
  google-generativeai>=0.8.0
  mistralai>=1.0.0
  pydub>=0.25.1
  httpx>=0.27.0
  # ffmpeg must also be installed: add to your Dockerfile / nixpacks config
  #   apt-get install -y ffmpeg
"""

from __future__ import annotations

import base64
import io
import os
from datetime import date

import httpx
from fastapi import APIRouter, Depends, Header, HTTPException

# ── optional heavy deps — fail clearly at call time, not import time ──────────
def _import_mistral():
    try:
        from mistralai import Mistral  # type: ignore
        return Mistral
    except ImportError as exc:
        raise RuntimeError("mistralai not installed — add it to requirements.txt") from exc

def _import_genai():
    try:
        import google.generativeai as genai  # type: ignore
        return genai
    except ImportError as exc:
        raise RuntimeError("google-generativeai not installed — add it to requirements.txt") from exc

def _import_pydub():
    try:
        from pydub import AudioSegment  # type: ignore
        return AudioSegment
    except ImportError as exc:
        raise RuntimeError("pydub not installed — add it to requirements.txt") from exc


# ── Config ────────────────────────────────────────────────────────────────────

GEMINI_API_KEY       = os.getenv("GEMINI_API_KEY", "")
MISTRAL_API_KEY      = os.getenv("MISTRAL_API_KEY", "")
SUPABASE_URL         = os.getenv("SUPABASE_URL", "")           # e.g. https://xxx.supabase.co
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY", "")   # service_role key (write access)
VOTD_ADMIN_KEY       = os.getenv("VOTD_ADMIN_KEY", "change-me-in-railway")
AUDIO_BUCKET         = "verse-audio"

router = APIRouter(prefix="/api/v1/votd", tags=["verse-of-the-day"])


# ── Auth dependency ───────────────────────────────────────────────────────────

def _require_admin(x_admin_key: str = Header(..., alias="X-Admin-Key")):
    if x_admin_key != VOTD_ADMIN_KEY:
        raise HTTPException(status_code=403, detail="Invalid admin key")


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.post("/generate-audio", dependencies=[Depends(_require_admin)])
async def generate_votd_audio():
    """
    Generates and stores devotional audio for today's verse.
    Idempotent — returns immediately if audio is already ready.
    Call this once per day (e.g. from a Railway cron job or Supabase webhook).
    """
    today_str = date.today().isoformat()

    async with httpx.AsyncClient(timeout=120) as http:

        # 1. Already done? Return early.
        existing = await _get_supabase_row(http, today_str)
        if existing and existing.get("audio_status") == "ready":
            return {"status": "already_exists", "audio_url": existing["audio_url"], "date": today_str}

        # 2. Fetch verse text.
        verse = await _fetch_votd(http)
        if not verse:
            raise HTTPException(status_code=503, detail="Could not fetch verse of the day from /en/votd")

        ref  = f"{verse['book_name']} {verse['chapter']}:{verse['verse']}"
        text = verse["text"]

        # 3. Mark as generating so concurrent calls bail early.
        await _upsert_row(http, today_str, ref, verse["book"],
                          verse["chapter"], verse["verse"], text, "KJV", "generating")

        try:
            # 4. Mistral writes the devotional script.
            script = _generate_script(ref, text)

            # 5. Gemini TTS converts script → WAV bytes.
            wav_bytes = _generate_audio_bytes(script)

            # 6. WAV → MP3.
            mp3_bytes = _wav_to_mp3(wav_bytes)

            # 7. Upload to Supabase Storage.
            audio_url = await _upload_audio(http, today_str, mp3_bytes)

            # 8. Persist URL + mark ready.
            await _update_row(http, today_str, audio_url, "ready")

            return {"status": "ok", "audio_url": audio_url, "date": today_str, "script_preview": script[:120] + "…"}

        except Exception as exc:
            await _update_row(http, today_str, None, "failed")
            raise HTTPException(status_code=500, detail=str(exc)) from exc


@router.get("/today")
async def get_today():
    """Returns today's verse + audio metadata (no auth required)."""
    today_str = date.today().isoformat()
    async with httpx.AsyncClient(timeout=15) as http:
        verse = await _fetch_votd(http)
        row   = await _get_supabase_row(http, today_str)
    return {
        "verse":        verse,
        "audio_url":    row.get("audio_url")    if row else None,
        "audio_status": row.get("audio_status") if row else "pending",
        "date":         today_str,
    }


# ── Generation helpers ────────────────────────────────────────────────────────

def _generate_script(ref: str, text: str) -> str:
    """Uses Mistral to write a 180-200 word spoken devotional."""
    Mistral = _import_mistral()
    client  = Mistral(api_key=MISTRAL_API_KEY)

    prompt = (
        "You are a warm, reverent biblical devotional speaker.\n"
        f"Write a 180-to-200-word spoken devotional about this verse:\n\n"
        f"{ref}: \"{text}\"\n\n"
        "Structure (spoken delivery — no headers, no markdown):\n"
        "1. Read the verse naturally.\n"
        "2. Briefly explain its historical or biblical context (2–3 sentences).\n"
        "3. Share a practical, encouraging application for today (3–4 sentences).\n"
        "4. Close with a short prayer or blessing (1–2 sentences).\n\n"
        "Write ONLY the spoken text. No stage directions."
    )

    resp = client.chat.complete(
        model="mistral-small-latest",
        messages=[{"role": "user", "content": prompt}],
        max_tokens=350,
        temperature=0.7,
    )
    return resp.choices[0].message.content.strip()


def _generate_audio_bytes(script: str) -> bytes:
    """
    Calls Gemini 2.5 Flash TTS to convert the script to WAV audio.
    Returns raw WAV bytes.
    """
    genai = _import_genai()
    genai.configure(api_key=GEMINI_API_KEY)

    from google.generativeai.types import (  # type: ignore
        GenerateContentConfig,
        SpeechConfig,
        VoiceConfig,
        PrebuiltVoiceConfig,
    )

    client = genai.Client(api_key=GEMINI_API_KEY)
    response = client.models.generate_content(
        model="gemini-2.5-flash-preview-tts",
        contents=script,
        config=GenerateContentConfig(
            response_modalities=["AUDIO"],
            speech_config=SpeechConfig(
                voice_config=VoiceConfig(
                    prebuilt_voice_config=PrebuiltVoiceConfig(
                        voice_name="Kore"   # warm, clear, reverent tone
                    )
                )
            ),
        ),
    )
    b64 = response.candidates[0].content.parts[0].inline_data.data
    return base64.b64decode(b64)


def _wav_to_mp3(wav_bytes: bytes) -> bytes:
    """Converts WAV bytes → MP3 bytes at 128 kbps. Requires ffmpeg."""
    AudioSegment = _import_pydub()
    seg = AudioSegment.from_wav(io.BytesIO(wav_bytes))
    buf = io.BytesIO()
    seg.export(buf, format="mp3", bitrate="128k")
    return buf.getvalue()


# ── Supabase helpers ──────────────────────────────────────────────────────────

_SB_HEADERS = lambda: {
    "apikey":        SUPABASE_SERVICE_KEY,
    "Authorization": f"Bearer {SUPABASE_SERVICE_KEY}",
    "Content-Type":  "application/json",
}


async def _fetch_votd(http: httpx.AsyncClient) -> dict | None:
    """Fetches today's verse from this service's own /api/v1/en/votd."""
    try:
        r = await http.get("http://localhost:8000/api/v1/en/votd", timeout=10)
        return r.json() if r.status_code == 200 else None
    except Exception:
        return None


async def _get_supabase_row(http: httpx.AsyncClient, date_str: str) -> dict | None:
    r = await http.get(
        f"{SUPABASE_URL}/rest/v1/verse_of_the_day",
        params={"date": f"eq.{date_str}", "select": "audio_url,audio_status"},
        headers=_SB_HEADERS(),
    )
    rows = r.json() if r.status_code == 200 else []
    return rows[0] if rows else None


async def _upsert_row(http, date_str, ref, book, chapter, verse, text, translation, status):
    await http.post(
        f"{SUPABASE_URL}/rest/v1/verse_of_the_day",
        json={
            "date": date_str, "verse_ref": ref, "book": book,
            "chapter": chapter, "verse": verse, "verse_text": text,
            "translation": translation, "audio_status": status,
        },
        headers={**_SB_HEADERS(), "Prefer": "resolution=merge-duplicates"},
    )


async def _upload_audio(http: httpx.AsyncClient, date_str: str, mp3_bytes: bytes) -> str:
    path = f"{date_str}.mp3"
    await http.post(
        f"{SUPABASE_URL}/storage/v1/object/{AUDIO_BUCKET}/{path}",
        content=mp3_bytes,
        headers={
            "Authorization": f"Bearer {SUPABASE_SERVICE_KEY}",
            "Content-Type":  "audio/mpeg",
            "x-upsert":      "true",
        },
    )
    return f"{SUPABASE_URL}/storage/v1/object/public/{AUDIO_BUCKET}/{path}"


async def _update_row(http: httpx.AsyncClient, date_str: str, audio_url: str | None, status: str):
    payload: dict = {"audio_status": status}
    if audio_url:
        payload["audio_url"] = audio_url
    await http.patch(
        f"{SUPABASE_URL}/rest/v1/verse_of_the_day",
        json=payload,
        params={"date": f"eq.{date_str}"},
        headers=_SB_HEADERS(),
    )
