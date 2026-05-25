# MERGEN Bilge

MERGEN Bilge, Türkçe odaklı, kurumsal kullanım için tasarlanmış, R/Shiny tabanlı gelişmiş bir yapay zeka asistanı uygulamasıdır. Uygulama; sohbet, dosya analizi, görsel üretimi, özetleme, süreç rehberliği, sesli etkileşim, destek merkezi ve kod odaklı çalışma alanı gibi çok sayıda yeteneği tek bir arayüzde bir araya getirir.

MERGEN Bilge, modern kurumsal kullanım için tasarlanmış, Türkçe odaklı bir yapay zekâ asistanıdır. Karakter sistemi, mitolojik temalar yerine farklı çalışma tarzlarını temsil eden modern ve kurgusal Türk AI persona'larından oluşur. Bu persona'lar kullanıcı deneyimine hem görsel hem davranışsal bir katman ekler ve her biri ayrı bir yaklaşım sunar.

Dokümantasyon Notu: Bu README, ürün kapsamını hızlıca anlamak için üst seviye bir özet sunar; ayrıntılı operasyonel kurallar ve asistan davranış ilkeleri için sırasıyla `CLAUDE.md` ve `ai_rehber.md` dosyalarına başvurulmalıdır.

---

## Genel Özellikler

### Yapay zeka söyleşi deneyimi
- Gerçek zamanlı akış (streaming) ile yanıt üretimi
- Türkçe odaklı sohbet deneyimi
- Kod bloklarında sözdizimi vurgulama
- Yapılandırma üzerinden açılıp kapatılabilen, streaming yanıtlar sonrasında da güvenilir çalışan takip sorusu önerileri ve mesaj eylemleri
- Farklı model ve araç aileleriyle çalışma
- Düşünebilen modeller (`thinking=TRUE`) için premium akıl yürütme kartı ve canlı düşünce akışı paneli
- Streaming durdurma/iptal akışı regresyon testleriyle korunur: gönder düğmesi normal duruma döner, typing/thinking göstergesi temizlenir, aktif istek durumu sıfırlanır ve kısmi/iptal edilmiş akışlar yinelenen asistan mesajı üretmez.
- Streaming iptal/abort karar mantığı `R/helpers_streaming_abort_lifecycle.R` içindeki saf `mergen_stream_abort_cleanup_plan()` yardımcısıyla test edilebilir hâle getirilmiştir; `tests/testthat/test-streaming-abort-lifecycle-smoke.R` kısmi yanıtı sonlandırma, boş placeholder temizleme, hata/iptal ayrımı ve UI reset sözleşmesini Shiny/DB/LLM başlatmadan doğrular.
- Tarayıcı tarafı streaming yaşam döngüsü de hafif smoke kapsamına alınmıştır: `www/js/streaming_manager.js`, yalnızca test amaçlı `window.MergenStreamingSmoke` arayüzünü sağlar; `www/smoke/ux-smoke.html` sentetik olarak init → delta → stale delta reddi → finalize akışını doğrular.
- Bu tarayıcı streaming sözleşmesi `tests/testthat/test-browser-smoke-harness-contract.R` ile korunur; amaç gerçek LLM çağrısı başlatmadan finalize sonrası streaming state, action button geri açılması ve yinelenen mesaj üretilmemesi risklerini yakalamaktır.
- Gerçek streaming reset/finalize sözleşmesi artık ayrı bir odak testle de korunur: `tests/testthat/test-true-streaming-reset-ui-contract.R`, sunucu tarafında aktif istek temizliği, `reset_chat_state_fn()` çağrısı, stop dosyası üretimi ve `finalizeStreamingMessage` mesajını; istemci tarafında request-id stale delta reddi, finalized state, action button geri açılması ve pending followup temizliğini doğrular. Bu test gerçek LLM, DB veya tarayıcı başlatmadan stop/cancel sonrası UI'ın gönderim modunda takılı kalması riskini yakalar.
- Sohbet girişindeki durdurma düğmesinin gerçek observer yolu da hafif smoke testiyle korunur: tests/testthat/test-chat-input-stop-button-smoke.R, tam uygulamayı, DB'yi, LLM'i, tarayıcıyı veya ses uç noktalarını başlatmadan send_stop_btn olayını shiny::testServer ile tetikler; stop sinyali, cancelled_* aktif istek kimliği, reset_chat_state çağrısı, is_sending/typing temizliği ve durdurma toast'ı doğrulanır.

- Dosya Özetleme akışında mevcut premium düşünme paneli korunur; özetleme için eski tek satırlık halka göstergesine geri dönülmez ve simulated aşama metinleri tutarlı biçimde gösterilir.
- Düşünme modeli tespiti, model adı regex tahminlerine değil yalnızca `R/config_api.R` içindeki `local_model_capabilities` bildirimlerine dayanır.
- Bakım sınırında `R/helpers_llm_sse_events.R` SSE olay/delta ayrıştırmasını, `R/helpers_ai_expert_chunking.R` ise AI Uzman TTS metin parçalama yardımcılarını taşır; bu ayrımlar dosya satır/fonksiyon bütçesini korumak için geri alınmamalıdır.
### Dosya ve veri odaklı çalışma
- Excel, PDF, Word, CSV, metin dosyaları ve diğer belgelerin yüklenmesi
- Dosya önizleme
- Dosyaların söyleşi bağlamına eklenmesi
- Özetleme, analiz ve veri işleme akışları
- MCP tabanlı araçlarla gelişmiş dosya işleme
- Dosya Yönetimi yaşam döngüsü, yüklenen dosyaların tarayıcı yenilemesi ve tam uygulama yeniden başlatması sonrasında görünür kalmasını hedefler.
- Kullanıcıya gösterilen dosya adları storage-prefix içeren kalıcı dosya adlarından ayrıdır; `dummy_test_data.xlsx` ve `Türkçe_çalışma_özeti_İstanbul.pdf` gibi özgün adlar Dosya Yönetimi tablosunda okunabilir biçimde korunur.
- Dosya Yönetimi canlı kullanıcı kimliği sınırı hafif smoke testleriyle korunur: SSO geçişinde placeholder `user_id = 0` kalıcı dosya yenilemesini tetiklemez, yenileme canlı `current_user_id` sağlayıcısını kullanır ve `Türkçe_çalışma_özeti_İstanbul.pdf` gibi görünen adlar yenileme/yeniden başlatma mantığında okunabilir kalır.
- Dosya Yönetimi kimlik hazır olma kararını canlı runtime kimlik sağlayıcısından alır; böylece SSO geçişinde placeholder kullanıcı kimliğiyle erken kalıcı dosya yenilemesi yapılmaz, doğrulama tamamlandıktan sonra kullanıcıya ait dosya klasörü güvenli biçimde yenilenir.
- Dosya Yönetimi tablo çizimi ve Model Bağlamı checkbox istemci bağlama mantığı `R/helpers_file_manager_table_runtime.R` içine ayrılmıştır; `R/module_file_manager.R` yalnızca sunucu tarafındaki `input$attach_toggled` davranışını taşır. Bu ayrım, davranışı değiştirmeden modülün satır/fonksiyon bütçesini korur.
- Bu refactor sözleşmesi `tests/testthat/test-maintainability-ratchet.R`, `tests/testthat/test-frontend-selector-contract.R`, `tests/testthat/test-source-manifest-contract.R` ve `tests/testthat/test-file-manager-state-runtime-contract.R` ile korunur; ratchet limitleri yükseltilmemeli, yeni sınır dosya ayrımıyla korunmalıdır.
- Çekirdek observer, boot-readiness, oturum zaman aşımı ve Dosya Yönetimi runtime bağlama akışı `R/server_core_observer_runtime.R` içine ayrılmıştır. `R/server_core_interaction_runtime.R` bu yardımcıyı `serverBindCoreObserverRuntime` üzerinden çağırır ve daha üst seviye çekirdek etkileşim orkestrasyonu ile sohbet kalıcılığı devrine odaklanır.
- Bu ayrım; `tests/testthat/test-server-core-observer-runtime-contract.R`, `tests/testthat/test-file-manager-module-policy-wiring.R`, `tests/testthat/test-frontend-selector-contract.R`, `tests/testthat/test-production-contracts.R`, `tests/testthat/test-source-manifest-contract.R` ve `tests/testthat/test-maintainability-ratchet.R` ile korunur. File Manager kimlik hazır olma kararı, canlı kullanıcı kimliği sağlayıcısı ve kaynak manifest sırası bu sınırda korunmalıdır.
- `tests/testthat/test-file-store-persistence-roundtrip-smoke.R`, PDF/DOCX/TXT/CSV/XLSX ve Türkçe dosya adları için tekrarlı listeleme/yenileme-benzeri çağrılarda görünen ad kalıcılığını doğrular; adların okunabilir ve tekil kaldığını, storage zaman damgası/hex adlarının UI'a sızmadığını güvenceye alır.
- Kalıcı dosya indeksi kısmen eski kaldığında yalnızca aynı kullanıcı klasöründe güvenli filesystem fallback uygulanır; çapraz kullanıcı/çapraz bucket çözümleme varsayılan olarak kapalı kalır.
- Dosya Yönetimi listeleme yolu, aynı fiziksel dosyanın indeks ve filesystem fallback üzerinden iki kez tabloya düşmesini engelleyecek şekilde görünen dosya adı kimliğiyle tekilleştirilir.
- Dosya Özetleme modu yalnızca Model Bağlamı seçili ve desteklenen belge türlerini kullanır; Excel dosyaları özetleme bağlamından çıkarılır ve MCP Excel analiz akışında kullanılmaya devam eder.
- MCP dosya çözümleme normal kullanıcı akışlarında mutlak dosya yolu argümanlarını kabul etmez; dosya adı veya seçili dosya jetonu kullanılmalıdır.
- ChartLab tabanlı grafik üretimi; canlı sohbetlerde ve kayıtlı/yeniden yüklenen söyleşilerde aynı Shiny çıktı bağlama yolu ile grafiklerin yeniden gösterilmesi

### Görsel ve medya özellikleri
- Yapay zeka ile görsel oluşturma
- Görsel galerisi
- Görsel Galerisi yenilemesi gereksiz fade/toast üretmeden sessiz biçimde yapılır; böylece sekme geçişlerinde titreme ve tekrarlı bilgilendirme mesajları azaltılır.
- TTS ile sesli yanıt
- STT ile sesli giriş
- Arka plan müziği ve karakter temalı deneyim
- Ana tema müziğinin tek seferlik çalınması, ardından seçili karaktere ait rastgele karakter müziklerine güvenli geçiş
- STT modalı normal iptal/gönder yolları dışında kapansa bile tarayıcı tarafı kapanış yedeğiyle müzik durumu temizlenir ve geri yüklenir.
- AI Uzman ses oynatımı tarayıcı autoplay engeline veya oynatma reddine takıldığında ses kaynağı temizlenir, müzik duck durumu bırakılır ve altyazı deneyimi korunur.
- TTS ses nesneleri tarayıcı tarafında `MergenAudioLifecycle` üzerinde `tts` sahibiyle işaretlenir; böylece global audio play/pause olayları TTS'i `external_audio` gibi ele almaz ve TTS/STT/arka plan müziği duck/unduck yaşam döngüsü `tests/testthat/test-audio-lifecycle-owner-smoke.R` ile hafif biçimde korunur.
- `tests/testthat/test-audio-lifecycle-owner-smoke.R` artık yalnızca owner/duck tokenlarını değil, `MusicManager` için tek aktif audio kaynağı sözleşmesini de korur: `_playTrack()` yeni `Audio(src)` oluşturmadan önce mevcut sesi durdurmalı, eski audio event’leri stale guard ile korunmalı ve gecikmiş playlist yanıtları `_pendingRequestId` üzerinden reddedilmelidir. Bu kapsam, tema/karakter müziği, TTS ve STT etkileşimlerinde üst üste binen arka plan müziği regresyonunu erken yakalamak içindir.
- Tarayıcı tarafı medya ve kayıtlı sohbet smoke kapsamı `www/smoke/ux-smoke.html` ile, bu smoke sayfasının kapsamı ise `tests/testthat/test-ux-smoke-browser-contract.R` ile korunur. Bu sözleşme testi Windows/Türkçe locale kırılganlığını azaltmak için Türkçe log/metin cümlelerini byte düzeyinde eşleştirmek yerine ASCII yapısal anchor'ları kullanır; TTS play olayının müziği duck etmesi, STT duck/cleanup sonrası müzik durumunun geri dönmesi, üst üste binen TTS+STT duck owner'larında STT aktifken TTS bırakılınca müziğin erken dönmemesi, cleanup sonrası aktif duck owner kalmaması ve kayıtlı sohbet yüklenince eski AI mesajlarının TTS autoplay başlatmaması korunur.
- Kayıtlı sohbet yeniden yükleme yolu ayrıca `tests/testthat/test-saved-chat-reload-no-tts-contract.R` ile korunur; yapısal/statik kontrollerin yanında hafif bir `shiny::testServer` runtime smoke da içerir ve `load_chat_from_storage` observer’ının tarihsel mesajları yalnızca render edip `playAudioMessage` veya TTS sentezleme yolunu tetiklememesini doğrular.

- AI Uzman konuşması, `settings_kisisel`, `admin_analytics` ve `health` sayfalarına geçişte etkinse nazikçe durdurulur; altyazı gizlenir ve müzik ducking durumu serbest bırakılır.
- AI Uzman metinlerinde `Bilge Yolaç` adının `Bilge Yola` olarak üretilmesi altyazı ve TTS öncesinde merkezi olarak düzeltilir.
### Gelişmiş deneyim katmanları
- Koyu tema varsayılan deneyim olarak korunur; açık tema ise `theme_tokens.css`, `theme_light.css`, `theme_light_extras.css` ve `theme_manager.js` üzerinden kurumsal renk paletiyle desteklenir. Tema seçimi `mergen_settings.theme` / localStorage ve `<html data-theme="...">` sözleşmesiyle kalıcı uygulanır.
- Açık temada karşılama ekranı, Ana Söyleşi, Bilge Yolaç, STT, Dosya Yönetimi, Kişiselleştirme, Yenilikler, Yönetici Paneli, Kayıtlı Söyleşiler ve Görsel Galerisi için okunabilirlik, kontrast ve cam yüzey uyarlamaları güçlendirilmiştir.
- Deep-space başlangıç/sürüm modalları ve Keşfet/cinematic akışları, açık temada da bilinçli olarak koyu uzay atmosferini korur.
- Karşılama ekranındaki hızlı işlem seçimleri, ilgili araç ailesine göre bağlamsal arka plan animasyonları gösterebilir; bu davranış Yapılandırma altındaki “Araç Arka Plan Animasyonları” anahtarıyla yönetilir.
- Araç arka planlarında alt-sol köşe yedigen kümesi ve çakışmayı önleyen sabit snippet lane düzeni kullanılır; snippet üretimi karşılama yükleme ekranındaki ortak codestream rendering mantığıyla hizalıdır.
- Araç arka planı snippet filtreleri ve yedek snippet kataloğu `www/js/tool_backgrounds_snippets.js` içine ayrılmıştır; `www/js/tool_backgrounds.js` ise çalışma zamanı davranışını, Shiny mesajlarını, katman yaşam döngüsünü ve `window.MergenToolBackgrounds` genel API sözleşmesini taşımaya devam eder.
- “Yeni Söyleşi” akışı, önceki araç ailesinden kalan arka plan durumunu temizleyerek eski görsel bağlamın yeni sohbete sızmasını engeller.
- “MERGEN Bilge” marka yazımı navbar, açılış yükleme ekranı, modern welcome başlığı ve deep-space başlığında `www/css/brand_title.css` üzerinden tek kaynaktan yönetilir; dış font/CDN kullanılmaz ve karışık küçük/büyük harf yazımı korunur.
- Sinematik başlangıç ekranı
- Uygulama açılışında SSO kimlik doğrulaması, Shiny bağlantısı, oturum kurulumu ve çalışma alanı hazırlığı boyunca tüm ekranı kaplayan modern, çok aşamalı yükleme katmanı gösterilir.
- Açılış yükleme katmanı satır içi CSS/JS ile erken görünür hâle gelir; `skip_intro` ayarını, azaltılmış hareket tercihini ve olağan dışı durumlar için güvenlik zaman aşımını dikkate alır.
- Hoş geldin selamlaması ekran gerçekten görünür olmadan başlamaz; tekrar tetiklenmelerde eski zamanlayıcılar iptal edilerek deep-space geçişi sırasında kaybolan animasyonlar engellenir.
- Bütünleşik mod ve karakter giriş videoları önden istenerek karakter adımındaki algılanan bekleme azaltılır.
- Hoş geldin ekranı
- Karakter seçimi
- Üç farklı deneyim modu
- AI Uzman rehberliği
- Bilge Yolaç sayfası ile kod odaklı ajan deneyimi
- Bilge Yolaç, Windows VM / SSO ortamında kullanıcı yükleme klasörleri ve ağ paylaşımı benzeri çalışma dizinleri için daha dayanıklı çalışır; `/rehisds/...`, `//rehisds/...`, UNC ve ASCII dışı karakter içeren yollar gerektiğinde yerel geçici runtime çalışma alanına aynalanır.
- Claude Code CLI bağlantı ve çalıştırma yolu Windows `.cmd` sarmalayıcıları için güvenli yerel başlatma dizini, doğru komut tırnaklama ve `processx` verbatim argüman davranışıyla korunur; böylece "Bağlantı Yok", `cmd.exe` invalid directory ve escaped quote kaynaklı CLI hataları azaltılır.
- Bilge Yolaç doküman özeti akışı, kullanıcı klasöründe oluşturulan `dosya_aciklamalari.txt` dosyasını kopyalama/staging adımına bağımlı kalmadan doğrudan tıklanabilir indirme kartına dönüştürür. Bu davranış, dosya fiziksel olarak oluştuğu halde bağlantı kartının hazırlanamaması sorununu önler.
- Bilge Yolaç tarafından indirilebilir `.txt` özet dosyaları UTF-8 BOM ile yazılır; böylece Windows VM, Explorer, Notepad ve kurumsal istemci ortamlarında Türkçe karakterlerin mojibake biçimine dönüşmesi engellenir.

Bilge Yolaç canlı araç kullanımı ve dosya üretimi görünürlüğü de güçlendirilmiştir. Kurumsal/on-prem varsayılan profilde Read, Write, Edit, MultiEdit, Glob, Grep, LS ve Bash araçları izinlidir; daha sıkı ortamlar için CLAUDE_CODE_ALLOWED_TOOLS `.Renviron` üzerinden daraltılabilir. Araç blokları canlı akışta gösterilir, akış sonunda finalToolUsesHtml ile eksik veya boş sayaçlar tamamlanır ve on-prem proxy tool_use bloklarını yayınlamadığında çalışma dizini farkından sentetik Write kayıtları üretilerek ARAÇ KULLANIMLARI bölümü gerçek dosya üretimini yansıtır.

Bilge Yolaç parser katmanı Claude Code stream-json varyasyonlarına karşı daha dayanıklıdır: assistant.message.content, tek nesneli content blokları ve tool_result çıktıları yakalanır; stream_event ile parça parça gelen metnin toplu assistant bloğu üzerinden ikinci kez yazılması engellenir. Windows VM/SSO ortamında UNC ve ağ paylaşımı yolları mapped-drive biçimine zorlanmadan korunur; aynı söyleşide runtime çalışma alanı yeniden kullanılır ve Türkçe/BOM metin önizleme ile dizin listeleme daha güvenli çalışır.

Bilge Yolaç kullanıcı deneyiminde yükleme klasörü içerik soruları gerektiğinde canlı akışta yanıtlanır, başarılı çalışma veya doküman özeti sonrası Dosya Yönetimi yumuşak biçimde yenilenir, Dizin İçeriği yenileme/Çalıştır/İndir eylemleri kullanıcıya anında “hazırlanıyor” veya “yenileniyor” geri bildirimi verir. TOOL_USE_DEBUG logları, on-prem proxy’nin stream-json olay dağılımını ve araç kullanımı yakalama durumunu sahada incelemek için kullanılabilir.

Bilge Yolaç bakım sınırında canlı akış yoklama, durdurma ve klavye gönderim gözlemcileri `R/module_claude_code_stream_poll.R` içinde tutulur. Ana modül `R/module_claude_code.R`, bu yardımcıyı bağlayarak davranışı korur; böylece kullanıcı deneyimi değişmeden 800+ satır ve fonksiyon yoğunluğu eşikleri aşılmaz.

- Bilge Yolaç güvenlik sözleşmeleri ek regresyon testleriyle güçlendirilmiştir: seçili çalışma dizini, izinli çıktı kökleri, traversal/absolute path engelleri, prompt path-intent doğrulaması, doğrudan mevcut dosya indirme linkleri, stream/tool-use HTML kaçışı ve sentetik araç kullanımı görünürlüğü korunur.
- Doğrudan mevcut dosya indirme linkleri artık açık izinli kökler olmadan üretilmez; buna rağmen doküman özeti akışında kullanıcı klasöründe gerçekten oluşturulan `dosya_aciklamalari.txt` için mevcut tıklanabilir indirme kartı davranışı korunur.
- Prompt güvenliği, `../outside/sonuc.txt` ve izinli kök dışındaki absolute yazma hedeflerini CLI başlamadan engeller; buna karşılık uzantısız, diskte var olmayan ve normal metin gibi kullanılan path-benzeri ifadeler gereksiz yere bloke edilmez.
- Bilge Yolaç tool-use ve stream HTML çıktıları, dosya yolu/komut/önizleme/sonuç alanlarında HTML kaçış sözleşmesiyle korunur; bu sayede araç blokları görünür kalırken istemci tarafına ham HTML/script sızması engellenir.

