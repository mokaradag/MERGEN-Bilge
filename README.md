# MERGEN Bilge

MERGEN Bilge, Türkçe odaklı, kurumsal kullanım için tasarlanmış, R/Shiny tabanlı gelişmiş bir yapay zeka asistanı uygulamasıdır. Uygulama; sohbet, dosya analizi, görsel üretimi, özetleme, süreç rehberliği, sesli etkileşim, destek merkezi ve kod odaklı çalışma alanı gibi çok sayıda yeteneği tek bir arayüzde bir araya getirir.

MERGEN adı, Türk ve Altay mitolojisinde bilgeliği, isabetli düşünceyi ve yol göstericiliği çağrıştırır. Uygulamadaki karakter sistemi de bu mitolojik temadan beslenir ve kullanıcı deneyimine hem görsel hem davranışsal bir katman ekler.

---

## Genel Özellikler

### Yapay zeka söyleşi deneyimi
- Gerçek zamanlı akış (streaming) ile yanıt üretimi
- Türkçe odaklı sohbet deneyimi
- Kod bloklarında sözdizimi vurgulama
- Takip soruları ve mesaj eylemleri
- Farklı model ve araç aileleriyle çalışma

### Dosya ve veri odaklı çalışma
- Excel, PDF, Word, CSV, metin dosyaları ve diğer belgelerin yüklenmesi
- Dosya önizleme
- Dosyaların söyleşi bağlamına eklenmesi
- Özetleme, analiz ve veri işleme akışları
- MCP tabanlı araçlarla gelişmiş dosya işleme

### Görsel ve medya özellikleri
- Yapay zeka ile görsel oluşturma
- Görsel galerisi
- TTS ile sesli yanıt
- STT ile sesli giriş
- Arka plan müziği ve karakter temalı deneyim

### Gelişmiş deneyim katmanları
- Sinematik başlangıç ekranı
- Hoş geldin ekranı
- Karakter seçimi
- Üç farklı deneyim modu
- AI Uzman rehberliği
- Bilge Yolaç sayfası ile kod odaklı ajan deneyimi

### Kurumsal ve yönetimsel bileşenler
- SSO / Keycloak desteği
- Kullanıcı bazlı sohbet ve dosya ayrımı
- Destek merkezi
- Geri bildirim ve hata bildirimi
- Sürüm bilgilendirme sayfası
- Yönetici paneli ve analitik ekranlar

---

## Sayfa Haritası

Uygulamadaki ana sayfalar aşağıdaki gibidir:

### Ana Söyleşi
Ana sohbet ekranıdır. Kullanıcı burada:
- soru sorabilir,
- dosya ekleyebilir,
- hızlı eylem kartlarıyla belirli akışları başlatabilir,
- model seçebilir,
- sesli giriş kullanabilir,
- görsel üretim, özetleme veya analiz odaklı kontrolleri aktif olarak kullanabilir.

### Söyleşi Yönetimi
Üç alt bölümden oluşur:
- **Söyleşi Geçmişi**
- **Kayıtlı Söyleşiler**
- **Görsel Galerisi**

### Bilge Yolaç
Claude Code tabanlı, web arayüzüne entegre edilmiş kod odaklı ajan sayfasıdır. Klasör seçimi, senaryo şablonları, model katmanları ve canlı akışlı araç kullanım görünümü içerir.

### Dosya Yönetimi
Kullanıcının yüklediği dosyaları yönettiği merkezdir. Yükleme, önizleme, listeleme ve söyleşiye bağlama işlemleri burada yapılır.

### Ayarlar
İki alt sayfa içerir:
- **Kişiselleştirme**
- **Yapılandırma**

### Destek
Dört alt sayfadan oluşur:
- **Yardım Merkezi**
- **Geri Bildirim & Hata**
- **Yenilikler**
- **Hakkında**

