# MERGEN-Bilge
Türkçe dilinde tasarlanmış MERGEN-Bilge, etkileşimli bir sohbet deneyimi, söyleşi yönetimi ve veri/dosya destekli iş akışlarını tek bir Shiny Dashboard arayüzünde birleştiren bir yapay zekâ asistanı uygulamasıdır. Uygulama, R tabanlıdır ve hem kurumsal veri kaynaklarıyla entegrasyon hem de kullanıcı dostu bir ön yüz sunmak için geniş bir paket ekosisteminden yararlanır.

## Genel Bakış
- **Ana Söyleşi:** Çoklu dil ve kod desteğiyle sohbet, akıcı cevap oluşturma, CodeMirror tabanlı kod düzenleme ve yanıt formatlama yetenekleri.
- **Söyleşi Yönetimi:** Geçmiş kayıtlarını görüntüleme, favorilere alma ve yeniden kullanma imkânı sağlayan sekmeler ("Söyleşi Geçmişi" ve "Kayıtlı Söyleşiler").
- **Dosya Yönetimi:** Belgeleri veya veri dosyalarını yükleyip işleme sokmak için merkezi bir bölüm.
- **Ayarlar:** Sistem ve kullanıcı tercihlerini yapılandırma; profil, örnekleme ve özet hesaplama gibi ağır işlemleri açıp kapatmaya yönelik seçenekler.
- **Sistem Durumu:** Sağlık kontrolleri ve günlük kayıtlarıyla uygulama servislerinin izlenmesi.
- **Görsel Kimlik:** Özelleştirilmiş marka alanı, yerleşik simgeler, özel yazı tipleri ve tema bileşenleri.

## Mimari
- **`app.R`:** Uygulamanın giriş noktası; `global.R`, `ui.R` ve `server.R` dosyalarını sırayla yükler ve Shiny uygulamasını başlatır.
- **`global.R`:** Ortak ayarlar (UTF-8, yerel saat, örnekleme oranları), loglama kurulumu, hata yakalayıcı, RData depo yolları ve tüm paket yüklemeleri burada tanımlanır.
- **`ui.R`:** `shinydashboard` ile oluşturulmuş başlık, kenar çubuğu ve gövde yerleşimi; CodeMirror editörü, özel stil/JS dosyaları, gizli bağımlılık yükleyicileri ve sekme bazlı gezinmeyi içerir.
- **`server.R`:** Sunucu tarafı iş mantığı; sohbet akışı, dosya ve söyleşi işlemleri, sağlık denetimleri ve ayarların uygulanmasından sorumludur.
- **Diğer dosyalar:**
  - **`welcome_screen.R`:** Açılış ekranı ve karşılama bileşenleri.
  - **`generate_schema_registry.R` & `Table Structure.txt`:** Veri şemalarına ilişkin yardımcı tanımlar.
  - **`R/` klasörü:** Yardımcı fonksiyonlar, modüller ve bileşenler.
  - **`www/` klasörü:** Statik varlıklar (CSS, JS, yazı tipleri, CodeMirror dağıtımı ve marka görselleri).

## Özellikler (Örnekler)
- **Gelişmiş kod desteği:** R, Python, SQL, JavaScript ve diğer popüler diller için vurgulu düzenleme (CodeMirror modları). 
- **Çok sekmeli gezinme:** "Ana Söyleşi", "Söyleşi Yönetimi", "Dosya Yönetimi", "Ayarlar" ve "Sistem Durumu" sekmeleriyle modüler yapı. 
- **Kayıt ve izleme:** `logs/` dizininde günlükler; hata izleme için özel `shiny.error` yakalayıcısı ve `dbg_dump` yardımcıları. 
- **Veri/Şema entegrasyonu:** RData depoları (`Rdata`, `RdataDaily`) ve şema kayıt dosyalarıyla veri keşfi ve profil oluşturma desteği. 
- **Performans kontrolleri:** Başlangıçta ağır işlemleri devre dışı bırakmak için örnekleme ve özet üretim ayarları, gerektiğinde açılabilir opsiyonlar.

## Sistem Gereksinimleri
- **R sürümü:** 4.2 veya üzeri önerilir.
- **İşletim sistemi:** Linux, macOS veya Windows (UTF-8 desteği önerilir). Windows için yol normalizasyonu `safe_windows_short_path()` ile ele alınır.
- **Bağımlı paketler (özet):** `shiny`, `shinydashboard`, `shinyjs`, `shinyWidgets`, `DT`, `dplyr`, `duckdb`, `arrow`, `DBI`, `future`, `logger`, `jsonlite`, `glue`, `readr`, `readxl`, `lubridate`, `promises`, `pool`, `httr`, `pdftools`, `stringr`, `tibble`, `tidyr`, `writexl`, `openssl`, `odbc`, `curl`, `htmltools`, `markdown`, `commonmark`, `data.table`, `purrr`, `stringi`, `urltools`, `fastmatch`, `cellranger`, `base64enc`, `later`, `shinycssloaders`, `shinyBS`, `cli`, `arrow` ve CodeMirror dağıtımını sağlayan statik dosyalar. 

