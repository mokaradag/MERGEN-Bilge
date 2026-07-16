# Sabit Persona Referans Sesleri

Her persona klasörü üç dosya kullanır:

```text
reference.txt
reference.wav
voice-lock.json
```

- `reference.txt` depoda tutulur ve merkezi persona ses profiliyle birebir eşleşir.
- `reference.wav`, `scripts/generate_persona_speech_wavs.R` ilk kez çalıştırıldığında oluşturulur.
- `voice-lock.json`, referans WAV, metin ve profil ayarlarının SHA-256 değerlerini kilitler.

Önceden üretilmiş konuşmalar ve çalışma zamanı/stream TTS aynı kilitli referans
çiftini kullanır. `reference.wav` veya kilit değişirse çalışma zamanı farklı bir
genel sese düşmez.

Referans WAV dosyalarını üretim VM'sinde kalıcı olarak saklayın ve yedekleyin.