### Yönetici Paneli
Yetkili kullanıcılar için:
- genel analitik,
- geri bildirim analizi,
- hata analizi,
- yanıt geri bildirimi analizi,
- sistem durumu

ekranları sunulur. Sistem Durumu içindeki İşçi Havuzu kartı artık yalnızca sabit cluster boyutunu değil, uygulama düzeyindeki asenkron görev doluluğunu da gösterir.

---

## Hızlı Eylem Kartları

Hoş geldin ekranındaki hızlı eylem sistemi, kullanıcıyı doğrudan belirli akışlara taşımak için tasarlanmıştır. Mevcut ana hızlı eylemler:

- Süreç Yönetimi Sistemi
- Uygulama Uzmanı
- Proje ve Kaynak Analizi
- Excel Analizi
- Görsel Oluşturma
- Kodlama Desteği
- Özetleme Desteği

Bu kartlar yalnızca görsel kısayol değildir; model seçimi, başlangıç mesajı ve araç davranışı üzerinde etkili olabilirler.

---

## Deneyim Modları

MERGEN Bilge üç temel deneyim modu sunar:

### Odak
Daha sade ve dikkat dağıtıcılardan arındırılmış kullanım.

### Dinamik
Denge odaklı kullanım. Görsellik ve işlev arasında orta noktayı hedefler.

### Bütünleşik
Tam deneyim modudur. Karakter, ses, rehberlik ve zengin etkileşimlerin en yoğun biçimde hissedildiği moddur.

---

## Karakter Sistemi

Uygulama beş ana karakter içerir:

- **Mergen**
- **Ülgen**
- **Kayra**
- **Erlik**
- **Umay Ana**

Karakter sistemi şu bileşenlerle ilişkilidir:
- yanıt tarzı,
- karakter kartları,
- görsel kimlik,
- AI Uzman tonu,
- TTS ses seçimi,
- tema renkleri,
- bazı rehberlik ve anlatım tercihleri.

Varsayılan karakter **Mergen**’dir.

---

## Mimari Özet

Uygulama, klasik tek-dosya Shiny yaklaşımından daha modüler bir yapıya sahiptir. Ana yapı aşağıdaki gibidir:

### `app.R`
Gerçek giriş noktasıdır. Şunları yapar:
- `safe_source()` tanımlar,
- `global.R`, `ui.R`, `server.R` dosyalarını yükler,
- `www/` alt klasörlerini resource path olarak kaydeder,
- uygulamayı başlatır.

### `global.R`
Küresel yapılandırma ve yükleme sırasını yönetir. Şunları içerir:
- UTF-8 ve locale ayarları
- `safe_source()` tanımı
- zorunlu ortam değişkeni kontrolü
- dosya deposu altyapısı
- paket yüklemeleri
- tüm yardımcı, modül ve server handler dosyalarının sıralı yüklenmesi

### `ui.R`
Arayüzün omurgasıdır. Şunları tanımlar:
- dashboard header
- sidebar
- tab içerikleri
- CSS/JS bağımlılıkları
- CodeMirror
- giriş ekranı bileşenleri
- gizli yardımcı input/output alanları

### `server.R`
Sunucu mantığının birleşim noktasıdır. Şunları koordine eder:
- oturum başlatma
- SSO / yerel kimlik çözümü
- ayarlar
- dosya yönetimi
- medya modülleri
- AI Uzman
- Bilge Yolaç
- sohbet motoru
- kayıtlı söyleşi ve galeri akışları
- LLM çağrı zinciri

---

## Yükleme Sırası ve Modüler Yapı

`global.R` içindeki yükleme sırası bilinçli olarak katmanlara ayrılmıştır:

### 1. Temel altyapı
- paketler
- ortak yardımcılar
- loglama
- rate limiter
- worker monitor helper
- yol ve dosya yardımcıları
- Excel okuyucu

