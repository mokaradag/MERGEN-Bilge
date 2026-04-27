# MERGEN Bilge

MERGEN Bilge, Türkçe odaklı, kurumsal kullanım için tasarlanmış, R/Shiny tabanlı gelişmiş bir yapay zeka asistanı uygulamasıdır. Uygulama; sohbet, dosya analizi, görsel üretimi, özetleme, süreç rehberliği, sesli etkileşim, destek merkezi ve kod odaklı çalışma alanı gibi çok sayıda yeteneği tek bir arayüzde bir araya getirir.

MERGEN adı, Türk ve Altay mitolojisinde bilgeliği, isabetli düşünceyi ve yol göstericiliği çağrıştırır. Uygulamadaki karakter sistemi de bu mitolojik temadan beslenir ve kullanıcı deneyimine hem görsel hem davranışsal bir katman ekler.

Dokümantasyon Notu: Bu README, ürün kapsamını hızlıca anlamak için üst seviye bir özet sunar; ayrıntılı operasyonel kurallar ve asistan davranış ilkeleri için sırasıyla `CLAUDE.md` ve `ai_rehber.md` dosyalarına başvurulmalıdır.

---

## Genel Özellikler

### Yapay zeka söyleşi deneyimi
- Gerçek zamanlı akış (streaming) ile yanıt üretimi
- Türkçe odaklı sohbet deneyimi
- Kod bloklarında sözdizimi vurgulama
- Takip soruları ve mesaj eylemleri
- Farklı model ve araç aileleriyle çalışma
- Düşünebilen modeller (`thinking=TRUE`) için premium akıl yürütme kartı ve canlı düşünce akışı paneli

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

Ana Söyleşi hoş geldin ekranında ayrıca **Son Konuşmalar** bölümü bulunur. Bu bölüm, en son **aktif olan** 3 söyleşiyi gösterir; kullanıcı "Yeni Söyleşi" ile yeni akışa geçtiğinde az önce tamamlanan söyleşi hoş geldin ekranına dönüldüğünde beklemeden bu listede görünür. Sıralama, oluşturulma zamanından ziyade söyleşi aktivitesine göre yapılır.

### Söyleşi Yönetimi
Üç alt bölümden oluşur:
- **Söyleşi Geçmişi**
- **Kayıtlı Söyleşiler**
- **Görsel Galerisi**

Bu akışlar kullanıcı bazlı veri ayrımıyla çalışır. Eski bir söyleşi yeniden aktif kullanıldığında, son aktiviteye göre son listelere tekrar yukarı taşınabilir.

### Bilge Yolaç
Claude Code tabanlı, web arayüzüne entegre edilmiş kod odaklı ajan sayfasıdır. Klasör seçimi, senaryo şablonları, model katmanları ve canlı akışlı araç kullanım görünümü içerir.

### Dosya Yönetimi
Kullanıcının yüklediği dosyaları yönettiği merkezdir. Yükleme, önizleme, listeleme ve söyleşiye bağlama işlemleri burada yapılır.

Dosya Yönetimi ekranında dosya başına varsayılan yükleme sınırı 25 MB’tır. Bu sınır yalnızca sunucu tarafında değil, tarayıcı tarafında da kontrol edilir; böylece büyük dosyalar Shiny upload süreci başlamadan önce reddedilir ve kullanıcıya anında uyarı gösterilir. Bu katmanlı yaklaşım, özellikle on-prem Windows VM üzerinde büyük PDF/Word/Excel dosyalarının arayüzü kilitlemesini veya geç yanıt veren upload akışları oluşturmasını önlemek için kullanılır.

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

### Sistem Durumu Sağlık Paneli

MERGEN Bilge, on-prem Windows VM dağıtımlarında yöneticilerin uygulama durumunu hızlıca değerlendirebilmesi için modüler ve offline-uyumlu bir “Sistem Durumu” sağlık paneli içerir. Panel yerel CSS/JS ile çalışır; CDN veya public internet bağımlılığı yoktur.

Panel sekmeleri:
- **Genel Bakış**
- **Bağlantılar**
- **Depolama**
- **Çalışma Zamanı**
- **Güvenlik & Yapılandırma**
- **Tanılama**

Panelde gizli değerler (API anahtarı/parola/token vb.) açık gösterilmez; yalnızca tanımlı/eksik durum bilgisi sunulur. Depolama yolu düğmeleri klasör açmayı denemek yerine tam yolu panoya kopyalar; kullanıcı bu yolu Windows Dosya Gezgini adres çubuğuna yapıştırıp Enter ile açar.

Sağlık kontrolleri güvenli, hafif ve yan etkisiz olacak şekilde tasarlanmıştır; public internet endpoint çağrısı gerektirmez. Otomatik yenileme yaklaşık 120 saniye aralığında tutulur ve sayfa yenileme düğmesiyle manuel yenileme desteklenir.

İlgili odak testleri:

```r
source("tests/testthat.R", encoding = "UTF-8")

testthat::test_file("tests/testthat/test-health-check-formatters.R")
testthat::test_file("tests/testthat/test-health-check-paths.R")
testthat::test_file("tests/testthat/test-health-check-env-contract.R")
testthat::test_file("tests/testthat/test-health-check-runtime-contract.R")
```

### Üretim Sertleştirme ve Upload Testleri
Son üretim sertleştirme kapsamında aşağıdaki testler ana test koşumuyla uyumlu hâle getirilmiştir:

```r
source("tests/testthat.R", encoding = "UTF-8")

testthat::test_file("tests/testthat/test-production-contracts.R")
testthat::test_file("tests/testthat/test-db-refactor-contract.R")
testthat::test_file("tests/testthat/test-chat-message-formatting-refactor-contract.R")
testthat::test_file("tests/testthat/test-claude-code-document-extractors-refactor-contract.R")
testthat::test_file("tests/testthat/test-claude-code-document-extractors-maintainability-contract.R")
testthat::test_file("tests/testthat/test-upload-size-policy.R")
testthat::test_file("tests/testthat/test-file-manager-upload-limit-ui.R")
testthat::test_file("tests/testthat/test-sse-worker-export-contract.R")
testthat::test_file("tests/testthat/test-server-live-user-provider-contract.R")
testthat::test_file("tests/testthat/test-offline-baseline-contract.R")
testthat::test_file("tests/testthat/test-mcp-session-user-id-contract.R")
testthat::test_file("tests/testthat/test-mcp-path-fallback-contract.R")
testthat::test_file("tests/testthat/test-mcp-debug-output-contract.R")
testthat::test_file("tests/testthat/test-logging-console-color-policy.R")
```

