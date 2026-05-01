# MERGEN Bilge

MERGEN Bilge, Türkçe odaklı, kurumsal kullanım için tasarlanmış, R/Shiny tabanlı gelişmiş bir yapay zekâ asistanı uygulamasıdır. Uygulama; sohbet, dosya analizi, görsel üretimi, özetleme, süreç rehberliği, sesli etkileşim, destek merkezi, yönetici panelleri ve Bilge Yolaç kod ajanı deneyimini tek bir on-prem arayüzde birleştirir.

MERGEN adı, Türk ve Altay mitolojisinde bilgeliği, isabetli düşünceyi ve yol göstericiliği çağrıştırır. Uygulamadaki karakter sistemi de bu mitolojik temadan beslenir ve kullanıcı deneyimine hem görsel hem davranışsal bir katman ekler.

Dokümantasyon notu: Bu README ürün kapsamını ve güncel mimari yönü özetler. Kod ajanları ve uygulama bakım kuralları için `CLAUDE.md`, kullanıcıya dönük asistan davranış ilkeleri için `ai_rehber.md` kullanılmalıdır.

---

## Genel Özellikler

### Yapay zekâ söyleşi deneyimi
- Türkçe odaklı gerçek zamanlı sohbet
- SSE/streaming yanıt üretimi
- Kod bloklarında sözdizimi vurgulama
- Takip soruları ve mesaj eylemleri
- Farklı yerel model ve araç aileleriyle çalışma
- Thinking/reasoning destekli modeller için akıl yürütme kartı ve canlı düşünce paneli

### Dosya ve veri odaklı çalışma
- Excel, PDF, Word, CSV ve metin dosyalarının yüklenmesi
- Dosya önizleme ve söyleşi bağlamına ekleme
- Özetleme ve belge analizi
- MCP tabanlı Excel/veri araçları
- Dosya Yönetimi üzerinden kalıcı kullanıcı dosyası ayrımı

### Görsel ve medya özellikleri
- Yapay zekâ ile görsel oluşturma
- Görsel galerisi
- TTS ile sesli yanıt
- STT ile sesli giriş
- Karakter temalı müzik ve deneyim katmanları

### Kurumsal bileşenler
- SSO / Keycloak desteği
- Kullanıcı bazlı sohbet, dosya ve galeri ayrımı
- Destek merkezi, geri bildirim ve hata bildirimi
- Sürüm bilgilendirme sayfası
- Yönetici paneli, analitik ekranlar ve Sistem Durumu sağlık paneli

---

## Sayfa Haritası

### Ana Söyleşi
Ana sohbet ekranıdır. Kullanıcı burada soru sorabilir, dosya ekleyebilir, hızlı eylem kartlarıyla belirli akışları başlatabilir, model seçebilir, sesli giriş kullanabilir, görsel üretim, özetleme veya analiz odaklı kontrolleri çalıştırabilir.

Hoş geldin ekranında **Son Konuşmalar** bölümü en son aktif olan 3 söyleşiyi gösterir. Sıralama, oluşturulma zamanından çok söyleşi aktivitesine göre yapılır.

### Söyleşi Yönetimi
Üç alt bölümden oluşur:

- **Söyleşi Geçmişi**
- **Kayıtlı Söyleşiler**
- **Görsel Galerisi**

Bu akışlar kullanıcı bazlı veri ayrımıyla çalışır.

### Dosya Yönetimi
Kullanıcının yüklediği dosyaları yönettiği merkezdir. Yükleme, önizleme, listeleme, kalıcı dosya yenileme ve söyleşiye bağlama işlemleri burada yapılır.

Varsayılan dosya yükleme sınırı 25 MB’tır. Bu sınır hem tarayıcı tarafında hem Shiny request seviyesinde hem de sunucu doğrulama katmanında korunur. Amaç, on-prem Windows VM üzerinde büyük dosyaların arayüzü kilitlemesini veya geç hata üretmesini önlemektir.

Dosya Yönetimi küçük sorumluluklara ayrılmıştır:

