# Önceden Üretilmiş Konuşma Varlıkları

Bu dizin, MERGEN Bilge karşılama konuşması ve sayfa rehberliği için kullanılan
ortak konuşma metinlerini ve persona bazlı WAV kayıt konumlarını içerir.

## İçerik modeli

- Karşılama konuşması için **10 ortak metin çeşidi** bulunur.
- Desteklenen her sayfa için **10 ortak metin çeşidi** bulunur.
- Aynı konuşma metni `emre`, `selin`, `deniz`, `can` ve `ipek` sesleriyle
  ayrı ayrı kaydedilir.
- Altyazı metni her zaman ortak `.txt` dosyasından okunur. Ses dosyası,
  metin dosyasıyla aynı temel dosya adını kullanmalıdır.

Örnek:

```text
scripts/pages/files/files_03.txt
audio/emre/pages/files/files_03.wav
audio/selin/pages/files/files_03.wav
audio/deniz/pages/files/files_03.wav
audio/can/pages/files/files_03.wav
audio/ipek/pages/files/files_03.wav
```

## Rehberlik bulunan sayfalar

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

## Sessiz kalması gereken sayfalar

Aşağıdaki sayfalar için sayfa rehberliği varlığı eklenmemelidir:

- `chat` — Ana Söyleşi; açılıştaki karşılama konuşması bu sayfayı zaten kapsar.
- `settings_kisisel` — Kişiselleştirme; persona tanıtım videoları burada oynatılır.
- `admin_analytics` — Genel Analiz.
- `admin_geri_bildirim` — Geri Bildirim Analizi.
- `admin_hata_analizi` — Hata Analizi.
- `admin_yanit_analizi` — Yanıt Geri Bildirimi.
- `admin_dokumantasyon` — Dokümantasyon.
- `health` — Sistem Durumu.

## Üretim iş akışı (RStudio / Windows VM)

Tüm üretim `tools/speech/generate_voxcpm2_assets.R` operatör betiğiyle yapılır;
elle kayıt yerleştirilmez. Sıra ve komutlar için tek yetkili belge:
`docs/speech-operator-runbook.md`.

1. `speech_asset_env_check()` ile ortam/uç nokta/metin ağacını doğrulayın.
2. Her persona için `generate_reference_candidate("<persona>")` ile aday
   referansı üretin, DİNLEYİN ve `approve_reference_voice("<persona>")` ile
   kilitleyin (voice-lock.json yazılır).
3. `generate_persona_speech_assets("<persona>")` ile 150 WAV'ı üretin
   (kesinti sonrası aynı komut kaldığı yerden sürer).
4. `validate_speech_assets()` ile sayıları/başlıkları/özetleri denetleyin.
5. `generate_speech_manifest()` ile `generated/speech_manifest.json` dosyasını
   OTOMATİK üretin. Süre ve sağlama toplamı bilgileri gerçek WAV
   başlıklarından türetilir; hiçbir alan elle girilmez.

Beklenen üretim sayıları: 150 ortak metin, persona başına 150 WAV, toplam
750 WAV, 5 referans WAV, 5 voice-lock ve 1 manifest.

## Üretilen dosyalar ve Git politikası

Üretilen dosyalar (referans WAV'lar, voice-lock kilitleri, 750 üretim WAV'ı,
manifest ve üretici durum/kilit/aday dosyaları) VM-YERELDİR ve `.gitignore`
ile GitHub dışında tutulur. Depo güncellemeleri/dağıtım senkronizasyonu bu
dosyaları SİLMEMELİDİR; `www/speech/` altındaki üretilmiş içerik düzenli
yedeklenmelidir. Ortak `.txt` metinleri, `reference.txt` dosyaları, README'ler
ve `.gitkeep` iskeleti commit edilir.

Varlıklar üretilmeden önce uygulama güvenli davranır: açılış kırılmaz, statik
karşılama/rehberlik sessizce atlanır ve kilitli referansı olmayan persona
için canlı konuşma başka bir sese düşmek yerine reddedilir (fail-closed).

Önerilen WAV profili: mono, 16 bit PCM, tutarlı ses düzeyi, en az başlangıç
sessizliği ve kısa, doğal bir bitiş sessizliği.