`tests/testthat.R` ana koşucusu sıkı modda kalmalıdır: `stop_on_failure = TRUE` ve `stop_on_warning = TRUE`. Bu nedenle üretim sözleşmesi testleri geniş, uyarı üretebilecek recursive kaynak taramalarından kaçınmalı; kritik boot/runtime sözleşmelerini deterministik ve warning-safe biçimde doğrulamalıdır.
Bu kapsamda eklenen `test-offline-baseline-contract.R`, air-gapped Windows VM üretim profili için temel offline sözleşmeyi varsayılan test koşumunda doğrular. Test, runtime R/CSS/JS dosyalarında açık CDN/public asset bağımlılığı arar ve `stop_on_warning = TRUE` ile uyumlu kalması için warning-safe metin tarama yaklaşımı kullanır. Daha geniş offline tarama hâlâ `MERGEN_STRICT_OFFLINE_TESTS=true` ile opsiyonel olarak çalıştırılır.

Bakım yapılabilirlik takibi için `tests/scripts/maintainability_report.R` script’i repo kökünden çalıştırılabilir. Bu script test koşucusunu değiştirmez; büyük dosyaları, yaklaşık satır sayılarını ve fonksiyon sayılarını raporlayarak kontrollü refactor kararlarını destekler. `library_queries.R`, sorgu bilgi tabanı niteliğinde olduğu için bu raporda ayrıca değerlendirilmelidir.

Bilge Yolaç doküman işleme hattında extractor sorumlulukları ayrı dosyaya taşınmıştır. `R/helpers_claude_code_document_extractors.R`; ikili doküman uzantı politikası, PDF/Excel/DOCX metin çıkarımı, destek dizini hazırlığı, cache adı temizleme ve yerel office reader template yolu çözümleme işlerinden sorumludur. `R/helpers_claude_code_documents.R` ise rehber/manifest üretimi, inline payload oluşturma, doküman prompt’u hazırlama, doküman bağlamı kurma ve doküman özetleme yardımcılarına odaklanır. Bu ayrım `global.R` kaynak sırasında extractor dosyasının `helpers_claude_code_documents.R` öncesinde yüklenmesini gerektirir.

Son MCP/loglama sertleştirme güncellemeleriyle dosya çözümleme hattı daha güvenli hâle getirilmiştir. `helpers_mcp_tools$get_session_user_id()` artık yalnızca scalar kullanıcı kimliği döndürür ve dosya kayıt defteri olan `current_session_files` alanını kullanıcı kimliği gibi kullanmaz. MCP path çözümleme tarafında `normalize_excel_path` için yerel fallback korunur; böylece worker veya izole test bağlamlarında global helper eksikliği geç hata üretmez. Ayrıca `[RESOLVE]` debug çıktıları üretimde raw `cat()` ile konsola basılmaz; `MERGEN_MCP_DEBUG=true` veya `options(mergen.mcp.debug = TRUE)` ile geçici olarak açılabilen kontrollü debug logger üzerinden geçer. Windows VM üretim loglarında ANSI renk kodlarının karışmasını önlemek için konsol renkleri de varsayılan kapalıdır (`MERGEN_LOG_CONSOLE_COLORS=false`).

Son üretim sertleştirme kontrolleri kapsamında `global.R` kaynak yükleme manifesti, secret/token sızıntısı, runtime public URL/CDN bağımlılığı ve kritik üretim dosyalarının UTF-8 parse edilebilirliği ayrı sözleşme testleriyle korunur. Runtime network-boundary testi R yorumlarını (parse/deparse), JS/CSS yorumlarını, SVG namespace adresini (`http://www.w3.org/2000/svg`), `example.com/.org/.net` dokümantasyon adreslerini ve kurum içi/intranet uçlarını (`localhost`, `test.local`, `korykos`, `mergen`, `wiki.sirket.com`, `.local/.lan/.intra/.internal`) yanlış pozitif saymaz. Offline olarak repoya alınmış `www/js/highlight.min.js` ve `www/css/all.min.css` dosyaları vendored asset kabul edildiği için içlerindeki upstream lisans/proje URL’leri runtime internet bağımlılığı olarak değerlendirilmez. Kuruma özel ek iç URL desenleri gerekiyorsa `MERGEN_ALLOWED_INTERNAL_URL_REGEX` test ortamında opsiyonel allowlist olarak kullanılabilir.

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

## Akıl Yürütme Deneyimi (Thinking=TRUE Modeller)

Thinking yeteneği açık olan modellerde premium bir akıl yürütme katmanı devreye alınır. Eski "Düşünüyorum" yılan animasyonu akıştan tamamen kaldırılmıştır (`typing-indicator.css`, `typing_animation.js`, `ui.R` kaydı ve `app_core.js` içindeki eski MutationObserver temizliği).

### Premium Reasoning Card
- `premium_reasoning.js` ile yönetilen durum makinesi: `idle → preparing → thinking → streaming → interrupted/error`
- 5 fazlı döngüsel akıl yürütme animasyonu
- `MM:SS` formatında geçen süre sayacı
- `FLICKER_GUARD_MS=420` ve `MIN_VISIBLE_MS=1200` kuralları ile hızlı yanıt titremesinin engellenmesi
- düşünmeden akışa geçerken yumuşak durum geçişi (`premiumReasoningStreamStart`)
- hata ve durdurma durumlarında ayrı görsel sinyal
- **Panel model çözümü**: Kodlama Desteği ve Excel Analizi gibi düşünme modeline bağlı araçlarda panelin model etiketi, istemci tarafında doğrudan seçili modelden değil `tool-resolved model` sonucundan hesaplanır.
- **`simulated` modu**: Yalnızca akışın gerçek reasoning içeriği taşımayacağı senaryolarda devreye girer. Düşünmeyen model akışlarında sunucudan `reasoning_delta` gelmediğinde istemci tarafında 1.8 sn aralıklarla sıralı sahte faz metinleri gösterilir: *Soru çözümleniyor → Bağlam toplanıyor → Yanıt planlanıyor → Cevap yazılıyor*.