### 2. Yapılandırma
- SSO
- dosya deposu
- karakterler
- sürüm geçmişi
- API
- Bilge Yolaç yapılandırması

### 3. Veritabanı ve SQL
- veritabanı bağlantıları
- sorgu kütüphanesi
- SQL yükleyici

### 4. Çekirdek yardımcılar
- dil yardımcıları
- mesaj biçimlendirme
- MCP araçları
- dosya pipeline
- önizleme
- görsel galeri
- AI Uzman yardımcıları
- Bilge Yolaç yardımcıları

### 5. LLM entegrasyon katmanı
- araç formatlayıcıları
- yanıt son işleme
- SSE
- worker çağrıları
- API istek oluşturma

### 6. Modüller
- sohbet modülleri
- dosya ve medya modülleri
- ayar modülleri
- AI / TTS / STT modülleri
- SSO ve oturum modülleri
- destek modülleri
- admin modülleri
- worker health metric helpers
- Bilge Yolaç modülleri

### 7. Sunucu işleyicileri ve observer katmanı
- session cache
- chat handlers
- image/summarization handlers
- audio handlers
- AI Uzman handlers
- welcome handlers
- observer dosyaları
- output ve download işleyicileri

---

## İşçi Havuzu ve Asenkron Görev İzleme

Yönetici Paneli > Sistem Durumu > İşçi Havuzu (Workers) kartı artık yalnızca sabit cluster boyutunu göstermemektedir. Bu kart, uygulamanın future tabanlı asenkron iş yükünü uygulama düzeyinde izler.

### Gösterilen metriklerin anlamı
- **Toplam İşçi**: Future cluster içinde yapılandırılmış toplam worker sayısıdır.
- **Aktif İşçi**: O anda aktif iş yükü taşıdığı varsayılan worker sayısıdır.
- **Boş İşçi**: O anda aktif iş yükü taşımayan worker sayısıdır.
- **Aktif İş**: Uygulamanın izlediği aktif asenkron görev sayısıdır.
- **Kuyruktaki İş**: Aktif görev sayısı worker kapasitesini aştığında bekleyen iş yükünü temsil eder.
- **Kullanım Oranı**: Aktif işçi / toplam işçi oranıdır.

### Önemli not
Bu metrikler **kullanıcı sayısını göstermez**. Bunlar; LLM çağrısı, TTS, görsel üretimi ve true streaming gibi uygulama tarafından başlatılan asenkron görevlerin izleme görünümüdür.

### İlgili dosyalar
- `R/helpers_worker_monitor.R`
- `R/module_health_worker_metrics.R`

İzleme uygulaması `tracked_future_promise(...)` sarmalayıcısı ile yürütülür. Asenkron çalışan yeni bir akış eklenirse, sağlık ekranında doğru görünmesi için ilgili future çağrısının izlemeli sarmalayıcı üzerinden başlatılması gerekir.

### tracked_future_promise() neden zorunlu?

Bu projede `tracked_future_promise(...)` yalnızca sağlık ekranı için metrik üretmez. Aynı zamanda worker üzerinde çalışan görevlerin ihtiyaç duyduğu global fonksiyonları ve paket bağımlılıklarını güvenli biçimde taşıyan standart sarmalayıcıdır.

Bu özellikle şu senaryolarda kritiktir:
- `SSO_ENABLED=TRUE`
- Windows VM üzerinde çalışma
- `app.R` dosyasının tamamını seçip `Ctrl+Enter` ile başlatma
- persistent future cluster kullanımı

Özellikle non-streaming araç akışlarında (`Excel Analizi`, `Proje ve Kaynak Analizi`, `Görsel Oluşturma` gibi), worker tarafında kullanılan yardımcı fonksiyonlar doğrudan görünmeyebilir. Bu nedenle yeni bir asenkron akış eklenirken ham `future_promise(...)` yerine `tracked_future_promise(...)` kullanılmalıdır.