- Ana Söyleşi'ye geri dönüldüğünde hoş geldin arka plan videosu gereksiz destroy/init döngüsüyle kesilmez; aktif video sürdürülür ve duraklamışsa autoplay recovery ile yeniden başlatılması denenir.
- Bilge Yolaç mini oyununda ekip kayması, otomatik ateş, fare hedefli ateş, `Çıktıyı Temizle` sonrası görünmeme ve seviye geçiş kilitlenmesi gibi akışlar düzeltilmiştir; BOŞLUK artık cooldown'lu manuel ateş tuşudur.
- Bilge Yolaç oyun HUD, başlık, seviye ve galibiyet ekranı yazıları daha okunabilir boyutlara çıkarılmıştır.
### Kurumsal ve yönetimsel bileşenler
- Sidebar alt kullanıcı paneli; canlı kimlikten gelen ad/avatar, Departman bilgisi, tema düğmesi, sürüm bilgisi ve SSO çıkış kısayolunu tek satırda görünür tutar; ilk render gecikmeleri statik iskelet görünümüyle karşılanır.
- SSO sonrası sidebar kimliği, `user_config_rv()` üzerinden canlı biçimde yeniden render edilir ve `MB_Users` profil satırıyla zenginleştirilir; böylece Keycloak claim'leri eksik veya geç gelse bile `KaynakAdi` ve `Departman` bilgileri veritabanındaki doğru değerlerden gösterilir.
- Sidebar kullanıcı ve kontrol çıktıları `suspendWhenHidden = FALSE` sözleşmesiyle korunur; gizli/yeniden render durumlarında panelin kalıcı olarak “Yerel Kullanıcı” / “Departman bilgisi yok” iskeletinde takılı kalması engellenir.
- Departman gösterimi `Departman`, `departman`, `department` sırasını izler; `Mudurluk` alanı kullanıcı panelinde kaynak olarak kullanılmaz.
- Sidebar tema düğmesi delegated click/touch/klavye işleyicisiyle sidebar yeniden render edilse bile çalışır; tema durumu yalnızca onaylı `dark` / `light` değerleriyle ayarlara yazılır.
- Görünür sürüm bilgisi sidebar, Hakkında, welcome ve Sistem Durumu alanlarında `R/config_version_history.R` içindeki `get_app_version_label()` tek doğru kaynağından okunur.
- SSO / Keycloak desteği
- Kullanıcı bazlı sohbet ve dosya ayrımı
- SSO oturum kimliği için odak smoke testi bulunur: `tests/testthat/test-sso-session-identity-smoke.R`, SSO başlangıcındaki `user_id = 0` placeholder değerinin kimlik doğrulama tamamlandıktan sonra canlı `current_user_id` sağlayıcısı üzerinden gerçek kullanıcı kimliğine geçtiğini doğrular.
- Destek merkezi
- Geri bildirim ve hata bildirimi
- Geri bildirim ve kullanım logu veritabanı yardımcıları `R/helpers_db_feedback.R` içine ayrılmıştır; `R/helpers_database.R` kullanıcı/profil odaklı DB işlemlerinde sade tutulur.
- Sürüm bilgilendirme sayfası
- Yönetici paneli ve analitik ekranlar
- Hata Analizi ekranındaki Öncelik ve Kategori ısı haritası için veri hazırlama mantığı `R/helpers_admin_hata_heatmap_data.R` içinde tutulur. Bu yardımcı yalnızca kategori/öncelik etiketlerini ve heatmap matrisini hazırlar; Shiny çıktı üretimi, highcharter çizimi, detay tablo runtime'ı, ek dosya modalı ve durum güncelleme davranışı bu dosyaya taşınmamalıdır.
- Hata Analizi detay bildirim tablosu, öncelik/durum rozetleri, ek dosya önizleme/indirme kartları ve durum güncelleme modalı `R/helpers_admin_hata_detail_runtime.R` içine ayrılmıştır. `R/module_admin_hata_analizi.R` bu runtime'ı yalnızca `admin_ha_register_detail_runtime()` üzerinden bağlar; böylece kullanıcıya görünen yönetici paneli davranışı değişmeden ana modül satır/fonksiyon bütçesi korunur.

### Türkçe karakter, emoji ve kodlama dayanıklılığı
- Türkçe karakterler, emoji ve yaygın mojibake bozulmaları için sunucu ve istemci tarafında ortak normalizasyon yardımcıları kullanılır.
- Sunucu tarafında `R/utils_text_encoding.R`; DB okuma/yazma sınırları, kayıtlı söyleşi yükleme, dosya görünen adları, sürüm geçmişi/Yenilikler metinleri, Bilge Yolaç süreç/akış çıktıları ve log metinleri için merkezi UTF-8 koruması sağlar.
- Log redaction katmanı, JWT ve Bearer/Basic değerlerine ek olarak URL query secret parametrelerini, generic key-value biçimindeki `api_key`, `token`, `password`, `client_secret` benzeri alanları ve Claude/API ilişkili ortam değişkeni değerlerini maskeleyecek şekilde genişletilmiştir.
- URL query redaction, yalnızca hassas parametre değerini maskeleyip `id=42` gibi normal query parametrelerini koruyacak biçimde test edilir.
- Test fixture’larında gerçek anahtar biçimine benzeyen örneklerin repoya girmemesi `test-secret-leak-contract.R` ile korunur; redaction testleri secret scanner’ı atlatmak için çalışma zamanında oluşturulan güvenli sahte değerler kullanır.
- DB yazım sınırında kullanıcıya görünen metinler önce açık biçimde `normalize_db_visible_value()` ile hazırlanır; teknik alanlar ise `normalize_db_technical_value()` ile onarımsız korunur. Karma DB parametre listelerinde `repair_mojibake = TRUE` tüm listeye uygulanmamalıdır. Böylece sohbet başlığı, mesaj içeriği, reasoning içeriği, düzenlenmiş mesaj, kayıtlı asistan yanıtı, kullanıcı görünen adı, geri bildirim etiketi/yorumu ve görsel galeri görünür mesaj metinleri korunurken ID, enum, bayrak, model adı, kullanıcı adı, e-posta, sicil, Keycloak ID ve dosya yolu benzeri teknik değerler gereksiz dönüştürülmez.
- `MB_Feedback` extended yazımlarında etiket ve yorum alanları kullanıcıya görünür metin olarak `normalize_db_visible_value()` ile hazırlanır; `FeedbackType` teknik enum alanı olarak `normalize_db_technical_value()` ile korunur. Bu sözleşme `R/helpers_db_feedback.R` içinde tutulur ve karma parametre listesine toplu `repair_mojibake = TRUE` uygulanmamalıdır.
- DB okuma tarafındaki normalizasyon, eski veya kısmen bozulmuş kayıtların ekranda okunabilir görünmesine yardımcı olabilir; ancak asıl sözleşme yeni kayıtların MB tablolarına doğru yazılmasıdır. Bu nedenle DB yazım sınırındaki değişiklikler mutlaka VM üzerinde SSMS ile doğrulanmalıdır.
- Windows VM / SSO / SQL Server ODBC ortamında DB yazım sınırı özellikle hassastır. `normalize_db_value()` ve `normalize_db_params()` kullanıcıya görünen metni onarırken DBI/ODBC parametre yazımında ortamın güvenli sınırını korumalıdır; yalnızca bağlantı seçeneği UTF-8 görünüyor diye ham UTF-8 metin zorla DB’ye gönderilmemelidir.
- Üretim VM ortamında Türkçe metin yazımları için `DB_CLIENT_ENCODING=WINDOWS-1254` davranışı korunur. Bu ayar Türkçe karakterlerin `Ã§`, `Ä±`, `Ã¶`, `ÅŸ`, `ÄŸ` gibi mojibake biçiminde MB tablolarına yazılmasını önlemek için kritik bir üretim sözleşmesidir.
- DB bağlantı sınırında `DB_CLIENT_ENCODING` ve `DB_NAME_ENCODING` ortam değişkenleri artık doğrudan dikkate alınır; ortam değişkenleri yoksa mevcut R option/default davranışına düşülür. Bu nedenle üretim VM üzerinde `.Renviron` içinde `DB_CLIENT_ENCODING=WINDOWS-1254` ve `DB_NAME_ENCODING=WINDOWS-1254` değerleri açıkça korunmalıdır.
- DB kodlama sorumluluğu küçük yardımcı dosyalara ayrılmıştır: `R/helpers_db_unicode_escape.R` Unicode kaçış/geri açma katmanını, `R/helpers_db_encoding.R` DB parametre normalizasyonu ve mojibake korumasını, `R/helpers_db_connection.R` ise yalnızca bağlantı/havuz/worker bağlantı katmanını taşır.
- SSO / `MB_Users` yazım sınırı için görünür alan ve teknik claim ayrımı `R/helpers_db_user_encoding.R` içinde tutulur. `R/helpers_database.R` bu yardımcıyı kullanır ve yerel kodlama sarmalayıcıları taşımaz; bu hem kodlama sözleşmesini merkezileştirir hem de maintainability satır bütçesini korur.
- `normalize_db_value()` yapılandırılmış DB istemci kodlamasını dikkate alır. DB istemci kodlaması UTF-8 değilse kullanıcıya görünen Türkçe metin, DBI/ODBC parametre sınırına uygun biçimde hazırlanır; böylece `MB_Messages.MessageContent`, `ReasoningContent`, sohbet başlıkları ve benzeri kullanıcıya görünen alanlarda yeni kayıtların `NasÄ±l`, `TÃ¼rkiye`, `baÅŸkent`, `yardÄ±mcÄ±` gibi mojibake biçiminde yazılması engellenir.
- Görsel galeri silme/güncelleme akışlarında `MB_Messages.MessageContent` kullanıcıya görünen metin olarak onarılır; `MessageID` gibi teknik alanlara mojibake onarımı uygulanmaz. Bu kural, kullanıcıya gösterilen Türkçe uyarı metnini korurken teknik DB parametrelerinin bozulmasını engeller.
- Bu düzeltme yeni yazımları korur; daha önce bozuk kaydedilmiş satırlar otomatik olarak değiştirilmez. Eski mojibake kayıtlar yalnızca DB yedeği alındıktan ve yeni yazım yolu SSMS üzerinde doğrulandıktan sonra ayrı bir tek-seferlik onarım planıyla ele alınmalıdır.
- Yeni `MB_Messages` yazımlarında yalnızca ön-normalizasyon yeterli kabul edilmez; mesaj DB’ye eklendikten sonra ve commit edilmeden önce `assert_mb_message_visible_encoding_clean()` ile `MessageContent` ve varsa `ReasoningContent` yeniden okunarak açık mojibake kalıntısı aranır. Bu kontrol hata verirse işlem rollback edilir ve yeni bozuk kayıt kalıcılaştırılmaz.
- Bu koruma hem normal `save_message_to_db()` akışını hem de worker/future tarafındaki `worker_save_assistant_response()` akışını kapsar. Böylece geçmişteki bozuk kayıtlar ayrı bir veri bakım konusu olarak kalırken yeni sohbet ve AI yanıtlarının Türkçe karakterleri bozarak DB’ye yazılması engellenir.
- `tests/scripts/run_vm_encoding_preflight_real.R` artık iki farklı sonucu ayırır: eski/historik `MB_Messages` mojibake kalıntıları varsayılan olarak uyarı üretir; `MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST=TRUE` ile çalışan transactional yeni yazım/okuma probu ise hâlâ kesin geçiş koşuludur. Eski kayıtları da bloklayıcı yapmak gerekirse `MERGEN_PREFLIGHT_FAIL_ON_LEGACY_MOJIBAKE=TRUE` kullanılabilir.
- `tests/scripts/repair_mb_messages_mojibake.R` yalnızca bakım amaçlı, tek-seferlik ve best-effort bir yardımcıdır. `source(...)` ile çalıştırılabilecek şekilde R oturumunu kapatan `quit()` çağrıları içermemelidir. Eski bozuk kayıtların tamamının eksiksiz onarılması garanti edilmez; kabul kriteri yeni kayıtların bozulmaması ve transactional preflight yazım testinin geçmesidir.
- Bu sınır `tests/testthat/test-db-normalization-contract.R` içinde ortam değişkeni okuma, `WINDOWS-1254` parametre davranışı ve yaygın Türkçe mojibake onarımı örnekleriyle korunur.
- Emoji ve benzeri `WINDOWS-1254` ile temsil edilemeyen Unicode karakterler artık DB yazım sınırında ham UTF-8 olarak zorlanmaz; `R/helpers_db_unicode_escape.R` bu karakterleri `[[MERGEN-U+...]]` biçimli ASCII kaçış belirteçlerine dönüştürür.
- Kayıtlı/yeniden yüklenen sohbetlerde bu belirteçler `normalize_db_read_visible_value()` ve `normalize_db_read_visible_frame()` üzerinden tekrar kullanıcıya görünen Unicode karakterlere açılır; böylece Türkçe DB güvenliği korunurken canlı ve kayıtlı sohbet deneyimi tutarlı kalır.
- Emoji kalıcılığı ham emoji karakterlerini SQL Server’a zorla yazma anlamına gelmez; üretim VM üzerinde `DB_CLIENT_ENCODING=WINDOWS-1254` ve `DB_NAME_ENCODING=WINDOWS-1254` sözleşmesi korunur.
- Test ortamında da çalışma zamanı kaynak sırası korunur: `tests/testthat/helper_bootstrap.R`, DB yardımcılarından önce `R/utils_text_encoding.R` dosyasını yükler. Böylece tekil `testthat::test_file(...)` çalıştırmalarında da mojibake onarımı gerçek uygulama davranışıyla aynı kalır.
- İstemci tarafında `www/js/encoding_utils.js`; genel Shiny mesajları, HTML metin/öznitelik onarımı ve Bilge Yolaç canlı akışı için ortak mojibake düzeltme/fallback katmanı sağlar.
- Bilge Yolaç streaming kodu büyük yerel mojibake haritaları taşımak yerine bu ortak istemci yardımcısını kullanır; böylece kullanıcı deneyimi korunurken bakım yükü azaltılır.
- Bilge Yolaç doküman özeti indirme sınırında `.txt` dosyaları `write_claude_code_utf8_bom_text_file()` ile UTF-8 BOM içerecek şekilde yazılır. Bu yalnızca indirilebilir metin dosyası algılamasını güçlendirir; DB yazım kodlaması, `DB_CLIENT_ENCODING` sözleşmesi ve SQL Server/ODBC sınırıyla karıştırılmamalıdır.
- Dosya Yönetimi görünen adları ve kalıcı dosya indeksi; Türkçe dosya adları, storage-prefix temizleme ve eski mojibake kayıtlarının okunabilir hâle getirilmesi için aynı merkezi normalizasyon hattını kullanır.
- Dosya yaşam döngüsü sertleştirmesi `R/config_file_store_index_mutation.R`, `R/config_file_store_listing_helpers.R`, `R/config_file_store_registry.R`, `R/helpers_file_manager_table.R`, `R/helpers_mcp_file_resolver.R` ve `R/module_summarization.R` sınırlarında korunur. Bu sözleşme storage adı ile görünen adın ayrılmasını, aynı kullanıcı filesystem fallback davranışını, yinelenen Dosya Yönetimi satırlarının engellenmesini, MCP mutlak yol reddini ve özetleme/Excel ayrımını kapsar.

- SSE streaming katmanı, çok baytlı UTF-8 karakterler iki akış parçası arasında bölünse bile durumlu çözücüyle parçaları birleştirir; `input string 1 is invalid UTF-8` hatası azaltılır.
### Kaynak manifesti ve MCP yükleme sırası
- Çalışma zamanı R kaynakları `R/config_source_manifest.R` üzerinden açık ve sıralı biçimde yüklenir; yeni runtime yardımcı dosyaları bu manifeste bağımlılık sırasıyla eklenmelidir.
- Açılış yükleme modülü `R/module_app_loading.R`, `R/config_source_manifest.R` içinde `R/module_startup_screen.R` sonrasında ve `R/module_quick_actions.R` öncesinde yüklenmelidir; `appLoadingUI()` ise `ui.R` içinde mümkün olan en erken noktada, `dashboardBody()` başlangıcında çağrılır.
- DB yardımcıları için açık sıra korunmalıdır: `R/utils_text_encoding.R` erken yüklenir; ardından `R/helpers_db_unicode_escape.R`, `R/helpers_db_encoding.R`, `R/helpers_db_connection.R`, `R/helpers_db_user_encoding.R`, `R/helpers_db_validation.R`, `R/helpers_chat_message_formatting.R`, `R/helpers_db_chat_readers.R`, `R/helpers_db_chat_mutations.R` ve `R/helpers_database.R` gelir.
- MCP yardımcı zincirinde yükleme sırası korunur: context, bootstrap, table readers, file resolver, schema helpers, basic tools, chart tools, analyze/visualize ve en son `helpers_mcp_tools.R`.
- `R/helpers_mcp_bootstrap.R` yalnızca MCP ortamını ve temel yol yardımcılarını hazırlar; downstream MCP helper dosyalarını gizli/dinamik biçimde source etmez.
- Bu sözleşme `test-source-manifest-contract.R`, `test-global-source-manifest-contract.R` ve MCP refactor testleriyle korunur; amaç kullanıcı deneyimini değiştirmeden boot/load-order kırılganlığını azaltmaktır.

### Ön yüz varlık manifesti ve bakım koruması
- Çalışma zamanı CSS/JS varlıkları `R/config_ui_assets.R` üzerinden açık ve sıralı biçimde yüklenir; CDN, bundle/minify veya gizli kaynak yükleme kullanılmaz.
- Ön yüz bakım raporu `tests/scripts/frontend_maintainability_report.R` ile üretilir. Bu rapor JS/CSS dosya boyutlarını, yaklaşık fonksiyon ve event handler yoğunluğunu, manifest dışı app-owned varlıkları, yinelenen CSS seçicileri ve yasak eski seçici kalıntılarını görünür kılar.
- `tests/testthat/test-frontend-maintainability-ratchet.R`, mevcut ön yüz taban çizgisinin sessizce büyümesini engeller. Vendor/minified dosyalar app-owned dosyalardan ayrı değerlendirilir.
- Ana Söyleşi hoş geldin ekranındaki hızlı işlem tooltip davranışı `www/js/welcome_tooltip_manager.js` içine ayrılmıştır. Bu dosya `www/js/app_core.js` sonrasında ve `www/js/streaming_manager.js` öncesinde yüklenir; böylece kullanıcı deneyimi değişmeden `app_core.js` çekirdek uygulama yaşam döngüsüne daha odaklı kalır.
- Bu sınır `tests/testthat/test-ui-asset-manifest-contract.R`, `tests/testthat/test-frontend-selector-contract.R`, `tests/testthat/test-frontend-maintainability-ratchet.R` ve `tests/testthat/test-maintainability-ratchet.R` ile korunur.
- Bu ayrımlar `tests/testthat/test-frontend-maintainability-ratchet.R`, `tests/testthat/test-maintainability-ratchet.R`, `tests/testthat/test-tool-backgrounds-contract.R`, `tests/testthat/test-source-manifest-contract.R` ve `tests/testthat/test-db-user-visible-encoding-boundaries.R` ile korunur.

#### Windows VM / SSO / SQL Server Türkçe Kodlama Güvencesi
- Üretim benzeri Windows VM ortamında `.Renviron` içinde `DB_CLIENT_ENCODING=WINDOWS-1254` ve `DB_NAME_ENCODING=WINDOWS-1254` değerleri bulunmalıdır; değişiklikten sonra yalnızca tarayıcıyı yenilemek yeterli değildir, R süreci tamamen yeniden başlatılmalıdır.
- Kullanıcıya görünen DB metinleri merkezi normalizasyon yardımcılarından geçmelidir; teknik kimlikler, bayraklar, enum değerleri, dosya yolları, model ID'leri, kullanıcı adı/e-posta/sicil/Keycloak ID gibi alanlarda mojibake onarımı yapılmamalıdır.
- SSO claim işleme, görünür ad/etiket alanlarını teknik kimlik alanlarından ayrı tutmalıdır. Destek sayfası geri bildirim/hata metinleri ve görsel galeri `MB_Messages.MessageContent` güncellemeleri yalnızca kullanıcıya görünen metin sınırında onarılır.
- Emoji ve benzeri desteklenmeyen Unicode karakterlerin kalıcılığı, ham UTF-8 DB yazımıyla değil `[[MERGEN-U+...]]` kaçış belirteçleriyle sağlanır; okuma/UI sınırında bu belirteçler geri açılır. Eski bozuk satırlar için otomatik migration yoktur.
- Gerçek VM doğrulaması için `tests/scripts/run_vm_encoding_preflight_real.R` kullanılmalıdır. `MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST=TRUE` açıldığında görünür ve teknik alan ayrımını gerçek DB yazma/okuma sınırında test eder ve test kayıtlarını rollback eder. Bu transactional yeni yazım probu başarısızsa değişiklik kabul edilmemelidir.
- Preflight sırasında eski `MB_Messages` mojibake kalıntıları bulunursa varsayılan davranış uyarıdır; bu durum geçmiş veri bakımını işaret eder, tek başına yeni yazım yolunun bozuk olduğunu kanıtlamaz. Eski kayıtların da bloklayıcı olmasını isterseniz `MERGEN_PREFLIGHT_FAIL_ON_LEGACY_MOJIBAKE=TRUE` ayarlanmalıdır.
- VM preflight mojibake denetimi yalnızca açık mojibake tokenlarını aramalıdır; geçerli Türkçe çıktıyı Windows byte dizileri üzerinden yanlış pozitif sayacak geniş `useBytes` desenleri kullanılmamalıdır.
- UTF-8 JavaScript dosyalarından kesit çıkaran R testlerinde `useBytes = TRUE` ile elde edilen byte pozisyonları `substr()` gibi karakter pozisyonu bekleyen fonksiyonlarla karıştırılmamalıdır. Dosyada Türkçe çok baytlı karakterler varsa bu karışım yanlış negatif test hatalarına yol açabilir; karakter pozisyonu ya da tamamen byte-güvenli çıkarım tutarlı biçimde kullanılmalıdır.
- `tests/scripts/parse_sanity_check.R`, VM preflight içinde uygulama/runtime parse sağlığını doğrulamak içindir. Tam test davranışı ayrıca `source("tests/testthat.R", encoding = "UTF-8")` ile doğrulanmalıdır.
- `testthat::test_file("tests/testthat/test-file-manager-live-provider-refresh-smoke.R")`
- `testthat::test_file("tests/testthat/test-e2e-quick-actions-streaming-regression.R")`
- `testthat::test_file("tests/testthat/test-sso-session-identity-smoke.R")`
- `testthat::test_file("tests/testthat/test-streaming-abort-lifecycle-smoke.R")`
- `testthat::test_file("tests/testthat/test-audio-lifecycle-owner-smoke.R")`
- `testthat::test_file("tests/testthat/test-true-streaming-reset-ui-contract.R")`
- `testthat::test_file("tests/testthat/test-fragile-flow-manual-preflight-contract.R")`
- `source("tests/scripts/run_fragile_flow_manual_preflight.R", encoding = "UTF-8")`
- Parser hassasiyeti olan R test kaynaklarında literal emoji yerine `intToUtf8(...)` kullanılmalıdır. Bu kural emoji desteğini kaldırmaz; yalnızca Windows VM parse dayanıklılığını artırır.