- `R/module_file_manager_ui.R`: `fileManagerUI()` ve tarayıcı tarafı upload sınırı kontrolü
- `R/module_file_manager.R`: `fileManagerServer()` ve Shiny runtime orkestrasyonu
- `R/helpers_file_manager_policy.R`: uzantı/yükleme/user-id politika yardımcıları
- `R/helpers_file_manager_context_policy.R`: model bağlamı seçim temizleme kuralları
- `R/helpers_file_manager_table.R`: tablo şeması ve satır HTML yardımcıları
- `R/helpers_file_manager_refresh_guard.R`: kalıcı dosya yenileme request-token koruması
- `R/helpers_file_manager_session_registry.R`: oturum içi dosya kayıt defteri
- `R/helpers_file_manager_runtime.R`: File Manager runtime yardımcı fabrikası
- `R/helpers_file_manager_storage.R`: kalıcı depolama yardımcıları

### Bilge Yolaç
Bilge Yolaç, Claude Code tabanlı ve web arayüzüne entegre edilmiş kod odaklı ajan sayfasıdır. Klasör seçimi, senaryo şablonları, model katmanları, canlı akışlı araç kullanımı ve doküman bağlamı desteği içerir.

Bilge Yolaç katmanı kademeli refactor yaklaşımıyla bölünmüştür:

- `R/module_claude_code_ui.R`: sayfa UI tanımı
- `R/module_claude_code.R`: sunucu/runtime mantığı
- `R/helpers_claude_code_model_config.R`: model/settings kararları
- `R/helpers_claude_code_process.R`: Node/CLI/processx yardımcıları
- `R/helpers_claude_code_document_extractors.R`: PDF/Excel/DOCX metin çıkarımı
- `R/helpers_claude_code_documents.R`: doküman bağlamı, prompt ve özetleme yardımcıları

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

### Yönetici Paneli ve Sistem Durumu
Yetkili kullanıcılar için genel analitik, geri bildirim analizi, hata analizi, yanıt geri bildirimi analizi ve Sistem Durumu ekranları sunulur.

Sistem Durumu paneli on-prem Windows VM dağıtımları için offline uyumlu tasarlanmıştır. Public internet çağrısı yapmamalı, gizli değerleri açık göstermemeli, sağlık kontrollerini hafif ve yan etkisiz tutmalıdır.

---

## Hızlı Eylem Kartları

Hoş geldin ekranındaki hızlı eylem sistemi kullanıcıyı doğrudan belirli akışlara taşır. Ana hızlı eylemler:

- Süreç Yönetimi Sistemi
- Uygulama Uzmanı
- Proje ve Kaynak Analizi
- Excel Analizi
- Görsel Oluşturma
- Kodlama Desteği
- Özetleme Desteği

Bu kartlar yalnızca görsel kısayol değildir; model seçimi, başlangıç mesajı, araç ailesi ve bazı runtime davranışları üzerinde etkili olabilir.

---

## Karakter Sistemi

Uygulama beş ana karakter içerir:

- **Mergen**
- **Ülgen**
- **Kayra**
- **Erlik**
- **Umay Ana**

Karakter sistemi yanıt tarzı, görsel kimlik, AI Uzman tonu, TTS ses seçimi, tema renkleri ve bazı rehberlik tercihleriyle ilişkilidir. Varsayılan karakter **Mergen**’dir.

---

## Mimari Özet

Uygulamanın boot girişi `app.R`, kaynak yükleme manifesti `global.R`, ana sunucu orkestrasyonu `server.R` içindedir. Kod tabanı kademeli olarak büyük dosyalardan küçük sorumluluklara ayrılmaktadır. Hedef, davranışı bozmadan kaynak sırası ve gizli state bağımlılıklarını azaltmaktır.

### Güncel önemli mimari sözleşmeler

#### UserSessionContext / kullanıcı oturumu başlatma

Kullanıcı kimliği ve SSO/local oturum kurulumu artık doğrudan `server.R` içinde dağınık şekilde yönetilmez. Bu sorumluluk `R/server_init_user_session.R` dosyasına taşınmıştır.

Bu dosyanın ana sorumlulukları:

- local ve SSO kimliğinden ortak `user_config` yapısı üretmek,
- mevcut `session$userData` anahtarlarını geriye dönük uyumlu biçimde doldurmak,
- `resolve_current_user_id` ve `current_user_id_provider` canlı sağlayıcılarını üretmek,
- SSO başlangıcındaki geçici `0L` kullanıcı kimliğinin dosya, sohbet, galeri ve destek modüllerine sızmasını önlemek,
- `server.R` içindeki kimlik orkestrasyon yükünü azaltmak.