Aksi halde worker tarafında aşağıdaki türde hatalar görülebilir:
- `call_llm_worker` fonksiyonu bulunamadı
- `generate_image` fonksiyonu bulunamadı

Kural:
- Asenkron iş başlatırken varsayılan tercih `tracked_future_promise(...)` olmalıdır.
- Gerekli bağımlılıklar mümkün olduğunda `task_fn` içinden türetilir.
- Özel durumlarda `globals = list(...)` ile açık bağımlılık geçmek hâlâ geçerli bir yaklaşımdır.

---

## Önemli Dizinler ve Dosyalar

### Kök dizin
- `app.R`
- `global.R`
- `ui.R`
- `server.R`
- `welcome_screen.R`
- `version_history.md`
- `CLAUDE.md`
- `README.md`
- `ai_rehber.md`

### `R/`
Uygulamanın asıl iş mantığı burada bulunur:
- `config_*.R`
- `helpers_*.R`
- `utils_*.R`
- `module_*.R`
- `server_*.R`

### `www/`
Statik varlıklar:
- `css/`
- `js/`
- `codemirror/`
- `lib/`
- `characters/`
- kök görseller ve logolar

### `bilge_yolac_plugins/`
Bilge Yolaç eklenti dizini. Her alt klasör bağımsız bir eklentidir. `plugin.json` ve isteğe bağlı bileşen dizinleri (`skills/`, `templates/` vb.) içerir. Uygulama bu klasörü otomatik olarak tarar; manuel kayıt gerekmez.

### Veri ve çalışma dizinleri
- `logs/`
- `api_keys/`
- `mergen_uploads/`
- `destek_uploads/`
- `bilge_yolac_downloads/` - Bilge Yolaç tarafından üretilen dosyaların tarayıcıdan indirilebilir olarak sunulduğu dizin. `global.R` tarafından `bilge_yolac_downloads` kaynak yolu olarak kaydedilir.

---

## Dosya Depolama Altyapısı

Dosya depolama sistemi `R/config_file_store.R` içinde merkezi olarak tanımlanır.

### Temel kavramlar
- Kullanıcı bazlı klasör yapısı
- Kalıcı yükleme dizini
- JSON indeks dosyası
- Dosya adı ile gerçek saklama adı ayrımı
- Eksik indeks kayıtları için fallback dosya sistemi taraması
- Periyodik garbage collection

### Önemli yollar
- `MERGEN_FILES_ROOT`
- `MERGEN_UPLOADS_DIR`
- `MERGEN_MCP_BASE_DIR`
- `MERGEN_INDEX_PATH`

### Zorunlu ortam değişkeni kontrolü
Uygulama açılışta şu değişkenleri kontrol eder:
- `LOCAL_LLM_ENDPOINT`
- `DB_DSN`
- `AI_KEYS_MASTER`

Bunlardan biri eksikse uygulama başlamaz.

---

## Kimlik Doğrulama ve SSO

Uygulama iki modda çalışabilir:

### Yerel geliştirme modu
`SSO_ENABLED=FALSE`

Bu durumda:
- sistem kullanıcısı veya yerel çözümleme ile kullanıcı tanımlanır,
- hızlı yerel geliştirme yapılır,
- Keycloak akışı devre dışıdır.

### SSO modu
`SSO_ENABLED=TRUE`

Bu durumda:
- Keycloak token akışı çalışır,
- claim alanları ayrıştırılır,
- kullanıcı veritabanı kaydı doğrulanır/güncellenir,
- oturum bilgileri token doğrulaması sonrası tamamlanır.

SSO ile ilgili ana yapılandırma `R/config_sso.R` içinde tanımlanır.

---

## Bilge Yolaç

Bilge Yolaç, proje içinde ayrı bir ürün katmanı gibi düşünülebilir. Klasik sohbet ekranından farklı olarak kod odaklı bir ajan deneyimi sunar.

