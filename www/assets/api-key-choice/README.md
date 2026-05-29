# API Anahtarı Seçim Modalı - Yerel Görsel/Medya Varlıkları

Bu klasör, "API Anahtarı Seçimi" onboarding modalının (`R/module_api_key_choice_modal.R`
+ `www/css/api_key_choice_modal.css`) kullandığı **tamamen yerel** görsel ve medya
varlıklarını içerir. Uygulama internet erişimi olmayan kurum içi / on-prem bir
sunucuda çalıştığı için burada **CDN, uzak görsel, uzak font, uzak video veya uzak
ikon kütüphanesi kullanılmaz**. Tüm varlıklar bu repoda saklanır ve yerel yollarla
referanslanır.

## Klasör yapısı

```
www/
└── assets/
    └── api-key-choice/
        ├── README.md                 (bu dosya)
        ├── mesh-background.svg        (arka plan ızgara dokusu)
        ├── security-orbit.svg         (başlık amblemi - CSS mask)
        ├── personal-key.svg           (kişisel anahtar kart ikonu - CSS mask)
        ├── corporate-key.svg          (kurum anahtarı kart ikonu - CSS mask)
        ├── backdrop-poster.svg        (arka plan videosu posteri / geri düşüş)
        └── backdrop.mp4               (OPSİYONEL - repoda yoktur; aşağıya bakın)
```

## Varlık listesi

| Dosya | Nasıl kullanılır | Amaç |
|-------|------------------|------|
| `mesh-background.svg` | `.akc-bg` içinde `background-image` (tekrarlanan doku) | Modal arka planındaki ince ızgara dokusu. |
| `security-orbit.svg` | `.akc-emblem` içinde CSS `mask` (gradyanla boyanır) | Başlıktaki güvenlik amblemi. |
| `personal-key.svg` | `.akc-card-icon--personal` içinde CSS `mask` | Kişisel API anahtarı kartı ikonu. |
| `corporate-key.svg` | `.akc-card-icon--corporate` içinde CSS `mask` | Varsayılan kurum anahtarı kartı ikonu. |
| `backdrop-poster.svg` | `<video poster=...>` ve geri düşüş | Video yokken/yüklenene kadar gösterilen poster. |
| `backdrop.mp4` | `<video><source ...></video>` | OPSİYONEL premium arka plan videosu. Repoda yer almaz. |

## Opsiyonel arka plan videosu (`backdrop.mp4`)

Modal, daha "premium" bir his için arka planda **opsiyonel** bir video oynatabilir.
Bu video repoya dahil **edilmemiştir** çünkü:

- uygulama internetsiz çalışır ve uzak video bağlantısı (hotlink) yasaktır,
- büyük ikili (binary) dosyalar repoyu şişirir.

Davranış **zarif geri düşüşlüdür**: `backdrop.mp4` yoksa modal bozulmaz; sırasıyla
`backdrop-poster.svg` posteri ve onun altındaki CSS gradyan/mesh/aurora katmanları
görünür. Yani video olmadan da tasarım eksiksiz çalışır.

### Video eklemek isterseniz (internetsiz on-prem için)

1. İnternet erişimi olan ayrı bir makinede, telifsiz/lisansı uygun, soyut ve sakin
   bir döngü (loop) videosu indirin. Örnek kaynak türleri (kurum politikanıza göre
   seçin): Pexels Videos, Pixabay Videos, Coverr gibi telifsiz video siteleri.
   Önerilen içerik: koyu, soyut "ağ/parçacık/akış" teması; ~10-20 sn; sessiz.
2. Dosyayı **web için optimize edin** (örn. H.264/MP4, ~1280x720, düşük bitrate,
   tercihen < 3-4 MB) ki sayfa hızlı açılsın.
3. Dosyayı tam olarak şu ada ve yola **yerel olarak** kopyalayın:

   ```
   www/assets/api-key-choice/backdrop.mp4
   ```

4. (İsteğe bağlı) Daha geniş tarayıcı uyumu için bir `.webm` da ekleyebilirsiniz;
   bu durumda `R/module_api_key_choice_modal.R` içindeki `<video>` bloğuna ikinci bir
   `tags$source(src = "assets/api-key-choice/backdrop.webm", type = "video/webm")`
   ekleyin.
5. (İsteğe bağlı) Videonun ilk karesinden bir poster üretip `backdrop-poster.svg`
   yerine `backdrop-poster.jpg` koyabilirsiniz; bu durumda `<video poster=...>`
   yolunu güncelleyin.

**Asla** `backdrop.mp4` için uzak bir URL kullanmayın (hotlink yasak). Dosyayı indirip
yukarıdaki yola yerel olarak koyun.

## Tasarım notları

- `security-orbit.svg`, `personal-key.svg` ve `corporate-key.svg` dosyaları CSS
  `mask` olarak kullanılır; bu nedenle renkleri önemli değildir (görünen renk CSS
  gradyanından gelir). Şekiller siyah (`#000`) dolgu/çizgi ile çizilmiştir.
- Bu maske/arka plan/video referanslarının her biri için CSS'te bir **gradyan
  tabanı** vardır. Böylece bir varlık eksik olursa modal yine de bozulmadan görünür.
- Video, azaltılmış hareket tercihinde (`prefers-reduced-motion`) otomatik olarak
  gizlenir/durdurulur; bunun yerine statik poster + gradyan gösterilir.

## Varlığı değiştirme

1. Yeni dosyayı aynı adla bu klasöre koyun.
2. Maske ikonları için tek renk (siyah dolgu) silüet hazırlayın.
3. Boyut/konumlandırma `www/css/api_key_choice_modal.css` içindeki `mask` /
   `background-*` / `.akc-video` kurallarından ayarlanır.
4. **Uzak URL kullanmayın.** Varlığı indirip bu klasöre koyun ve yerel yolla
   referanslayın. Büyük raster dosyalardan kaçının; mümkünse SVG/CSS gradyanı
   tercih edin.
