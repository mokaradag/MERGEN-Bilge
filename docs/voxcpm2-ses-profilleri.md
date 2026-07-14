# VoxCPM2 Referans-Ses Profilleri

MERGEN Bilge'nin beş personası (Emre, Selin, Deniz, Can, İpek) için
**uygulama-tarafı** VoxCPM2 referans-ses klonlama sistemi. Bu belge mimariyi,
güvenlik sınırını, başlangıç davranışını, dağıtımı, doğrulamayı ve geri dönüşü
(rollback) anlatır.

İlgili özet sözleşme: [`CLAUDE.md`](../CLAUDE.md) → "VoxCPM2 referans-ses profili
contract". Şablon: [`deployment/tts_voices_template/`](../deployment/tts_voices_template/).

---

## 1. Genel bakış

İki jenerik TTS sesi yerine, seçilen personaya göre bir **referans WAV** isteğe
eklenir ve VoxCPM2 o sesi klonlar. Persona → profil eşlemesi:

| Persona | Profil | Jenerik yedek ses |
|--------|--------|-------------------|
| Emre   | `emre`   | `default` |
| Selin  | `selin`  | `default` |
| Deniz  | `deniz`  | `default` |
| Can    | `can`    | `default` |
| İpek   | `ipek`   | `default` |

Bu, hem "Yanıtları Seslendir" hem de "AI Uzman Konuşması" yollarında aynı
profili kullanır. Uzak TTS sunucusunda önceden tanımlı adlandırılmış ses
GEREKMEZ; çözüm tamamen uygulama tarafındaki referans-ses ile çalışır.

VoxCPM2 istek gövdesi: `model`, `input`, `voice`, `response_format`, `speed`,
`ref_audio` (referans WAV base64 veri URL'si) ve `ref_text` (referansın birebir
dökümü). Üretim hızı `1.0`'dır (global `--slow` yoktur); yanıt biçimi
yapılandırılabilir, varsayılan `wav`.

---

## 2. Neden tek ortak transcript?

Beş kişi de **aynı** Türkçe pasajı okur; böylece tek bir transcript tüm
profiller için `ref_text` olur. Kanonik pasaj:

> Merhaba, bugün Mergen Bilge için doğal ve anlaşılır bir Türkçe ses örneği
> kaydediyorum. Konuşurken sakin bir hız kullanıyor, sözcükleri açık biçimde
> söylüyor ve cümleler arasında kısa duraklamalar yapıyorum.

Kayıt bu pasajı birebir içermelidir (sözcük eksik/fazla, yeniden başlama, arka
plan konuşması veya doğaçlama olmadan).

---

## 3. Güvenlik ve biyometrik-veri sınırı

Gerçek referans kayıtları biyometrik/kişisel veridir. Bu nedenle:

- `www` altında tutulmaz, GitHub'a commit edilmez, kaynak koda gömülmez,
- loglanmaz (base64 değeri asla loglanmaz) ve tarayıcıya döndürülmez,
- yalnızca dağıtım-yerel bir klasörde (`LOCAL_TTS_VOICE_DIR`, depo dışında) durur.

GitHub'daki [`deployment/tts_voices_template/`](../deployment/tts_voices_template/)
yalnızca yer tutucu (`.gitkeep`) ve `*.example` dosyaları içerir; `.gitignore`
oradaki gerçek `*.wav`, `manifest.json` ve `reference_transcript_tr_v1.txt`
dosyalarını yok sayar.

---

## 4. Mimari (dosyalar)

