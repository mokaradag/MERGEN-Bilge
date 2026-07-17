# Otomatik Üretilen Konuşma Üst Verileri

Bu dizin `speech_manifest.json`, üretici durum dosyaları
(`generation_state_<persona>.json`), üretici eşzamanlılık kilidi
(`generator.lock`) ve dinlenmeyi bekleyen aday referanslar (`candidates/`)
için ayrılmıştır. Bu dosyaların TAMAMI otomatik üretilir ve GitHub'a commit
edilmez (kök `.gitignore`).

Süre değerlerini, sağlama toplamlarını, persona eşlemelerini veya dosya
yollarını elle girmeyin. `speech_manifest.json`,
`tools/speech/generate_voxcpm2_assets.R` içindeki `generate_speech_manifest()`
komutuyla; ortak konuşma metinlerinden, gerçek WAV başlıklarından, dosya
özetlerinden ve onaylı voice-lock kilitlerinden türetilerek atomik yazılır.

Çalışma zamanı manifesti süreç başına bir kez yükleyip doğrular ve önbelleğe
alır; 750 WAV her Shiny oturumunda taranmaz. Yeniden üretim/dağıtım sonrası
manifest, uygulama yeniden başlatıldığında (veya R konsolundan
`mergen_speech_manifest_refresh()` çağrısıyla) tazelenir. Manifest yoksa
uygulama açılışı KIRILMAZ; statik konuşma varlıkları kullanılamaz sayılır ve
teşhis logu yazılır.