Kırılgan kullanıcı akışları için ek manuel preflight:
- Yerel modda `SSO_ENABLED=FALSE` ile streaming mesaj gönderme, streaming sırasında durdurma, PDF/DOCX/TXT/CSV/XLSX yükleme, tarayıcı yenileme, tam uygulama yeniden başlatma ve kayıtlı sohbet yüklemede eski TTS otomatik oynatmama kontrol edilmelidir.
- Windows VM / SSO modunda `SSO_ENABLED=TRUE` ile doğrulanmış kullanıcı kimliği, kullanıcıya özel son sohbet/geçmiş/kayıtlı sohbet/galeri satırları, Türkçe dosya adı yenileme/yeniden başlatma dayanıklılığı ve TTS/STT/arka plan müziği tekil playback/ducking davranışı kontrol edilmelidir.
- Bu adımların tekrarlanabilir kaydı için `tests/scripts/run_fragile_flow_manual_preflight.R` kullanılabilir; betik uygulamayı başlatmaz, ağır tarayıcı otomasyonu eklemez ve sonucu UTF-8 CSV olarak yazar.
- RStudio / Windows VM konsolunda `readline()` kaynaklı geçici giriş hatalarına karşı manuel preflight betiği güvenli giriş yardımcısı kullanır; bu davranış gerçek uygulama akışını değiştirmez, yalnızca preflight kaydının kesilmesini önler.
- Tüm adımlar daha önce manuel olarak doğrulandıysa, tekrarlı girişleri hızlandırmak için bilinçli olarak `MERGEN_PREFLIGHT_ASSUME_STATUS=PASS` kullanılabilir. Bu mod yalnızca preflight CSV kaydını doldurur; gerçek manuel doğrulamanın yerine geçecek şekilde kullanılmamalıdır.
- Odak test/preflight komutları:
  - `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")`
  - `testthat::test_file("tests/testthat/test-claude-code-document-download-link-encoding.R")`
  - `testthat::test_file("tests/testthat/test-claude-code-process-refactor-contract.R")`
  - `testthat::test_file("tests/testthat/test-claude-code-runtime-workdir-contract.R")`
  - `testthat::test_file("tests/testthat/test-claude-code-security-policy-contract.R")`
  - `testthat::test_file("tests/testthat/test-claude-code-synthetic-tools-contract.R")`
  - `testthat::test_file("tests/testthat/test-claude-code-policy-split-contract.R")`
  - `testthat::test_file("tests/testthat/test-db-user-visible-encoding-boundaries.R")`
  - `testthat::test_file("tests/testthat/test-db-refactor-contract.R")`
  - `testthat::test_file("tests/testthat/test-db-normalization-contract.R")`
  - `testthat::test_file("tests/testthat/test-text-encoding-utils.R")`
  - `testthat::test_file("tests/testthat/test-file-manager-display-name-contract.R")`
  - `testthat::test_file("tests/testthat/test-file-lifecycle-hardening-contract.R")`
  - `testthat::test_file("tests/testthat/test-file-resolution-security-contract.R")`
  - `testthat::test_file("tests/testthat/test-resolve-uploaded-file.R")`
  - `testthat::test_file("tests/testthat/test-mcp-excel-resolve.R")`
  - `testthat::test_file("tests/testthat/test-e2e-file-context-regression.R")`
  - `testthat::test_file("tests/testthat/test-upload-size-policy.R")`
  - `testthat::test_file("tests/testthat/test-upload-validator.R")`
  - `testthat::test_file("tests/testthat/test-config-file-store-registry-refactor-contract.R")`
  - `testthat::test_file("tests/testthat/test-production-contracts.R")`
  - `testthat::test_file("tests/testthat/test-browser-smoke-harness-contract.R")`
  - `testthat::test_file("tests/testthat/test-saved-chat-reload-no-tts-contract.R")`
  - `testthat::test_file("tests/testthat/test-file-store-persistence-roundtrip-smoke.R")`
  - `testthat::test_file("tests/testthat/test-ux-smoke-browser-contract.R")`
  - `source("tests/scripts/parse_sanity_check.R", encoding = "UTF-8")`
  - `source("tests/scripts/run_vm_encoding_preflight_real.R", encoding = "UTF-8")`
  - `Sys.setenv(MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST = "TRUE")`
  - `Sys.setenv(MERGEN_PREFLIGHT_FAIL_ON_LEGACY_MOJIBAKE = "FALSE")`
  - `source("tests/scripts/run_vm_encoding_preflight_real.R", encoding = "UTF-8")`
  - `Sys.setenv(MERGEN_REPAIR_MOJIBAKE_APPLY = "FALSE")`
  - `source("tests/scripts/repair_mb_messages_mojibake.R", encoding = "UTF-8")`
  - `source("tests/scripts/run_vm_encoding_preflight_real.R", encoding = "UTF-8")`
  - `Sys.setenv(MERGEN_PREFLIGHT_CHECK_FILE_STORE = "TRUE")`
  - `source("tests/scripts/run_vm_preflight_real.R", encoding = "UTF-8")`
  - `source("tests/testthat.R", encoding = "UTF-8")`.

---

## Sayfa Haritası

Uygulamadaki ana sayfalar aşağıdaki gibidir:

### Frontend varlık manifesti ve bakım koruması
- Ön yüz CSS/JS varlıkları `R/config_ui_assets.R` üzerinden açık gruplar ve açık yükleme sırası ile yönetilir; çevrimdışı/on-prem çalışma sözleşmesi gereği CDN, bundling veya minification tabanlı gizli kaynak akışı kullanılmaz.
- `tests/scripts/frontend_maintainability_report.R`, `www/js/*.js` ve `www/css/*.css` dosyaları için satır, byte, yaklaşık fonksiyon sayısı, event handler sayısı, Shiny özel mesaj handler sayısı, manifestte yer alma durumu, CSS tekrar eden seçiciler ve yasak eski seçici eşleşmelerini raporlar.
- `tests/testthat/test-frontend-maintainability-ratchet.R`, mevcut üretim taban çizgisini bozmadan app-owned frontend dosyalarının sessizce büyümesini, yeni runtime CSS/JS dosyalarının manifest dışında kalmasını ve eski kırılgan seçicilerin geri dönmesini engeller.
- Vendor/minified varlıklar raporda görünür kalır, ancak app-owned dosyalar için ayrı ve daha anlamlı bütçeler kullanılır. Bu koruma kullanıcı deneyimini değiştirmez; yalnızca bakım sınırını testlerle görünür hâle getirir.
- Frontend değişikliklerinden sonra odak doğrulama için şu kontroller çalıştırılmalıdır: `source("tests/scripts/frontend_maintainability_report.R", encoding = "UTF-8")`, `testthat::test_file("tests/testthat/test-frontend-maintainability-ratchet.R")`, `testthat::test_file("tests/testthat/test-ui-asset-manifest-contract.R")`, `testthat::test_file("tests/testthat/test-frontend-selector-contract.R")` ve `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")`.

### Ana Söyleşi
Ana sohbet ekranıdır. Kullanıcı burada:
- soru sorabilir,
- dosya ekleyebilir,
- hızlı eylem kartlarıyla belirli akışları başlatabilir,
- model seçebilir,
- sesli giriş kullanabilir,
- görsel üretim, özetleme veya analiz odaklı kontrolleri aktif olarak kullanabilir.

Ana Söyleşi hoş geldin ekranında ayrıca **Son Konuşmalar** bölümü bulunur. Bu bölüm, en son **aktif olan** 3 söyleşiyi gösterir; kullanıcı "Yeni Söyleşi" ile yeni akışa geçtiğinde az önce tamamlanan söyleşi hoş geldin ekranına dönüldüğünde beklemeden bu listede görünür. Sıralama, oluşturulma zamanından ziyade söyleşi aktivitesine göre yapılır.

Ana Söyleşi mesaj gönderme hattı son bakım güncellemesiyle daha ayrık hâle getirilmiştir. `R/server_send_message.R` artık istek yaşam döngüsü, araç yönlendirme, model/API hazırlığı ve streaming/non-streaming dispatch akışına odaklanır. Karakter stili, kaynakça talimatı, sistem promptu birleştirme ve yüklü dosya bağlamı hazırlığı `R/helpers_send_message_prompting.R` içine taşınmıştır. Bu ayrım, kullanıcıya görünen davranışı değiştirmeden mesaj gönderme yolunda bakım baş boşluğu oluşturur ve SQL analizi, MCP Excel ve MCP kapalı dosya bağlamı sözleşmelerini odak testlerle korur.

Son takip sorusu önerileri bakımında, Yapılandırma sayfasındaki "Takip sorusu önerilerini göster" seçeneği sunucu tarafında daha toleranslı okunacak şekilde güçlendirilmiştir. Takip soruları artık yalnızca AI tabanlı öneri üretimine bağlı değildir; yerel/deterministik öneri üretimi ve güvenli varsayılan öneriler sayesinde AI öneri çağrısı başarısız olsa bile özellik sessizce kaybolmaz. Streaming mesajlarda takip sorusu kapsayıcısı ilk render sırasında oluşmamışsa tarayıcı tarafındaki `updateFollowupSuggestions` işleyicisi bu kapsayıcıyı gerektiğinde oluşturur. Bu davranış `tests/testthat/test-followup-suggestions-regression.R` ile korunur.

Son ön yüz seçici bakımında Ana Söyleşi giriş alanının tarayıcı tarafı sözleşmesi daha açık ve merkezi hâle getirilmiştir. `www/js/input_handlers.js` artık eski `message_input` aramasına dayanmaz; gerçek UI sözleşmesi olan `#user_input`, `.chat-input` ve `textarea[name="user_input"]` seçicilerini tek yardımcı üzerinden kullanır ve bu sözleşmeyi `window.MERGEN_CHAT_INPUT_SELECTOR` ile `window.getMergenChatInputElement()` üzerinden diğer istemci kodlarına açar. `www/js/utils.js` içindeki karakter sayacı ve `www/js/app_core.js` içindeki `sendCapabilityMessage()` akışı da bu ortak yardımcıyı tercih eder; programatik input olayları bubbling ile gönderildiği için doküman seviyesinde bağlı input handler’ları güvenilir biçimde tetiklenir. Sunucu tarafı oturum aktivite izleme sözleşmesinde de eski `send_btn` yerine gerçek `send_stop_btn` kullanılır. Böylece karakter sayacı, otomatik yükseklik ayarı, Enter ile gönderme, Shift+Enter ile yeni satır, Escape ile temizleme, gönder düğmesi ve stop-mode davranışı aynı güncel DOM sözleşmesine bağlı kalır. Bu sınır `tests/testthat/test-frontend-selector-contract.R` ile korunur; test tüm `www/js/*.js` dosyalarında eski `message_input` izlerini tarar, `#_content_container` fallback’inin geri gelmesini engeller, CodeMirror observer cleanup sözleşmesini, hızlı eylem düğmesi sözleşmesini, Dosya Yönetimi getter kullanımını, STT/TTS anchor’larını ve Bilge Yolaç akış anchor’larını doğrular.

Son seçici/DOM sözleşmesi sertleştirmesinde sohbet içerik alanı ve dinamik ön yüz gözlemcileri de güncellenmiştir. Ana mesaj gözlemcisi ve CodeMirror gözlemcisi artık yalnızca gerçek sohbet kökleri olan `#chat_content_container` ve `.chat-container` üzerinden başlatılır; eski `#_content_container` fallback seçicisi geri getirilmemelidir. Gözlemciler yeniden bağlantılarda önce kapatılıp yeniden kurulur ve `shiny:disconnected` sırasında temizlenir. Bu sayede Shiny yeniden bağlandığında otomatik kaydırma, geniş ekran mesaj sarmalayıcı güncellemeleri ve CodeMirror başlatma davranışı eski DOM referanslarına takılmadan devam eder; aynı zamanda bağlantı yenilenmesi, sayfa yenilemesi veya dinamik mesaj ekleme sonrasında biriken MutationObserver kayıtları engellenir. Sohbet ve Dosya Yönetimi sürükle-bırak akışlarında da `#chat_input_wrapper` ve `#file_manager_module-main_drop_zone` için başlangıçta cache’lenen jQuery nesneleri yerine güncel DOM düğümünü çözen küçük yardımcılar kullanılır; bu, Shiny redraw/sekme geçişi sonrasında görsel `dragging` durumunun eski node üzerinde takılı kalmasını önler. TTS görselleştirici mesaj işleyicisi de erken gelen Shiny mesajlarında görselleştirici henüz başlatılmamışsa güvenli biçimde çıkacak şekilde korunmuştur.

Son ön yüz seçici sözleşmesi bakımında grafik çizdirme ve karşılama animasyonu sınırı da daraltılmıştır. `www/js/chart_renderer.js` artık eski `chat_content_wrapper` yedeğine başvurmaz; kaydedilmiş ChartLab grafiklerini `getChartRenderRoot()` yardımıyla yalnızca güncel sohbet kökleri olan `#chat_content_container` ve `.chat-container` üzerinden arar. Grafik çizdirme yolu artık kapsayıcı bulunamadığında geniş `document.body` taramasına veya `querySelector('.' + wrapperId)` gibi dinamik sınıf seçici kurulumlarına düşmez; böylece seçici drift’i gizlenmez ve grafikler amaçlanan sohbet yüzeyi dışında başlatılmaz. Ayrıca `showNeuralAnimation` Shiny özel mesaj işleyicisi tek merkezde, `www/js/shiny_message_handlers.js` içinde kalacak şekilde düzenlenmiş; `www/js/neural_welcome.js` ise yalnızca `window.startNeuralWelcomeAnimation()` yardımcı fonksiyonunu sağlar. Böylece deferred yükleme sırası veya yeniden bağlantı durumlarında çift handler kaydı, eski sohbet kökü taraması ve gizli DOM sözleşmesi drift’i önlenir. Bu sınır `tests/testthat/test-frontend-selector-contract.R` içinde `chat_content_wrapper` eski seçicisinin geri gelmemesi, grafik çizdirmenin güncel sohbet köklerini kullanması, geniş `document.body` fallback’inin geri dönmemesi, mesaj/CodeMirror gözlemcilerinin yeniden bağlantıda kurulması ve karşılama animasyonunun tek Shiny handler üzerinden başlatılması kontrolleriyle korunur.


Frontend bakım koruması da test kapsamına alınmıştır. `tests/scripts/frontend_maintainability_report.R`; en büyük JS/CSS dosyalarını, yaklaşık JS fonksiyon ve event-handler yoğunluğunu, Shiny custom message handler sayılarını, CSS seçici tekrarlarını ve yasak eski seçici kalıntılarını raporlar. `tests/testthat/test-frontend-maintainability-ratchet.R` ise mevcut üretim taban çizgisini kırmadan bundan sonraki sessiz büyümeyi yakalamak için pratik eşikler uygular.

Bilge Yolaç tarafında statik 16x16 piksel karakter frame verileri `www/js/claude_code_pixel_chars.js` dosyasına ayrılmıştır. `www/js/claude_code.js` yalnızca çalışma zamanı animasyon, mesaj ve UI davranışını yönetmeye devam eder. `R/config_ui_assets.R` bu statik veri dosyasını `js/claude_code.js` öncesinde yüklemeli; bu sıra `test-ui-asset-manifest-contract.R` ile korunmalıdır.

Son UI varlık manifesti bakımında `ui.R` içindeki uzun CSS/JS listesi küçük ve açık bir manifest dosyası olan `R/config_ui_assets.R` içine taşınmıştır. `ui.R` artık varlıkları `ui_asset_tags()` üzerinden üretir; yükleme sırası ise manifestte kritik CSS, sayfa CSS, CodeMirror CSS/JS, Three.js, SSO, kritik JS, ertelenmiş JS ve Bilge Yolaç JS gruplarıyla açık biçimde izlenir. Son sertleştirme adımıyla bu grupların gerçekten render edilme sırası `ui_asset_js_render_plan` altında tek merkezde tanımlanmıştır; `ui_asset_validate_js_render_plan()` her JS grubunun tam bir kez render planında yer aldığını ve ertelenmiş/senkron grup bilgisinin `ui_asset_deferred_js_groups` ile uyumlu kaldığını doğrular. Böylece manifestte yeni bir JS grubu tanımlanıp yanlışlıkla UI çıktısına eklenmemesi gibi kırılgan durumlar erken yakalanır. Kritik tarayıcı bağımlılıkları ayrıca `ui_asset_js_order_rules` içinde manifest düzeyinde tanımlanır ve `ui_asset_validate_js_order()` ile doğrulanır. Ertelenmiş JS grupları `ui_asset_deferred_js_paths()` üzerinden tek merkezden çözülür; CodeMirror ve SSO senkron kalır, Three.js ve Bilge Yolaç bağımlılık sırası korunur, müzik yöneticisi STT/TTS tüketicilerinden önce yüklenir, welcome/video/neural/greeting ve streaming/Bilge Yolaç sırası açık kurallarla izlenir. Ayrıca deferred yüklenen modern karşılama neural bileşeninde `updateNeuralColor` handler kaydı `shiny:connected` olayını kaçırsa bile güvenli ve tekil biçimde kurulacak şekilde korunmuştur. Bu değişiklik kullanıcı deneyimini değiştirmez; ancak SSO, CodeMirror, Three.js, streaming, TTS/STT, müzik, görsel araçlar, özetleme araçları ve Bilge Yolaç yükleme sırasının test edilebilir ve bakımı kolay bir sözleşmeye bağlanmasını sağlar. Bu sınır `tests/testthat/test-ui-asset-manifest-contract.R` ve `tests/testthat/test-frontend-selector-contract.R` ile korunur; testler ayrıca yüklü JS dosyalarında yinelenen `Shiny.addCustomMessageHandler(...)` kayıtlarını engeller.

Son sağlık paneli varlık bakımında, Sistem Durumu sayfasına ait `css/health_dashboard.css` ve `js/health_dashboard.js` dosyaları da aynı UI varlık manifestine alınmıştır. `R/module_health.R` artık bu dosyaları kendi `tags$head(...)` bloğunda tekrar yüklemez; böylece sağlık paneli de tek merkezli asset yükleme sözleşmesine uyar. Sağlık paneline özgü tooltip temizleme, klasör yolu kopyalama ve sayfa kapatma temizliği `www/js/health_dashboard.js` içinde kalırken, `updateHealthTimestamp` ve `updateAdminTimestamp` mesajları tek merkezli olarak `www/js/shiny_message_handlers.js` içindeki ortak zaman damgası işleyicisi tarafından yönetilir. Bu sınır `tests/testthat/test-ui-asset-manifest-contract.R` ve `tests/testthat/test-e2e-health-dashboard-regression.R` ile korunur.

Son medya ve arka plan müziği bakımında, sinematik başlangıç ekranındaki Dinamik/Bütünleşik mod seçiminden Ana Söyleşi hoş geldin ekranına geçişte müzik yaşam döngüsü sıkılaştırılmıştır. `SpaceIntroMusic` yalnızca giriş ekranı için çalışır; ana `MusicManager` ise giriş kapanışından sonra tek ses kaynağıyla başlatılır. Ana tema müziği oturumda bir kez çalar, ardından seçili karaktere ait müzikler rastgele döngüyle devam eder. Yinelenen `toggleMusic(TRUE)` çağrılarının ana tema playlist isteğini geçersiz kılarak karakter müziğine erken atlaması engellenmiştir. Karakter müziği dosya URL’leri Windows/SSO ortamında UTF-8 path segment kodlamasıyla üretilir; özellikle Ülgen dosyalarında `Ü` karakterinin hatalı `%DC` yerine doğru `%C3%9C` biçiminde kodlanması korunur. Hatalı veya oynatılamayan ses URL’lerinde tarayıcıyı kilitleyebilecek sonsuz hızlı yeniden deneme döngüsü de sınırlandırılmıştır. Bu davranış `tests/testthat/test-e2e-media-audio-state-regression.R`, `tests/testthat/test-ui-asset-manifest-contract.R`, `tests/testthat/test-frontend-selector-contract.R`, `tests/testthat/test-e2e-boot-welcome-regression.R`, `tests/testthat/test-source-manifest-contract.R` ve `tests/testthat/test-production-contracts.R` ile korunur.

### UX regresyon koruma sözleşmesi

Son UX dayanıklılık bakımında, mimari, güvenlik, kaynak yükleme sırası ve bakım refactor’larının kullanıcı deneyimini sessizce azaltmaması için ek regresyon korumaları eklenmiştir. Bu korumalar özellikle Ana Söyleşi hoş geldin ekranı, hızlı işlem kartları, medya yaşam döngüsü, TTS/STT etkileşimi, stop butonu, otomatik kaydırma ve düşünce paneli sınırlarını hedefler.

Korunan davranışlar şunlardır:

- Hoş geldin ekranında sol sinematik video, sağ neural animasyon, kişisel karşılama metni, hızlı işlem kartları ve Son Konuşmalar alanı birlikte çalışmaya devam etmelidir.
- Welcome ekranı yeniden bağlandığında veya Yeni Söyleşi sonrası geri geldiğinde video/neural/greeting bileşenleri eski DOM durumuna takılmadan yeniden başlatılmalıdır.
- Welcome yerleşiminde üst boşluk regresyonu oluşmamalı; tam ekran yerleşim sözleşmesi korunmalıdır.
- Hızlı işlem kartları doğru model ve araç modunu seçmeli, hazır yönlendirme mesajını göstermeli ve hızlı çift tıklamada yinelenen olay üretmemelidir.
- Arka plan müziğinde aynı anda tek aktif kaynak olmalı; karakter müziği tema müziğinin üzerine binmemeli, TTS müziği geçici olarak kısmalı, STT modalı müziği duraklatıp kapandığında geri getirmelidir.
- TTS yalnızca yeni AI yanıtları için otomatik oynatılmalı; kayıtlı/eski sohbet yükleme akışları otomatik seslendirme başlatmamalıdır.
- Stop butonu yanıt üretimini, düşünce paneli durumunu ve aktif TTS çalmasını birlikte temizlemelidir.
- Düşünen modellerde düşünce paneli görünmeli, otomatik kaydırma bozulmamalı ve tamamlanma/durdurma sonrasında panel yaşam döngüsü güvenli kalmalıdır.

Bu sınırları korumak için hafif regresyon testleri `tests/testthat/test-ux-regression-guardrails.R` içinde toplanmıştır. Buna ek olarak gerçek tarayıcı DOM’u üzerinde çalışan, üretim SSO/Keycloak ortamına uyumlu hafif smoke katmanı `www/smoke/ux-smoke.html` içinde tutulur; bu katmanı güncel tutan sözleşme testi `tests/testthat/test-browser-smoke-harness-contract.R` dosyasıdır. İlgili değişikliklerden sonra en az şu odak testler çalıştırılmalıdır:

- `tests/testthat/test-ux-regression-guardrails.R`
- `tests/testthat/test-e2e-boot-welcome-regression.R`
- `tests/testthat/test-frontend-selector-contract.R`
- `tests/testthat/test-e2e-media-audio-state-regression.R`
- `tests/testthat/test-quick-action-intro.R`
- `tests/testthat/test-quick-action-routing.R`
- `tests/testthat/test-ui-asset-manifest-contract.R`
- `tests/testthat/test-browser-smoke-harness-contract.R`
- `tests/testthat/test-maintainability-ratchet.R`

#### Tarayıcı düzeyi smoke doğrulaması

Gerçek tarayıcı davranışını hızlıca doğrulamak için repo içinde hafif bir browser smoke katmanı bulunur:

- Smoke sayfası: `www/smoke/ux-smoke.html`
- Sözleşme testi: `tests/testthat/test-browser-smoke-harness-contract.R`
- Yerel açıcı betik: `tests/scripts/open_ux_smoke.R`

Başarılı çalışmanın beklenen sonucu şudur:

- `UX_SMOKE_DONE:PASS`

Yerel geliştirme ortamında uygulama çalışırken smoke sayfasını açmak için:

- `Sys.setenv(MERGEN_SMOKE_BASE_URL = "http://127.0.0.1:3838")`
- `source("tests/scripts/open_ux_smoke.R", encoding = "UTF-8")`

Üretim veya SSO/Keycloak yolu üzerinde smoke doğrulaması yapılacaksa sayfa aynı origin üzerinden açılmalıdır. Örneğin uygulama `/bilge` altında yayınlanıyorsa `/bilge/smoke/ux-smoke.html` kullanılmalıdır. Cross-origin Keycloak/login yönlendirmesi iframe içindeki app DOM’unun okunmasını engeller; bu durumda smoke hatası uygulama UX regresyonu değil, yanlış origin/yönlendirme problemidir.