| Dosya | Sorumluluk |
|------|------------|
| `R/helpers_tts_voice_config.R` | `mergen_build_tts_config()`, `mergen_tts_voice_profiles_enabled()`, `mergen_tts_profile_for_character()` |
| `R/helpers_tts_voice_manifest.R` | WAV başlığı ayrıştırma/doğrulama, manifest yükleme, tek profil çözme (base64) |
| `R/helpers_tts_voice_cache.R` | Profil bellek önbelleği (dedup, sürümlü, base64 bir kez) |
| `R/helpers_tts_audio_cache.R` | Üretilen-ses önbelleği (anahtar, atomik okuma/yazma, TTL/boyut temizliği) |
| `R/helpers_tts_request.R` | İstek gövdesi + konuşma planı (profil çözüm + önbellek anahtarı/okuma) |
| `R/helpers_tts_queue.R` | Sınırlı eşzamanlılık kuyruğu (iptal-farkındalı) |
| `R/helpers_tts_profile_preload.R` | Başlangıç/ön yükleme politikası (yalnızca yükle+doğrula) |
| `R/module_tts.R` | Entegrasyon: plan → önbellek → kuyruk → worker; `preload_profile` |

`config_api.R` source-time'da `mergen_build_tts_config()` çağırır (bu yüzden
config üreticisi ondan önce yüklenir). Çalışma zamanı yardımcıları
`tts_ses_profilleri` manifest bölümündedir ve `module_tts.R`'den önce yüklenir.
Bölüm `medya_ses` seam'ine aittir.

Üç ayrı işlem birbirine karıştırılmaz:

1. **Profil yükleme** — yalnızca doğrula + base64 (ağsız). `preload_profile`.
2. **Uzak model ısıtma** — ayrı bir istek yapılmaz; ilk gerçek konuşma isteği
   ısıtma görevini görür (dummy cümle üretilmez).
3. **Konuşma üretimi** — gerçek sentez; AI Uzman'ın ilk-parça ön ısıtması gerçek
   ilk ifadeyi sentezler.

---

## 5. Başlangıç davranışı (şerit + deneyim modu)

### Hızlı Başlangıç (`fast_lane`)
Uygulama kullanılabilir olana kadar TTS için: WAV okunmaz, base64 yapılmaz, TTS
uç noktası çağrılmaz, 0–100 yükleme çubuğuna TTS eklenmez ve zorunlu boot
anahtarlarına (`connect`, `auth_ready`, `welcome_client_ready`) TTS girmez.
Kayıtlı ayar TTS'i açık gösterse bile önce Ana Söyleşi açılır; ardından yalnızca
seçili persona profili düşük öncelikle (later ile ertelenmiş) yüklenir.

### Zengin Deneyim (`rich_lane`)
0–100 yükleme kapısına tam TTS hazırlığı eklenmez.

- **Odak (`odak`)** ve **Dinamik (`denge`)**: TTS ve AI Uzman kapalı → hiçbir
  profil yüklenmez. Kullanıcı sonradan bir konuşma özelliği açarsa yüklenir.
- **Bütünleşik (`kesif`)**: TTS ve AI Uzman açık. Nihai persona seçimi
  onaylandıktan sonra yalnızca seçili profil asenkron yüklenir; Ana Söyleşi
  geçişi bloklanmaz. AI Uzman'ın içerik-özel ilk-parça ön ısıtması korunur.

Karakter sonradan değişirse yeni profil tembel yüklenir (önbellekte varsa
yeniden kullanılır). Profil yükleme idempotenttir ve bellek önbelleğiyle dedup
edilir.

---

## 6. Profil bellek önbelleği

Bir profil yalnızca gerektiğinde yüklenir. Yüklendiğinde süreç ömrü boyunca
doğrulanmış üst veri, birebir transcript, WAV/transcript sağlaması, base64 veri
URL'si ve sürüm saklanır. Aynı WAV her parça için yeniden base64'lenmez.

Önbellek kaynak değişiminde otomatik geçersizleşir: manifest mtime, WAV mtime/
boyut veya transcript mtime/boyut değişimi. `mergen_tts_invalidate_profile()` /
`mergen_tts_invalidate_all_profiles()` açık geçersizleme sağlar. Başarısız
çözümlemeler de önbelleklenir (her istekte aynı hatayı loglamamak için) ve
manifest değişince veya kısa bir TTL sonrası yeniden denenir.

---

## 7. Üretilen-ses önbelleği

Aynı metin için birebir aynı ses, ağ turu olmadan geri döner. Önbellek anahtarı
çıktıyı belirleyen tüm bileşenleri içerir: model, profil kimliği, profil sürümü,
WAV sağlaması, transcript sağlaması, nihai metin, hız ve yanıt biçimi. Herhangi
biri değişince anahtar değişir.