### Bileşenleri
- CLI yapılandırması
- klasör seçici modülü
- yerel klasör kopyalama (seçilen klasör çalışma alanına kopyalanır, yalnızca yüklenmez)
- canlı akış modülü
- araç kullanımı HTML biçimlendirme katmanı
- özel JS/CSS görünümü
- düşünme mesajları
- model katmanları
- senaryo şablonları
- eklenti yönetim paneli (sol kenar çubuğunda daraltılabilir)
- PDF / XLS / XLSX / DOCX yerel metin çıkarımı ve özetleme (`.doc` desteklenmez)
- `dosya_aciklamalari.txt` otomatik üretimi
- üretilen dosyalar için indirilebilir bağlantı kartları (`bilge_yolac_downloads/` üzerinden)

### Model katmanları
- Hızlı
- Dengeli
- Güçlü

### Kullanım örnekleri
- kod inceleme
- hata ayıklama
- dokümantasyon üretimi
- test yazımı
- refaktoring
- ofis belgesi üretimi (DOCX, XLSX, PPTX, PDF)
- güvenlik denetimi
- serbest komut

---

## Bilge Yolaç Eklenti Sistemi

Bilge Yolaç, kök dizindeki `bilge_yolac_plugins/` klasöründen beslenen, çevrimdışı çalışan bir eklenti sistemine sahiptir. Hiçbir CLI veya internet bağlantısı gerektirmez.

### Çalışma biçimi
- Uygulama açılışında `scan_local_plugins()` `bilge_yolac_plugins/` klasörünü tarar.
- Her alt klasördeki `plugin.json` okunur.
- Bileşen dizinleri (`skills/`, `commands/`, `agents/`, `hooks/`, `mcp/`, `templates/`) otomatik tespit edilir.
- Eklentiler Bilge Yolaç sol kenar çubuğundaki **Eklentiler** panelinde listelenir.
- Panel varsayılan olarak daraltılmış başlar; kullanıcı başlığa tıklayarak açabilir.

### Bir eklentinin dizin yapısı
```
bilge_yolac_plugins/<eklenti-adı>/
├── plugin.json          # Zorunlu: ad, açıklama, sürüm
├── skills/              # İsteğe bağlı: model yetenek metinleri
│   └── main.md
├── commands/            # İsteğe bağlı: slash komutları
├── agents/              # İsteğe bağlı: alt ajanlar
├── hooks/               # İsteğe bağlı: olay tabanlı otomasyon
├── mcp/                 # İsteğe bağlı: MCP sunucu yapılandırması
└── templates/           # İsteğe bağlı: hazır kod şablonları
```

### Varsayılan eklentiler

**Temel eklentiler:**
- `skill-creator` - Claude Code yetenek dosyası oluşturma rehberi
- `plugin-dev` - eklenti geliştirme rehberi
- `frontend-design` - arayüz tasarımı ve erişilebilirlik
- `claude-md-management` - CLAUDE.md dosyası yönetimi

**Geliştirme iş akışı:**
- `code-review` - sistematik kod inceleme
- `code-simplifier` - kod sadeleştirme
- `commit-commands` - Git commit yönetimi
- `feature-dev` - özellik geliştirme yaşam döngüsü
- `pr-review-toolkit` - pull request inceleme
- `ralph-loop` - tekrarlayan görev döngüleri

**Kalite ve analiz:**
- `test-gen` - test oluşturma
- `security-audit` - güvenlik denetimi
- `doc-gen` - kod dokümantasyonu üretimi
- `debug-detective` - sistematik hata ayıklama

**Belge üretimi:**
- `office` - DOCX, XLSX, PPTX, PDF üretimi (R `officer`/`openxlsx` tabanlı)

### Office eklenti çerçevesi
`office` eklentisi, hazır R yardımcı fonksiyonları içeren bir `templates/` dizini barındırır:

- `bilge_yolac_plugins/office/templates/docx_helpers.R` - officer tabanlı Word yardımcıları
- `bilge_yolac_plugins/office/templates/xlsx_helpers.R` - openxlsx tabanlı Excel yardımcıları
- `bilge_yolac_plugins/office/templates/pptx_helpers.R` - officer tabanlı PowerPoint yardımcıları
- `bilge_yolac_plugins/office/templates/pdf_helpers.R` - yerleşik grDevices ile PDF (ek paket gerekmez)
- `bilge_yolac_plugins/office/templates/document_readers.R` - PDF, XLS/XLSX ve DOCX dosyalarından çevrimdışı metin çıkarım yardımcıları (`.doc` desteklenmez)

Bu şablonlar Shiny uygulamasına `source()` ile yüklenmez. Bilge Yolaç oturumunda ajan tarafından ihtiyaç duyuldukça çağrılacak bağımsız R betikleridir. Endişelerin ayrımı şu şekildedir:
- `skills/main.md` - ne zaman ve neden kullanılacağı bilgisi
- `templates/*.R` - gerçek çalışan kod

### Yeni eklenti eklemek için
1. `bilge_yolac_plugins/<ad>/` dizinini oluşturun.
2. İçine `plugin.json` dosyasını yazın:
   ```json
   {
     "name": "ad",
     "description": "Türkçe açıklama",
     "version": "1.0.0"
   }
   ```
3. Gerektiği kadar bileşen dizini ekleyin (`skills/`, `commands/` vb.).
4. Uygulamayı yeniden başlatın veya Eklentiler panelindeki yenile düğmesine tıklayın.

Hiçbir R kodu değişikliği gerekmez; tarama otomatiktir.

---

## Yardım, Destek ve Sürüm Geçmişi

### Yardım Merkezi
Destek iletişim bilgileri ve uygulama hakkında soru sorulabilen yardım chatbotu içerir.

### Geri Bildirim & Hata
Kullanıcı geri bildirimleri ve hata raporları burada toplanır.

### Yenilikler
`version_history.md` dosyasından okunur ve uygulamada sürüm geçmişi olarak gösterilir.

### Hakkında
Uygulamanın tanıtım ve kullanım rehberi sayfasıdır.

---

## `ai_rehber.md` Dosyasının Rolü

`ai_rehber.md` sıradan bir belge değildir. Şu iki amaçla aktif olarak kullanılır:

1. Destek sayfasındaki yardım chatbotunun bilgi tabanı
2. AI Uzman prompt yapısının referans kaynağı

Bu nedenle bu dosyada yapılan değişiklikler, doğrudan ürün davranışını etkileyebilir.

---

## Kurulum

## Gereksinimler
Önerilen:
- R 4.2+
- UTF-8 destekli ortam
- uygun ODBC sürücüleri
- gerekli sistem kütüphaneleri

## Temel R paketleri
Uygulama `R/config_packages.R` içinde çok sayıda pakete dayanır. Başlıca paketler:

- `shiny`
- `shinydashboard`
- `shinyjs`
- `shinyWidgets`
- `shinyBS`
- `shinycssloaders`
- `DBI`
- `odbc`
- `pool`
- `future`
- `promises`
- `jsonlite`
- `httr`
- `dplyr`
- `DT`
- `readxl`
- `readr`
- `arrow`
- `duckdb`
- `pdftools`
- `openssl`
- `stringr`
- `stringi`
- `data.table`
- `writexl`
- `xml2`
- `av`

## Paket kurulumu örneği
```r
pkgs <- c(
  "arrow", "base64enc", "cellranger", "cli", "commonmark", "curl",
  "data.table", "DBI", "dplyr", "DT", "duckdb", "fastmatch",
  "future", "glue", "htmltools", "httr", "jsonlite", "later",
  "lubridate", "markdown", "odbc", "openssl", "pdftools", "pool",
  "promises", "purrr", "readr", "readxl", "shiny", "shinyBS",
  "shinycssloaders", "shinydashboard", "shinyjs", "shinyWidgets",
  "stringdist", "stringi", "stringr", "tibble", "tidyr", "urltools",
  "writexl", "xml2", "av"
)

install.packages(pkgs, dependencies = TRUE)
```