Bu browser smoke katmanı bilinçli olarak tek oturumlu ve hafif tutulmuştur. Sayfa uygulamayı bir kez iframe içinde açar, insan etkileşimi gerektiren Deep Space başlangıç ekranını smoke’a özel `localStorage` hazırlığıyla atlar, Ana Söyleşi hoş geldin ekranını doğrular, sentetik reasoning fixture’ını gerçek hızlı işlem/sohbet yan etkilerinden önce izole biçimde çalıştırır ve ardından hızlı işlem, sohbet girişi, medya, kayıtlı sohbet TTS davranışı ve konsol sağlığını kontrol eder. Smoke sonunda kendi değiştirdiği `localStorage` değerlerini geri yükler.

Doğrulanan başlıklar özetle şunlardır:

- Ana Söyleşi hoş geldin ekranı, sol video alanı, neural canvas, dinamik karşılama, hızlı işlem kartları, Son Konuşmalar alanı ve üst boşluk regresyonu olmaması.
- Hızlı işlem kartında gerçek tarayıcı dispatch’i, model/tool olayı ve hızlı çift tıklamada tek olay üretimi.
- Enter ile gönderme, Shift+Enter ile yeni satır, stop-mode koruması ve otomatik kaydırma durumunun korunması.
- TTS, STT, AI Uzman sesi ve arka plan müziği duck/restore akışı; STT modal kapanış yedeği ve AI Uzman autoplay reddi sonrası müzik geri yükleme davranışı.
- Kayıtlı sohbet yüklenince eski AI yanıtlarının otomatik TTS oynatmaması.
- Düşünce panelinin izole fixture içinde görünmesi, delta alması, AI balonuna taşınması ve stop/finish sonrası temizlenmesi.
- Tarayıcı konsolunda bloklayıcı JS hatası olmaması.

Bu katman `shinytest2`, Playwright, Chromote, Selenium, Node veya npm bağımlılığı gerektirmez. Normal kullanıcı arayüzünün parçası değildir ve `R/config_ui_assets.R` manifestine eklenmemelidir; yalnızca doğrudan smoke URL’si açıldığında çalışır.

Üretim VM/SSO zamanlamaları nedeniyle hızlı işlem intro mesajı görsel görünürlüğü browser smoke içinde bloklayıcı koşul değildir. Bu davranış warning/non-blocking tutulur; hızlı işlem intro, model ve araç modu sözleşmeleri deterministik odak testlerle korunmaya devam eder.

Konsolda görülebilen bilinen `Shiny.setInputValue` / `Shiny.setinputValue` zamanlama uyarıları smoke içinde warning-only kabul edilir. Buna karşılık kullanıcıya yansıyan welcome, input, media, saved-chat TTS, reasoning veya quick-action dispatch davranışları bozulursa smoke başarısız olmalıdır.

Bu testler görsel tasarımın yerini almaz; ancak future refactor’ların mevcut Türkçe UX, animasyonlar, sesli etkileşimler ve hızlı işlem akışlarını yanlışlıkla azaltmasını erken yakalamak için sözleşme katmanı sağlar.

Kişiselleştirme sayfasından farklı bir karakter seçildikten sonra doğrudan Ana Söyleşi sayfasına dönüldüğünde hoş geldin ekranı artık yeniden görünür DOM ölçüleriyle başlatılır. Daha önce hafif yeniden gösterme yolunda yalnızca mevcut welcome DOM’u gösteriliyor, modern welcome video/neural/greeting başlangıcı her zaman tekrar tetiklenmiyordu. `R/server_welcome_handlers.R` içindeki bağlı welcome dönüş yolu `initModernWelcome` ve `initPersonalGreeting` mesajlarını yeniden gönderir; `www/js/character_manager.js` ise gizli welcome canvas’ını sıfır ölçüyle destroy/init yapmamak için görünürlük kontrolü kullanır. Böylece karakter değişimi sonrası Ana Söyleşi’ye dönüşte sol video, sağ neural animasyon ve dinamik karşılama metni beklenen şekilde görünür.

Son request lifecycle sertleştirmesinde `send_message()` içinde üretilen istek kimliği cleanup/abort akışlarına da taşınmıştır. `R/helpers_send_message_core.R` içindeki typing wrapper temizliği artık request-id kontrolüyle çalışabilir; böylece eski bir async callback veya durdurulmuş istek, daha yeni bir isteğin düşünme/typing wrapper’ını yanlışlıkla kaldırmaz. Bu davranış `tests/testthat/test-send-message-request-lifecycle-contract.R` ile doğrudan test edilir. Aktif istek kimliği okunamadığında da cleanup güvenli tarafta kalır ve yeni isteğin wrapper’ını kaldırmaz.

Son kaynak manifesti bakım güncellemesinde çalışma zamanı kaynak listesi `global.R` içindeki uzun ve kırılgan `safe_source()` dizisinden çıkarılarak küçük ve açık bir manifest dosyası olan `R/config_source_manifest.R` içine taşınmıştır. `global.R` artık yüksek seviyeli boot akışını, UTF-8 güvenli `safe_source()` yüklemesini, future/test güvenlik kapılarını ve manifest doğrulama/yükleme çağrılarını yönetir; kritik kaynak gruplarını kendi içinde tekrar eden elle yazılmış `safe_source()` bloklarıyla tutmaz. Future öncesi temel kaynaklar `source_manifest_load(source_manifest_group_1_paths)` ile, future planı belirlendikten sonra yüklenmesi gereken kaynaklar ise `source_manifest_load(source_manifest_after_future_paths)` ile manifestten doğrudan yüklenir. Son sertleştirme adımıyla `app.R`, `R/config_source_manifest.R` dosyasını zorunlu boot dosyaları arasına alır; `global.R` ise bu manifest dosyasını yüklemeden önce `source_manifest_validate(order_rules = list(), paths = "R/config_source_manifest.R")` çağrısıyla dosyanın varlığını ve parse edilebilirliğini doğrular. Manifest yüklendikten hemen sonra `source_manifest_validate_config_objects()` çağrılır; böylece `source_manifest_group_1_paths`, `source_manifest_after_future_paths` ve `source_manifest_runtime_paths` nesnelerinin varlığı, geçerliliği ve `source_manifest_runtime_paths` değerinin iki grubun bire bir birleşimi olması erken doğrulanır. Manifest doğrulama ve kritik sıra kuralları `R/bootstrap_source_manifest.R` içinde kalır; gerçek kaynak sırası ise yalnızca `R/config_source_manifest.R` içindeki `source_manifest_group_1_paths`, `source_manifest_after_future_paths` ve `source_manifest_runtime_paths` nesneleriyle açık biçimde izlenir. `source_manifest_validate()` artık `global.R` içinden `safe_source()` kayıtlarını çıkarmaya çalışmaz; doğrulanacak yollar açıkça manifestten verilmelidir. Tüm runtime yükleme yine `safe_source()` üzerinden yapıldığı için Windows VM/SSO ortamındaki UTF-8 koruması ve Türkçe hata mesajları korunur. Eksik, yinelenen, parse edilemeyen, manifest nesnesi bozuk veya kritik sırayı bozan kaynaklar uygulama boot zincirinde erken yakalanır. Source-order sözleşmesini kontrol eden testler de artık `global.R` içindeki kaynak listelerini değil `R/config_source_manifest.R` manifestini ve `global.R` içindeki yüksek seviyeli manifest doğrulama/yükleme çağrılarını doğrular. Bu yapı `tests/testthat/helper_source_manifest_contract.R`, `tests/testthat/test-source-manifest-contract.R`, `tests/testthat/test-e2e-boot-welcome-regression.R`, `tests/testthat/test-production-contracts.R`, `tests/testthat/test-global-source-manifest-contract.R` ve `tests/testthat/test-maintainability-ratchet.R` ile korunur.

Son sunucu çalışma zamanı ve modül bağlama bakımında `server.R` dosyasının orkestrasyon rolü korunurken, uzun ve kırılgan parametre geçişleri küçük, adlandırılmış bağımlılık paketleriyle daha güvenli hâle getirilmiştir. Çekirdek etkileşim bağımlılıkları `serverBuildCoreInteractionBundle()` ile doğrulanır; sohbet motoru bağımlılıkları ise `R/server_chat_engine_dependencies.R` içindeki `serverBuildChatEngineDependencyBundle()` üzerinden taşınır. Sohbet motoru bağlama akışı `R/server_chat_engine_runtime.R` dosyasına ayrılmış, `R/server_module_wiring.R` ise orta seviye modül bağlama sorumluluğunda tutulmuştur. Runtime context sözleşme yardımcıları da küçük tutulmak için temel yardımcılar ve adlandırılmış sözleşme yardımcıları arasında bölünmüştür. Bu düzenleme kullanıcıya görünen davranışı değiştirmez; amaç SSO/local başlatma akışında eksik bağımlılıkları erken ve anlaşılır hatalarla yakalamak, `current_user_id`, `streaming_state` ve `ai_msg` gibi eksik nesne regresyonlarını önlemek ve bakım ratchet sınırlarını korumaktır. Bu sınır `tests/testthat/test-source-manifest-contract.R`, `tests/testthat/test-production-contracts.R`, `tests/testthat/test-server-module-wiring-chat-engine.R`, `tests/testthat/test-server-core-interaction-runtime.R` ve `tests/testthat/test-maintainability-ratchet.R` ile korunur.

### Söyleşi Yönetimi
Üç alt bölümden oluşur:
- **Söyleşi Geçmişi**
- **Kayıtlı Söyleşiler**
- **Görsel Galerisi**

Bu akışlar kullanıcı bazlı veri ayrımıyla çalışır. Eski bir söyleşi yeniden aktif kullanıldığında, son aktiviteye göre son listelere tekrar yukarı taşınabilir.

Söyleşi Geçmişi davranışı, seçilen tarih aralığına göre çalışır. Sayfa ilk açıldığında varsayılan tarih aralığı olan son 30 gün hızlı biçimde yüklenir; tablo sabit bir ilk 120/125 sohbet sınırına bağlı kalmamalıdır. Kullanıcı tarih aralığını genişlettiğinde veya değiştirdiğinde, tablo seçilen zaman aralığı için yeniden yüklenir. Sayfa seçimi sırasında arka plan ısıtma nedeniyle ikinci bir DataTable render/titreme oluşmamalıdır.

Söyleşi Geçmişi bakım sınırında, eski arka plan ısıtma yaklaşımının iki riski vardır: sayfa seçildiğinde ikinci render üretmek veya background yükleme kapatıldığında tabloyu ilk 120/125 sohbetle sınırlamak. Gelecek değişikliklerde bu iki regresyon tekrar edilmemelidir; hızlı ilk yükleme tarih aralığına göre yapılmalı, genişletilmiş tarih aralıkları ise kullanıcı değişikliğiyle açıkça yenilenmelidir.

Log güvenliği ve üretim preflight kapsamı güçlendirilmiştir. Başarısız mesaj kaydı fallback logları dosyaya yazılmadan önce `redact_sensitive_text()` üzerinden geçirilmelidir. VM preflight log redaction kontrolü gerçek sırlar yerine çalışma zamanında üretilen güvenli sahte değerlerle yapılmalı ve repoya secret scanner desenleriyle eşleşen sahte password/secret literal’leri eklenmemelidir.

VM encoding preflight, eski/historik mojibake kalıntılarını varsayılan olarak uyarı kabul eder; yeni yazım yolu ise `MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST=TRUE` transactional write/read/rollback probu ile kesin olarak doğrulanır. Eski kayıtların varlığı yeni yazım regresyonuyla karıştırılmamalıdır.

### Bilge Yolaç
Claude Code tabanlı, web arayüzüne entegre edilmiş kod odaklı ajan sayfasıdır. Klasör seçimi, senaryo şablonları, model katmanları ve canlı akışlı araç kullanım görünümü içerir.

Bilge Yolaç canlı akışı, Türkçe karakter ve emoji bütünlüğünü korumak için hem sunucu tarafındaki `R/utils_text_encoding.R` normalizasyon sınırından hem de istemci tarafındaki `www/js/encoding_utils.js` savunmacı fallback katmanından geçer. Bu yapı, Windows VM/SSO ortamlarında görülebilen çift kodlama ve mojibake risklerini kullanıcı deneyimini azaltmadan merkezi biçimde yönetir.

#### Bilge Yolaç güvenli CLI çalıştırma politikası

Bilge Yolaç, Claude Code CLI çalıştırma davranışını merkezi bir güvenlik ilkesi üzerinden yönetir. Bu sınırın temel amacı, kullanıcı deneyimini bozmadan dosya sistemi erişimini daha denetlenebilir hâle getirmektir. CLI izinleri, çalışma dizini kökleri, çıktı kökleri ve tehlikeli izin kararları `R/helpers_claude_code_security_policy.R` içinde; kullanıcı promptu içindeki dış dosya yolu yazma/düzenleme/silme niyetleri ise `R/helpers_claude_code_prompt_security_policy.R` içinde izole edilmiştir.

Varsayılan davranış şöyledir:

- `--dangerously-skip-permissions` varsayılan olarak kapalıdır.
- Tehlikeli izin atlama modu yalnızca açık bir yönetici/geliştirme tercihiyle etkinleşebilir.
- Normal kullanımda `--permission-mode acceptEdits` kullanılır; böylece kullanıcı seçili çalışma dizini içinde dosya okuma, oluşturma ve düzenleme istediğinde tekrar tekrar onay soruları ile karşılaşmaz.
- Varsayılan ek izinli araçlar `Read`, `Write`, `Edit`, `MultiEdit`, `Glob`, `Grep` ve `LS` ile sınırlıdır.
- `Bash` varsayılan izinli araç değildir; yalnızca güvenilir iç geliştirme makinelerinde açıkça yapılandırılmalıdır.
- Kullanıcının arayüzde seçtiği mevcut çalışma dizini, `CLAUDE_CODE_ALLOW_USER_SELECTED_WORKDIRS=TRUE` iken yalnızca o çalışma için güvenli çalışma kökü olarak kabul edilebilir.
- Çalışma dizinleri normalize edilir; UNC/ağ paylaşımı, Windows yolu ve Türkçe karakter içeren dizinler mevcut esnek dizin çözümleme yardımcıları üzerinden doğrulanır.
- Kullanıcı promptunda açıkça mutlak yol veya `../` benzeri traversal ile seçili çalışma dizini dışına dosya oluşturma, düzenleme, silme, taşıma veya kopyalama isteği algılanırsa CLI başlatılmadan önce çalışma güvenli biçimde engellenir.
- Bu engel kullanıcıya açık bir hata mesajı olarak gösterilir; istek sessizce geçilmez ve tehlikeli moda düşülmez.
- `R/module_claude_code.R`, bu doğrulamaları inline tutmaz; seçili çalışma dizini ve prompt-yol güvenliği `R/helpers_claude_code_run_lifecycle.R` içindeki `cc_prepare_safe_workdir_for_run()` yardımcısına delege edilir.
- Üretilen ve indirilebilir hâle getirilen dosyalar yalnızca seçili çalışma dizini, runtime çalışma dizini veya açıkça izinli çıktı kökleri içindeyse sahnelenir.
- Bilge Yolaç güvenlik ilkesi kullanıcı promptuna veya system prompta metin olarak enjekte edilmez; kullanıcının gerçek komutu Claude Code CLI’a aynen korunarak iletilir.
- `--allowedTools` ve `--disallowedTools` gibi araç bayraklarının kullanıcı promptunu yutmaması için prompt, CLI argümanlarında `--` sonlandırıcısından sonra verilir.

Önerilen güvenli `.Renviron` başlangıç ayarları:

    CLAUDE_CODE_ALLOW_DANGEROUS_PERMISSIONS=FALSE
    CLAUDE_CODE_ALLOW_USER_SELECTED_WORKDIRS=TRUE
    CLAUDE_CODE_PERMISSION_MODE=acceptEdits
    CLAUDE_CODE_ALLOWED_TOOLS=Read;Write;Edit;MultiEdit;Glob;Grep;LS
    CLAUDE_CODE_DISALLOWED_TOOLS=

Daha geniş araç erişimi gerekiyorsa, özellikle `Bash`, yalnızca kontrollü ve güvenilir iç geliştirme ortamlarında açıkça eklenmelidir. Bu durumda dahi `CLAUDE_CODE_ALLOW_DANGEROUS_PERMISSIONS=FALSE` varsayılanı korunmalıdır.

Bu davranışın temel sözleşmesi aşağıdaki testlerle korunur:

- `tests/testthat/test-claude-code-security-policy-contract.R`
- `tests/testthat/test-claude-code-run-lifecycle-contract.R`
- `tests/testthat/test-claude-code-process-refactor-contract.R`
- `tests/testthat/test-claude-code-runtime-workdir-contract.R`
- `tests/testthat/test-claude-code-workdir-scan-contract.R`
- `tests/testthat/test-maintainability-ratchet.R`

Bu güvenlik sertleştirmesi aynı zamanda bakım sınırlarını da korur: prompt-yol denetimi ayrı helper dosyasında, çalışma yaşam döngüsü davranışı lifecycle helper katmanında, ana Shiny modül orkestrasyonu ise `R/module_claude_code.R` içinde tutulur. Böylece güvenlik kontrolü eklenirken Bilge Yolaç sayfasının canlı akış, dizin gezgini, dosya üretme ve indirme bağlantısı deneyimi korunur.

Bilge Yolaç yapısı son bakım refactor’larıyla daha ayrık hâle getirilmiştir. Sayfa UI tanımı `R/module_claude_code_ui.R` içinde, sunucu mantığı ise `R/module_claude_code.R` içinde tutulur. Model/settings karar yardımcıları `R/helpers_claude_code_model_config.R` dosyasına taşınmış; süreç/CLI çalıştırma yardımcıları `R/helpers_claude_code.R` içinde bırakılmıştır. Bu ayrımlar, büyük dosyaları tek seferde yeniden yazmadan kontrollü bakım yapılabilirlik artışı sağlamak için uygulanmıştır.

Son Bilge Yolaç bakım refactor’larında başlangıç/setup observer kümesi `R/helpers_claude_code_server_setup.R` dosyasına, çalışma/akış yaşam döngüsü ise `R/helpers_claude_code_run_lifecycle.R` dosyasına ayrılmıştır. Setup helper’ı CLI yol tespiti, bağlantı rozeti, karakter/tema senkronizasyonu, kullanıcı yükleme klasörüne geçiş, yerel klasör yükleme, model değişiminde oturum sıfırlama, senaryo düğmeleri, dizin yenileme, çıktı temizleme ve düşünme mesajı güncelleme bağlayıcılarını üstlenir. Kullanıcı kimliği hazır olma sözleşmesi `R/helpers_claude_code_user_guard.R` içinde tutulur; SSO tamamlanmadan veya geçerli kullanıcı kimliği çözülmeden Bilge Yolaç’ın kullanıcıya özel çalışma alanı/dizin işlemleri `user_id = 0` ile devam etmez. Çalışma yaşam döngüsü helper’ı ise aktif çalışma kimliği üretimi, stale async/promise callback ayrımı, doküman özetleme sonucu koruması ve güvenli finalization akışını yönetir. `Durdur` düğmesi artık süreç öldürüldükten sonra poll observer’a güvenmeden UI finalization mesajlarını doğrudan gönderir; böylece saniye sayacı, düşünme animasyonu, stop düğmesi ve pasif kalan `Çalıştır` düğmesi takılı kalmaz. Bu ayrımlar `R/module_claude_code.R` dosyasını 1254 satırdan 799 satıra düşürmüş ve Bilge Yolaç sunucu modülünün çalışma zamanı orkestrasyonuna odaklanmasını sağlamıştır.

Son Bilge Yolaç çalışma dizini bakım refactor’ında Windows VM üzerinde sorun çıkarabilen UNC, ağ paylaşımı veya Türkçe karakter içeren çalışma dizinleri için kullanılan yerel runtime aynalama mantığı `R/helpers_claude_code_runtime_workdir.R` dosyasına ayrılmıştır. `R/helpers_claude_code.R` artık CLI çalıştırma, bağlantı kontrolü ve kalan Claude Code yardımcılarına odaklanır. Runtime çalışma dizinleri artık aynı kullanıcı için ortak `active_dir` klasörünü paylaşmaz; `run_request_id` tabanlı benzersiz klasörler kullanılır. Böylece hızlı ardışık veya eşzamanlı Bilge Yolaç çalıştırmalarında yeni bir çalışma, önceki çalışmanın geçici dizinini silerek snapshot, indirme toplama veya geri senkronlama akışını bozmaz. Bu sözleşme `test-claude-code-runtime-workdir-contract.R`, `test-source-manifest-contract.R`, `test-claude-code-process-refactor-contract.R`, `test-claude-code-run-lifecycle-contract.R`, `test-claude-code-stream-finalize-contract.R` ve `test-maintainability-ratchet.R` ile korunur.

Son Bilge Yolaç çalışma dizini tarama refactor’ında snapshot/diff üretimi, dosya yolu kanonikleştirme, dosya tekilleştirme, ikili doküman üretme/okuma niyet tespiti ve yeni/değişen dosyalar için staging öncesi kısa kararlılık bekleme mantığı `R/helpers_claude_code_workdir_scan.R` dosyasına ayrılmıştır. `R/helpers_claude_code_workdir_snapshot.R` artık indirilebilir dosya toplama/staging orkestrasyonu ve Türkçe metin kodlama normalizasyonuna odaklanır. Bu ayrım, özellikle Windows VM üzerinde Claude Code veya alt süreçler dosya üretimini yeni tamamlamışken mtime/size bilgisinin henüz kararlı olmadığı durumlarda eksik/kısmi indirme ya da erken `.txt` kodlama normalizasyonu riskini azaltır. Bu sözleşme `test-claude-code-workdir-scan-contract.R`, `test-source-manifest-contract.R` ve `test-maintainability-ratchet.R` ile korunur.

Son Bilge Yolaç dizin listeleme bakım refactor’ında klasör içeriklerini listeleme, UNC/ağ paylaşımı/path varyantı deneme, kalıcı depolama görünen ad çözümleme ve dizin öğesi normalizasyonu `R/helpers_claude_code_directory_listing.R` dosyasına ayrılmıştır. `R/helpers_claude_code.R` artık CLI çalıştırma, bağlantı kontrolü, çıktı biçimlendirme ve düşünme mesajı yardımcılarına odaklanır. Dizin yenileme akışı SSO kullanıcı kimliği hazır olmadan `user_id = 0` ile ilerlemez; `dir_refresh_guard` ile eski refresh sonuçlarının yeni UI durumunu ezmesi engellenir. Bu ayrım `R/helpers_claude_code.R` dosyasını 25+ fonksiyon eşiğinin altına indirerek ara bakım adımlarında büyük dosya/fonksiyon eşiği riskini azaltmış; son kabul edilen ratchet durumunda bakım yapılabilirlik taban çizgisi `100/100` olarak korunmaktadır. `test-claude-code-directory-listing-contract.R`, `test-source-manifest-contract.R`, `test-claude-code-dir-ui-refactor-contract.R` ve `test-maintainability-ratchet.R` bu sınırı korur.

