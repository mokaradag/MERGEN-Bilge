# Pre-generated Speech Assets

This directory contains the shared scripts and persona-specific WAV locations for
MERGEN Bilge welcome speech and page guidance.

## Content model

- There are **10 shared script variants** for the welcome speech.
- There are **10 shared script variants** for each supported page.
- The exact same script text is recorded separately in the voices of `emre`,
  `selin`, `deniz`, `can`, and `ipek`.
- Subtitle text is always read from the shared `.txt` file. The audio file must
  use the same basename.

Example:

```text
scripts/pages/files/files_03.txt
audio/emre/pages/files/files_03.wav
audio/selin/pages/files/files_03.wav
audio/deniz/pages/files/files_03.wav
audio/can/pages/files/files_03.wav
audio/ipek/pages/files/files_03.wav
```

## Pages with guidance

- `history` — Söyleşi Geçmişi
- `saved_chats` — Kayıtlı Söyleşiler
- `ortak_sohbetler` — Ortak Söyleşiler
- `image_gallery` — Görsel Galerisi
- `claude_code` — Çalışma Alanı
- `claude_code_sessions` — Oturumlar
- `ortak_bilge_yolac` — Ortak Bilge Yolaç Oturumları
- `ortak_calismalar` — Ortak Çalışmalarım
- `files` — Dosya Yönetimi
- `settings_yapilandirma` — Yapılandırma
- `destek_yardim` — Yardım Merkezi
- `destek_geri_bildirim` — Geri Bildirim & Hata
- `destek_surum` — Yenilikler
- `destek_hakkinda` — Hakkında

## Pages that must remain silent

No page-guidance assets should be added for:

- `chat` — Ana Söyleşi; the startup welcome speech already covers it.
- `settings_kisisel` — Kişiselleştirme; persona introduction videos play there.
- `admin_analytics` — Genel Analiz.
- `admin_geri_bildirim` — Geri Bildirim Analizi.
- `admin_hata_analizi` — Hata Analizi.
- `admin_yanit_analizi` — Yanıt Geri Bildirimi.
- `admin_dokumantasyon` — Dokümantasyon.
- `health` — Sistem Durumu.

## Recording workflow

1. Select a shared `.txt` script.
2. Record the exact text in each persona voice.
3. Save every recording as PCM WAV with the same basename as the script.
4. Do not copy or rewrite subtitle text inside persona folders.
5. The playback-integration step must generate `generated/speech_manifest.json`
   automatically after WAV files are added. Duration and checksums must be
   derived from the WAV files; they are never entered manually.

This asset-only scaffold does not yet add the manifest generator or runtime
playback wiring.

Recommended WAV profile: mono, 16-bit PCM, consistent loudness, minimal leading
silence, and a short natural trailing silence.
