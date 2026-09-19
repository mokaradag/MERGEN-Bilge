---
paths:
  - "R/config_characters.R"
  - "R/config_speech_*.R"
  - "R/helpers_ai_expert*.R"
  - "R/helpers_speech*.R"
  - "R/helpers_stt*.R"
  - "R/module_ai_expert.R"
  - "R/module_character_video.R"
  - "R/module_stt.R"
  - "R/module_tts*.R"
  - "R/server_ai_expert_handlers.R"
  - "R/server_music_handlers.R"
  - "R/server_speech*.R"
  - "R/server_tts_handlers.R"
  - "www/**/*speech*.js"
  - "www/**/*audio*.js"
  - "tests/**/*speech*.R"
  - "tests/**/*tts*.R"
  - "tests/**/*stt*.R"
  - "tests/**/*character*.R"
---

# Persona, AI Expert, speech and media

- Persona identity is canonicalized through the configured character helpers;
  do not create parallel persona maps or silently fall back to another voice.
- AI Expert speech lifecycle has one owner. Preserve priority, tokens,
  stale-event rejection, music ducking and visualizer timing.
- Reactive reads inside promise/later callbacks must remain isolated/guarded;
  a top-level reactive-context error can terminate the app.
- Speech-side worker dispatch stays non-blocking; explicit worker globals must
  remain complete.
- Idle talk is lowest priority and must not queue ahead of user-facing work.
- Locked-reference speech mode is fail-closed when its validated voice reference
  is absent. Missing generated assets must not crash unrelated app features.
- Static welcome/page guidance and live synthesis have distinct paths; do not
  reintroduce an LLM call into navigation-time page guidance.
- WAV duration/validation comes from real audio headers, not elapsed time.
- Generated production speech assets are VM-local/gitignored; tests use small
  deterministic fixtures and must not require production WAVs.
- STT chunk acceptance, size/pending limits, ordering and retry semantics must
  not lose or duplicate user speech.
- Current persona/asset inventories are derived from config/manifest files, not
  copied into Claude instructions.
- See `docs/speech-operator-runbook.md` for operator workflow and the archive
  for historical race/voice-lock rationale.