Son Bilge Yolaç akış sonlandırma güvenliği güncellemesinde normal başarılı ve hatalı canlı akış bitişleri de aktif çalışma kimliği (`env$request_id`) ile `finalize_streaming()` çağıracak şekilde sıkılaştırılmıştır. Böylece eski bir poll/callback sonucunun daha yeni bir Bilge Yolaç çalışmasının UI ve runtime durumunu temizlemesi engellenir. Bu davranış `test-claude-code-run-lifecycle-contract.R` içindeki request-id korumalı normal finalization sözleşmesiyle, yakın sınıra gelmiş runtime dosyalarının mevcut baş boşluğu ise `test-maintainability-ratchet.R` içindeki near-limit bütçe kontrolleriyle korunur.

Son Bilge Yolaç erken-abort yaşam döngüsü güncellemesinde, canlı akış başlamadan önce durdurulan çalıştırma girişimleri de aynı request-id güvenlik sınırına alınmıştır. CLI bulunamaması, SSO/kimlik hazır olmaması, kullanıcı çalışma alanı oluşturulamaması, modelin çalıştırmaya kapalı olması veya process başlatma öncesi hata alınması gibi durumlarda `cc_abort_run_before_streaming()` yalnızca hâlâ aktif olan isteğin `rv$is_running` ve `rv$active_request_id` durumunu temizler. Kullanıcıya gösterilen ortak engelleme mesajları `cc_send_run_blocked_message()` üzerinden üretilir. Böylece başlamadan iptal edilen eski bir Bilge Yolaç çalıştırması, sonraki geçerli çalışmanın durumunu kirletecek stale request state bırakmaz. Bu davranış `test-claude-code-run-lifecycle-contract.R` ve `test-maintainability-ratchet.R` ile korunur.

Son doküman özetleme güvenliği güncellemesinde Bilge Yolaç’ın doküman özeti rotasında CLI oturum bağlamı açık bir yardımcıyla sıfırlanır. `cc_reset_document_summary_session_context()` doküman özetleme çalışmasının eski `cli_session_id` veya önceki CLI konuşma bağlamını devralmasını engeller; `cc_handle_document_summary_run()` bu helper üzerinden ilerler. Davranış `tests/testthat/test-claude-code-run-lifecycle-contract.R` içinde test edilir.

Son Bilge Yolaç ön yüz sözleşmesi sertleştirmesinde canlı akış araç sonuçları için `toolId` değeri artık doğrudan CSS attribute selector içine yerleştirilmez. `www/js/claude_code_streaming.js` araç bloklarını `data-tool-id` değerini düz metin olarak karşılaştıran küçük bir yardımcıyla bulur. Böylece tırnak, köşeli parantez, ters eğik çizgi veya seçici açısından özel karakter içeren araç kimlikleri tarayıcıda selector syntax hatası üretmeden güvenli biçimde işlenir.

### Dosya Yönetimi
Kullanıcının yüklediği dosyaları yönettiği merkezdir. Yükleme, önizleme, listeleme ve söyleşiye bağlama işlemleri burada yapılır.

Dosya Yönetimi ekranında dosya başına varsayılan yükleme sınırı 25 MB’tır. Bu sınır yalnızca sunucu tarafında değil, tarayıcı tarafında da kontrol edilir; böylece büyük dosyalar Shiny upload süreci başlamadan önce reddedilir ve kullanıcıya anında uyarı gösterilir. Bu katmanlı yaklaşım, özellikle on-prem Windows VM üzerinde büyük PDF/Word/Excel dosyalarının arayüzü kilitlemesini veya geç yanıt veren upload akışları oluşturmasını önlemek için kullanılır.

Dosya yükleme sınırı artık tek merkezden yönetilir: uygulama genelinde `getOption("mergen.upload_max_mb", 25L)` değeri esas alınır ve `shiny.maxRequestSize` bu merkezi değerden türetilir. Böylece tarayıcı tarafı uyarı, sunucu tarafı doğrulama ve Shiny HTTP upload sınırı farklı sabit değerlere ayrışmaz.

Dosya Yönetimi yapısı bakım yapılabilirliği artırmak için küçük sorumluluklara ayrılmıştır: `R/module_file_manager_ui.R` yalnızca `fileManagerUI()` arayüzünü ve tarayıcı tarafı upload sınırı kontrolünü içerir; `R/module_file_manager.R` ise `fileManagerServer()` tarafındaki yükleme, silme, bağlama, kalıcı dosya yenileme ve oturum durumu işlemlerine odaklanır. Ortak seçim/uzantı/yükleme politikaları, kullanıcı kimliği normalizasyonu ve küçük saf biçimlendirme yardımcıları `R/helpers_file_manager_policy.R` içinde tutulur. Model bağlamı temizleme planı, stale seçim ID’leri, MCP Excel-only kuralı ve tek Excel seçimi `R/helpers_file_manager_context_policy.R` içinde saf biçimde hesaplanır. Dosya tablosu şeması ve satır HTML üretimi `R/helpers_file_manager_table.R` içinde tutulur; böylece sunucu modülü tablo markup ayrıntılarını tekrar yazmadan dosya durumu ve refresh akışına odaklanır. Oturum içi dosya kayıt defteri ve UNC/yerel path normalizasyonu `R/helpers_file_manager_session_registry.R` içinde tutulur; böylece aynı path/registry davranışı yükleme, özet senkronizasyonu ve refresh geri yükleme akışlarında tekrar yazılmaz. File Manager sunucu çalışma zamanı yardımcıları `R/helpers_file_manager_runtime.R`, kalıcı depolama yardımcıları ise `R/helpers_file_manager_storage.R` içinde tutulur. SSO akışında geçici `0` kullanıcı kimliği gerçek kullanıcı sağlayıcısını maskelemez. Kalıcı dosya yenileme akışında eskiyen refresh isteklerinin yeni dosya durumunu ezmesini önlemek için request-token tabanlı koruma uygulanır. Bu request-token koruması `R/helpers_file_manager_refresh_guard.R` içinde saf ve test edilebilir bir yardımcı olarak tutulur; `R/module_file_manager.R` yalnızca refresh orkestrasyonu ve Shiny state güncellemesine odaklanır. Son File Manager bakım refactor’ında dosya state mutasyonu ve kalıcı klasörden yenileme çalışma zamanı `R/helpers_file_manager_state_runtime.R` dosyasına ayrılmıştır. Bu dosya `sync_file_to_context`, `append_uploaded_file_row`, `remove_file_by_name`, `process_uploaded_file` ve `fm_create_refresh_from_user_folder()` gibi yardımcıları tek sorumluluk altında toplar. `R/module_file_manager.R` artık ağırlıklı olarak Shiny modül orkestrasyonu, observer bağlama ve UI/state akışını koordine etmeye odaklanır. Toplu yükleme akışında SSO/kimlik hazır olmadan dosya state’inin mutasyona uğramasını önleyen auth-readiness koruması eklenmiş; kalıcı dosya yenilemede request-token tabanlı eski istek koruması korunmuştur. Bu ayrım `R/module_file_manager.R` dosyasını 800 satır eşiğinin altına düşürmüş ve File Manager refactor kazanımı `test-file-manager-state-runtime-contract.R`, `test-file-manager-module-policy-wiring.R`, `test-source-manifest-contract.R` ve `test-maintainability-ratchet.R` ile güvence altına alınmıştır.

Son ön yüz seçici bakımında File Manager model bağlamı checkbox sözleşmesi ayrıca sertleştirilmiştir. `removeExcelFromContext` artık dosya adını doğrudan CSS attribute selector içine yerleştirmez; `input.attach-checkbox[data-filename]` öğelerini dolaşıp `data-filename` değerini düz metin olarak karşılaştırır. Böylece tırnak, köşeli parantez, ters eğik çizgi veya seçici açısından özel karakter içeren dosya adları tarayıcıda selector hatası üretmeden bağlamdan çıkarılabilir. Sessiz checkbox durum güncellemesi için kullanılan istemci handler kaydı da `R/helpers_file_manager_attach_client.R` içine ayrılmıştır; bu yardımcı `R/config_source_manifest.R` içinde `R/module_file_manager.R` öncesinde yüklenir ve `test-source-manifest-contract.R` ile korunur. Son güncellemede bu sınır daha da daraltılmış; attach-state istemci kaydı `R/module_file_manager.R` içinde tekrar gömülü JS olarak tutulmak yerine yalnızca `R/helpers_file_manager_attach_client.R` üzerinden yapılacak şekilde merkezileştirilmiş ve global no-op handler’ın tek kez, namespace bazlı `setAttachState` handler’larının ise modül namespace’iyle kaydolması korunmuştur.

Son File Manager politika testleri, kullanıcıya özel yükleme klasörünün `user_<id>` biçiminde deterministik türetilmesini ve `0`, `unknown` gibi geçersiz kullanıcı kimlikleriyle kalıcı indeks/persist işlemi yapılmamasını doğrular. Son davranış kapsamı ayrıca özetleme modunda Excel dosyalarının reddedilmesini, MCP Excel bağlam temizliğinde non-Excel ve fazla Excel seçimlerinin kaldırılmasını, refresh guard ile eski yenileme sonuçlarının yeni dosya durumunu ezmemesini ve upload validator tarafında bozuk UTF-8 dosya adlarının, ASCII denetim baytı içeren güvensiz adların reddedilmesini sınar. Geçerli UTF-8 Türkçe dosya adları korunur; noktalı beyaz liste uzantıları ve büyük harfli görünen dosya adları doğru kabul edilir. Bu davranışlar `R/helpers_file_manager_policy.R`, `R/helpers_file_manager_context_policy.R`, `R/helpers_file_manager_refresh_guard.R`, `R/helpers_file_manager_storage.R` ve `R/utils_upload_validator.R` sınırında `tests/testthat/test-file-manager-policy-contract.R`, `tests/testthat/test-upload-validator.R` ve `tests/testthat/test-e2e-file-context-regression.R` ile korunur.

#### Dosya çözümleme ve kullanıcı izolasyonu

Dosya çözümleme akışı kullanıcı kovasını esas alacak şekilde sertleştirilmiştir. `resolve_uploaded_file()` normal kullanıcı akışlarında önce yalnızca geçerli kullanıcının indeks kovasını ve kendi fiziksel yükleme klasörünü dener. İndeks eksik, boş, eski veya UTF-8/görünen ad bilgisi bozulmuş olsa bile aynı kullanıcının kendi klasöründeki dosyalar güvenli filesystem fallback ile çözümlenebilir; bu fallback başka kullanıcı kovalarını taramaz.

Doğrudan fiziksel path çözümleme varsayılan olarak kapalıdır. Mutlak veya doğrudan dosya yolları yalnızca açık `allow_direct_path = TRUE` izniyle ve kullanıcının kendi güvenli kökü ya da açıkça verilen `trusted_roots` altında bulunuyorsa kabul edilir. Çapraz kullanıcı/kova çözümleme de varsayılan olarak kapalıdır; yalnızca bakım, geçiş veya kontrollü yönetici senaryoları için açık `allow_cross_bucket = TRUE` izniyle kullanılmalıdır.

MCP Excel dosya çözümleme hattı da aynı güvenlik sınırını izler. Araç argümanı olarak verilen mutlak path değerleri doğrudan dosya okuma yetkisine çevrilmez; dosyalar oturum kayıt defteri, geçerli kullanıcı kovası veya açık izinli bakım akışları üzerinden çözülür. Eski root-level legacy indeks kayıtları normal çalışmada kullanılmaz; geçiş amaçlı çapraz arama davranışı yalnızca açık opt-in ile etkinleşir.

Bu sınır `tests/testthat/test-resolve-uploaded-file.R`, `tests/testthat/test-mcp-excel-resolve.R`, `tests/testthat/test-file-resolution-security-contract.R`, `tests/testthat/test-upload-size-policy.R` ve VM preflight içindeki File Store izolasyon kontrolleriyle korunur.

Son dosya yolu ve görüntüleme bakım güncellemesinde, dosya/UNC/path karşılaştırma yardımcıları `R/helpers_files_path.R` dosyasına ayrılmıştır. Böylece `R/helpers_files.R` dosyası dosya içerik okuma ve MCP kalıcı yükleme/kopyalama akışlarına odaklanır. Kalıcı depolamada çakışma riskini azaltmak için dosya adlarında zaman damgası ve benzersiz token içeren iç storage adları kullanılabilir; ancak bu adlar kullanıcı arayüzüne sızdırılmaz. Dosya Yönetimi tablosu ve `Model Bağlamı` checkbox metadata alanları kullanıcıya yalnızca temiz/orijinal dosya adını gösterir. Bu davranış `test-helpers-files-path-contract.R`, `test-file-manager-display-name-contract.R`, `test-source-manifest-contract.R` ve `test-maintainability-ratchet.R` ile korunur. Test ortamında File Store public API yükleme sırası `tests/testthat/helper_load_file_store.R` ile korunur; izole smoke testleri için `normalize_for_path_compare` ve registry/mutation yardımcıları hazır olsun diye `R/helpers_files_path.R`, bölünmüş `config_file_store_*` public API dosyalarından önce yüklenir.

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
Geri Bildirim Analizi sayfasında public UI shell, sekme UI üretimi ve etiket sayımı `R/helpers_admin_geri_bildirim.R` içinde tutulur. SQL sorgu paketi ve enjekte edilebilir veri çekim yardımcısı ise `R/helpers_admin_geri_bildirim_queries.R` dosyasına ayrılmıştır. `R/module_admin_geri_bildirim.R` artık Shiny server orkestrasyonu, refresh/reactive veri akışı ve chart/table render fonksiyonlarına odaklanır. Bu ayrım modülü 800 satır eşiğinin altına indirir ve `test-admin-geri-bildirim-refactor-contract.R`, `test-admin-geri-bildirim-query-contract.R`, `test-source-manifest-contract.R` ve `test-maintainability-ratchet.R` ile korunur.

Hata Analizi sayfasında SQL sorgu paketi, kategori/öncelik/durum etiketleri, kategori sayımı ve sekme UI üretimi `R/helpers_admin_hata_analizi.R` içine ayrılmıştır. `R/module_admin_hata_analizi.R` artık public Shiny module API, refresh/reactive orkestrasyonu, chart/table render fonksiyonları ve modal/event işlemlerine odaklanır. Bu ayrım `test-admin-hata-analizi-refactor-contract.R`, `test-source-manifest-contract.R` ve `test-maintainability-ratchet.R` ile korunur.

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

Yeni sağlık paneli E2E/yariş durumu regresyon dilimi, gerçek DB, gerçek LLM, gerçek TTS/STT, gerçek görsel üretim endpoint’i, tarayıcı otomasyonu veya public internet gerektirmeden panelin kritik çalışma sözleşmelerini deterministik olarak sınar. Bu dilim; gizli ortam değişkenlerinin ham değer olarak sızmamasını, public endpoint’lerin ağ çağrısı yapılmadan uyarı/atlandı durumuna düşmesini, manuel/otomatik refresh sonuçlarının idempotent uygulanmasını, stale refresh sonuçlarının yeni panel durumunu ezmemesini ve sağlık paneli timestamp/tooltip temizleme hook’larının korunmasını denetler.

İlgili odak testleri:

```r
source("tests/testthat.R", encoding = "UTF-8")

testthat::test_file("tests/testthat/test-health-check-formatters.R")
testthat::test_file("tests/testthat/test-health-check-paths.R")
testthat::test_file("tests/testthat/test-health-check-env-contract.R")
testthat::test_file("tests/testthat/test-health-check-runtime-contract.R")
testthat::test_file("tests/testthat/test-e2e-health-dashboard-regression.R")
```

### E2E ve Yarış Durumu Regresyon Testleri

Son test güncellemesiyle, gerçek DB, gerçek LLM, TTS/STT, görsel üretim endpoint’i veya public internet gerektirmeyen deterministik bir E2E/yariş durumu regresyon temeli eklenmiştir. Bu temel, tarayıcı otomasyonu veya yeni offline kurulumu zor bir bağımlılık eklemeden `testthat` içinde çalışır.

Son küçük davranışsal test güncellemesi; hızlı işlem yönlendirmesinin Dosya Yönetimi politikalarıyla uyumunu, choices içermeyen thinking model yanıtlarında üst düzey `reasoning_content` ayrıştırmasını ve durdurulmuş aktif `send_message` isteğinin typing/wrapper temizliğini ek olarak güvence altına alır. Böylece özetleme hızlı işleminin Excel dosyalarını kabul etmemesi, MCP Excel modunun tek Excel dosyasıyla sınırlı kalması, reasoning fallback davranışının model ayarına bağlı kalması ve durdurulan isteğin yeni bir isteğin typing wrapper’ını kaldırmaması doğrudan test edilir.

Son davranış odaklı test güncellemesiyle statik sözleşme testlerinin yanında gerçek regresyon riski yüksek akışlar için ek birim/entegrasyon kontrolleri güçlendirilmiştir. Bu kapsamda hızlı eylem kimliği → araç ailesi → model seçimi eşlemesi, gerçek `mergen_determine_tool_family()` yönlendirmesinde MCP Excel’in dosyasızken `mcp_excel` olmaması ve `skip_mcp_once` önceliği, hızlı eylem konfigürasyonunda yinelenen id/aile/bayrak oluşmaması, LLM yanıt ayrıştırmada `choices`, üst düzey `message$content`, `delta$content`, choice `text`, üst düzey `response$text`, iç içe metin düğümleri ve reasoning fallback davranışı, request-id kapsamlı `send_message()` cleanup davranışı, stale cleanup sırasında yeni typing wrapper’ın korunması, File Manager kullanıcı klasörü/persist güvenliği, özetleme ve MCP Excel dosya seçim politikaları, upload validator UTF-8, ASCII denetim baytı ve noktalı/büyük harfli uzantı kontrolleri, Bilge Yolaç stale finalization/dizin yenileme koruması, doküman özetleme bağlam sıfırlaması ve SSO `authenticated=TRUE` olsa bile `auth_ready=FALSE` iken user-scoped refresh yapılmaması odak testlerle korunur. Bu testler gerçek DB, gerçek LLM endpoint’i, gerçek SSO/Keycloak sunucusu, tarayıcı otomasyonu, API anahtarı veya internet gerektirmeden hızlı ve deterministik çalışacak şekilde tasarlanmıştır.

Eklenen test altyapısı:

- `tests/testthat/helper_e2e_race_harness.R`
- `tests/testthat/test-e2e-quick-actions-streaming-regression.R`
- `tests/testthat/test-quick-action-routing.R`
- `tests/testthat/test-llm-content-reasoning-fallback.R`
- `tests/testthat/test-send-message-request-lifecycle-contract.R`
- `tests/testthat/test-file-manager-policy-contract.R`
- `tests/testthat/test-upload-validator.R`
- `tests/testthat/test-claude-code-run-lifecycle-contract.R`
- `tests/testthat/test-e2e-sso-identity-readiness-regression.R`

Ek ön yüz seçici sözleşmesi dosyası:

- `tests/testthat/test-frontend-selector-contract.R`: güncel chat input, send/stop, welcome, Dosya Yönetimi, STT/TTS ve Bilge Yolaç selector/DOM sözleşmelerini ve eski selector regresyonlarını doğrular.

Bu test; Ana Söyleşi giriş alanı, gönder/stop düğmesi, hoş geldin ve sohbet konteynerleri, dosya yükleme/sürükle-bırak seçicileri, File Manager bağlam checkbox sözleşmesi, STT görselleştirici anchor’ları ve Bilge Yolaç prompt/output/welcome streaming anchor’larının güncel UI ile hizalı kalmasını denetler. Windows VM ortamında bazı büyük JS dosyaları geçersiz UTF-8 uyarısı üretebildiği için test, dosyaları raw byte olarak okuyup `iconv(..., sub = "byte")` ile normalize eder ve ASCII seçici kontrollerini byte-safe fixed matching ile yapar. Bu okuyucu düz `readLines(..., encoding = "UTF-8")` ile değiştirilmemelidir.

Son hızlı eylem istemci güvenliği güncellemesi de aynı dilimin kapsamındadır. Karşılama ekranındaki hızlı eylem düğmeleri, aynı eylem/model çiftine çok kısa aralıkla yapılan çift tıklamaları Shiny olayına dönüştürmeden istemci tarafında bastırır; farklı bir hızlı eyleme geçiş ise engellenmez. Bu davranış `www/js/shiny_message_handlers.js` içindeki `_handleQuickAction` işleyicisinin debounce sözleşmesi ve `tests/testthat/test-e2e-quick-actions-streaming-regression.R` içindeki deterministik istemci koruması testleriyle korunur.

LLM yanıt ayrıştırma davranışı da genişletilmiştir. `extract_llm_content_and_sources()` artık OpenAI uyumlu `message$content`, streaming `delta$content`, `text` alanı, iç içe metin düğümleri ve `reasoning_content` fallback senaryoları için odak testlerle korunur. Fallback açıkken boş content reasoning metnine düşebilir; fallback kapalıyken görünür content boş kalır ancak reasoning izi korunur.

Son medya/ses yarış durumu dilimi de aynı test mimarisine eklenmiştir:

- `tests/testthat/helper_e2e_media_audio_harness.R`
- `tests/testthat/test-e2e-media-audio-state-regression.R`

Son dosya bağlamı ve yenileme yarış durumu dilimi de aynı deterministik test mimarisine eklenmiştir:

- `tests/testthat/helper_e2e_file_context_harness.R`
- `tests/testthat/test-e2e-file-context-regression.R`

Son kayıtlı söyleşi, geçmiş ve görsel galeri yarış durumu dilimi de aynı deterministik test mimarisine eklenmiştir:

- `tests/testthat/helper_e2e_chat_persistence_harness.R`
- `tests/testthat/test-e2e-chat-persistence-regression.R`

Son sağlık paneli yarış durumu dilimi de aynı deterministik test mimarisine eklenmiştir:

- `tests/testthat/helper_e2e_health_dashboard_harness.R`
- `tests/testthat/test-e2e-health-dashboard-regression.R`

Son boot/karşılama ekranı regresyon dilimi de aynı deterministik test mimarisine eklenmiştir:

- `tests/testthat/test-e2e-boot-welcome-regression.R`

Son premium reasoning / thinking UI regresyon dilimi de aynı deterministik test mimarisine eklenmiştir:

- `tests/testthat/helper_e2e_reasoning_ui_harness.R`
- `tests/testthat/test-e2e-premium-reasoning-ui-regression.R`

Son streaming istemci request-id güvenliği regresyon dilimi de aynı deterministik test mimarisine eklenmiştir:

- `tests/testthat/test-e2e-streaming-client-request-id-regression.R`
- `tests/testthat/test-send-message-prompting-contract.R`

Son SSO kimlik hazır olma ve refreshable modül yarış durumu dilimi de aynı deterministik test mimarisine eklenmiştir:

- `tests/testthat/helper_e2e_sso_identity_harness.R`
- `tests/testthat/test-e2e-sso-identity-readiness-regression.R`

Bu kayıtlı söyleşi/geçmiş/galeri dilimi; gerçek DB, gerçek LLM, gerçek görsel üretim endpoint’i veya tarayıcı otomasyonu gerektirmeden kayıtlı söyleşi sıralamasını, aynı request için final yanıtın yalnızca bir kez kalıcılaştırılmasını, eski kayıtlı söyleşi yüklenirken TTS’in otomatik tetiklenmemesini, mevcut söyleşi silindikten sonra stale load olayının yoksayılmasını, geçersiz/erken kullanıcı kimliğiyle geçmiş ve galeri refresh akışlarının mevcut geçerli state’i silmemesini ve galeri yenilemenin kullanıcı kapsamını korumasını sınar. Türkçe başlık ve içerikler bu test diliminde özellikle korunur.