---

## `.Renviron` Örneği

Aşağıdaki örnek yalnızca şablondur. Gerçek değerleri kendi ortamınıza göre doldurmalısınız.

```ini
# Zorunlu
LOCAL_LLM_ENDPOINT=https://your-llm-endpoint.example.com/v1/chat/completions
DB_DSN=YourMainOdbcDsn
AI_KEYS_MASTER=your-long-random-secret

# İsteğe bağlı - ikincil LLM endpoint
LOCAL_LLM_ENDPOINT_ALT=https://your-secondary-llm-endpoint.example.com/v1/chat/completions
LOCAL_LLM_ENDPOINT_ALT_API_KEY=your-secondary-endpoint-key
FILTER_MODEL=your-default-model
AI_EXPERT_MODEL=your-ai-expert-model
DESTEK_CHATBOT_MODEL=your-support-chatbot-model

# TTS
LOCAL_TTS_ENDPOINT=https://your-tts-endpoint.example.com/v1
LOCAL_TTS_API_KEY=your-tts-key
LOCAL_TTS_MODEL=tts-1-hd
LOCAL_TTS_VOICE=tr-male-1
LOCAL_TTS_TIMEOUT=30
LOCAL_TTS_VERIFY_SSL=TRUE

# STT
LOCAL_STT_ENDPOINT=https://your-stt-endpoint.example.com/v1/audio/transcriptions
LOCAL_STT_MODEL=whisper-large-v3

# Görsel üretimi
IMAGE_GEN_ENDPOINT=https://your-image-endpoint.example.com/v1/images/generations
IMAGE_GEN_MODEL=dall-e-3
IMAGE_GEN_TIMEOUT=180
TRANSLATION_MODEL=your-translation-model

# SSO
SSO_ENABLED=FALSE
SSO_KEYCLOAK_URL=https://your-keycloak.example.com
SSO_REALM=byd_intranet_apps
SSO_CLIENT_ID=mergen_bilge
SSO_VALIDATE_ISSUER=TRUE
SSO_VALIDATE_EXPIRY=TRUE
SSO_TOKEN_REFRESH_MARGIN=300
SSO_DEBUG=FALSE

# Bilge Yolaç
CLAUDE_CODE_CLI_PATH=
CLAUDE_CODE_DEFAULT_WORKDIR=
CLAUDE_CODE_TIMEOUT=600
CLAUDE_CODE_MODEL=
CLAUDE_CODE_MAX_CONCURRENT=5
CLAUDE_CODE_PERSIST_SESSIONS=TRUE

# MCP dosya deposu
MCP_FILES_BASE=
```

---

## Çalıştırma

Bu depo için en güvenli yaklaşım, `app.R` dosyasını doğrudan çalıştırmaktır.

### R oturumundan
```r
source("app.R", encoding = "UTF-8")
```

### Alternatif
RStudio veya benzeri bir ortamda `app.R` dosyasının tamamını seçip çalıştırabilirsiniz.

### Neden bu yaklaşım?
Çünkü `app.R`:
- `safe_source()` tanımlar,
- `www/` klasörlerini resource path olarak kaydeder,
- Windows/VM kullanım senaryoları için daha güvenli bir başlatma akışı sağlar.

---

## Geliştirme İlkeleri

### 1. UTF-8 güvenliği
Bu repoda Türkçe karakterler kritik önemdedir. Şunlara dikkat edin:
- yeni dosyaları UTF-8 kaydedin,
- text/JSON okuma-yazma akışlarını bozmayın,
- gereksiz encoding dönüşümleri yapmayın.