- Dağıtım-yerel disk önbelleği (`LOCAL_TTS_CACHE_DIR`), hashli dosya adları.
- Atomik yazma (geçici dosya + yeniden adlandırma); kısmi dosya döndürülmez.
- Boyut (`LOCAL_TTS_CACHE_MAX_MB`) ve TTL (`LOCAL_TTS_CACHE_TTL_DAYS`) ile
  sınırlı; temizlik açılışı bloklamaz.
- Metaveride düz kullanıcı metni tutulmaz (yalnızca hash). `LOCAL_TTS_CACHE_ENABLED=FALSE`
  ile kapatılabilir. Bozuk girdi yeniden üretime yol açar, uygulamayı düşürmez.
- Bu klasör depoya commit edilmez ve dizin listelemesi dışa açılmaz; dağıtım
  klasörü kısıtlı dosya sistemi izinleriyle korunmalıdır.

---

## 8. Sınırlı eşzamanlılık

VoxCPM2 referans-ses istekleri sınırsız paralel gönderilmez. Süreç-kapsamlı kuyruk
en fazla `LOCAL_TTS_MAX_CONCURRENCY` (varsayılan 2) işi aynı anda çalıştırır, FIFO
bekletir ve iptal-farkındalıdır. Oynatma sırası istemci tarafında `chunkIndex`/
`index` ile korunur; kuyruk çıktıyı yeniden sıralamaz. Bir işin hatası kuyruğu
kilitlemez; farklı oturumlar kullanılabilir kalır.

---

## 9. Fallback ve geri dönüş (rollback)

- Profiller kapalıysa veya model VoxCPM2 değilse jenerik (profilsiz) yol
  kullanılır (mevcut davranış: mp3, ref alanları yok).
- Bir profil geçersizse yalnızca o profil devre dışı kalır; jenerik yedek sese
  düşülür ve diğer profiller çalışmaya devam eder.
- Profil dizini yoksa uygulama açılışı düşmez.
- Eski modele dönüş yalnızca `.Renviron` ile yapılır (kod değişikliği gerekmez):
  `LOCAL_TTS_MODEL` değerini değiştirin veya `LOCAL_TTS_PROFILES_ENABLED=FALSE`.

---

## 10. Kayıt gereksinimleri (her `reference.wav`)

- ~8–12 saniye (kabul edilen üst sınır 30 saniyeyi aşamaz),
- mono, PCM 16-bit, 16 kHz,
- sessiz ortam; müzik/fan/arka plan gürültüsü yok,
- kırpma, güçlü yankı veya agresif gürültü bastırma izi yok,
- doğal Türkçe söyleyiş, normal hız, sabit mikrofon mesafesi.

---

## 11. Dağıtım (Windows VM)

1. Depo dışında güvenli klasör: `C:/MERGEN_Bilge_Data/tts_voices`.
2. `deployment/tts_voices_template/manifest.example.json` → oraya `manifest.json`.
3. `reference_transcript_tr_v1.txt.example` → oraya `reference_transcript_tr_v1.txt`
   (pasaj kayıtla birebir aynı).
4. Her persona klasörüne o kişinin `reference.wav` kaydını koyun.
5. `.Renviron`: `LOCAL_TTS_MODEL=VoxCPM2`, `LOCAL_TTS_PROFILES_ENABLED=TRUE`,
   `LOCAL_TTS_VOICE_DIR=...` (bkz. §13).
6. R sürecini **tamamen yeniden başlatın** (tarayıcı yenilemesi yetmez).

Nihai dağıtım-yerel yapı:

```
C:/MERGEN_Bilge_Data/
├── tts_voices/
│   ├── manifest.json
│   ├── reference_transcript_tr_v1.txt
│   ├── emre/reference.wav
│   ├── selin/reference.wav
│   ├── deniz/reference.wav
│   ├── can/reference.wav
│   └── ipek/reference.wav
└── tts_cache/            (MERGEN Bilge tarafından otomatik yönetilir)
```

