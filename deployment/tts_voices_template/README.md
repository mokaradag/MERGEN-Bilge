# VoxCPM2 Ses Profili Şablonu (yalnızca yer tutucu)

Bu klasör, MERGEN Bilge'nin beş personası (Emre, Selin, Deniz, Can, İpek) için
VoxCPM2 referans-ses profillerinin **dağıtım-yerel** kurulumunu göstermek üzere
bir **şablondur**. Üretimde doğrudan kullanılmaz.

> **UYARI — Biyometrik/kişisel veri:** Gerçek referans ses kayıtları (`.wav`)
> biyometrik/kişisel veridir. Bu klasöre veya GitHub deposunun herhangi bir
> yerine **gerçek WAV, gerçek `manifest.json` veya gerçek transcript
> ASLA commit edilmez.** Gerçek dağıtım verisi depo dışında, erişimi kısıtlı bir
> klasörde tutulur (ör. Windows VM'de `C:/MERGEN_Bilge_Data/tts_voices`).

## Bu klasörde ne var?

- `README.md` — bu dosya.
- `manifest.example.json` — örnek manifest (gerçek `manifest.json` değildir).
- `reference_transcript_tr_v1.txt.example` — beş kişinin de birebir okuyacağı
  ortak Türkçe pasaj (gerçek `reference_transcript_tr_v1.txt` değildir).
- `emre/`, `selin/`, `deniz/`, `can/`, `ipek/` — her persona için boş klasör
  (`.gitkeep` ile korunur). Gerçek `reference.wav` buraya konmaz; dağıtım-yerel
  kopyaya konur.

`.gitignore`, bu şablon altındaki gerçek `*.wav`, `manifest.json` ve
`reference_transcript_tr_v1.txt` dosyalarını yok sayar; yalnızca `.gitkeep`,
`README.md` ve `*.example*` dosyaları izlenir.

## Ortak transcript neden tek?

Beş kişi de **aynı** pasajı okur; böylece tek bir transcript tüm profiller için
`ref_text` olarak kullanılır. Kayıt sırasında pasaj **birebir** okunmalıdır:
sözcük eksiltmeden/eklemeden, yeniden başlamadan, arka planda başka ses olmadan.

Kanonik pasaj (`reference_transcript_tr_v1.txt.example` içindekiyle aynıdır):

> Merhaba, bugün Mergen Bilge için doğal ve anlaşılır bir Türkçe ses örneği
> kaydediyorum. Konuşurken sakin bir hız kullanıyor, sözcükleri açık biçimde
> söylüyor ve cümleler arasında kısa duraklamalar yapıyorum.

## Gerekli WAV biçimi (her `reference.wav`)

- yaklaşık 8–12 saniye (kabul edilen üst sınır 30 saniyeyi aşamaz),
- mono (tek kanal),
- PCM 16-bit,
- 16 kHz örnekleme hızı,
- sessiz ortam; müzik, fan/arka plan gürültüsü yok,
- kırpma (clipping), güçlü yankı veya agresif gürültü bastırma izi yok,
- doğal Türkçe söyleyiş, normal konuşma hızı, sabit mikrofon mesafesi.

## Zorunlu dosya adları (dağıtım-yerel)

```
<LOCAL_TTS_VOICE_DIR>/
├── manifest.json
├── reference_transcript_tr_v1.txt
├── emre/reference.wav
├── selin/reference.wav
├── deniz/reference.wav
├── can/reference.wav
└── ipek/reference.wav
```

## Dağıtım adımları (Windows VM)

1. Depo dışında güvenli bir klasör oluşturun, ör. `C:/MERGEN_Bilge_Data/tts_voices`.
2. `manifest.example.json` dosyasını oraya `manifest.json` olarak kopyalayın.
3. `reference_transcript_tr_v1.txt.example` dosyasını oraya
   `reference_transcript_tr_v1.txt` olarak kopyalayın (pasaj kayıtla birebir aynı olmalı).
4. Her persona klasörüne (`emre/`, `selin/`, ...) o kişinin `reference.wav`
   kaydını koyun.
5. `.Renviron` içinde `LOCAL_TTS_VOICE_DIR` değerini bu klasöre ayarlayın ve
   `LOCAL_TTS_MODEL=VoxCPM2`, `LOCAL_TTS_PROFILES_ENABLED=TRUE` yapın.
6. R sürecini **tamamen yeniden başlatın** (tarayıcı yenilemesi yetmez).

## Doğrulama

- Uygulama açılışta profili yalnızca gerektiğinde (bir konuşma özelliği açıkken)
  tembel yükler; WAV başlığı gerçekten ayrıştırılıp biçim denetlenir.
- Bir profil geçersizse yalnızca o profil devre dışı kalır; diğerleri çalışır ve
  jenerik yedek sese düşülür.

## Sürüm/sağlama ile önbellek geçersizleme

- Bir kaydı güncellerken manifestteki ilgili profilin `version` değerini artırın
  **veya** WAV/transcript içeriğini değiştirin.
- Profil bellek önbelleği manifest/WAV/transcript değişimini otomatik algılar;
  üretilen-ses önbelleği anahtarı model + profil kimliği + sürüm + WAV sağlaması +
  transcript sağlaması + metin + hız + biçim içerdiğinden değişiklikte
  otomatik geçersizleşir.
