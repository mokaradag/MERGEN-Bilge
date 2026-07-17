# Sabit Persona Referans Sesleri

Her persona klasörü üç dosya kullanır:

```text
reference.txt
reference.wav
voice-lock.json
```

- `reference.txt` depoda tutulur; `reference.wav` içinde AYNEN okunan metindir
  ve merkezi persona ses profiliyle birebir eşleşir.
- `reference.wav` üretim VM'sinde iki aşamalı operatör akışıyla oluşturulur:
  önce `generate_reference_candidate("<persona>")` ile ADAY üretilir ve
  DİNLENİR; uygun bulununca `approve_reference_voice("<persona>")` ile
  onaylanıp buraya atomik olarak kurulur. Komutlar
  `tools/speech/generate_voxcpm2_assets.R` betiğiyle yüklenir.
- `voice-lock.json` onay anında yazılır ve referans WAV, referans metni,
  persona ses profili (model/hız/kimlik parametreleri) ve beklenen ses
  özelliklerinin SHA-256 değerlerini kilitler.

Önceden üretilmiş konuşmalar ve çalışma zamanı/stream TTS aynı kilitli referans
çiftini kullanır. `reference.wav` veya kilit eksikse ya da özetler uyuşmuyorsa
çalışma zamanı FARKLI BİR SESE DÜŞMEZ; o persona için konuşma isteği reddedilir
(fail-closed). Onaylı bir referans sessizce değiştirilemez; bilinçli değişim
`approve_reference_voice("<persona>", reset_reference = TRUE)` gerektirir ve o
personanın üretilmiş TÜM WAV'larını geçersiz kılar.

`reference.wav` ve `voice-lock.json` GitHub'a COMMIT EDİLMEZ (bkz. kök
`.gitignore`); üretim VM'sinde kalıcıdır. Depo güncellemeleri bu dosyaları
silmemelidir; düzenli olarak yedekleyin. Ayrıntılı akış:
`docs/speech-operator-runbook.md`.
