# Persona WAV Recordings

The audio tree mirrors the shared script tree for each persona.

Place PCM WAV files in the matching directory and preserve the script basename.
For example:

```text
scripts/pages/history/history_04.txt
audio/emre/pages/history/history_04.wav
audio/selin/pages/history/history_04.wav
```

The `.gitkeep` files only preserve empty recording directories and may remain
after WAV files are added. Subtitle text comes from `../scripts`; do not add
duplicate `.txt` files under `audio`.
