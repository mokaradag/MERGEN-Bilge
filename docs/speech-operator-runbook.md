# Hibrit VoxCPM2 Konuşma Varlıkları - Windows VM Operatör Rehberi

Bu rehber, üretim Windows VM'sinde **hiç üretilmemiş** bir `www/speech/`
ağacından başlayarak tüm konuşma varlıklarının (5 referans sesi, 5 kilit,
750 WAV, 1 manifest) güvenle üretilmesini adım adım anlatır. Komutlar
RStudio'dan çalıştırılır; Shiny uygulamasının açık olması gerekmez.

## 1. Mimari özet

- **Ortak metinler** (`www/speech/scripts/`, 150 adet `.txt`) depoda commit
  edilidir: 10 karşılama + 14 rehberli sayfa x 10 çeşit. Metinler beş persona
  tarafından ortak kullanılır; persona yalnızca SES kaydını değiştirir.
- **Rehberli 14 sayfa**: `history`, `saved_chats`, `ortak_sohbetler`,
  `image_gallery`, `claude_code`, `claude_code_sessions`, `ortak_bilge_yolac`,
  `ortak_calismalar`, `files`, `settings_yapilandirma`, `destek_yardim`,
  `destek_geri_bildirim`, `destek_surum`, `destek_hakkinda`.
- **Sessiz sayfalar** (rehberlik klibi OYNATILMAZ): `chat` (Ana Söyleşi;
  karşılama dizisi kapsar), `settings_kisisel` (persona tanıtım videoları),
  tüm Yönetici Paneli sayfaları ve `health`.
- **Sabit persona sesleri**: her persona tek, kalıcı ve tanınabilir bir
  konuşmacıya kilitlenir (`voices/<persona>/reference.wav` +
  `voice-lock.json`). Üç erkek persona (emre, deniz, can) ÜÇ AYRI konuşmacı,
  iki kadın persona (selin, ipek) İKİ AYRI konuşmacı olmalıdır. Toplu üretim
  ve canlı akış TTS aynı kilitli referansı kullanır.
- **Fail-closed**: kilitli referansı olmayan/bozulan persona için konuşma
  reddedilir; hiçbir zaman genel bir sese veya başka personaya düşülmez.

## 2. Ön koşullar