### Canlı Düşünce Akışı Paneli
- Sahte durum cümleleri yerine modelin gerçek düşünce akışının token-token aktarımı
- Daraltılabilir ve iç kaydırmalı panel yapısı
- `completed/interrupted` sonrasında panelin balon içinde kalıcı görünümü
- Düşünmeyen modelde yanıt akışı başlar başlamaz panel balona taşınmaz; sönümlenerek kaldırılır

### Model Bazlı Reasoning Request Overrides
- Bazı OpenAI-uyumlu yerel uçlar reasoning akışını kendiliğinden ayrı `delta$reasoning` alanında üretirken, bazı thinking modeller açık istek alanı bekleyebilir.
- Bu nedenle `R/config_api.R` içindeki `local_model_capabilities[[model]]$request_overrides` alanı üretim sözleşmesinin parçasıdır.
- Gemma tarzı thinking modeller için gerekli olduğunda istek gövdesine şu alan eklenir:
  ```r
  request_overrides = list(
    chat_template_kwargs = list(
      enable_thinking = TRUE
    )
  )
  ```
Bu override `apply_model_request_overrides(...)` ile hem true SSE streaming yoluna hem de non-streaming LLM çağrılarına uygulanır.
`R/helpers_llm_api.R` içindeki non-streaming LLM yolunda da istek gövdesi kurulduktan (ve sıcaklık/temperature işlemleri tamamlandıktan) sonra `apply_model_request_overrides(body, selected_model)` uygulanır; böylece thinking/reasoning modellerde SSE streaming ile non-streaming/tool/fallback akışları aynı davranış sözleşmesini korur.
True streaming future worker içinde de aynı davranışın korunması için `apply_model_request_overrides` fonksiyonu worker globals listesine taşınmalıdır.
Kimi tarzı modellerde reasoning ayrı `delta$reasoning` alanından gelebilir; Gemma tarzı modellerde ise `enable_thinking` gönderilmezse akış yalnızca normal `delta$content` olarak dönebilir ve `MB_Messages.ReasoningContent` boş kalabilir.
True SSE streaming akışında worker prewarm/export listesi ile `tracked_future_promise(..., globals = list(...))` sözleşmesi aynı kritik yardımcıları taşımalıdır. Özellikle reasoning delta, stop-file kontrolü ve model bazlı request override davranışı için `append_stream_reasoning_line`, `streaming_should_stop`, `apply_model_request_overrides` ve ilgili yardımcıların worker tarafında görünür kalması gerekir. Bu sözleşme `test-sse-worker-export-contract.R` ile korunur.

### Kalıcılık ve Geçmiş Sohbetler
- Akıl yürütme metni artık yalnızca yanıt HTML’ine gömülmez; `MB_Messages.ReasoningContent` sütununda da saklanır
- Non-streaming yolunda da reasoning metni worker çıktısından mesaj kaydına kadar taşınır; düşünen model yanıtlarında `MB_Messages.ReasoningContent` artık dolu kaydedilir
- Geçmişten yüklenen mesajlarda `ReasoningContent` varsa arşiv bloğu (`<details class="reasoning-block">`) otomatik render edilir
- Eski şema ile uyumluluk için sütun yoksa sessiz geri dönüş (fallback) korunur
- Veritabanı geri dönüş davranışı `ReasoningContent` için daha dar ve kontrollü tutulur; kullanıcı bazlı geçmiş yükleme akışları da daha sağlamlaştırılmıştır
- Gerçek düşünce metni olmayan `simulated` akışlar kalıcılığa yazılmaz ve geçmişte reasoning arşivi olarak dönmez

#### Üretim Debug Davranışı
Reasoning stream teşhis çıktıları üretimde varsayılan olarak kapalıdır.
Geçici teşhis gerektiğinde `MERGEN_REASONING_DEBUG=TRUE` ayarlanarak `[REASONING DEBUG]` satırları yeniden etkinleştirilebilir.
Normal üretim koşumunda bu değişken kapalı kalmalıdır; aksi halde SSE akışında gereksiz console/log gürültüsü oluşur.


### Düşünme Kabuğunun Ortak Açılması ve Flicker Koruması
- `server_send_message.R`, hem düşünen hem düşünmeyen model yolunda `#typing-animation-wrapper` kabuğunu `premiumReasoningStart` ile birlikte açar
- Sunucudan `simulated` bayrağı (`thinking_model_active` terslenmiş değer) istemciye taşınır
- Klasik "Düşünüyorum" halkası yerine premium panel devreye girsin diye kabuk `data-panel-takeover="true"` ile işaretlenir ve boş içerikle eklenir
- `app_core.js` içindeki `MutationObserver`, `data-panel-takeover="true"` işaretli kabukta `TypingAnimationManager.create(...)` çağrısını atlayarak flicker oluşumunu engeller
- İstemci tarafında `sanitizeModelLabel()` savunması ile panel başlığında `[object Object]` gibi bozuk model etiketleri engellenir

### Görsel Durum Geri Bildirimi (Shimmer)
- Panel alt kenarındaki sola-sağa akan mor shimmer animasyonu (`rp-shimmer`) yeniden etkinleştirilmiştir
- Shimmer; `completed`, `interrupted/stopped` ve `error` durumlarında otomatik kapanır
- `prefers-reduced-motion` tercihinde shimmer devre dışı kalır

### Şema Geçişi
```sql
ALTER TABLE MB_Messages ADD ReasoningContent NVARCHAR(MAX) NULL;
```

Uygulama, klasik tek-dosya Shiny yaklaşımından daha modüler bir yapıya sahiptir. Ana yapı aşağıdaki gibidir:

### `app.R`
Gerçek giriş noktasıdır. Şunları yapar:
- önce zorunlu boot dosyalarının varlığını doğrular (`R/utils_safe_source.R`, `global.R`, `ui.R`, `server.R`),
- `R/utils_safe_source.R` dosyasını yükler,
- ortak `safe_source()` ile sırasıyla `global.R`, `ui.R`, `server.R` dosyalarını çağırır,
- `www/` alt klasörlerini resource path olarak kaydeder,
- uygulamayı başlatır.