Bu sağlık paneli dilimi; gerçek DB, gerçek LLM, gerçek TTS/STT, gerçek görsel üretim endpoint’i, tarayıcı otomasyonu veya public internet gerektirmeden Sistem Durumu panelinin offline ve güvenli refresh sözleşmelerini sınar. Panel çıktılarında gizli değerlerin yalnızca tanımlı/eksik biçiminde gösterilmesini, public endpoint yapılandırmalarında ağ çağrısı yapılmadan uyarı/atlandı sonucuna dönülmesini, aynı refresh sonucunun ikinci kez uygulanmamasını, eski refresh sonuçlarının yeni panel durumunu ezmemesini ve `R/helpers_health_checks.R`, `R/module_health.R`, `ui.R`, `www/js/health_dashboard.js` içindeki kritik health dashboard wiring/hook sözleşmelerinin korunmasını denetler.

Bu boot/karşılama dilimi; gerçek DB, gerçek LLM, gerçek TTS/STT, gerçek görsel üretim endpoint’i, tarayıcı otomasyonu veya public internet gerektirmeden uygulamanın non-SSO test modunda güvenli biçimde source edilebilmesini, `MERGEN_RUN_APP=false` ve `MERGEN_DISABLE_FUTURES=true` kapılarının korunmasını, `create_mergen_app()` çıktısının geçerli Shiny uygulaması olmasını, modern karşılama ekranının hızlı işlem kartları ve son konuşmalarla render edilmesini, hızlı işlem/prompt gönderim/client restore yollarının birbirinden ayrık kalmasını ve browser/localStorage restore akışının eski sohbet yüklerken TTS veya müzik tetiklememesini sınar. Türkçe karakterlerin karşılama HTML’i ve statik JS/R sözleşmelerinde bozulmadan kalması bu dilimde özellikle korunur.

Bu premium reasoning / thinking UI dilimi; gerçek tarayıcı DOM’u, gerçek LLM, gerçek SSE endpoint’i, gerçek DB veya public internet gerektirmeden düşünen modellerin canlı akıl yürütme paneli yaşam döngüsünü deterministik olarak sınar. Testler; panelin aynı istek için yinelenmemesini, yeni istek başladığında eski reasoning callback’lerinin yoksayılmasını, stream başlangıcında panelin doğru mesaj balonuna taşınmasını, reset/finalization akışının idempotent kalmasını, simulated reasoning fazlarının gerçek reasoning olarak kalıcılaştırılmamasını ve görünür yanıt içeriği ile reasoning izinin birbirine karışmamasını korur. Windows VM üzerinde kodlama uyarılarını önlemek için statik JS/R sözleşme kontrolleri ASCII-safe/byte-safe yaklaşımı izler.

Bu streaming istemci request-id güvenliği dilimi; gerçek tarayıcı DOM’u, gerçek LLM, gerçek SSE endpoint’i, gerçek DB veya public internet gerektirmeden true SSE ve premium reasoning istemci mesajlarının aynı istek kimliğiyle korunmasını sınar. Testler; `premiumReasoningStart`, `premiumReasoningStreamStart`, `initStreamingMessage`, `streamingReasoningDelta`, `streamingDelta`, `streamingUpdate` ve `finalizeStreamingMessage` mesajlarında `requestId` sözleşmesinin korunmasını, eski/stale callback’lerin yeni aktif isteği kirletmemesini ve istemci tarafı finalization işleminin aynı istek için yinelenmemesini denetler. Bu dilim, server tarafındaki request-id/finalization korumalarını tarayıcı mesaj katmanına bağlayan statik ve byte-safe sözleşme kontrolüdür.

Bu send_message prompt bağlamı sözleşmesi; gerçek DB, gerçek LLM, gerçek SSE endpoint’i veya tarayıcı otomasyonu gerektirmeden karakter/system prompt hazırlığını, kaynakça talimatlarını, SQL system prompt birleştirmesini, MCP Excel dosya bağlamı talimatlarını ve MCP kapalı dosya özet bağlamını sınar. Böylece `R/helpers_send_message_prompting.R` içine taşınan davranışların `R/server_send_message.R` içine geri dağılması veya kullanıcıya görünen prompt sözleşmelerinin bozulması erken yakalanır.

Bilge Yolaç sunucu tarafı akış yaşam döngüsü için eklenen sözleşme de aynı yaklaşımı izler: normal `Tamamlandı` ve `Hata` finalization yolları request-id parametresiz kalamaz. Böylece durdurma ve zaman aşımı yollarında zaten kullanılan stale-run koruması, normal süreç tamamlanması ve hata bitişleri için de zorunlu hale gelir.

Bu SSO kimlik hazır olma dilimi; gerçek Keycloak, gerçek DB, gerçek LLM, gerçek tarayıcı, gerçek TTS/STT, gerçek görsel üretim endpoint’i veya public internet gerektirmeden SSO oturum geçişlerinde geçici `user_id = 0` ile çalışan erken modül yenilemelerini deterministik olarak sınar. Testler; File Manager ve Görsel Galerisi gibi refreshable modüllerin SSO kimliği gerçekten hazır olmadan kullanıcı kapsamlı yenileme yapmamasını, SSO zaten hazırsa ilk yenilemenin observer beklemeden hemen yapılmasını, yerel non-SSO modun bu SSO hook’undan etkilenmemesini ve `R/server_module_wiring.R` içindeki auth-ready refresh wiring sözleşmesinin korunmasını denetler.

Son server runtime sözleşme refactor’ında düşük seviyeli runtime doğrulama ve auth-ready callback hata sarmalama yardımcıları R/helpers_server_runtime_contracts.R dosyasına ayrılmıştır. R/server_runtime_context.R artık ağırlıklı olarak runtime context orkestrasyonu, modül bağlama ve SSO auth-ready refresh akışına odaklanır. serverRuntimeOnSsoAuthReady() içinde SSO zaten hazır olduğunda çalışan immediate yol ile observer üzerinden çalışan yol aynı callback sarmalayıcısını kullanır; böylece File Manager, Görsel Galerisi ve benzeri refreshable modüllerde auth-ready davranışının iki farklı kolda sessizce ayrışması engellenir. Bu kaynak sırası ve davranış sözleşmesi test-server-runtime-context.R, test-source-manifest-contract.R ve test-maintainability-ratchet.R ile korunur.

Bu dosya bağlamı dilimi; gerçek DB, gerçek kalıcı dosya deposu, gerçek LLM veya tarayıcı otomasyonu gerektirmeden Dosya Yönetimi yükleme/bağlama durumunu, özetleme modu uzantı kısıtlarını, MCP Excel-only ve tek Excel dosyası kuralını, geçersiz/erken kullanıcı kimliğiyle refresh atlamayı, stale refresh sonuçlarının yeni state’i ezmemesini ve tarayıcı yenilemesi sonrası stale attachment ID’lerinin güvenle yok sayılmasını sınar. Türkçe dosya adları bu akışta özellikle korunur.

Bu medya dilimi; gerçek tarayıcı `Audio`, mikrofon, TTS/STT endpoint’i, DB, LLM veya public internet gerektirmeden TTS kuyruğu, STT modal sessize alma/geri yükleme davranışı ve arka plan müziği tek ses kaynağı sözleşmesini deterministik olarak sınar. Windows VM üzerinde JS dosyalarındaki Türkçe yorumlardan kaynaklanabilecek native/ANSI kodlama farkları için JS sözleşme testi byte-safe okuma kullanır; test yalnızca ASCII hook/adlandırma sözleşmelerini arar ve invalid UTF-8 uyarısı üretmemelidir.

Bu ilk regresyon dilimi özellikle hızlı eylemler ve gerçek SSE akış yaşam döngüsü etrafındaki sistemik riskleri hedefler:

- hızlı eylem tıklamasının doğru araç/model modunu seçmesi,
- hoş geldin ekranının kapanması ve hazır yönlendirme mesajının gösterilmesi,
- hızlı eylem tıklamasının kendiliğinden LLM çağrısı başlatmaması,
- hızlı eylem intro mesajının DB’ye, kayıtlı söyleşilere veya model bağlamına eklenmemesi,
- hızlı çift tıklamada tek aktif araç moduna yakınsama,
- aynı hızlı eylem/model çiftine yapılan çok hızlı çift tıklamanın tarayıcı tarafında Shiny olayına dönüşmeden bastırılması,
- farklı hızlı eyleme hızlı geçişin korunması ve son seçilen araç/model durumunun geçerli kalması,
- hızlı eylemin hemen ardından gönderilen kullanıcı isteminin yalnızca tek LLM isteği üretmesi,
- SSE görünür delta metni ile reasoning delta metninin ayrı kalması,
- aynı istek için stream finalization işleminin yalnızca bir kez gerçekleşmesi,
- stale async/finalization callback’lerinin yeni isteği ezmemesi,
- stop-generation bayrağının bir sonraki isteğe sızmaması,
- simulated reasoning fazlarının gerçek reasoning olarak kalıcılaştırılmaması.

Medya/ses regresyon dilimi ayrıca şu sözleşmeleri korur:

- arka plan müziğinde aynı anda yalnızca tek aktif ses kaynağı bulunması,
- gecikmiş/eski playlist yanıtlarının yeni müzik durumunu ezmemesi,
- karakter veya mod değişiminde eski parçanın temizlenip yeni akışa geçilmesi,
- TTS parçalarının indeks sırasına göre kuyruklanması,
- TTS konuşurken arka plan müziğinin kısılması ve kuyruk tamamen bitmeden geri yükselmemesi,
- TTS durdurulduğunda kuyruk, aktif ses ve `tts_is_playing` durumunun temizlenmesi,
- STT modalı açıkken müziğin tam sessize alınması,
- STT aktifken normal TTS/music unduck çağrılarının müziği erken geri getirmemesi,
- STT modalı kapandığında müzik durumunun güvenli biçimde geri yüklenmesi,
- sayfa geçişi veya yeni söyleşi sırasında stale TTS/STT/müzik durumunun kalmaması,
- `music_manager.js`, `tts_manager.js`, `stt_client.js` ve `premium_reasoning.js` içinde beklenen JS hook sözleşmelerinin korunması.

Dosya bağlamı regresyon dilimi ayrıca şu sözleşmeleri korur:

- desteklenen dosya yüklendiğinde Dosya Yönetimi state’inde ve tabloda görünmesi,
- `Model Bağlamı` seçiminin parent oturum dosya bağlamını güncellemesi,
- özetleme modunda yalnızca desteklenen belge türlerinin bağlama alınması,
- MCP/Excel modunda Excel dışı dosyaların ve fazla Excel seçimlerinin kaldırılması,
- MCP/Excel modunda aynı anda yalnızca tek Excel dosyasının bağlamda kalması,
- SSO kimliği hazır değilken veya kullanıcı kimliği geçersizken refresh’in mevcut dosya state’ini silmemesi,
- request-token tabanlı stale refresh korumasının yeni refresh sonucunu koruması,
- tarayıcı yenilemesi veya eski client state geri yüklemesinde ghost attachment ID’lerinin bağlamı bozmaması,
- `module_file_manager.R` ile `file_handlers.js` arasındaki upload, file action, attach toggle ve silent attach-state hook sözleşmelerinin korunması.

Kayıtlı söyleşi/geçmiş/galeri regresyon dilimi ayrıca şu sözleşmeleri korur:

- yeni tamamlanan yanıt sonrasında kayıtlı söyleşi sıralamasının son aktiviteye göre güncellenmesi,
- aynı request için stream/finalization sonucu iki kez kaydedilmemesi,
- kayıtlı eski bir söyleşi yüklenirken TTS’in otomatik başlamaması,
- mevcut söyleşi silindiğinde hoş geldin ekranına güvenli şekilde dönülmesi,
- silinen söyleşiye ait gecikmiş/stale yükleme olaylarının yeni UI state’ini ezmemesi,
- geçmiş yenilemede geçersiz veya erken kullanıcı kimliğinin mevcut geçerli cache’i temizlememesi,
- görsel galeri yenilemesinin kullanıcı kapsamını koruması,
- geçersiz kullanıcı kimliğiyle galeri refresh denemesinin önceki geçerli kullanıcı cache’ini silmemesi,
- `server_observers_saved_chats.R`, `module_saved_chats.R`, `module_chat_history.R`, `module_image_gallery.R` ve `server_module_wiring.R` içindeki kritik wiring/race sözleşmelerinin korunması.

Sağlık paneli regresyon dilimi ayrıca şu sözleşmeleri korur:

- gizli ortam değişkenleri ve token/parola/API anahtarı benzeri değerler ham biçimde sağlık çıktısına veya render edilmiş sekme metnine sızmamalıdır,
- public internet endpoint’leri sağlık panelinden doğrudan çağrılmamalı; ağ denemesi yapılmadan uyarı/atlandı durumuna düşmelidir,
- yerel/on-prem endpoint kontrolleri testlerde stub ile temsil edilir ve public internet gerektirmez,
- aynı refresh isteğinin sonucu yalnızca bir kez uygulanmalıdır,
- daha eski refresh sonuçları yeni panel durumunu ezmemelidir,
- timestamp ve tooltip temizleme custom message sözleşmeleri korunmalıdır,
- sağlık paneli JS dosyası public URL bağımlılığı taşımamalıdır,
- `R/helpers_health_checks.R`, `R/module_health.R`, `ui.R` ve `www/js/health_dashboard.js` içindeki offline refresh, public URL guard ve cleanup hook sözleşmeleri korunmalıdır.

Odak test koşumu:

    testthat::test_file("tests/testthat/test-e2e-boot-welcome-regression.R")
    testthat::test_file("tests/testthat/test-e2e-premium-reasoning-ui-regression.R")
    testthat::test_file("tests/testthat/test-e2e-streaming-client-request-id-regression.R")
    testthat::test_file("tests/testthat/test-e2e-sso-identity-readiness-regression.R")
    testthat::test_file("tests/testthat/test-e2e-quick-actions-streaming-regression.R")
    testthat::test_file("tests/testthat/test-e2e-media-audio-state-regression.R")
    testthat::test_file("tests/testthat/test-e2e-file-context-regression.R")
    testthat::test_file("tests/testthat/test-e2e-chat-persistence-regression.R")
    testthat::test_file("tests/testthat/test-e2e-health-dashboard-regression.R")

İlgili destekleyici kontrat testleri:

    testthat::test_file("tests/testthat/test-send-message-request-lifecycle-contract.R")
    testthat::test_file("tests/testthat/test-quick-action-routing.R")
    testthat::test_file("tests/testthat/test-llm-content-reasoning-fallback.R")
    testthat::test_file("tests/testthat/test-file-manager-policy-contract.R")
    testthat::test_file("tests/testthat/test-upload-validator.R")
    testthat::test_file("tests/testthat/test-claude-code-run-lifecycle-contract.R")
    testthat::test_file("tests/testthat/test-llm-stream-io-contract.R")
    testthat::test_file("tests/testthat/test-streaming-should-stop.R")
    testthat::test_file("tests/testthat/test-sse-worker-export-contract.R")
    testthat::test_file("tests/testthat/test-file-manager-context-policy-contract.R")
    testthat::test_file("tests/testthat/test-file-manager-refresh-guard-contract.R")
    testthat::test_file("tests/testthat/test-file-manager-state-runtime-contract.R")
    testthat::test_file("tests/testthat/test-file-manager-module-policy-wiring.R")
    testthat::test_file("tests/testthat/test-resolve-uploaded-file.R")
    testthat::test_file("tests/testthat/test-server-chat-persistence-wiring-contract.R")
    testthat::test_file("tests/testthat/test-health-check-formatters.R")
    testthat::test_file("tests/testthat/test-health-check-paths.R")
    testthat::test_file("tests/testthat/test-health-check-env-contract.R")
    testthat::test_file("tests/testthat/test-health-check-runtime-contract.R")
    testthat::test_file("tests/testthat/test-maintainability-ratchet.R")
    source("tests/scripts/maintainability_report.R", encoding = "UTF-8")

Tam sıkı koşum:

    source("tests/testthat.R", encoding = "UTF-8")

Ayrıca `tests/testthat/test-resolve-uploaded-file.R` bireysel çalıştırıldığında da kendi gerekli File Store kaynak zincirini yükleyecek şekilde güçlendirilmiştir. Böylece bu test yalnızca tam suite içinde önceki testlerin global ortamda bıraktığı fonksiyonlara bağlı kalmaz.

`tests/testthat/test-llm-reasoning-request-overrides.R` tek başına çalıştırıldığında test log dizinini güvenli biçimde hazırlar ve logger appender’ını geçici test log dosyasına yönlendirir; böylece strict test koşumunda `stop_on_warning = TRUE` altında eksik log dosyası uyarısı üretmemelidir.

Bu testler yalnızca test dosyaları altında bulunduğu için çalışma zamanı bakım yapılabilirlik ratchet’ini değiştirmez; `maintainability_report.R` çalışma zamanı dosyalarını değerlendirmeye devam eder. Kayıtlı söyleşi/geçmiş/galeri dilimi de bu kurala uyar; yeni yardımcı ve test dosyaları `tests/testthat/` altında kalır ve runtime dosya satır/fonksiyon eşiklerini etkilemez.

### Üretim Sertleştirme ve Upload Testleri
Son Windows VM gerçek preflight sertleştirmesinde tests/scripts/run_vm_preflight_real.R betiği SSO üretim yapılandırmasını varsayılan olarak zorunlu doğrulayacak şekilde güçlendirilmiştir. Gerçek VM koşumunda MERGEN_PREFLIGHT_REQUIRE_SSO=TRUE varsayılandır; bu durumda SSO_ENABLED=TRUE olmalı ve SSO_KEYCLOAK_URL tanımlı bulunmalıdır. LOCAL_LLM_ENDPOINT, DB_DSN ve AI_KEYS_MASTER gibi zorunlu ortam değişkenleri eksikse preflight uygulama boot etmeden önce hızlı ve açık bir hata ile durur. app.R yüklendikten sonra SSO_CONFIG içindeki issuer_url, auth_endpoint, logout_endpoint, token_endpoint, client_id ve realm alanları da doğrulanır. Böylece Windows VM üzerinde uygulamanın yanlışlıkla lokal/non-SSO kimlik modunda açılıp kullanıcı bazlı sohbet, dosya, geçmiş ve galeri akışlarını yanlış kullanıcı bağlamında test etmesi engellenir.

Son Windows VM preflight güncellemesiyle gerçek üretim kontrolü iki katmana ayrılmıştır. Varsayılan koşum; uygulama boot doğrulaması, SSO yapılandırması, temel yazılabilir dizinler, atomik yazım, UTF-8 yaz/oku roundtrip, canlı `current_user_id` provider sözleşmesi, gerçek DB sağlık kontrolü ve yerel LLM endpoint erişilebilirlik kontrolünü kapsar. Gerçek paylaşımlı/indexli dosya deposuna dokunan File Store roundtrip kontrolü ise daha ağır ve ortama duyarlı bir tanılama olduğu için varsayılan olarak kapalıdır; gerektiğinde `MERGEN_PREFLIGHT_CHECK_FILE_STORE=TRUE` ile açıkça çalıştırılır. Preflight betiği kendi ayarladığı `MERGEN_DISABLE_FUTURES`, `MERGEN_RUN_APP` ve `MERGEN_SQL_LOADER_STRICT` değerlerini çıkışta geri yükler; böylece aynı R oturumunda daha sonra çalıştırılan `testthat` koşumları preflight strict ortamından etkilenmez.

Son SSO yenileme sertleştirmesinde `ServerRuntimeContext` içindeki auth-ready refresh sözleşmesi güçlendirilmiştir. SSO kimlik doğrulaması ve kullanıcı kimliği hazır olma durumu, File Manager veya Görsel Galeri gibi refreshable modüllerin observer kaydından önce tamamlanmışsa `serverRuntimeOnSsoAuthReady(...)` callback’i artık observer olayını beklemeden güvenli biçimde hemen çalıştırır. Böylece Windows VM SSO akışında ilk kalıcı dosya/galeri yenilemesinin kaçırılması ve modüllerin manuel yenilemeye kadar boş kalması riski azaltılmıştır. Bu koruma, yeni üst seviye helper fonksiyon eklemeden mevcut runtime fonksiyonu içinde tutulduğu için bakım yapılabilirlik ratchet’i `100/100`, 25+ fonksiyon dosyası sayısı `0` ve en yüksek fonksiyon sayısı `24` taban çizgisinde kalır.

Lokal veya non-SSO smoke koşumu gerektiğinde bu kontrol açıkça devre dışı bırakılabilir:

    Sys.setenv(MERGEN_PREFLIGHT_REQUIRE_SSO = "FALSE")
    source("tests/scripts/run_vm_preflight_real.R", encoding = "UTF-8")

Windows VM üretim-benzeri koşumda beklenen kullanım:

    Sys.setenv(MERGEN_PREFLIGHT_REQUIRE_SSO = "TRUE")
    source("tests/scripts/run_vm_preflight_real.R", encoding = "UTF-8")

Opsiyonel File Store roundtrip tanılaması gerektiğinde:

    Sys.setenv(MERGEN_PREFLIGHT_CHECK_FILE_STORE = "TRUE")
    source("tests/scripts/run_vm_preflight_real.R", encoding = "UTF-8")

Bu kontrol, gerçek dosya deposu/index/display-name çözümleme hattına dokunduğu için günlük hızlı VM preflight koşumunun parçası değildir. Dosya yükleme akışı normal çalışıyor ancak kalıcı indeks, görünen ad veya path çözümleme davranışı özel olarak incelenecekse kullanılmalıdır.

Bu preflight sözleşmesi aşağıdaki odak testlerle korunur:

    testthat::test_file("tests/testthat/test-vm-preflight-contract.R")
    testthat::test_file("tests/testthat/test-vm-preflight-guard-contract.R")
    testthat::test_file("tests/testthat/test-vm-preflight-helper-contract.R")

SSO auth-ready refresh sözleşmesi ayrıca aşağıdaki odak testlerle korunur:

    testthat::test_file("tests/testthat/test-server-runtime-context.R")
    testthat::test_file("tests/testthat/test-server-module-wiring-runtime-bindings.R")
    source("tests/scripts/run_vm_preflight_real.R", encoding = "UTF-8")

Son üretim sertleştirme kapsamında aşağıdaki testler ana test koşumuyla uyumlu hâle getirilmiştir:

```r
source("tests/testthat.R", encoding = "UTF-8")

testthat::test_file("tests/testthat/test-production-contracts.R")
testthat::test_file("tests/testthat/test-db-refactor-contract.R")
testthat::test_file("tests/testthat/test-chat-message-formatting-refactor-contract.R")
testthat::test_file("tests/testthat/test-claude-code-document-extractors-refactor-contract.R")
testthat::test_file("tests/testthat/test-claude-code-document-extractors-maintainability-contract.R")
testthat::test_file("tests/testthat/test-upload-size-policy.R")
testthat::test_file("tests/testthat/test-file-manager-policy-contract.R")
testthat::test_file("tests/testthat/test-file-manager-context-policy-contract.R")
testthat::test_file("tests/testthat/test-file-manager-refresh-guard-contract.R")
testthat::test_file("tests/testthat/test-file-manager-module-policy-wiring.R")
testthat::test_file("tests/testthat/test-file-manager-state-runtime-contract.R")
testthat::test_file("tests/testthat/test-file-manager-ui-refactor-contract.R")
testthat::test_file("tests/testthat/test-file-manager-upload-limit-ui.R")
testthat::test_file("tests/testthat/test-api-model-config-refactor-contract.R")
testthat::test_file("tests/testthat/test-llm-reasoning-request-overrides.R")
testthat::test_file("tests/testthat/test-sse-worker-export-contract.R")
testthat::test_file("tests/testthat/test-llm-stream-io-contract.R")
testthat::test_file("tests/testthat/test-streaming-should-stop.R")
testthat::test_file("tests/testthat/test-server-user-session-context.R")
testthat::test_file("tests/testthat/test-user-session-identity-contract.R")
testthat::test_file("tests/testthat/test-server-runtime-context.R")
testthat::test_file("tests/testthat/test-server-runtime-context-accessors.R")
testthat::test_file("tests/testthat/test-server-core-interaction-runtime.R")
testthat::test_file("tests/testthat/test-server-module-wiring-runtime-bindings.R")
testthat::test_file("tests/testthat/test-server-module-wiring-chat-engine.R")
testthat::test_file("tests/testthat/test-session-user-data-store.R")
testthat::test_file("tests/testthat/test-server-boundary-contract.R")
testthat::test_file("tests/testthat/test-helpers-files-path-contract.R")
testthat::test_file("tests/testthat/test-file-manager-display-name-contract.R")
testthat::test_file("tests/testthat/test-source-manifest-contract.R")
testthat::test_file("tests/testthat/test-server-live-user-provider-contract.R")
testthat::test_file("tests/testthat/test-server-chat-persistence-wiring-contract.R")
testthat::test_file("tests/testthat/test-effective-user-id.R")
testthat::test_file("tests/testthat/test-offline-baseline-contract.R")
testthat::test_file("tests/testthat/test-mcp-session-user-id-contract.R")
testthat::test_file("tests/testthat/test-mcp-path-fallback-contract.R")
testthat::test_file("tests/testthat/test-mcp-debug-output-contract.R")
testthat::test_file("tests/testthat/test-mcp-bootstrap-refactor-contract.R")
testthat::test_file("tests/testthat/test-mcp-table-readers-refactor-contract.R")
testthat::test_file("tests/testthat/test-mcp-file-resolver-refactor-contract.R")
testthat::test_file("tests/testthat/test-mcp-basic-tools-refactor-contract.R")
testthat::test_file("tests/testthat/test-mcp-chart-tools-refactor-contract.R")
testthat::test_file("tests/testthat/test-chartlab-spec-refactor-contract.R")
testthat::test_file("tests/testthat/test-mcp-analyze-visualize-refactor-contract.R")
testthat::test_file("tests/testthat/test-logging-console-color-policy.R")
testthat::test_file("tests/testthat/test-llm-content-reasoning-fallback.R")
testthat::test_file("tests/testthat/test-admin-yanit-analizi-refactor-contract.R")
testthat::test_file("tests/testthat/test-admin-hata-analizi-refactor-contract.R")
testthat::test_file("tests/testthat/test-admin-geri-bildirim-query-contract.R")
testthat::test_file("tests/testthat/test-maintainability-ratchet.R")
testthat::test_file("tests/testthat/test-pk-analysis-security-summary-contract.R")
testthat::test_file("tests/testthat/test-claude-code-ui-refactor-contract.R")
testthat::test_file("tests/testthat/test-claude-code-model-config-refactor-contract.R")
testthat::test_file("tests/testthat/test-claude-code-process-refactor-contract.R")
testthat::test_file("tests/testthat/test-claude-code-runtime-workdir-contract.R")
testthat::test_file("tests/testthat/test-claude-code-workdir-scan-contract.R")
testthat::test_file("tests/testthat/test-claude-code-upload-folder-refactor-contract.R")
testthat::test_file("tests/testthat/test-claude-code-dir-ui-refactor-contract.R")
testthat::test_file("tests/testthat/test-claude-code-directory-listing-contract.R")
testthat::test_file("tests/testthat/test-claude-code-user-guard-contract.R")
testthat::test_file("tests/testthat/test-claude-code-run-lifecycle-contract.R")
testthat::test_file("tests/testthat/test-claude-code-stream-finalize-contract.R")
```

`tests/testthat.R` ana koşucusu sıkı modda kalmalıdır: `stop_on_failure = TRUE` ve `stop_on_warning = TRUE`. Bu nedenle üretim sözleşmesi testleri geniş, uyarı üretebilecek recursive kaynak taramalarından kaçınmalı; kritik boot/runtime sözleşmelerini deterministik ve warning-safe biçimde doğrulamalıdır.
Bu kapsamda eklenen `test-offline-baseline-contract.R`, air-gapped Windows VM üretim profili için temel offline sözleşmeyi varsayılan test koşumunda doğrular. Test, runtime R/CSS/JS dosyalarında açık CDN/public asset bağımlılığı arar ve `stop_on_warning = TRUE` ile uyumlu kalması için warning-safe metin tarama yaklaşımı kullanır. Daha geniş offline tarama hâlâ `MERGEN_STRICT_OFFLINE_TESTS=true` ile opsiyonel olarak çalıştırılır.

Runtime context accessor sözleşmesi `test-server-runtime-context-accessors.R`, `test-production-contracts.R`, `test-server-core-interaction-runtime.R`, `test-server-live-user-provider-contract.R` ve `test-file-manager-module-policy-wiring.R` ile korunur; bu testler eski ham `runtime_ctx$...` erişimini geri getirmek yerine doğrulanmış accessor kullanımını bekler.

Sunucu başlangıç mimarisinde kabul edilen güncel kimlik sınırı `serverRuntimeRequireIdentity(...)` sözleşmesidir. `server.R`, kimlik değerlerini doğrudan `user_session` veya `session$userData` üzerinden okumaz; önce `runtime_ctx` oluşturulur, ardından `identity <- serverRuntimeRequireIdentity(...)` ile doğrulanmış kimlik bölümü alınır ve mevcut canlı provider alias’ları bu sözleşmeden türetilir. Bu yaklaşım `serverRuntimeBuildIdentityPorts()` gibi ek bir identity-port katmanı gerektirmez; `R/server_runtime_context.R` dar kapsamlı boot-time context sınırı olarak kalmalıdır.

Son kullanıcı oturumu kimlik sözleşmesi güncellemesinde, kimlik ilişkili `session$userData` okuma/yazma akışı `R/helpers_user_session_identity.R` içindeki `make_user_session_data_accessors()` yardımcısı altında toplanmıştır. `apply_user_session_identity()` artık bu merkezi yazım yolunu kullanır; `R/server_init_user_session.R` ise SSO başlangıç yer tutucusunu ve fallback kimlik okumalarını aynı accessor üzerinden yürütür. Böylece SSO modunda `user_id = 0` başlangıç değerinin gerçek kullanıcı kimliğini maskelemesi, yerel/SSO davranışının ayrışması ve farklı helper’ların `session$userData` alanlarını örtük biçimde farklı yorumlaması riski azaltılmıştır. Bu davranış `test-user-session-identity-contract.R`, `test-server-user-session-context.R` ve `test-server-live-user-provider-contract.R` ile korunur.

Bakım yapılabilirlik takibi için `tests/scripts/maintainability_report.R` script’i repo kökünden çalıştırılabilir. Bu script test koşucusunu değiştirmez; büyük dosyaları, yaklaşık satır sayılarını ve fonksiyon sayılarını raporlayarak kontrollü refactor kararlarını destekler. `library_queries.R`, sorgu bilgi tabanı niteliğinde olduğu için bu raporda ayrıca değerlendirilmelidir.

Son LLM worker araç sonucu biçimlendirme refactor’ı sonrası güncel bakım yapılabilirlik ratchet taban çizgisi `100/100` skordur; 800+ satır dosya sayısı `0`, 25+ fonksiyon dosya sayısı `0`, 1500+ satır dosya sayısı `0`, maksimum dosya satırı `796` ve maksimum fonksiyon sayısı `24` olarak korunur. Bu güncel durumda maintainability raporunda refactor adayı kalmamıştır; bundan sonraki iyileştirmeler yalnızca skor takibi için değil, belirli üretim güvenilirliği veya yarış koşulu risklerini azaltmak için seçilmelidir.

Son API yapılandırması bakım refactor’ında model yeteneği çözümleme, thinking/reasoning istek override’ları, yerel LLM uç noktası/kimlik bilgisi çözümleme, API anahtarı doğrulama hedefi seçimi ve hızlı işlem/araç modu model eşleştirme yardımcıları `R/helpers_api_model_config.R` dosyasına ayrılmıştır. `R/config_api.R` artık ağırlıklı olarak ortam değişkenleri, `api_config`, TTS/STT ayarları ve API doğrulama orkestrasyonuna odaklanır. Bu ayrım `R/config_api.R` dosyasını 800 satır eşiğinin altına indirerek ara bakım adımlarında büyük dosya/fonksiyon eşiği riskini azaltmış; son kabul edilen ratchet durumunda bakım yapılabilirlik taban çizgisi `100/100` olarak korunmaktadır. Kaynak sırası `R/config_api.R` → `R/helpers_api_model_config.R` → LLM/SSE helper katmanı şeklinde korunmalıdır; bu sözleşme `test-api-model-config-refactor-contract.R`, `test-llm-reasoning-request-overrides.R`, `test-source-manifest-contract.R`, `test-sse-worker-export-contract.R` ve `test-maintainability-ratchet.R` ile güvence altına alınır.

LLM gerçek akış hattında SSE akış dosyası satır protokolü ayrı bir yardımcı dosyaya taşınmıştır. `R/helpers_llm_stream_io.R`; delta/reasoning JSONL satırı yazma, base64 payload çözme ve stop-file iptal kontrolü sorumluluklarını üstlenir. `R/helpers_llm_sse.R` ise SSE olay ayrıştırma, delta/reasoning çıkarımı, HTTP stream yönetimi ve worker orkestrasyonuna odaklanır. Bu ayrım, `helpers_llm_sse.R` dosyasını 800 satır ve 25 fonksiyon eşiklerinin altında tutarak gerçek streaming davranışını değiştirmeden bakım yapılabilirlik skorunu yükseltir.

Son LLM worker bakım refactor’ında mesaj payload ve grafik/içgörü hazırlama sorumlulukları `R/helpers_llm_worker_payload.R` dosyasına ayrılmıştır. Bu dosya sohbet geçmişini API mesajlarına dönüştürme, system mesajlarını öne birleştirme, grafik niyeti/türü algılama, devre dışı fallback grafik passthrough’u, grafik özeti ve otomatik içgörü üretimi gibi saf yardımcıları içerir. `R/helpers_llm_worker.R` artık MCP/LLM worker orkestrasyonu, API isteği, araç çağrısı, ikinci geçiş ve hata yönetimi akışına odaklanır. Eski ikinci geçiş/recursive yolların kırılmaması için `merge_system_messages_to_front()` uyumluluk sarmalayıcısı korunur. Bu ayrım `test-llm-worker-payload-refactor-contract.R`, `test-source-manifest-contract.R` ve `test-maintainability-ratchet.R` ile güvence altına alınır.

Son LLM worker araç sonucu refactor’ında MCP araç çıktılarının loglanması, tablo/grafik sonuçlarının ikinci geçiş için metne dönüştürülmesi, dataframe sonuçlarının markdown tabloya çevrilmesi ve araç sonuç metinlerinin birleştirilmesi `R/helpers_llm_worker_tool_results.R` dosyasına ayrılmıştır. `R/helpers_llm_worker.R` böylece API isteği, MCP orkestrasyonu, araç yürütme ve ikinci geçiş karar akışına odaklanır; `call_llm_worker()` public çalışma zamanı sözleşmesi korunmuştur. MCP araç yürütme sırasında canlı `settings$shiny_session` değerine geri dönmek yerine, üstte `mcp_registry_snapshot` ile hazırlanmış `session_obj` kullanılmalıdır; bu, async worker sırasında dosya bağlamı veya oturum durumu değişse bile snapshot korumasının boşa çıkmasını engeller. Kaynak sırası `R/helpers_llm_worker_payload.R` → `R/helpers_llm_worker_tool_results.R` → `R/helpers_llm_worker.R` olarak korunur. Bu ayrım ve yeni 100/100 ratchet taban çizgisi `test-llm-worker-payload-refactor-contract.R`, `test-llm-worker-tool-results-refactor-contract.R`, `test-source-manifest-contract.R` ve `test-maintainability-ratchet.R` ile güvence altına alınır.

Son ChartLab bakım refactor’ında grafik türü normalizasyonu, eksen/mapping tahmini ve agregasyon davranışı `R/helpers_chartlab_spec.R` dosyasına ayrılmıştır. `R/helpers_chartlab.R` artık ağırlıklı olarak `chartlab` bloklarını ayrıştırma, Shiny çıktı yer tutucularını üretme ve grafik motoru bağlama sorumluluğuna odaklanır. Kayıtlı veya tarayıcı yenilemesi sonrası geri yüklenen ChartLab mesajları da statik JS-only grafik yoluna bağımlı kalmadan aynı Shiny output placeholder kimliklerini üretir ve `chat_rebind_all_charts()` ile UI flush sonrasında yeniden bağlanır. Bu sayede canlı üretilen grafikler ile geçmişten açılan grafikler aynı render sözleşmesini paylaşır. Bu ayrım `test-chartlab-spec-refactor-contract.R`, `test-chat-message-formatting-refactor-contract.R`, `test-source-manifest-contract.R` ve `test-maintainability-ratchet.R` ile korunur.

`test-maintainability-ratchet.R`, bu raporu varsayılan test koşumunda regresyon korumasına dönüştürür: Son kabul edilen ratchet durumunda bakım yapılabilirlik taban çizgisi `100/100` skor, 800+ satır dosya sayısı `0`, 25+ fonksiyon dosya sayısı `0`, 1500+ satır dosya sayısı `0`, maksimum dosya satırı `796` ve maksimum fonksiyon sayısı `24` olarak güncellenmiştir. hedef ani bir büyük refactor zorlamak değil, mevcut tabanın kötüleşmesini engellemektir. Kullanıcı oturumu kimlik yardımcılarının ayrımı da aynı kademeli yaklaşımı izler: davranış korunur, source-order sözleşmesi `test-source-manifest-contract.R` ile, SSO/local kimlik davranışı ise `test-user-session-identity-contract.R` ile korunur. Dosya Yönetimi tarafındaki `fileManagerUI()` ayrımı ve MCP bootstrap ayrımı, büyük dosyaları kademeli olarak küçültme yaklaşımının örneklerindendir; bu ayrımlar hem kaynak sırası sözleşmeleriyle hem de bakım yapılabilirlik ratchet testiyle korunur. Son File Manager, Bilge Yolaç çalışma yaşam döngüsü/stop-finalization, LLM SSE stream I/O, MCP analyze/visualize, Admin Yanıt Analizi, Admin Geri Bildirim Analizi, Admin Hata Analizi ve Proje/Kaynak Analizi güvenlik-özet refactor’ları sonrasında Son dosya yolu/helper extraction ve Dosya Yönetimi temiz görüntü adı güncellemeleri sonrasında varsayılan ratchet eşikleri yeniden sıkılaştırılmıştır: minimum maintainability score: `100/100`, max 800+ line files: 0, max 25+ function files: 0, max 1500+ line files: 0, max file lines: 796, max file functions: 24. Dosya bazlı ratchet bütçeleri içinde `R/helpers_claude_code_workdir_scan.R`için sınır 423 satır ve 14 fonksiyon;`R/helpers_claude_code_workdir_snapshot.R`için sınır 450 satır ve 24 fonksiyon;`R/helpers_claude_code.R` için sınır 617 satır ve 29 fonksiyondur. Bu global değerler yalnızca raporun genel sayaçları gerçekten iyileştiğinde yeniden sıkılaştırılmalıdır.

Chat/mesaj yazma tarafında `R/helpers_db_chat_mutations.R` artık `create_new_chat_in_db()`, `save_message_to_db()`, `save_message_safely()`, `update_message_reasoning_content()`, `update_message_content_in_db()`, `update_chat_title_in_db()`, `delete_chat_from_db()`, `clear_all_chats_from_db()`, `worker_save_assistant_response()` ve `sanitize_input()` yardımcılarının sahibidir; `R/helpers_database.R` ise kullanıcı, SSO alanı, geri bildirim, usage-log ve kalan DB orkestrasyon sorumluluklarına odaklanır. `save_message_to_db()` ve `worker_save_assistant_response()` içindeki MessageOrder `UPDLOCK/HOLDLOCK` yarış koruması `test-db-refactor-contract.R` ile korunur; bu ayrım maintainability skorunu 84'ten 86'ya yükseltip 25+ fonksiyonlu dosya sayısını 5'ten 4'e indirmiştir.

Proje/Kaynak Analizi bakım refactor’ında `R/helpers_pk_analysis_security_summary.R` dosyası eklenmiştir. Bu dosya `resolve_pk_analysis_username()`, `get_user_rls_info()`, `apply_rls_to_data()` ve `generate_statistical_summary()` yardımcılarını içerir. `resolve_pk_analysis_username()` özellikle Windows VM SSO akışında kimlik doğrulama tamamlanmadan analiz hattının `Unknown` kullanıcısı ile RLS/DB sorgusuna düşmesini engeller. `R/module_proje_kaynak_analizi.R` artık bu yardımcıları çağıran sorgu/analiz orkestrasyonuna odaklanır. Bu ayrım `test-pk-analysis-security-summary-contract.R`, `test-source-manifest-contract.R` ve `test-maintainability-ratchet.R` ile korunur. Admin Hata Analizi ayrımı ayrıca `R/module_admin_hata_analizi.R` için 800 satır altı sınırını ve `R/helpers_admin_hata_analizi.R` için kontrollü helper boyutunu koruyan dosya bazlı ratchet testleriyle güvence altına alınır.

Fonksiyon slot yardımcısı da 25+ fonksiyonlu dosya sayısını artırmamak için ayrı dosyada tutulmuştur. Dosya bazlı kazanımlar ayrıca korunur; örneğin Admin Geri Bildirim Analizi ayrımı artık `MERGEN_TEST_MAX_ADMIN_GERI_BILDIRIM_LINES = 799` ve `MERGEN_TEST_MAX_ADMIN_GERI_BILDIRIM_FUNCTIONS = 5` eşikleriyle korunur; yeni SQL helper dosyası için `R/helpers_admin_geri_bildirim_queries.R` bütçesi 260 satır ve 3 fonksiyon olarak izlenir. Admin Yanıt Analizi ayrımı ise `MERGEN_TEST_MAX_ADMIN_YANIT_ANALIZI_LINES` ile korunabilir. Son Bilge Yolaç setup ve çalışma yaşam döngüsü extraction kazanımı ayrıca dosya bazlı ratchet ile korunur: `R/module_claude_code.R` için varsayılan üst sınır `MERGEN_TEST_MAX_CLAUDE_CODE_LINES = 799` olarak belirlenmiştir. Ek olarak mevcut büyük ve fonksiyon yoğun dosyalar için dosya bazlı bütçeler eklenmiştir; böylece genel skor değişmese bile `config_api.R`, `helpers_llm_worker.R`, `helpers_claude_code.R`, `helpers_db_chat_mutations.R`, azaltılmış `helpers_database.R` bütçesi, `helpers_chartlab.R` ve benzeri dosyaların sessizce büyümesi engellenir. Bu değer, mevcut 954 satırlık durumu korurken küçük güvenli düzeltmelere sınırlı hareket alanı bırakır. Bu sınır ancak yeni maintainability raporu daha iyi bir taban çizgisi gösterdiğinde sıkılaştırılmalıdır. LLM worker payload ayrımı da dosya bazlı ratchet ile korunur: `R/helpers_llm_worker.R` için varsayılan üst sınır `MERGEN_TEST_MAX_LLM_WORKER_LINES = 860`, `R/helpers_llm_worker_payload.R` için ise `MERGEN_TEST_MAX_LLM_WORKER_PAYLOAD_LINES = 320` ve `MERGEN_TEST_MAX_LLM_WORKER_PAYLOAD_FUNCTIONS = 12` olarak belirlenmiştir.

Bu değerler gerektiğinde `MERGEN_TEST_MIN_MAINTAINABILITY_SCORE`, `MERGEN_TEST_MAX_800_LINE_FILES`, `MERGEN_TEST_MAX_25_FUNCTION_FILES`, `MERGEN_TEST_MAX_1500_LINE_FILES`, `MERGEN_TEST_MAX_FILE_LINES` ve `MERGEN_TEST_MAX_FILE_FUNCTIONS` ile bilinçli olarak sıkılaştırılabilir. Windows VM’de yüklü `testthat` sürümüyle uyumluluk için testte sayısal helperlar yerine `expect_true(..., info = ...)` kullanılır.

Son Ana Söyleşi bakım refactor’ında mesaj gönderme yaşam döngüsü `R/helpers_send_message_request_lifecycle.R` dosyasına ayrılmıştır. Bu dosya istek kimliği üretimi, current/stale/stopped istek ayrımı, prompt snapshot alma, ertelenmiş sohbet oluşturma kararı, sohbet hazırlığı, hoş geldin ekranı temizliği, düşünme paneli planı ve true-streaming ertelenmiş kalıcı kayıt koruması gibi küçük yardımcıları içerir. `R/server_send_message.R` artık mesaj gönderme orkestrasyonuna odaklanır ve 800 satır eşiğinin altına indirilmiştir. True-streaming hattında ertelenmiş sohbet kalıcı kaydı, eski veya finalize edilmiş isteklerin yeni sohbet durumunu ezmesini önlemek için `mergen_should_run_deferred_stream_persist(...)` korumasından geçer. Bu kazanım `test-send-message-request-lifecycle-contract.R`, `test-send-message-maintainability-ratchet.R`, `test-source-manifest-contract.R` ve ana `test-maintainability-ratchet.R` ile korunur.

Bilge Yolaç doküman işleme hattında extractor sorumlulukları ayrı dosyaya taşınmıştır. `R/helpers_claude_code_document_extractors.R`; ikili doküman uzantı politikası, PDF/Excel/DOCX metin çıkarımı, destek dizini hazırlığı, cache adı temizleme ve yerel office reader template yolu çözümleme işlerinden sorumludur. `R/helpers_claude_code_documents.R` ise rehber/manifest üretimi, inline payload oluşturma, doküman prompt’u hazırlama, doküman bağlamı kurma ve doküman özetleme yardımcılarına odaklanır. Bu ayrım `global.R` kaynak sırasında extractor dosyasının `helpers_claude_code_documents.R` öncesinde yüklenmesini gerektirir.

