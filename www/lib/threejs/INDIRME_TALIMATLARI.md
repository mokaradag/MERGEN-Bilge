# Three.js Yerel Dosyalar - İndirme Talimatları

Bu dizin, derin uzay giriş animasyonu için gereken Three.js kütüphanesi
ve doku dosyalarını içermelidir. Sunucu internet erişimi olmadığı için
bu dosyaların manuel olarak indirilmesi gerekmektedir.

## 1. Three.js Kütüphane Dosyaları

Aşağıdaki dosyaları `www/lib/threejs/` dizinine indirin:

**ÖNEMLİ:** Three.js v0.147.0 kullanılmalıdır. Bu sürüm, `examples/js/`
klasöründeki UMD (global) yapıyı destekleyen son sürümdür. v0.148.0 ve
sonrası sadece ES module (`examples/jsm/`) destekler.

### Ana Kütüphane
- **three.min.js** (Three.js r147 UMD build)
  - Kaynak: https://cdn.jsdelivr.net/npm/three@0.147.0/build/three.min.js

### Eklenti Dosyaları (UMD/global versiyonları)
Bu dosyalar global `THREE` nesnesine eklenti olarak eklenir ve
ES module import gerektirmez:

- **OrbitControls.js** (Kamera kontrolleri)
  - Kaynak: https://cdn.jsdelivr.net/npm/three@0.147.0/examples/js/controls/OrbitControls.js

### Post-Processing Bağımlılıkları
**ÖNEMLİ:** EffectComposer ve UnrealBloomPass dahili olarak aşağıdaki dosyaları
gerektirir. Bu dosyalar olmadan bloom efekti çalışmaz (ancak sahne yine de
doğrudan render ile görüntülenir).

- **CopyShader.js** (EffectComposer bağımlılığı)
  - Kaynak: https://cdn.jsdelivr.net/npm/three@0.147.0/examples/js/shaders/CopyShader.js

- **LuminosityHighPassShader.js** (UnrealBloomPass bağımlılığı)
  - Kaynak: https://cdn.jsdelivr.net/npm/three@0.147.0/examples/js/shaders/LuminosityHighPassShader.js

- **Pass.js** (Post-processing geçişlerinin temel sınıfı)
  - Kaynak: https://cdn.jsdelivr.net/npm/three@0.147.0/examples/js/postprocessing/Pass.js
  - NOT: `ShaderPass.js`, `RenderPass.js` ve `UnrealBloomPass.js` dosyaları
    `THREE.Pass` sınıfını beklediği için bu dosya onlardan önce yüklenmelidir.

- **ShaderPass.js** (EffectComposer bağımlılığı)
  - Kaynak: https://cdn.jsdelivr.net/npm/three@0.147.0/examples/js/postprocessing/ShaderPass.js

- **EffectComposer.js** (Post-processing ana modülü)
  - Kaynak: https://cdn.jsdelivr.net/npm/three@0.147.0/examples/js/postprocessing/EffectComposer.js

- **RenderPass.js** (Sahne render adımı)
  - Kaynak: https://cdn.jsdelivr.net/npm/three@0.147.0/examples/js/postprocessing/RenderPass.js

- **UnrealBloomPass.js** (Bloom/parlama efekti)
  - Kaynak: https://cdn.jsdelivr.net/npm/three@0.147.0/examples/js/postprocessing/UnrealBloomPass.js

### Diğer Eklentiler
- **Lensflare.js** (Güneş lens parlama efekti)
  - Kaynak: https://cdn.jsdelivr.net/npm/three@0.147.0/examples/js/objects/Lensflare.js

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

Animasyonda kullanılan fontlar `www/css/fonts.css` dosyasındaki
`@font-face` tanımlarıyla yerel olarak yüklenir.

### Google Fonts
- **Orbitron** (ağırlıklar: 400-900) - MERGEN başlık yazısı
  - https://fonts.google.com/specimen/Orbitron
  - Dosyalar: Orbitron-VariableFont_wght.ttf (veya sabit ağırlık dosyaları)

- **Jura** (ağırlıklar: 300-700) - Alt başlık ve açıklama metinleri
  - https://fonts.google.com/specimen/Jura
  - Dosyalar: Jura-VariableFont_wght.ttf (veya sabit ağırlık dosyaları)

Bu font dosyaları `www/fonts/` dizinine yerleştirilmelidir.
`www/css/fonts.css` dosyasında bu fontların `@font-face` tanımları
zaten mevcuttur.

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
├── fonts/
│   ├── Orbitron-VariableFont_wght.ttf
│   ├── Orbitron-Regular.ttf
│   ├── Orbitron-Medium.ttf
│   ├── Orbitron-SemiBold.ttf
│   ├── Orbitron-Bold.ttf
│   ├── Orbitron-ExtraBold.ttf
│   ├── Orbitron-Black.ttf
│   ├── Jura-VariableFont_wght.ttf
│   ├── Jura-Light.ttf
│   ├── Jura-Regular.ttf
│   ├── Jura-Medium.ttf
│   ├── Jura-SemiBold.ttf
│   └── Jura-Bold.ttf
├── css/
│   └── fonts.css
├── lib/
│   └── threejs/
│       ├── three.min.js
│       ├── OrbitControls.js
│       ├── CopyShader.js
│       ├── LuminosityHighPassShader.js
│       ├── Pass.js
│       ├── ShaderPass.js
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