Son hardening güncellemeleriyle `app.R` tarafında açık boot doğrulaması uygulanır: `validate_boot_state()` ile `safe_source`, `ui` ve `server` yükleri doğrulanır; beklenen durum sağlanmazsa başlangıç fail-fast mantığıyla durdurulur. Kod akışında `create_mergen_app()` ve `run_mergen_app()` yardımcılarının davranış/sözleşmesi korunmalıdır. Ayrıca `MERGEN_RUN_APP` artık gevşek "false dışı her şey" yaklaşımı yerine açık truthy/falsy normalizasyonuyla yorumlanır; `run_mergen_app()` yalnızca env’den gelen değeri değil, çağrıdaki açık `port` girdisini de yeniden normalize eder ve geçersiz/boş/sayısal olmayan/aralık dışı portları deterministik olarak `8009`a düşürür.

#### Üretim Başlatma Sözleşmesi

Windows VM üretim başlatma akışı iki katmanlıdır:

1. VM üzerindeki yerel başlatıcı:
   - `C:\MergenLauncher\start_mergen_prod.bat`

2. Uygulama klasöründeki gerçek üretim başlatıcısı:
   - `run_mergen_prod.bat`

Ağ paylaşımı doğrudan `cmd.exe` çalışma dizini yapılamadığı için kısayollar doğrudan UNC path üzerindeki `run_mergen_prod.bat` dosyasını hedeflememelidir. Bunun yerine VM’deki yerel başlatıcı kullanılmalıdır. Yerel başlatıcı `\\rehisds\uygulamalar` paylaşımını geçici olarak bir sürücü harfine map eder ve gerçek uygulama başlatıcısını mapped-drive yolu üzerinden çağırır.

Önerilen üretim kısayolu:

```text
Target:
C:\MergenLauncher\start_mergen_prod.bat

Start in:
C:\MergenLauncher
```

`run_mergen_prod.bat`, uygulama kök dizininde kalır ve mapped-drive üzerinden çağrıldığında `%~dp0` ile gerçek uygulama klasörünü bulur. Başlatma sırasında:

* `MERGEN_HOST=0.0.0.0`
* `MERGEN_PORT=8009`
* `SSO_ENABLED=TRUE`

değerleri üretim profili olarak ayarlanır.

`run_mergen_prod.bat`, Rscript yolunu sabit bir R sürümüne bağlamaz. `C:\Program Files\R` altında bulunan en yeni `R-*` klasörünü dinamik olarak seçer; örneğin `C:\Program Files\R\R-4.5.1\bin\Rscript.exe`. Böylece ileride daha yeni bir R sürümü kurulduğunda başlatıcı elle güncellenmeden en yeni Rscript’i kullanabilir.

Başlatıcı, uygulamayı doğrudan `shiny::runApp('.')` ile değil, üretim giriş noktası olan `run_mergen_prod.R` üzerinden çalıştırmalıdır. Bu sayede `.Renviron` yükleme, repo kökü çözümleme, ortam değişkeni kontrolleri, `MERGEN_RUN_APP` davranışı ve `run_mergen_app()` üretim sözleşmesi korunur.

Başlatma öncesinde R oturumu tanılaması ve paket görünürlüğü kontrol edilir. Özellikle şu hata sınıfı için bu kontrol önemlidir: RStudio’da uygulama çalışırken `.bat` dosyasından başlatıldığında paketlerin eksik görünmesi. Bu durum genellikle farklı `Rscript.exe` veya farklı `.libPaths()` kullanılmasından kaynaklanır. Başlatıcı artık kullanılan Rscript’i, R sürümünü ve `.libPaths()` değerlerini konsola basar.

UNC path ve Türkçe karakter kaynaklı kırılganlığı azaltmak için üretim başlatma akışında şu ilkeler korunmalıdır:

* Kısayol doğrudan `\\rehisds\...` altındaki `.bat` dosyasını hedeflememelidir.
* Yerel VM başlatıcısı mapped-drive yolu üretmelidir.
* `run_mergen_prod.bat` içinde `pushd "%APP_DIR%."` kullanılmamalıdır; gerekiyorsa `pushd "%APP_DIR%"` tercih edilmelidir.
* Büyük `if (...)` blokları içinde parantez içeren `echo` satırları kullanılmamalıdır; CMD parse hatalarını önlemek için gerekirse `goto` tabanlı hata blokları tercih edilmelidir.
* Üretim portu `8009` olarak korunmalıdır.

Başlatma:

```bat
C:\MergenLauncher\start_mergen_prod.bat
```

Uygulama klasöründeki gerçek üretim başlatıcı:

```bat
run_mergen_prod.bat
```

Üretim R giriş noktası:

```r
run_mergen_prod.R
```

#### Üretim Log İzleme

Normal uygulama çalışma zamanı loglarını canlı izlemek için `view_latest_mergen_app_log.bat` kullanılmalıdır. Bu dosya `logs` klasöründeki en güncel `mergen_*.log` dosyasını salt-okunur biçimde izler; loga yazmaz, uygulamayı durdurmaz ve kullanıcı işlemlerini etkilemez.

`view_latest_mergen_app_log.bat` de UNC path sorunu yaşamayacak şekilde mapped-drive mantığıyla çalışmalıdır. Dosya doğrudan UNC çalışma dizini varsayımına dayanmamalı ve `pushd "%~dp0"` gibi UNC-kırılgan bir kalıba geri dönmemelidir.

Üretim ortamında iki farklı log kullanımı ayrılmalıdır:

* `logs/run_mergen_prod_console.log` veya başlatıcı konsol çıktısı: üretim başlatıcının Rscript, paket preflight, boot ve startup hata teşhisi için kullanılır.
* `logs/mergen_YYYYMMDD.log`: uygulamanın normal çalışma zamanı loglarıdır.

Canlı uygulama log izleme:

```bat
view_latest_mergen_app_log.bat
```

Notepad/Notepad++ ile log açmak yalnızca anlık inceleme için uygundur; canlı takip için `view_latest_mergen_app_log.bat` tercih edilmelidir.

#### Üretim Başlatıcı Self-Test

VM üzerinde üretim başlatma zincirinin tekrar bozulmaması için yerel bir self-test bulunur:

```bat
C:\MergenLauncher\test_mergen_prod_launcher.bat
```

Bu test uygulamayı başlatmaz. Yalnızca üretim başlatma ortamını doğrular:

* `\\rehisds\uygulamalar` paylaşımının mapped-drive ile erişilebilirliği
* gerçek `MERGEN Bilge` uygulama klasörünün keşfi
* `run_mergen_prod.bat`, `run_mergen_prod.R`, `app.R` dosyalarının varlığı
* `run_mergen_prod.bat` içinde `MERGEN_PORT=8009` sözleşmesi
* UNC-kırılgan `pushd "%APP_DIR%."` kullanımının bulunmaması
* `view_latest_mergen_app_log.bat` dosyasının UNC-kırılgan `pushd "%~dp0"` kalıbına dönmemesi
* en yeni Rscript’in `C:\Program Files\R\R-*` altından dinamik bulunması
* R `.libPaths()` ve gerekli paket görünürlüğü
* `.Renviron` / zorunlu ortam değişkenleri
* `8009` portunun durumu

Self-test, Türkçe karakter mojibake sorunlarını azaltmak için `Geliştirme` gibi path parçalarını hard-code etmemeli; mapped-drive altında `run_mergen_prod.bat` dosyasını arayarak gerçek uygulama klasörünü keşfetmelidir. Paket listesi ve ortam değişkeni listesi R’ye doğrudan kırılgan `-e` quoting ile değil, ASCII-safe geçici R script yaklaşımıyla aktarılmalıdır.

Çalıştırma:

```bat
C:\MergenLauncher\test_mergen_prod_launcher.bat
```

Açılan pencerenin kapanmaması için alternatif:

```bat
cmd /k "C:\MergenLauncher\test_mergen_prod_launcher.bat"
```

Başarılı sonuçta test özeti `[RESULT] PASSED` göstermelidir.


### `global.R`
Küresel yapılandırma ve yükleme sırasını yönetir. Şunları içerir:
- UTF-8 ve locale ayarları
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
Sunucu mantığının ana birleşim ve bağlama noktasıdır. Ancak artık tüm kurulum ayrıntılarını tek başına taşımaz; bazı başlangıç ve yardımcı kurulumları `R/server_init_*.R` dosyalarına ayrılmıştır. Sohbet sıfırlama/geçiş akışlarında hoş geldin ekranı yeniden çizilmeden önce kayıtlı söyleşi meta verisinin yenilenmesi, Son Konuşmalar listesinin güncel kalması için korunur.

`server.R` başlıca şunları koordine eder:
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
- modüller arası bağlama ve son fonksiyon kayıtları

Amaç, `server.R` dosyasını iş mantığının tek sahibi yapmak değil; uygulamanın **composition root** katmanı olarak temiz ve okunabilir tutmaktır.
Recency odaklı UI bileşenlerinde uygun olduğunda çıplak oluşturulma zamanı yerine `last_message_timestamp` önceliklendirilir (`timestamp` yalnızca geri dönüş alanıdır).
SSO modunda kullanıcı kimliği başlangıçta geçici `0L` olabilir; bu nedenle kullanıcıya özel modüllere startup snapshot yerine canlı `current_user_id_provider` fonksiyonu geçirilmelidir. Dosya, kayıtlı söyleşi, geçmiş, galeri, destek ve performans gibi kullanıcı kapsamlı akışlar bu provider üzerinden gerçek kullanıcı kimliğini kullanım anında çözmelidir. Bu sözleşme `test-server-live-user-provider-contract.R` ile korunur.

---

## Yükleme Sırası ve Modüler Yapı

`global.R` içindeki yükleme sırası bilinçli olarak katmanlara ayrılmıştır:

Not: Ortak `safe_source()` helper’ı (`R/utils_safe_source.R`) önce normal `source(..., encoding = "UTF-8")` yolunu dener. Kodlama/BOM kaynaklı hata veya uyarı alırsa dosyayı ham bayt olarak okuyup UTF-8 BOM işaretini temizleyerek çoklu kodlama (UTF-8 / WINDOWS-1254 / latin1) ile yeniden çözmeyi dener; ardından metni parse/eval ederek hedef environment içine yükler. Bu davranış özellikle Windows VM ve BOM işaretli UTF-8 dosyalarında dayanıklılık sağlamak içindir.

### 1. Temel altyapı
- paketler
- ortak yardımcılar
- loglama
- rate limiter
- worker monitor helper
- yol ve dosya yardımcıları
- Excel okuyucu

Not: `R/config_logging.R` içindeki güvenli log sarmalayıcıları (`log_info`, `log_warn`, `log_error`, `log_debug`) hassas karakter verilerini redakte edecek şekilde korunur. Ancak `logger` içindeki `{ ... }` glue ifadelerinin çağıran ortamda çözülmesi bozulmamalıdır. Özellikle SSO akışlarında `{nchar(token)}` gibi ifadeler, generic bir ara wrapper içinde çağıran frame kaybedilerek çalıştırılırsa VM üzerinde gerçek runtime hatası üretebilir.
Konsol renkli loglama üretimde varsayılan kapalıdır; gerekirse yalnızca geçici yerel teşhis için `MERGEN_LOG_CONSOLE_COLORS=true` ile açılmalıdır.

### 2. Yapılandırma
- SSO
- dosya deposu
- karakterler
- sürüm geçmişi
- API
- Bilge Yolaç yapılandırması

### 3. Veritabanı ve SQL
- `R/helpers_db_connection.R`: DB bağlantısı, bağlantı bırakma, havuz sağlık kontrolü, worker tarafı DB bağlantısı ve DB parametre kodlama normalizasyonu
- `R/helpers_db_validation.R`: kullanıcı adı, sohbet başlığı ve mesaj içeriği doğrulama yardımcıları
- `R/helpers_chat_message_formatting.R`: veritabanından okunan mesajların uygulama içi mesaj nesnesine dönüştürülmesi; görsel mesaj, Chartlab, markdown, zaman damgası ve reasoning alanı biçimlendirmesi
- `R/helpers_database.R`: kullanıcı, sohbet, mesaj ve kalıcı kayıt veritabanı işlemleri
- `R/library_queries.R`: Proje ve Kaynak Analizi için hazır sorgu bilgi tabanı
- `R/config_sql_loader.R`: SQL dosyası yükleme ve sorgu yapılandırma altyapısı

Son modülerleşme güncellemeleriyle `helpers_database.R` içindeki bağlantı, doğrulama ve mesaj biçimlendirme sorumlulukları ayrı dosyalara taşınmıştır. Bu değişiklik davranış değiştirmeden bakım yapılabilirliği artırmak için yapılmıştır; `format_chat_messages()` gibi geriye dönük uyumluluk gerektiren fonksiyon adları korunmuştur. Source sırası kritik olduğu için `helpers_db_connection.R`, `helpers_db_validation.R` ve `helpers_chat_message_formatting.R`, `helpers_database.R` dosyasından önce yüklenmelidir.