Bilge Yolaç’ın ana UI ve model/config katmanları da aynı ratcheted refactor yaklaşımıyla ayrılmıştır. `R/module_claude_code_ui.R`, `claudeCodeUI()` tanımını içerir ve `R/module_claude_code.R` dosyasının sunucu sorumluluklarına odaklanmasını sağlar. `R/helpers_claude_code_model_config.R` ise CLI yolu çözümleme, `settings.json` okuma, model katman eşleştirme, düşünme modeli yetenekleri ve ikili doküman görevlerinde model fallback kararlarını içerir. Bu ayrımlar sırasıyla `test-claude-code-ui-refactor-contract.R` ve `test-claude-code-model-config-refactor-contract.R` ile korunur.

Son MCP/loglama sertleştirme güncellemeleriyle dosya çözümleme ve Excel okuma hattı daha güvenli hâle getirilmiştir. `helpers_mcp_tools$get_session_user_id()` artık yalnızca scalar kullanıcı kimliği döndürür ve dosya kayıt defteri olan `current_session_files` alanını kullanıcı kimliği gibi kullanmaz. MCP path çözümleme tarafında `normalize_excel_path` için yerel fallback korunur; böylece worker veya izole test bağlamlarında global helper eksikliği geç hata üretmez. MCP bootstrap/fallback source sorumlulukları `R/helpers_mcp_bootstrap.R` dosyasına ayrılmıştır; bu dosya izole test/debug/worker bağlamlarında destek dosyalarını çalışma dizininden bağımsız bulur ve kritik MCP helper sözleşmesini doğrular. MCP tablo okuyucu sorumlulukları `R/helpers_mcp_table_readers.R` dosyasına ayrılmıştır; bu dosya Excel/genel tablo okuma ve Markdown tablo üretme yardımcılarını `helpers_mcp_tools` ortamına bağlar. MCP temel dosya özeti, kolon istatistiği, DuckDB varlık kontrolü ve yüklenen dosya üzerinde SQL çalıştırma araçları `R/helpers_mcp_basic_tools.R` dosyasına ayrılmıştır; bu ayrım `test-mcp-basic-tools-refactor-contract.R` ile korunur. MCP oturum dosya kayıt defteri ve dosya adı/yol çözümleme sorumlulukları da `R/helpers_mcp_file_resolver.R` dosyasına ayrılmıştır; `resolve_file_argument()` varsayılan olarak yalnızca oturum kayıt defteri, etkin kullanıcı bucket'ı, legacy flat index ve güvenli kullanıcı klasörü fallback'lerini kullanır. Cross-bucket index lookup üretimde varsayılan kapalıdır ve yalnızca açık opt-in ile geçiş/migrasyon amaçlı kullanılmalıdır. Özellikle `safe_read_excel_table()` fonksiyonunun environment değeri `helpers_mcp_tools` olarak korunur; böylece MCP/tool/worker bağlamlarında `normalize_excel_path`, `resolve_readable_path` ve `path_exists_relaxed` görünür kalır. Ayrıca `[RESOLVE]` debug çıktıları üretimde raw `cat()` ile konsola basılmaz; `MERGEN_MCP_DEBUG=true` veya `options(mergen.mcp.debug = TRUE)` ile geçici olarak açılabilen kontrollü debug logger üzerinden geçer. Windows VM üretim loglarında ANSI renk kodlarının karışmasını önlemek için konsol renkleri de varsayılan kapalıdır (`MERGEN_LOG_CONSOLE_COLORS=false`).

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

Karakter sistemi, mitolojik temalar yerine farklı çalışma tarzlarını temsil eden modern ve kurgusal Türk AI persona'larından oluşur. Uygulama beş ana persona içerir:

- **Emre Onat** — Ana Asistan (dengeli, pragmatik yardımcı)
- **Selin Sezgin** — Yapıcı Uzman (sorunu çerçeveler, çözüm önerir)
- **Deniz Özgün** — Stratejist (büyük resim, yol haritası, karar matrisi)
- **Can Yalın** — Eleştirel Eş (varsayım ve risk doğrulayıcı)
- **İpek Duru** — Rehber (sade dil, adım adım öğretici)

Karakter sistemi şu bileşenlerle ilişkilidir:
- yanıt tarzı,
- persona kartları,
- görsel kimlik,
- AI Uzman tonu,
- TTS ses seçimi,
- tema renkleri,
- bazı rehberlik ve anlatım tercihleri.

Varsayılan persona **Emre Onat**'tır.

Persona sisteminin tek kaynağı `R/config_characters.R` dosyasıdır. Kanonik persona kimlikleri `emre`, `selin`, `deniz`, `can` ve `ipek`'tir. Yeni modüller doğrudan karakter adı veya klasör switch'i yazmamalı; `get_characters_data()`, `get_character_record()`, `get_character_asset_paths()` ve `normalize_character_id()` yardımcılarını kullanmalıdır.

Eski mitolojik karakter kimlikleri (mergen, ulgen, kayra, erlik, umay, umay_ana) yalnızca `normalize_character_id()` sınırında desteklenir. Eski kayıtlı kullanıcı tercihleri otomatik olarak yeni kimliklere taşınır: `mergen → emre`, `ulgen → selin`, `kayra → deniz`, `erlik → can`, `umay/umay_ana → ipek`. "MERGEN Bilge" ürün adı korunur; Mergen artık seçilebilir bir persona değildir.

---

## Mimari Özet

### Kullanıcı Oturumu Başlatma Sınırı

Kullanıcı kimliği ve oturum kurulumu artık doğrudan `server.R` içinde dağınık şekilde yönetilmez; bu sorumluluk `R/server_init_user_session.R` içine taşınmıştır. Bu katman, yerel geliştirme modu (`SSO_ENABLED=FALSE`) ve Keycloak/SSO modu (`SSO_ENABLED=TRUE`) için aynı oturum sözleşmesini korur.

Amaç, `server.R` içindeki kimlik doğrulama orkestrasyonunu azaltmak, SSO başlangıcındaki geçici `0L` kullanıcı kimliğinin kullanıcıya özel modüllere sızmasını önlemek ve `current_user_id_provider` / `resolve_current_user_id()` yaklaşımını tek noktadan korumaktır. Mevcut `session$userData` alanları geriye dönük uyumluluk için korunur.

Bu oturum sözleşmesi artık erken sunucu başlatma bağlamı olan `R/server_runtime_context.R` üzerinden `server.R` içine taşınır. `server.R`, kimlik bölümünü doğrudan `runtime_ctx$identity` üzerinden okumak yerine `serverRuntimeRequireIdentity(...)` ile doğrulanmış bir kimlik sözleşmesi olarak alır. Ardından `user_config_rv`, `resolve_current_user_id`, `current_user_id_provider`, `current_user_first_name` ve `current_user_display_name` değerlerini bu doğrulanmış kimlik sınırı üzerinden kullanır. Oturum durumu da `serverRuntimeRequireState(...)` ile doğrulanır; böylece kullanıcı kimliği, kullanıcı görünen adı, SSO hazır olma durumu, önbellek, ileri referanslar, reaktif oturum durumu ve sohbet çalışma zamanı tek bir doğrulanabilir başlatma sınırıyla korunur.

Son runtime context güncellemesiyle `R/server_runtime_context.R`, `serverRuntimeRequireIdentity(...)`, `serverRuntimeRequireState(...)` ve `serverRuntimeRequireCache(...)` yardımcılarını da içerir. Bu yardımcılar, orta seviye wiring katmanlarının eksik veya yanlış başlatılmış runtime bölümleriyle ilerlemesini engeller. Amaç yeni bir servis lokatörü kurmak değil; mevcut küçük `ServerRuntimeContext` sınırını daha açık ve test edilebilir hâle getirmektir.

Kullanıcı oturumu kimlik yardımcıları ayrıca `R/helpers_user_session_identity.R` içine ayrılmıştır. Bu dosya; SSO/local kullanıcı yapılandırmasını oluşturan `build_user_session_config()`, geriye dönük uyumluluk için `session$userData` kimlik alanlarını tek noktadan yazan `apply_user_session_identity()` ve canlı kullanıcı kimliği sağlayıcısını kuran `make_current_user_id_provider()` yardımcılarını içerir. `R/server_init_user_session.R` artık bu saf yardımcıları kullanarak Shiny/SSO orkestrasyonuna odaklanır. Bu ayrım, kullanıcı kimliği biçimlendirme kurallarını test edilebilir hâle getirirken mevcut SSO/non-SSO davranışını korur.

### Oturum Runtime Store Sözleşmesi

Oturum içi liste biçimli `session$userData` depoları artık dağınık anahtar yazımlarıyla değil, `R/utils_session_cleanup.R` içindeki küçük `SessionRuntimeStore` sözleşmesiyle yönetilir. Bu sözleşme; `current_session_files`, `file_summaries`, `chart_store` ve `mcp_registry_snapshot` alanlarını tek noktadan adlandırır, sıfırlar, okur/yazar ve MCP kayıt defteri anlık görüntüsünü günceller.

`R/server_init_session_state.R`, ortak oturum depolarını `session_runtime_store_reset(session)` ile hazırlar. `R/server_session_cache.R` ise MCP kayıt defteri senkronizasyonunu `session_runtime_store_snapshot_mcp(...)` üzerinden yapar. Böylece dosya bağlamı, özet deposu, grafik deposu ve MCP Excel dosya görünürlüğü için gizli source-order/state bağımlılığı azaltılır.

Bu sözleşme `tests/testthat/test-session-user-data-store.R` ve `tests/testthat/test-source-manifest-contract.R` ile korunur. Yeni kod, bu ortak depolar için doğrudan `session$userData$... <- list()` veya boot dosyalarında ham `session_user_data_*` anahtar orkestrasyonu eklemek yerine `session_runtime_store_*` yardımcılarını kullanmalıdır.

### Sunucu Modül Bağlama Sınırı

`server.R` içindeki orta seviye modül bağlama yükü kademeli olarak azaltılmıştır. Performans/sağlık/destek modülleri, ayarlar ve ileri referans kurulumu, Bilge Yolaç başlangıç bağlantısı, medya modülleri ve dosya önizleme/takip sorusu ön hazırlığı artık `R/server_module_wiring.R` içinde küçük ve açık bağımlılık alan yardımcılarla bağlanır.

Bu ayrım `server.R` dosyasının iş mantığına dönmesini engeller; `server.R` artık ilgili modül ailesini doğrudan tek tek başlatmak yerine aşağıdaki üst seviye yardımcıları çağırır:

```r
service_modules <- serverBindServiceModules(...)
settings_bundle <- serverBindSettingsAndRefs(...)
media_modules <- serverBindMediaModules(...)
file_prelude_modules <- serverBindFilePreludeModules(...)

core_interaction <- serverBindCoreInteractionRuntime(
  ...,
  runtime_ctx = runtime_ctx,
  media_modules = media_modules,
  user_config_provider = function(default = NULL) {
    runtime_ctx$identity$get_user_config(default = default)
  },
  user_first_name_fn = function(default = "") {
    current_user_first_name(default = default)
  }
)

runtime_ctx <- core_interaction$runtime_ctx
saved_chats_data <- core_interaction$saved_chats_data
file_manager_data <- core_interaction$file_manager_data

chat_engine <- serverBindChatEngineRuntime(...)
```

`serverBindCoreInteractionRuntime(...)`, `server.R` içindeki çekirdek etkileşim orkestrasyonunu küçük bir sınıra taşır. Bu sınır; hızlı eylemler, ayar gözlemcileri, oturum zaman aşımı, File Manager runtime, sohbet UI/navigasyon/startup gözlemcileri, AI Uzman işleyicileri, depolama gözlemcileri, dosya gözlemcileri, dosya tıklama gözlemcileri ve sohbet kalıcılığı bağlantısını tek açık bağımlılık kümesiyle kurar. File Manager ve sohbet kalıcılığı hâlâ `R/server_module_wiring.R` içindeki odak helper’lar üzerinden bağlanır; sadece bu bağlama artık `server.R` yerine `R/server_core_interaction_runtime.R` üzerinden yapılır.

Bu yardımcılar mevcut modül ID’lerini, mevcut başlatma sırasını ve canlı `current_user_id_provider` kullanımını korur. Amaç davranış değiştirmek değil, kaynak sırası ve state orkestrasyonu riskini azaltmaktır. `serverBindCoreInteractionRuntime(...)` `R/server_core_interaction_runtime.R` içinde yer alır ve önce Dosya Yönetimi bağlantısını `serverBindFileManagerRuntime(...)` ile, ardından kayıtlı sohbetler/geçmiş/galeri/hoş geldin/indirme/mesaj arama bağlantılarını `serverBindChatPersistenceModules(...)` ile delege eder.

Bu dosya `global.R` içinde observer/output yardımcılarından sonra kaynaklanır; böylece `serverBindCoreInteractionRuntime(...)` somut observer fonksiyonlarına geriye dönük placeholder kullanmadan erişir.

Sohbet motoru bağlantısı da aynı sınır içine alınmıştır. `serverBindChatEngineRuntime()`; sohbet çalışma zamanı, LLM yanıt işleyicileri, sohbet giriş gözlemcileri, çeşitli UI gözlemcileri, sohbet eylemleri, TTS işleyicileri ve `sendMessageInit()` bağlantısını tek bir açık bağımlılık sınırı altında toplar. Böylece `server.R` içinde `trigger_tts_for_message` için geçici yer tutucu tanımlama ve sonra yeniden atama deseni kullanılmaz; bunun yerine `R/server_runtime_function_slot.R` içindeki `serverRuntimeCreateFunctionSlot()` ile geç bağlanan, test edilebilir bir fonksiyon slotu kullanılır. Bu yardımcı ayrı dosyada tutulur; amaç `R/server_runtime_context.R` dosyasını yeni bir monolite dönüştürmeden kaynak sırası ve TTS tetikleme zamanlaması riskini azaltmaktır.

Son runtime-context güncellemesiyle Dosya Yönetimi hattı ayrıca açık bir **FileRuntime** sınırına alınmıştır. `serverBindFilePreludeModules()` dosya önizleme, fallback takip sorusu aracı ve takip sorusu modülünü `runtime_ctx$file` altına bağlayabilir; `serverBindFileManagerRuntime()` ise `file_manager_data` nesnesini aynı FileRuntime sınırına ekler. `server.R`, dosya ön hazırlığı ve Dosya Yönetimi nesnelerini artık doğrudan dağınık yerel değişkenlerden değil, `serverRuntimeRequireFileRuntime(...)` sözleşmesi üzerinden alır. Geriye dönük uyumluluk için `runtime_ctx$modules$file_manager` ve `session$userData$file_manager_data` açıkları korunmuştur; amaç davranış değiştirmek değil, dosya alt sistemindeki gizli başlatma sırası ve state yayılımı riskini azaltmaktır.

Bu sınır aşağıdaki testlerle korunur:

```r
testthat::test_file("tests/testthat/test-server-module-wiring-contract.R")
testthat::test_file("tests/testthat/test-server-runtime-context.R")
testthat::test_file("tests/testthat/test-server-runtime-context-accessors.R")
testthat::test_file("tests/testthat/test-server-core-interaction-runtime.R")
testthat::test_file("tests/testthat/test-server-module-wiring-runtime-bindings.R")
testthat::test_file("tests/testthat/test-production-contracts.R")
testthat::test_file("tests/testthat/test-server-live-user-provider-contract.R")
testthat::test_file("tests/testthat/test-source-manifest-contract.R")
```

### Oturum Yerel Liste Depoları

Oturum içinde `session$userData` altında tutulan liste tabanlı ortak durumlar artık doğrudan dağınık atamalarla yönetilmez. `current_session_files`, `file_summaries`, `chart_store` ve `mcp_registry_snapshot` gibi oturum-yerel depolar `R/utils_session_cleanup.R` içindeki küçük yardımcılarla okunur, yazılır ve temizlenir.

Bu yardımcılar, dosya bağlamı ve MCP kayıt defteri gibi kritik akışlarda “önce hangi modül bu listeyi oluşturdu?” bağımlılığını azaltır. Başlangıç listeleri `R/server_init_session_state.R` içinde hazırlanır; dosya yükleme/özetleme hattı, dosya tıklama observer’ları, yeni söyleşi temizliği ve MCP registry snapshot güncellemesi aynı merkezi liste-store sözleşmesini kullanır.

Bu davranış `tests/testthat/test-session-user-data-store.R` ile korunur.


SSO akışında `sso_state$authenticated` gibi Shiny reaktif alanları init sırasında doğrudan okunmamalıdır. Bu değerler yalnızca `shiny::observeEvent(...)`, `shiny::observe(...)`, `shiny::reactive(...)` veya güvenli `shiny::isolate(...)` bağlamlarında okunmalıdır. Bu kural, SSO girişinden hemen sonra oluşabilecek “Can't access reactive value outside of reactive consumer” hatalarını önler.

SSO sonrasında tek sefer çalışması gereken modül yenilemeleri `server.R` içinde tekrar eden doğrudan `observeEvent(sso_state$authenticated, ...)` bloklarıyla çoğaltılmamalıdır. Refresh edilebilir modüller için tercih edilen üst seviye sözleşme `R/server_runtime_context.R` içindeki `serverRuntimeAttachRefreshableModule(...)` yardımcısıdır. Bu yardımcı, modül dönüş nesnesini `serverRuntimeAttachModule(...)` ile runtime context içine kaydeder, gerekiyorsa SSO sonrası yenilemeyi `serverRuntimeRefreshModuleOnSsoAuthReady(...)` üzerinden bağlar ve geçici geriye uyumluluk gerektiren oturum verilerini `serverRuntimeExposeSessionData(...)` ile açık parametre üzerinden yazar. Dosya Yönetimi kalıcı dosya yenilemesi ve Görsel Galerisi yenilemesi artık bu tek yardımcı üzerinden bağlanır. Böylece `server.R` içinde attach + refresh + session$userData uyumluluk yazımı kalıbı tekrar etmez; eksik modül/fonksiyon sözleşmeleri erken yakalanır ve SSO hazır olma zamanlaması tek bir doğrulanabilir sınıra toplanır.

```r
runtime_ctx <- serverRuntimeAttachRefreshableModule(
  ctx = runtime_ctx,
  name = "file_manager",
  value = file_manager_data,
  required_functions = c("refresh_persisted_files", "file_contents"),
  refresh_function = "refresh_persisted_files",
  refresh_args = list("auth_ready"),
  label = "file_manager_refresh",
  expose_session_key = "file_manager_data"
)
```

```r
identity <- runtime_ctx$identity

user_config_rv <- identity$user_config_rv
resolve_current_user_id <- identity$resolve_current_user_id
current_user_id_provider <- identity$current_user_id_provider
current_user_first_name <- identity$get_first_name
current_user_display_name <- identity$get_display_name
```

Dosya Yönetimi tarafında auth-ready kararı artık `session$userData$auth_initialized` alanına doğrudan bakarak değil, `auth_ready_provider = runtime_ctx$identity$is_auth_ready` sağlayıcısı üzerinden verilir. Bu yaklaşım, SSO sırasında geçici `0` kullanıcı kimliğinin kalıcı dosya yenileme akışını erken tetiklemesini engeller.

İlgili testler:

```r
testthat::test_file("tests/testthat/test-server-user-session-context.R")
testthat::test_file("tests/testthat/test-server-runtime-context.R")
testthat::test_file("tests/testthat/test-server-runtime-context-accessors.R")
testthat::test_file("tests/testthat/test-server-boundary-contract.R")
testthat::test_file("tests/testthat/test-source-manifest-contract.R")
testthat::test_file("tests/testthat/test-server-live-user-provider-contract.R")
testthat::test_file("tests/testthat/test-effective-user-id.R")
testthat::test_file("tests/testthat/test-production-contracts.R")
testthat::test_file("tests/testthat/test-file-manager-module-policy-wiring.R")
```

### Server Runtime Context

`R/server_runtime_context.R`, `server.R` içindeki erken başlatma nesneleri için küçük ve açık sözleşmeli bir çalışma zamanı bağlamı sağlar. Bu katmanın amacı yeni bir framework oluşturmak değil; daha önce ayrı ayrı taşınan kritik boot nesnelerini doğrulanabilir bir sınır altında toplamaktır.

Bu bağlam şu nesneleri kapsar:

- `session_cache`
- `user_session` / canlı kullanıcı kimliği sağlayıcıları
- `forward_refs`
- `state_bundle`
- `chat_runtime`
- sınırlı modül dönüş nesnesi kayıtları (`runtime_ctx$modules`)
- SSO sonrası auth-ready callback kayıtları (`serverRuntimeOnSsoAuthReady(...)`)

`server.R` içinde bu nesneler hâlâ aynı sırayla oluşturulur; ancak eksik fonksiyon veya yanlış başlatma sırası artık daha erken ve daha anlaşılır hata üretir. Bu yaklaşım, strict `global.R` kaynak sırası ve `server.R` orkestrasyon bağımlılığını kademeli olarak azaltmak için uygulanmıştır.

Bu bağlam bir servis bulucuya dönüştürülmemelidir. Yeni alanlar yalnızca `server.R` içinde zaten oluşturulan, birden fazla alt modüle taşınan ve açık required-function sözleşmesiyle doğrulanabilen erken boot nesneleri için eklenmelidir. Kimlik ve auth-ready alanları bu nedenle `runtime_ctx$identity` altında tutulur. `runtime_ctx$modules` da genel amaçlı global kayıt defteri değildir; yalnızca File Manager ve Görsel Galerisi gibi, SSO auth-ready sonrası güvenli şekilde yenilenmesi gereken modül dönüş nesneleri için dar kapsamlı kullanılmalıdır.

Son runtime-context güncellemesiyle `serverRuntimeAttachModule(...)` tek başına modül kaydı için kalırken, modül okuma ve SSO sonrası yenileme davranışı daha açık yardımcılarla korunur. `serverRuntimeGetModule(...)`, kayıtlı modül dönüş nesnesini doğrulanmış şekilde alır; `serverRuntimeRefreshModuleOnSsoAuthReady(...)`, SSO tamamlandıktan sonra çalışacak tek seferlik modül yenilemelerini standartlaştırır; `serverRuntimeExposeSessionData(...)` ise kaçınılmaz legacy `session$userData` paylaşımlarını görünür ve test edilebilir hâle getirir. Yeni SSO sonrası refresh akışlarında `server.R` içinde doğrudan `ctx$modules$...` erişimi veya özel callback gövdesi yazılmamalıdır.

Korunan ana sözleşmeler:

```r
testthat::test_file("tests/testthat/test-server-runtime-context.R")
testthat::test_file("tests/testthat/test-server-runtime-context-accessors.R")
testthat::test_file("tests/testthat/test-server-boundary-contract.R")
testthat::test_file("tests/testthat/test-source-manifest-contract.R")
testthat::test_file("tests/testthat/test-production-contracts.R")
testthat::test_file("tests/testthat/test-server-live-user-provider-contract.R")
```

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

Thinking/reasoning modellerinde bazı yanıtlarda `content` alanı boş gelirken kullanılabilir metin `reasoning` veya `reasoning_content` içinde bulunabilir. Güncel çıkarım sözleşmesi, boş `content` alanlarının kullanılabilir fallback metnini ezmesini engeller; normal içerik, reasoning fallback açık/kapalı ve delta tarzı reasoning yanıtları `test-llm-content-reasoning-fallback.R` ile korunur.

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