---

## 12. Doğrulama

Çevrimdışı testler (gerçek ses/uç nokta gerektirmez):

```r
testthat::test_file("tests/testthat/test-tts-voice-config-behavior.R")
testthat::test_file("tests/testthat/test-tts-voice-manifest-behavior.R")
testthat::test_file("tests/testthat/test-tts-voice-cache-behavior.R")
testthat::test_file("tests/testthat/test-tts-audio-cache-behavior.R")
testthat::test_file("tests/testthat/test-tts-request-behavior.R")
testthat::test_file("tests/testthat/test-tts-queue-behavior.R")
testthat::test_file("tests/testthat/test-tts-profile-preload-behavior.R")
testthat::test_file("tests/testthat/test-tts-persona-profile-contract.R")
testthat::test_file("tests/testthat/test-tts-voice-template-contract.R")
```

VM'de canlı doğrulama (kanıt yalnızca VM'de üretilir):

- Bağımsız test: `Rscript tests/scripts/test_voxcpm2_tts.R --ref-audio <wav> --ref-text "<pasaj>"`.
- "Yanıtları Seslendir" ile bir yanıt üretin; ses personaya benzemeli.
- "AI Uzman Konuşması" (Bütünleşik mod) ilk ifadeyi hızlı üretmeli.
- Aynı sabit ifadeyi tekrar üretin; üretilen-ses önbelleği birebir aynı sesi
  ağ turu olmadan döndürmeli.

---

## 13. Tam `.Renviron` yapılandırması

```ini
LOCAL_TTS_ENDPOINT=https://<tts-endpoint>/v1
LOCAL_TTS_MODEL=VoxCPM2
LOCAL_TTS_VOICE=default
LOCAL_TTS_VERIFY_SSL=TRUE
LOCAL_TTS_TIMEOUT=90
LOCAL_TTS_API_KEY=

LOCAL_TTS_PROFILES_ENABLED=TRUE
LOCAL_TTS_VOICE_DIR=C:/MERGEN_Bilge_Data/tts_voices
LOCAL_TTS_SPEED=1.0
LOCAL_TTS_RESPONSE_FORMAT=wav
LOCAL_TTS_USE_REF_TEXT=TRUE
LOCAL_TTS_MAX_CONCURRENCY=2

LOCAL_TTS_CACHE_ENABLED=TRUE
LOCAL_TTS_CACHE_DIR=C:/MERGEN_Bilge_Data/tts_cache
LOCAL_TTS_CACHE_MAX_MB=512
LOCAL_TTS_CACHE_TTL_DAYS=30
```

---

## 14. Bir sesi güvenle değiştirme / önbellek geçersizleme

Bir kaydı güncellerken: ya manifestteki ilgili profilin `version` değerini
artırın **ya da** WAV/transcript içeriğini değiştirin. Profil bellek önbelleği
manifest/WAV/transcript değişimini otomatik algılar; üretilen-ses önbelleği
anahtarı sürüm + WAV sağlaması + transcript sağlaması içerdiğinden değişiklikte
otomatik geçersizleşir. Değişiklikten sonra R sürecini yeniden başlatmak
önerilir.

---

## 15. Sorun giderme

- **Ses klonlanmıyor, jenerik geliyor:** `LOCAL_TTS_MODEL` VoxCPM2 mi,
  `LOCAL_TTS_PROFILES_ENABLED=TRUE` mı, `LOCAL_TTS_VOICE_DIR` doğru mu? Loglarda
  "Ses profili yüklenemedi" satırına bakın.
- **Profil yüklenemedi:** WAV mono/16-bit/16 kHz mi, süre ≤ 30 sn mi, transcript
  UTF-8 ve dolu mu, `manifest.json` `schema_version: 1` mi?
- **Değişiklik yansımıyor:** R sürecini tam yeniden başlattınız mı? Profil
  sürümünü artırdınız mı?
- **Yavaş ilk yanıt:** ilk istek uzak modeli ısıtır; sonraki istekler ve önbellek
  isabetleri hızlıdır.