### 4. Çekirdek yardımcılar
- dil yardımcıları
- mesaj biçimlendirme
- MCP araçları
- yol ve dosya yardımcıları
- dosya pipeline
- Excel okuyucu
- önizleme
- görsel galeri
- AI Uzman yardımcıları
- Bilge Yolaç yardımcıları

Not: MCP Excel yol çözümleme davranışı `utils_path_helpers`, `helpers_files`, `utils_excel_reader`, `helpers_mcp_tools` ve `helpers_send_message_core` yardımcılarının koordineli çalışmasına bağlıdır.

Not: MCP dosya çözümleme zincirinde kullanıcı kimliği, dosya kayıt defteriyle karıştırılmamalıdır. `current_session_files` yalnızca oturum dosyalarını temsil eder; kullanıcı kapsamı için scalar kullanıcı kimliği kullanılmalıdır. Araç/worker bağlamlarında path yardımcılarının eksik kalmaması için `helpers_mcp_tools` kendi güvenli fallback’lerini taşımalıdır.

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

### 7. Sunucu işleyicileri, init yardımcıları ve observer katmanı
Bu katman, `server.R` içindeki bağlama yükünü azaltmak için kullanılan yardımcı kurulum dosyalarını, işleyicileri ve observer kayıtlarını içerir. Özellikle sohbetten hoş geldin ekranına dönüşlerde kayıtlı söyleşi metadatası önce yenilenir, ardından ekran yeniden çizilir; böylece Son Konuşmalar görünümü stale kalmaz ve "bir adım geriden gelme" problemi önlenir.

- `R/server_session_cache.R`
- `R/server_init_forward_refs.R`
- `R/server_init_session_state.R`
- `R/server_init_chat_runtime.R`
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

Not: Aktif log dizini sabit `logs/` varsayımına bağlı değildir; `R/config_logging.R` üzerinden `MERGEN_LOG_DIR` ile override edilebilir. Log ayrıntı seviyesi de `MERGEN_LOG_THRESHOLD` ile çalışma anında yönetilebilir. Bu yaklaşım özellikle Windows VM üretim hazırlığı ve testlerde temp-sandbox izolasyonu için kullanılır.

---

## Dosya Depolama Altyapısı

Dosya depolama sistemi `R/config_file_store.R` içinde merkezi olarak tanımlanır.

### Temel kavramlar
- Kullanıcı bazlı klasör yapısı
- Kalıcı yükleme dizini
- JSON indeks dosyası
- Kullanıcıya görünen ad (display name) ile iç saklama adı ayrımı
- İndeks yazımlarında atomik güncelleme (geçici dosya + taşıma/kopyalama)
- Boş/bozuk indeks durumunda güvenli boş duruma düşme
- Bozuk indeks için `.corrupt_<timestamp>` yedeği alma
- Fallback listede gerektiğinde zaman damgalı/rastgele saklama önekini temizleyerek display name kurtarma
- Eksik indeks kayıtları için fallback dosya sistemi taraması
- Periyodik garbage collection
- GC zamanlayıcısında tek-seferlik başlatma koruması (aynı R oturumunda yeniden source/app restart ile döngü çoğaltmama)

### Dosya Yönetimi yenileme dayanıklılığı
Dosya Yönetimi yenileme akışı kullanıcı açısından rollback-safe olacak şekilde korunur: yenileme/rehydrate adımı hata verirse önceki bellek içi dosya durumu silinmez; başarılı yenilemede daha önce bağlama eklenmiş dosyalar yeniden işaretlenerek geri yüklenir.

### Dosya Boyutu Sınırı ve Katmanlı Doğrulama
Yükleme güvenliği üç katmanlıdır:
- Tarayıcı tarafı kontrol: `module_file_manager.R` içindeki istemci tarafı kontrol, dosya boyutunu Shiny upload başlamadan önce denetler.
- Shiny/request sınırı: `shiny.maxRequestSize`, HTTP upload düzeyinde üst sınır sağlar.
- Sunucu tarafı doğrulama: `validate_uploaded_file()` dosya varlığı, okunabilirlik, uzantı, güvenli dosya adı ve boyut sınırı gibi kontrolleri yapar.

Varsayılan üretim politikası dosya başına 25 MB’tır. Bu değer `MERGEN_UPLOAD_MAX_MB` / `mergen.upload_max_mb` hattı üzerinden yönetilir; ancak üretim davranışında büyük dosyaların UI’ı kilitlememesi için tarayıcı tarafı erken ret mekanizması temel güvenlik katmanı olarak korunmalıdır.

### Excel Analizi / MCP yol çözümleme dayanıklılığı
- Excel Analizi aracında, oturum dosya kayıt defteri ile fiziksel dosya yolu çözümleme zinciri güçlendirilmiştir.
- Özellikle Windows VM / SSO / MCP akışlarında `helpers_mcp_tools`, `helpers_files`, `utils_path_helpers`, `utils_excel_reader` ve `helpers_send_message_core` üzerinden dosya yolu yardımcıları daha dayanıklı çalışacak şekilde hizalanmıştır.
- Kritik yardımcılar (`path_exists_relaxed`, `resolve_readable_path`) araç ortamında güvenli biçimde erişilebilir tutulur; böylece aynı dosyanın Dosya Yönetimi’nde görünmesine rağmen Excel aracında “dosya bulunamadı” hatası üretilmesi engellenir.
- Windows kısa yol (8.3) davranışı nedeniyle fiziksel path basename’i her zaman kullanıcı dostu/orijinal dosya adıyla aynı olmayabilir; kullanıcıya görünen ad için `display`/`display_name` alanı esas alınmalıdır.
- Bu davranış için küçük bir regresyon testi eklendi: MCP Excel çözümleme zincirinde helper ortamı ve session registry tabanlı dosya bulma yeniden test kapsamına alınmıştır.

### Son bakım notu (mimari)
Son bakım turunda özellikle dosya yöneticisi tarafında davranış değiştirmeden tekrar eden politika metinleri azaltılmış, izinli uzantı/politika yardımcıları merkezileştirilmiş ve tekrar eden satır/aksiyon/bağlama-ekle hücre üretimleri küçük yardımcı yapılarla ayrıştırılmıştır.