### 2. Küçük ve kontrollü değişiklik
Geniş refaktör yerine hedefe yönelik düzeltmeler tercih edilir.

### 3. `global.R` yükleme sırasına saygı
Yeni bir modül/yardımcı eklenirse doğru gruba eklenmelidir.

### 4. Kod yorumları Türkçe olmalı
Koda yorum eklenecekse Türkçe yazılmalıdır.

### 5. Reaktif ve worker ayrımı
`future()` veya arka plan işlerinde reaktif nesneleri doğrudan kullanmayın.

---

## Sorun Giderme

### Uygulama başlamıyor
Kontrol edin:
- `.Renviron` mevcut mu
- `LOCAL_LLM_ENDPOINT`, `DB_DSN`, `AI_KEYS_MASTER` tanımlı mı
- ODBC bağlantısı çalışıyor mu

### Türkçe karakterler bozuk görünüyor
Kontrol edin:
- dosyalar UTF-8 mi
- VM/SSO akışında encoding davranışı değişmiş mi
- JSON, DB veya stream katmanında çift dönüşüm olmuş mu

### Statik dosyalar yüklenmiyor
Kontrol edin:
- `app.R` üzerinden mi çalıştırdınız
- `www/` alt klasörleri doğru kaydediliyor mu
- `img/` prefix’iyle sunulan kök dosya yolları doğru mu

### Yüklenen dosya adı anlamsız görünüyor
Kontrol edin:
- indeks kaydı
- display name alanı
- kullanıcı bucket çözümleme akışı

### SSO açıkken sorun çıkıyor, yerelde çıkmıyor
Kontrol edin:
- token claim’leri
- kullanıcı oturumunun auth sonrası kurulma zamanı
- UTF-8 / Türkçe alanlar
- auth sonrası dosya yükleme/yenileme akışları

### Bilge Yolaç akışı bozuk
Kontrol edin:
- `R/helpers_claude_code_streaming.R`
- `www/js/claude_code_streaming.js`
- Unicode semboller
- canlı akışlı parça birleştirme mantığı

### İşçi Havuzu değerleri kullanıcı sayısı ile uyuşmuyor
Bu beklenen bir durumdur. İşçi metrikleri giriş yapan kullanıcı sayısını değil, uygulamadaki asenkron iş yükünü gösterir. Kullanıcı sayısı ile worker/task doluluğu ayrı metrikler olarak yorumlanmalıdır.

### Belirli araçlar prompt sonrası çalışmıyor ama streaming akışlar çalışıyor
Kontrol edin:
- ilgili akış `tracked_future_promise(...)` ile mi başlatılıyor
- worker tarafına gerekli fonksiyonlar taşınıyor mu
- ham `future_promise(...)` kullanımı kalmış mı
- özellikle `SSO_ENABLED=TRUE` ve VM ortamında persistent cluster davranışı test edildi mi

---

## Sürüm Bilgisi

`version_history.md` içeriğine göre güncel genel sürüm hattı:

- **v1.0** - resmi lansman
- **v0.9** - beta sürümü

---

## Kısa Geliştirici Notu

Bu repo sadece bir Shiny uygulaması değildir; aynı zamanda:
- canlı prompt altyapısı,
- modüler medya sistemi,
- dosya indeksleme sistemi,
- SSO geçişli kurumsal oturum yönetimi,
- ve çok katmanlı bir kullanıcı deneyimi

barındırır.

Bu yüzden küçük görünen değişiklikler;
- encoding,
- resource path,
- observer sırası,
- session state,
- veya tool-family akışını beklenmedik biçimde etkileyebilir.

Özellikle `app.R`, `global.R`, `server.R`, `ui.R`, `config_file_store.R`, `helpers_ai_expert.R`, `module_claude_code.R` ve `ai_rehber.md` dosyalarını merkez dosyalar olarak düşünmek gerekir.