> Not: Paket listesinin tamamı `global.R` içinde yer alır; yeni ortam kurulumunda eksik paketleri `install.packages()` ile yükleyin.

## Kurulum ve Çalıştırma
1. Depoyu klonlayın:
   ```bash
   git clone https://<repo-url>/MERGEN-Bilge.git
   cd MERGEN-Bilge
   ```
2. Gerekli R paketlerini yükleyin (yalın kurulum örneği):
   ```r
   pkgs <- c(
     "shiny", "shinydashboard", "shinyjs", "shinyWidgets", "shinycssloaders", "shinyBS",
     "DT", "dplyr", "duckdb", "arrow", "DBI", "future", "logger", "jsonlite", "glue",
     "readr", "readxl", "lubridate", "promises", "pool", "httr", "pdftools", "stringr",
     "tibble", "tidyr", "writexl", "openssl", "odbc", "curl", "htmltools", "markdown",
     "commonmark", "data.table", "purrr", "stringi", "urltools", "fastmatch", "cellranger",
     "base64enc", "later", "cli"
   )
   install.packages(pkgs, dependencies = TRUE)
   ```
3. Uygulamayı başlatın:
   ```r
   # R oturumunda
   source("app.R")
   # veya
   shiny::runApp(".")
   ```
4. Tarayıcıda otomatik açılmazsa `http://localhost:3838` (veya R konsolunda belirtilen port) adresini ziyaret edin.

## Yapılandırma
- **Performans anahtarları:** `global.R` içindeki `options(mergen.rdata.*)` değerlerini kullanarak profil/özet üretimini açabilir veya örnekleme oranını değiştirebilirsiniz.
- **Geçici dizinler:** `options(mergen.duckdb.temp_directory = Sys.getenv("MERGEN_DUCKDB_TEMP_DIR", tempdir()))` üzerinden DuckDB geçici dizinini kontrol edin.
- **Günlükler:** `logs/` klasörü başlangıçta oluşturulur; günlük adı `mergen_YYYYMMDD.log` formatındadır. Hata ve debug çıktıları sırasıyla `shiny.error` ve `dbg_dump()` ile kaydedilir.
- **Yerel ayarlar:** UTF-8 karakter seti ve Türkçe yerelleştirme için `Sys.setlocale("LC_CTYPE", "Turkish_Turkey.UTF-8")` çağrısı yapılır.
- **Sesli yanıt (TTS):** OpenAI uyumlu bir seslendirme servisi için `LOCAL_TTS_ENDPOINT` (örn. `https://<host>/v1`) ve gerekiyorsa `LOCAL_TTS_API_KEY` ortam değişkenlerini ayarlayın. Model/isim varsayılanları `LOCAL_TTS_MODEL` (varsayılan: `tts-1-hd`) ve `LOCAL_TTS_VOICE` (varsayılan: `tr-female-1`) ile özelleştirilebilir. Ayarlar sekmesinde seslendirmeyi açıp kapatabilir ve ses tipini seçebilirsiniz.

## Geliştirme Notları
- Arayüz `shinydashboard` üzerinde sekmeli yapıda çalışır; yeni sekmeler eklemek için `ui.R` içindeki `sidebarMenu` ve `body` bölümlerini güncelleyin.
- Sunucu tarafında yeni modüller eklerken asenkron işlemler için `future` ve `promises` paketleri kullanılabilir.
- Kod düzenleme/görselleştirme bileşenleri CodeMirror çıktılarıdır; ek dil desteği için `www/codemirror/mode` altındaki ilgili JS dosyalarını ekleyin ve `ui.R` içinde `tags$script` ile yükleyin.
- Test veya üretim ortamında ağır profil/özet işlemleri devredeyse `mergen.rdata.refresh_on_boot`, `mergen.rdata.enable_profiles`, `mergen.rdata.enable_aggregates` gibi seçenekleri ihtiyaçlarınıza göre ayarlayın.

## Sorun Giderme
- **Eksik paket hatası:** `install.packages()` ile eksik paketi kurun, ardından R oturumunu yeniden başlatın.
- **Yerelleştirme/UFT-8 sorunları:** Sistem dilini Türkçe'ye veya UTF-8 uyumlu bir yerel ayara çekin; Windows'ta kısa yol düzeltmeleri için `safe_windows_short_path()` işlevi otomatik uygulanır.
- **Port çakışması:** `shiny::runApp(port = <yeni_port>)` parametresiyle farklı bir port belirleyin.
- **Büyük veri/özelleştirme:** RData klasör yollarını (`Rdata`, `RdataDaily`) yapılandırın ve örnekleme oranını (`mergen.rdata.profile_sample_frac`) artırıp azaltarak performans dengesini sağlayın.

## Lisans
Bu depo içinde lisans bilgisi belirtilmemiştir. Kurum içi kullanım veya dağıtım koşullarını kendi gereksinimlerinize göre belirleyin.