### Önemli yollar
- `MERGEN_FILES_ROOT`
- `MERGEN_UPLOADS_DIR`
- `MERGEN_MCP_BASE_DIR`
- `MERGEN_INDEX_PATH`
- `MERGEN_LOG_DIR`
- `MERGEN_LOG_THRESHOLD`

Not: Dosya deposu kökleri artık ortam değişkenleriyle override edilebilir yapıdadır (`MERGEN_FILES_ROOT`, `MERGEN_UPLOADS_DIR`, `MERGEN_INDEX_PATH`) ve testlerde izole geçici dizinlerle (temp sandbox) doğrulanacak şekilde özellikle test edilebilir tutulur.

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

## Test Altyapısı ve Çalıştırma

Bu repodaki test altyapısı `testthat` tabanlıdır. Ana çalıştırıcı dosya `tests/testthat.R`, test bağlamı/bootstrap helper dosyası ise `tests/testthat/helper_bootstrap.R` olarak konumlanır.

`helper_bootstrap.R`, testlerde dosya sistemi ve log yollarını temp sandbox ortam değişkenleriyle izole edecek şekilde kurgulanmıştır; özellikle `MERGEN_LOG_DIR` ve dosya-deposu köklerinin (`MERGEN_FILES_ROOT`, `MERGEN_UPLOADS_DIR`, `MERGEN_INDEX_PATH`, `MERGEN_MCP_BASE_DIR`) sözleşmesi bu izolasyona uyumlu kalmalıdır.

Mevcut birim test kapsamı çekirdek olarak şu alanları içerir:
- `safe_source`
- BOM işaretli UTF-8 dosyalarının `safe_source()` ile güvenli yüklenmesi
- `tracked_future_promise` görev defteri temizleme davranışı
- `register_session_cleanup_on_end()` ve `safe_unlink_if_exists()` yardımcılarının oturum kapanışı/temizlik davranışı; sahte test oturumlarının `list` yanında `environment` biçiminde de gelebilmesi
- DB doğrulama yardımcıları
- dosya indeksleme yardımcıları
- worker monitor yardımcıları
- `send_message` çekirdeğindeki araç ailesi / akış profili kararları
- `safe_join_path` güvenli yol birleştirme davranışı (path traversal reddi, mutlak yol reddi, Windows ayraç normalizasyonu ve Türkçe karakterli güvenli yollar)
- `config_logging.R` güvenli log sarmalayıcıları ve `dbg_dump()` redaksiyon davranışı; ayrıca `logger` glue ifadelerinin çağıran ortamda güvenli çözülmesi
- `app.R` giriş noktası için boot sözleşmeleri (`boot_step(...)`, `validate_boot_state()`, `create_mergen_app()`, `run_mergen_app()`) artık test kapsamındadır ve Windows VM uyumlu kurgulanmıştır; bu kapsam `MERGEN_RUN_APP` için sıkı autorun-flag ayrıştırmasını ve açık `run_mergen_app(port = ...)` geçersiz girişlerinde `8009` fallback sözleşmesini de korur
- `config_logging.R` log wrapper regresyon testleri, çağıran frame’de glue çözümlemesinin korunmasını ve aktif log dizini davranışını doğrular; log/debug dosyaları `MERGEN_LOG_DIR` (yoksa varsayılan aktif dizin) altında ele alınır
- repo quality-gate testleri kırılgan ham `readLines(..., encoding = "UTF-8")` taraması yerine script/entrypoint sözleşmelerini parse-tabanlı doğrulamayla sınar; bu yaklaşım Windows VM’de daha dayanıklıdır
- `test-atomic-write.R`, UTF-8 doğruluğunu locale kırılgan metin okumaları yerine ham-bayt/deterministik UTF-8 güvenli beklentilerle sınar
- file-store index testleri Windows-safe, shape-agnostic beklentiler kullanır; Windows VM’de tek kayıtlı Türkçe display-name kenar durumunda JSON sadeleştirme/yükleyici şekil farklarının yanlış negatif üretmesini engelleyip stabil sözleşmeyi doğrular
- thinking/reasoning modeller için `request_overrides` sözleşmesi
- true SSE yolunda `apply_model_request_overrides(...)` kullanımının korunması
- future worker globals içinde `apply_model_request_overrides` taşınması
- SSE delta ayrıştırıcısının `content`, `reasoning`, `reasoning_content` ve atomic delta/message edge-case davranışı
- `MERGEN_REASONING_DEBUG` varsayılanının üretimde kapalı kalması
- Bu davranış için regresyon kapsamı `tests/testthat/test-llm-reasoning-request-overrides.R` ve `tests/testthat/test-llm-sse-delta-reasoning-contract.R` dosyalarında tutulur.
- Yeni/sertleştirilen sözleşme testleri: `test-safe-source-encoding-contract.R`, `test-global-source-manifest-contract.R`, `test-production-env-policy-contract.R` ve güncellenen `test-llm-reasoning-request-overrides.R`; bu kapsam UTF-8 BOM + Türkçe `safe_source()` yükleme davranışını, `safe_source()` içinde gerçek syntax hatalarının yutulmamasını, `global.R` kritik source sırasını, testte future cluster kapatma/sequential güvenliğini, `MERGEN_RUN_APP` sıkı truthy/falsy ayrıştırmasını, üretimde 25 MB upload üst sınırı sözleşmesini ve non-streaming `request_overrides` paritesini doğrular.

Testler repo kök dizininden çalıştırılmalıdır. Özellikle Windows VM ortamında testleri mümkünse temiz bir R oturumunda çalıştırmak tercih edilir. Promise/later tabanlı testlerde tek bir `later::run_now()` çağrısının her zaman yeterli olmayabileceği unutulmamalı; testler gerekiyorsa later kuyruğunu birkaç tur tüketerek kararlı son durumu beklemelidir. `summary` reporter ile başarılı koşuda yalnızca dosya adları, noktalar ve `== DONE ==` görülebilir; bu normaldir. Fail durumunda genellikle `Failed`, `Error`, `Warnings` veya `Test failures` benzeri bloklar görünür.