`server.R` artık bu alanda yalnızca `serverInitUserSession(...)` çağrısını yapmalı ve dönen `user_session` nesnesinden `user_config_rv`, `resolve_current_user_id` ve `current_user_id_provider` alanlarını almalıdır.

#### Kaynak yükleme sırası

`global.R` hâlâ bilinçli bir manifesttir. Yeni dosya eklenirse doğru katmana konmalı ve ilgili source-order testleri güncellenmelidir. `R/server_init_user_session.R`, `R/module_user_identity.R` sonrasında ve diğer server init yardımcılarından önce yüklenmelidir.

Beklenen sıra:

```r
safe_source("R/server_init_forward_refs.R",  encoding = "UTF-8")
safe_source("R/server_init_user_session.R",  encoding = "UTF-8")
safe_source("R/server_init_session_state.R", encoding = "UTF-8")
safe_source("R/server_init_chat_runtime.R",  encoding = "UTF-8")
```

#### Canlı kullanıcı kimliği sağlayıcısı

SSO modunda başlangıç kullanıcı kimliği geçici olarak `0L` olabilir. Kullanıcıya özel modüllere bu snapshot doğrudan geçirilmemelidir. Bunun yerine `current_user_id_provider` veya `resolve_current_user_id()` kullanılmalıdır.

Bu sözleşme özellikle şunları korur:

- Dosya Yönetimi
- Kayıtlı Söyleşiler
- Söyleşi Geçmişi
- Görsel Galerisi
- Destek modülleri
- performans/oturum izleme

---

## Testler ve Üretim Sözleşmeleri

Ana test koşucusu sıkı modda kalmalıdır:

```r
source("tests/testthat.R", encoding = "UTF-8")
```

Özellikle mimari refactor sonrası çalıştırılması beklenen odak testleri:

```r
testthat::test_file("tests/testthat/test-server-user-session-context.R")
testthat::test_file("tests/testthat/test-server-live-user-provider-contract.R")
testthat::test_file("tests/testthat/test-effective-user-id.R")
testthat::test_file("tests/testthat/test-source-manifest-contract.R")
testthat::test_file("tests/testthat/test-production-contracts.R")
testthat::test_file("tests/testthat/test-maintainability-ratchet.R")
```

Diğer önemli sözleşme aileleri:

- DB/helper ayrımı: `test-db-refactor-contract.R`, `test-chat-message-formatting-refactor-contract.R`
- File Manager ayrımı: `test-file-manager-*`
- MCP ayrımı: `test-mcp-*`
- Bilge Yolaç ayrımı: `test-claude-code-*`
- Health paneli: `test-health-check-*`
- Offline üretim profili: `test-offline-baseline-contract.R`
- SSE worker export sözleşmesi: `test-sse-worker-export-contract.R`

---

## Çalıştırma Notları

Yerel geliştirme ve üretim VM davranışı farklı olabilir:

- Yerelde genellikle `SSO_ENABLED=FALSE` kullanılır.
- Windows VM üzerinde `SSO_ENABLED=TRUE` ile Keycloak/SSO akışı çalışır.
- Uygulama runtime’da public internet veya CDN bağımlılığına güvenmemelidir.
- Tüm asset’ler yerel `www/` altında veya repo içinde paketlenmiş olmalıdır.
- Türkçe karakterler ve UTF-8 bütünlüğü korunmalıdır.

---

## Güvenli Değişiklik İlkesi

Bu repo büyük bir Shiny uygulamasıdır. Refactor yaklaşımı:

1. Tek bir sorumluluk alanını seç.
2. Davranışı koru.
3. Küçük ve anlamlı bir helper/module sınırı oluştur.
4. `global.R` source sırasını güncelle.
5. Aynı batch içinde kontrat testi ekle.
6. Sıkı test koşumunu çalıştır.
7. Bir sonraki batch’e ancak bu sınır sağlamlaştıktan sonra geç.

Büyük framework değişimi, Shiny’den uzaklaşma, cloud-only servis, CDN veya runtime download önerilmez.