1. Depo VM'de güncel (`git pull`) ve `.Renviron` depo kökünde tanımlı.
2. `.Renviron` içinde en az şunlar dolu:
   - `LOCAL_TTS_ENDPOINT` (VoxCPM2 servis URL'si)
   - `LOCAL_TTS_API_KEY` (veya `LOCAL_LLM_API_KEY`)
   - `LOCAL_TTS_MODEL=voxcpm2` (servisteki gerçek model kimliği)
   - `VOXCPM2_EXPECTED_SAMPLE_RATE` (modelin doğal hızı; varsayılan 16000)
   - Gerekiyorsa `VOXCPM2_REF_AUDIO_FIELD` / `VOXCPM2_REF_TEXT_FIELD`
     (uç noktanın referans klonlama alan adları; bkz. Bölüm 8)
3. R paketleri: `httr`, `jsonlite`, `openssl`, `base64enc`, `curl`
   (uygulamanın normal kurulumu bunları zaten içerir).

## 3. Sıfırdan tam üretim (kesin komut sırası)

RStudio'da:

```r
setwd("C:/path/to/MERGEN-Bilge")   # depo kökü

source("tools/speech/generate_voxcpm2_assets.R", encoding = "UTF-8")

# 0) Ortam ve 150 metnin ön kontrolü (hiçbir şey üretmez)
speech_asset_env_check()

# 1) EMRE - aday referans üret, DİNLE, onayla, 150 WAV üret
generate_reference_candidate("emre")
#   -> www/speech/generated/candidates/emre_reference_candidate.wav
#   Dosyayı çift tıklayıp DİNLEYİN. Ses uygun değilse bu komutu yeniden
#   çalıştırın (gerekirse .Renviron'da VOXCPM2_DESIGN_VOICE_EMRE değişkenine
#   DOĞAL DİL ses tasarımı tanımı yazın; bu bir kayıtlı ses adı veya sayısal
#   tohum DEĞİLDİR, tanım input metninin başına eklenir).
approve_reference_voice("emre")
generate_persona_speech_assets("emre")

# 2-5) Diğer personalar için aynı üçlü
generate_reference_candidate("selin")
approve_reference_voice("selin")
generate_persona_speech_assets("selin")

generate_reference_candidate("deniz")
approve_reference_voice("deniz")
generate_persona_speech_assets("deniz")

generate_reference_candidate("can")
approve_reference_voice("can")
generate_persona_speech_assets("can")

generate_reference_candidate("ipek")
approve_reference_voice("ipek")
generate_persona_speech_assets("ipek")

# 6) Bütünsel doğrulama ve manifest
validate_speech_assets()
generate_speech_manifest()
```

Ardından Shiny uygulamasını yeniden başlatın; manifest açılışta yüklenir.

Notlar:

- **Kesinti/devam**: `generate_persona_speech_assets()` kesilirse aynı komutu
  yeniden çalıştırın; geçerli mevcut dosyalar (WAV + metin/kilit/profil özeti
  doğrulanarak) atlanır, kalanlar üretilir.
- **Küçük deneme**: tam koşudan önce
  `generate_persona_speech_assets("emre", max_files = 3)` ile 3 dosyalık
  deneme yapabilir, `preview = TRUE` ile plan görebilirsiniz.
- **Toplu koşu**: referansları onayladıktan sonra
  `generate_all_persona_speech_assets()` kalan tüm personaları sırayla üretir
  (onaysız persona atlanır ve raporlanır; onay ATLANMAZ).
- **Eşzamanlılık**: üretici `generated/generator.lock` ile korunur; ikinci bir
  RStudio oturumu aynı ağaca yazamaz. Bayat kilit için
  `speech_gen_release_lock()`.
- **Yeniden deneme**: zaman aşımı/429/5xx sınırlı üstel geri çekilmeyle
  otomatik denenir; 4xx doğrulama/kimlik hataları denenmez.

## 4. Referans sesi değiştirme (bilinçli reset)

Onaylı bir referans sessizce değiştirilemez. Yeni ses istiyorsanız:

```r
generate_reference_candidate("emre")          # yeni aday; DİNLEYİN
approve_reference_voice("emre", reset_reference = TRUE)
generate_persona_speech_assets("emre")        # 150 WAV yeniden üretilir
validate_speech_assets()
generate_speech_manifest()
```

`reset_reference = TRUE` o personanın üretilmiş TÜM WAV kayıtlarını geçersiz
kılar; komut bu sonucu açıkça bildirir.

## 5. Üretilecek dosyalar ve beklenen sayılar

| İçerik | Konum | Adet |
| --- | --- | --- |
| Onaylı referans WAV | `www/speech/voices/<persona>/reference.wav` | 5 |
| Ses kilidi | `www/speech/voices/<persona>/voice-lock.json` | 5 |
| Karşılama WAV | `www/speech/audio/<persona>/welcome/` | 5 x 10 = 50 |
| Sayfa rehberliği WAV | `www/speech/audio/<persona>/pages/<sayfa>/` | 5 x 140 = 700 |
| Manifest | `www/speech/generated/speech_manifest.json` | 1 |
| Üretici durumu | `www/speech/generated/generation_state_<persona>.json` | 5 |

WAV profili: PCM, mono, 16 bit, `VOXCPM2_EXPECTED_SAMPLE_RATE` hızında.
Doğrulayıcı gerçek RIFF/WAVE başlığını okur; süreler başlıktan hesaplanır.

## 6. Git ve yedekleme politikası

- Üretilen dosyalar `.gitignore` ile GitHub DIŞINDA tutulur; VM-yereldir.
- `git pull` / dağıtım senkronizasyonu bu dosyaları SİLMEZ; yine de
  `www/speech/voices/` ve `www/speech/audio/` ağacını düzenli olarak güvenli
  bir paylaşıma yedekleyin (özellikle referans WAV + voice-lock çiftlerini:
  bunlar persona ses kimliğinin kendisidir).
- Geri yükleme: yedeği aynı yollara kopyalayın, ardından
  `validate_speech_assets()` + `generate_speech_manifest()` çalıştırın.

## 7. Varlıklar üretilmeden önce çalışma zamanı davranışı

- Uygulama açılışı KIRILMAZ; manifest yoksa statik konuşma "kullanılamaz"
  sayılır ve `[SPEECH]` teşhis logu yazılır.
- Karşılama/sayfa rehberliği konuşmasız atlanır; altyazı/görselleştirici
  yanlış tetiklenmez; konuşma dışı tüm özellikler normal çalışır.
- Kilitli referansı olmayan persona için canlı TTS (boşta konuşma, Yanıtları
  Seslendir, kişisel önek) reddedilir; BAŞKA SESLE KONUŞULMAZ. Log'da
  `fail-closed` nedeni görünür.
- Geçici operatör kaçışı (önerilmez): `MERGEN_SPEECH_VOICE_MODE=legacy_alias`
  eski `tr-male-1`/`tr-female-1` davranışına bilinçli döner.

## 8. VoxCPM2 uç nokta sözleşmesi doğrulaması (ilk kurulum)

Aday referans üretimi (1. aşama) referanssız bir **Voice Design** isteğidir ve
VM'de `tests/scripts/test_voxcpm2_persona_voices.R` ile doğrulanmış sözleşmeyi
kullanır: istek her zaman `voice = "default"` ile gider (bu kurulumda
`tr-male-1` / `tr-female-1` gibi kayıtlı ses adları YOKTUR; kayıtlı olmayan bir
ad gönderilirse servis HTTP 503 "No Healthy Address Found" döndürür) ve doğal
dil ses tasarımı tanımı `input` metninin başına parantez içinde eklenir.
`LOCAL_TTS_VOICE` yalnızca eski `legacy_alias` çalışma zamanı modunu
ilgilendirir; aday isteğine asla karışmaz.

Üretim aşaması (150 WAV) ise klonlama isteğidir: adaptör OpenAI uyumlu
`/audio/speech` gövdesine referans klonlama alanları
ekler; varsayılan alan adları `ref_audio` (base64 WAV) ve `ref_text`
(birebir transkript). Kurulu servisin gerçek alan adları farklıysa
`.Renviron` içinde eşleyin:

```ini
VOXCPM2_REF_AUDIO_FIELD=prompt_audio
VOXCPM2_REF_TEXT_FIELD=prompt_text
```

İlk üretimden önce tek dosyalık deneme (`max_files = 1`) yapıp üretilen WAV'ı
dinleyerek klonlamanın gerçekten uygulandığını doğrulayın (iki farklı persona
klibi FARKLI seslerde olmalı).

## 9. Akış modu (chunked_pcm) - isteğe bağlı

`VOXCPM2_STREAMING_MODE=buffered` varsayılandır ve her uç noktayla çalışır
("tamponlu": tam yanıt gelir, sonra çalınır; cümle parçalamayla gecikme
düşürülür — bu GERÇEK akış değildir ve öyle etiketlenmez). Uç nokta ham PCM'i
parça parça gönderebiliyorsa (`response_format = "pcm"` + kademeli chunked
yanıt) `VOXCPM2_STREAMING_MODE=chunked_pcm` gerçek akışı açar: ses, sentez
bitmeden Web Audio kuyruğunda duyulmaya başlar. VM'de doğrulamadan açmayın;
akış başlatılamazsa yanıt seslendirmesi otomatik olarak tamponlu hatta düşer.

## 10. Sorun giderme

| Belirti | Neden / Çözüm |
| --- | --- |
| `Üretici kilidi aktif` | Başka koşu var ya da bayat kilit: `speech_gen_release_lock()` |
| Aday üretiminde `HTTP 503: No Healthy Address Found` | İstek kayıtlı olmayan bir ses adıyla gitmiş olabilir (örn. `voice=tr-male-1`). Aday sözleşmesi `voice=default` + input başında doğal dil tasarım tanımıdır; depo/kod güncel mi kontrol edin, gerekirse servisi `tests/scripts/test_voxcpm2_persona_voices.R` ile doğrulayın |
| `onaylı referans yok` | Önce `generate_reference_candidate` + `approve_reference_voice` |
| `voice_lock_degisti` nedeniyle toplu yeniden üretim planı | Kilit/parametre değişti; beklenen davranıştır |
| `profil_parmak_izi_uyusmuyor` | `.Renviron`'daki VOXCPM2_SPEED/CFG değerleri onay anındakinden farklı; ya geri alın ya `reset_reference` akışını uygulayın |
| Karşılama çalmıyor, log `statik hazır değil` | Manifest üretilmemiş/bayat: `validate_speech_assets()` + `generate_speech_manifest()` + uygulamayı yeniden başlat |
| `ornekleme_hizi_uyusmuyor` | `VOXCPM2_EXPECTED_SAMPLE_RATE` servis çıkışıyla uyuşmuyor; düzeltin ve yeniden üretin |
| Kişisel önek hiç duyulmuyor | Normal olabilir: önek `VOXCPM2_PREFIX_DEADLINE_MS` içinde hazır değilse atılır ve statik karşılama beklemeden başlar |