Windows VM ortamında gömülü NUL bayt içeren karakter dizileri normal R stringleri içinde güvenilir biçimde temsil edilemediği için bu durum doğrudan birim testte bire bir doğrulanmaz. Buna rağmen `safe_join_path()` içindeki çalışma zamanı NUL koruması korunur. Test stratejisi bunun yerine Windows üzerinde güvenilir biçimde doğrulanabilen güvenlik kurallarına odaklanır.

`register_session_cleanup_on_end()` yardımcısında test ve Shiny benzeri sahte oturum nesnelerinin `environment` olarak gelebileceği dikkate alınmalıdır. Bu nedenle helper yalnızca `list` değil, `onSessionEnded` metodu taşıyan `environment` oturum nesneleriyle de uyumlu kalmalıdır; ilgili regresyon `tests/testthat/test-session-cleanup.R` altında korunmaktadır.

### `tests/scripts/` doğrulama akışı
- `tests/scripts/parse_sanity_check.R`: repo kökünden UTF-8 parse/syntax için hızlı bir sanity kontrolü yapar.
- `tests/scripts/smoke_app_boot.R`: tam uygulamayı ayağa kaldırmadan `app.R` dosyasını source eder; `safe_source`, `ui`, `server`, `create_mergen_app()` varlığını doğrular ve `shiny.appobj` üretilebildiğini kontrol eder.
- `tests/scripts/run_ci_local.R`: GitHub CI akışının yerel eşdeğeridir; parse/smoke adımlarından sonra oturum kirlenmesini önlemek için `tests/testthat.R` çalıştırmasını CLEAN CHILD R SESSION içinde yapar.
- `tests/scripts/run_vm_preflight_real.R`: gerçek on-prem Windows VM üzerinde, gerçek ortam değişkenleriyle production-benzeri preflight kontrolü için kullanılır; önce zorunlu env guard (`LOCAL_LLM_ENDPOINT`, `DB_DSN`, `AI_KEYS_MASTER`) çalışır, sonra aktif yapılandırılmış yazılabilir yollar (aktif log dizini dahil) ve boot doğrulamaları yapılır.

Not: GitHub CI ve `run_ci_local.R` gerçek on-prem DB/LLM bağlantısına gitmez; yalnızca placeholder env değişkenleriyle boot/yapı/test doğrulaması yapar. Gerçek VM tarafı entegrasyon varsayımları `run_vm_preflight_real.R` ile sınanmalıdır.

GitHub Actions iş akışı Ubuntu ve Windows üzerinde, R 4.4 ve R 4.5 kombinasyonlarında sırasıyla (1) parse sanity check, (2) app boot smoke, (3) testthat adımlarını çalıştırır. Bu CI hattı bilinçli olarak altyapıdan bağımsızdır ve gerçek kurum içi LLM/DB sistemlerine bağlanmaz.

### Tüm testleri çalıştırma
```r
source("tests/testthat.R", encoding = "UTF-8")
```

### `test_dir` ile doğrudan çalıştırma
```r
testthat::test_dir("tests/testthat", reporter = "summary")
```

### Tek bir test dosyasını çalıştırma
```r
testthat::test_file("tests/testthat/test-safe-source.R")
```

### Sertleştirme sözleşmelerini hızlı doğrulama
```r
source("tests/testthat.R", encoding = "UTF-8")

testthat::test_file("tests/testthat/test-safe-source-encoding-contract.R")
testthat::test_file("tests/testthat/test-global-source-manifest-contract.R")
testthat::test_file("tests/testthat/test-production-env-policy-contract.R")
testthat::test_file("tests/testthat/test-llm-reasoning-request-overrides.R")
testthat::test_file("tests/testthat/test-source-manifest-contract.R")
testthat::test_file("tests/testthat/test-secret-leak-contract.R")
testthat::test_file("tests/testthat/test-runtime-network-boundary-contract.R")
testthat::test_file("tests/testthat/test-production-contracts.R")
```

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

### 3A. `server.R` temiz kalmalı
Yeni özellik eklerken mümkün olduğunda iş mantığını uygun `module_*`, `helper_*`, `server_handler_*`, `server_observers_*` veya `server_init_*` dosyalarına yerleştirin.

Tercih edilen yaklaşım:
- `server.R` dosyasını composition root olarak tutmak
- oturum-yerel başlangıç kurulumlarını `server_init_*` dosyalarına ayırmak
- iş mantığını doğrudan `server.R` içine gömmemek
- geniş ve riskli refaktör yerine küçük, kontrollü ayırmalar yapmak

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

### Testler Windows VM'de beklenmedik şekilde hata veriyor
Kontrol edin:
- çalışma dizininin repo kökü olup olmadığını
- testlerin, uygulama ile kirlenmiş aynı R oturumunda çalıştırılıp çalıştırılmadığını
- helper bootstrap’ın repo kökünü doğru çözüp çözmediğini
- mümkünse temiz bir R oturumunda yeniden deneme yapmayı
- Windows VM’de bazı düşük seviye string uç durumlarında (özellikle gömülü NUL beklentilerinde) farklılık olabileceğini ve helper testlerinde base R stringlerinde bayt-birebir kurulum zorlaması yerine repodaki Windows uyumlu test stratejisinin izlenmesi gerektiğini
- Windows VM üzerinde helper/test script çalıştırırken code-page regresyonlarını izole ederek incelemeyi; kullanıcıya görünen Türkçe metinlerin UTF-8 kalmasını, yeni eklenen kod sembollerinin/identifier adlarının ise mümkün olduğunda ASCII-safe tutulmasını
- Windows VM’de ham JSON metni veya tek kayıtlı Türkçe display-name yapısı etrafındaki hataların her zaman uygulama regresyonu olmayabileceğini; önce test şekli/encoding kaynaklı farklılıkları elemek ve katı iç-shape yerine sözleşme düzeyi doğrulama tercih etmek gerektiğini

### Yerelde açılıyor / SSO'da açılıyor ama diğer modda davranış farklı
Kontrol edin:
- `SSO_ENABLED=FALSE` ve `SSO_ENABLED=TRUE` akışlarının aynı başlangıç yardımcılarını farklı bağlamlarda çağırabildiğini
- başlangıç korumalarında gereksiz reaktif bağımlılık kurulup kurulmadığını
- startup guard yapılarında `reactiveVal()` yerine düz oturum-yerel durumun daha uygun olup olmadığını
- özellikle `R/server_observers_startup.R` içindeki başlangıç yükleme korumalarını

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
