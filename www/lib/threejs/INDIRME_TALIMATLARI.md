# Three.js Yerel Dosyalar - İndirme Talimatları

Bu dizin, derin uzay giriş animasyonu için gereken Three.js kütüphanesi
ve doku dosyalarını içermelidir. Sunucu internet erişimi olmadığı için
bu dosyaların manuel olarak indirilmesi gerekmektedir.

## 1. Three.js Kütüphane Dosyaları

Aşağıdaki dosyaları `www/lib/threejs/` dizinine indirin:

### Ana Kütüphane
- **three.min.js** (Three.js r160 UMD build)
  - Kaynak: https://cdn.jsdelivr.net/npm/three@0.160.0/build/three.min.js

### Eklenti Dosyaları (UMD versiyonları gerekli)
Orijinal HTML ES module kullandığı için bu dosyaların UMD/global yapıya
dönüştürülmüş versiyonları gereklidir:

- **OrbitControls.js**
  - Kaynak: https://cdn.jsdelivr.net/npm/three@0.160.0/examples/js/controls/OrbitControls.js

- **EffectComposer.js**
  - Kaynak: https://cdn.jsdelivr.net/npm/three@0.160.0/examples/js/postprocessing/EffectComposer.js

- **RenderPass.js**
  - Kaynak: https://cdn.jsdelivr.net/npm/three@0.160.0/examples/js/postprocessing/RenderPass.js

- **UnrealBloomPass.js**
  - Kaynak: https://cdn.jsdelivr.net/npm/three@0.160.0/examples/js/postprocessing/UnrealBloomPass.js

- **Lensflare.js**
  - Kaynak: https://cdn.jsdelivr.net/npm/three@0.160.0/examples/js/objects/Lensflare.js

**NOT:** Three.js r160 sürümünde `examples/js/` klasörü hala mevcuttur.
Bu dosyalar global `THREE` nesnesine eklenti olarak eklenir ve
ES module import gerektirmez.

## 2. Doku (Texture) Dosyaları

Aşağıdaki dosyaları `www/lib/threejs/textures/` dizinine indirin:

### Samanyolu Arka Planı
- **starmap.jpg** (Eşdikdörtgen projeksiyon Samanyolu haritası)
  - Kaynak: https://cdn.eso.org/images/large/eso0932a.jpg
  - Boyut: ~30 MB (yüksek çözünürlüklü versiyonu tercih edin)
  - NOT: Bu dosya olmadan arka plan siyah kalır

### Dünya Dokuları
- **earth_atmos_2048.jpg** (Dünya yüzey haritası - atmosferli)
  - Kaynak: https://raw.githubusercontent.com/mrdoob/three.js/master/examples/textures/planets/earth_atmos_2048.jpg

- **earth_normal_2048.jpg** (Dünya normal haritası - yüzey detayları)
  - Kaynak: https://raw.githubusercontent.com/mrdoob/three.js/master/examples/textures/planets/earth_normal_2048.jpg

- **earth_specular_2048.jpg** (Dünya yansıma haritası - okyanus parlamaları)
  - Kaynak: https://raw.githubusercontent.com/mrdoob/three.js/master/examples/textures/planets/earth_specular_2048.jpg

- **earth_clouds_1024.png** (Dünya bulut katmanı)
  - Kaynak: https://raw.githubusercontent.com/mrdoob/three.js/master/examples/textures/planets/earth_clouds_1024.png

- **earth_lights_2048.png** (Dünya gece ışıkları haritası)
  - Kaynak: https://raw.githubusercontent.com/mrdoob/three.js/master/examples/textures/planets/earth_lights_2048.png

### Ay Dokusu
- **moon_1024.jpg** (Ay yüzey haritası)
  - Kaynak: https://raw.githubusercontent.com/mrdoob/three.js/master/examples/textures/planets/moon_1024.jpg

## 3. Font Dosyaları

Animasyonda kullanılan fontlar CSS `@import` ile yüklenmektedir.
İnternet erişimi olmayan ortamda bu fontların da yerel olarak
sunulması gerekir:

### Google Fonts
- **Orbitron** (ağırlıklar: 500, 900) - MERGEN başlık yazısı
  - https://fonts.google.com/specimen/Orbitron
  - Dosyalar: Orbitron-Medium.woff2, Orbitron-Black.woff2

- **Jura** (ağırlıklar: 300, 600) - Alt başlık ve açıklama metinleri
  - https://fonts.google.com/specimen/Jura
  - Dosyalar: Jura-Light.woff2, Jura-SemiBold.woff2

Bu font dosyaları `www/fonts/` dizinine yerleştirilmeli ve
`www/css/fonts.css` dosyasına `@font-face` tanımları eklenmelidir.
Mevcut `fonts.css` dosyanızda bu fontlar zaten tanımlı olabilir.

## 4. Şirket Logosu

- **company_logo.png** - Beyaz renkli, transparan arka planlı şirket logosu
  - Konum: `www/company_logo.png`
  - Önerilen boyut: Genişlik 200-400px, yükseklik orantılı
  - Format: PNG (transparan arka plan)
  - Giriş ekranında sol üst köşede ~42px yüksekliğinde gösterilecek

## Dizin Yapısı (Tamamlandığında)

```
www/
├── company_logo.png
├── lib/
│   └── threejs/
│       ├── three.min.js
│       ├── OrbitControls.js
│       ├── EffectComposer.js
│       ├── RenderPass.js
│       ├── UnrealBloomPass.js
│       ├── Lensflare.js
│       ├── INDIRME_TALIMATLARI.md
│       └── textures/
│           ├── starmap.jpg
│           ├── earth_atmos_2048.jpg
│           ├── earth_normal_2048.jpg
│           ├── earth_specular_2048.jpg
│           ├── earth_clouds_1024.png
│           ├── earth_lights_2048.png
│           └── moon_1024.jpg
```
