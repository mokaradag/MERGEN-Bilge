# MERGEN Bilge Değişiklik Notları

Bu belge, MERGEN Bilge değişiklik notları, doğrulama caveat'leri, özellik güncellemeleri ve operasyonel bakım notları için merkezi başvuru kaynağıdır. README ilk giriş ve yön bulma belgesi olarak kısa tutulur; ayrıntılı teknik ve operasyonel notlar burada veya ilgili derin dokümanlarda korunur.

## Genel Bakış

MERGEN Bilge değişiklik notları; yapay zekâ söyleşi deneyimi, dosya yönetimi, görsel anlama, güvenlik/SSO, Türkçe karakter dayanıklılığı, UI tema cilaları, ses akışları, Bilge Yolaç/Claude Code alanı, test/doğrulama ve bağımlılık kilitleme başlıklarını birlikte izler.

- Operasyonel ayrıntılar için [`../RUNBOOK.md`](../RUNBOOK.md).
- Mimari yön bulma için [`architecture-map.md`](architecture-map.md).
- DB tablo yapısı için [`database-schema.md`](database-schema.md).
- Bağımlılık kilitleme için [`dependency-locking.md`](dependency-locking.md) ve [`../RENV_LOCK_STATUS.md`](../RENV_LOCK_STATUS.md).
- Geniş teknik referans için [`technical-reference.md`](technical-reference.md).

## Son Değişiklikler


### 2026-06-22 İşlem-güvenli DB bağlantı havuzu + etkileşimli soak seridi

Bu sürüm iki operasyonel dayanıklılık zaafiyetini kapatır: (1) DB bağlantı
yönetiminin havuzsuz/placeholder olması ve (2) operasyonel soak kanıtının
GET-only HTTP seridine dayanması.

**İşlem-güvenli DB bağlantı havuzu (opt-in).** Yeni `R/helpers_db_pool.R`
katmanı `pool` paketi üzerine kurulur ve şu genel API'yi sunar:
`is_db_pool_enabled`, `db_pool_config`, `init_db_pool_once`, `close_db_pool_once`,
`with_db_connection` (salt-okunur), `with_db_transaction` (işlem-güvenli),
`db_acquire_tx_connection`/`db_release_tx_connection` ve secret-safe
`db_pool_status_snapshot`. Havuz **varsayılan KAPALI**'dır
(`MERGEN_DB_POOL_ENABLED`, varsayılan `FALSE`), bu yüzden bulut/test/boot
davranışı değişmez. Açıkken `app.R` `onStart`'ta bir kez başlatılır, `onStop`'ta
kapatılır. Okuma yolları değiştirilmemiş `get_connection()` üzerinden otomatik
havuzlanır; işlem sitesi `save_message_to_db()` gerçek `poolCheckout()` ile
işlem-güvenli checkout kullanır ve **bağlantıyı iade etmeden önce rollback**
çalıştırır (havuza açık işlemle dönüş engellenir). Encoding sözleşmesi korunur:
havuz `DB_CLIENT_ENCODING`/`DB_NAME_ENCODING` değerlerini ODBC bağlantısına
geçirir. `worker_save_assistant_response()` ayrı süreçte çalıştığı için doğrudan
`worker_db_connect()` kullanmaya devam eder. Ayrıntı:
[`database-pooling.md`](database-pooling.md).

**Etkileşimli (interactive) soak seridi.** Yeni `tests/scripts/soak_interactive_lane.R`,
GET-only HTTP seridinin açmadığı sohbet/DB/streaming/stop yollarını **gerçek DB
havuzu** üzerinde (RSQLite arka ucu) alıştırır: oturum açma + anahtar izolasyonu,
sohbet/mesaj yazma (`with_db_transaction`), gerçek streaming-delta sınıflandırma,
stop/iptal kararı + niyetli işlem ROLLBACK, dosya yükleme doğrulaması ve
kullanıcı-kapsamlı geçmiş okuma. `soak_evidence.json` artık bir `interactive_lane`
bloğu (oturum/eylem sayısı, DB havuz checkout/return/sızıntı/tx sayaçları,
izolasyon/rollback/upload/mojibake) ve `interactive_metrics.csv` üretir. HTTP
seridi `MERGEN_SOAK_HTTP_LANE=false` ile kapatılarak uygulamasız bulut kanıtı
alınabilir.

**Doğrulanan (bulut/offline).** `tests/testthat/test-db-pool-behavior.R` (54 PASS,
gerçek SQLite: enable/disable, once semantiği, ödünç/iade sızıntısızlığı,
commit/rollback yalıtımı, Türkçe round-trip, gerçek-checkout, secret-safe
snapshot). `test-maintainability-ratchet.R` 100/100 korundu. App boot smoke PASS.
`test-operational-soak-gate-contract.R` 157 PASS. Uygulamasız soak koşumu
(`MERGEN_SOAK_HTTP_LANE=false`, 15 oturum/120 eylem) **PASS**: checkout=return=121,
sızıntı=0, tx commit=45/rollback=15, izolasyon PASS, mojibake 0;
`effective_success_rate`/`no_server_crash` HTTP seridi kapalı olduğu için
`UNMEASURED`.

**Henüz kanıtlanmayan (Windows VM gerekli).** Havuzun SQL Server'a karşı üretim
doğrulaması: `MERGEN_DB_POOL_ENABLED=TRUE` ile VM'de
`run_vm_encoding_preflight_real.R` Türkçe at-rest yazımı, SSMS satır teyidi ve
attach soak sınır koşumuyla gerçek-sohbet kapasite farkı. Etkileşimli serit
tek-süreçte ardışık oturumlardır ve lane-yerel SQLite kullanır; gerçek
tarayıcı/websocket eşzamanlılığını veya SQL Server T-SQL davranışını kanıtlamaz.
Gerçek LLM üretim throughput'u ayrı bir konudur (real-canary upstream gateway
`ERR-234` ile bloke kalmaya devam eder).

### 2026-06-20 Windows VM limit-push soak ve evidence gate notu

Windows VM üzerinde sınırı zorlamak için canlı uygulamaya attach edilen
`proxy_llm` / `proxy` koşumu **1000 aktif eşzamanlı kullanıcı / 5400 saniye
(90 dakika)** olarak çalıştırıldı ve **FAIL** ile tamamlandı
(`artifacts/soak/20260620-111106/soak_evidence.json`, VM console observed):
227285 istek, 132405 başarı, 0 hata, 94880 timeout, `effective_success_rate=0.5826`
(< 0.98), p95=16965.9 ms ve throughput=2524.9/dk. Bu, 1000 eşzamanlı uzun
proxy-lane işletim zarfının mevcut eşiklerle aşıldığını gösteren negatif/guardrail
kanıttır; kapasite/readiness PASS olarak yorumlanmamalıdır.

Güvenlik ve doğruluk kontrolleri yük altında temiz kaldı: anahtar yönlendirme 5/5,
cross-session key isolation TRUE, upload validation 7/7, encoding round-trip 1,
secret leak 0, mojibake 0 ve server crash yok. `memory_growth_mb` ve
`browser_console_errors` ölçülmedi. Aynı VM oturumunda evidence gate
`artifacts/vm-evidence/20260620-104919/evidence.json` ile `Toplam: 13 passed,
0 failed, 0 skipped` olarak geçti; bu yapı/boot/encoding/UX kanıtıdır ve uzun
1000-eşzamanlı soak FAIL sonucunu geçersiz kılmaz.

Aşağıdaki bölüm, güncel değişiklik notlarını kronolojik/tematik bakım izi kaybolmadan izler.

### 2026-06-19 Windows VM post-index-cache operasyonel soak notu

Root-page/index caching optimizasyonu sonrası Windows VM konsolunda izole
`GET /` timing'i pre-cache yaklaşık 0.64 saniyeden warm cache yaklaşık 0.006-0.008
saniyeye düştü; cold build hâlâ `[PERF] event=index_render elapsed_ms=740
cache=miss_build bytes=311206` olarak gözlendi. Reproduction komutu:
``curl.exe -w "%{time_total}`n" -o NUL -s http://127.0.0.1:8009/``.

Tarihsel pre-index-cache fake-lane kanıtı 22 aktif eşzamanlı kullanıcı / 300 saniye
PASS idi (`artifacts/soak/20260619-153052/soak_evidence.json`). Index-cache sonrası
VM console observed en güçlü fake-lane gözlem artık 1000 aktif eşzamanlı kullanıcı /
420 saniye PASS'tir (`artifacts/soak/20260619-205535/soak_evidence.json`, p95=8377.8
ms, throughput=7931.4/dk, 0 hata, 0 timeout). Ayrıca 250 aktif kullanıcı / 420 saniye
PASS (`artifacts/soak/20260619-204704/soak_evidence.json`, p95=1983.8 ms,
throughput=8016.8/dk), 1000 kullanıcı / 30 saniye PASS
(`artifacts/soak/20260619-204455/soak_evidence.json`, p95=9427.6 ms,
throughput=8532.4/dk) ve stress/proxy final PASS
(`artifacts/soak/20260619-210427/soak_evidence.json`, p95=734.5 ms,
throughput=8029.2/dk) gözlendi.

Bu checkout içinde `artifacts/soak/...` JSON dosyaları bulunmadığı için yeni değerler
şimdilik **VM console observed** olarak belgelenir ve artifact JSON ile yeniden
doğrulanmalıdır. `memory_growth_mb` ve `browser_console_errors` bu koşularda
`UNMEASURED` kaldığı için ölçülmüş PASS olarak yorumlanmaz. Bu kanıt GET-only
index-serving/fake-proxy soak yolunu güçlendirir; gerçek LLM/model üretiminin
hızlandığını, browser UX'in temiz olduğunu veya 1000 eşzamanlı gerçek insan chat
oturumunun desteklendiğini kanıtlamaz.


### Operasyonel soak / yük kapısı eklendi (fake/proxy/real-canary seritleri)

MERGEN Bilge'ye, uygulamanın operasyonel kırılganlığını kullanıcılar fark etmeden
önce keşfetmek için **operasyonel soak/yük kapısı** eklendi:
`tests/scripts/run_operational_soak_gate.R` (+ `soak_*` ve `mock_llm_server.R` /
`proxy_llm_server.R` yardımcı modülleri). Tam belge:
[`operational-soak-gate.md`](operational-soak-gate.md).

Tasarım üç **serit** üzerine kuruludur: **fake** (yerel OpenAI-uyumlu sahte LLM;
ana yüksek-eşzamanlılık seridi; sıfır gerçek anahtar), **proxy** (çok sayıda sahte
kişisel anahtarla kişisel/varsayılan/eksik anahtar yönlendirme ve oturumlar arası
izolasyon kanıtı; ham anahtar loglanmaz), ve **real-canary** (tek gerçek anahtar,
çok düşük eşzamanlılık). Bu ayrım bilinçlidir: tek gerçek geliştirici anahtarı
app-seviyesi soak'un darboğazı yapılmaz ve fake/proxy/canary koşumlarından gerçek
1.000 eşzamanlı kullanıcı hazırlığı iddia edilmez. "1.000 kullanıcı" bir kullanıcı
tabanıdır; ilk ciddi aktif-eşzamanlılık hedefi 50–100'dür.

Kapı VM kanıt kapısının yerine geçmez; ayrı ve tamamlayıcıdır. Profiller:
`smoke` (varsayılan), `pilot`, `org`, `stress`, `fake_llm`, `proxy_llm`,
`real_llm`. Fake/proxy sunucular `httpuv` + `promises` + `later` ile bloklamayan
gecikme uygular (tek thread'li event loop'ta gerçek eşzamanlılık); yük `curl`
multi-handle havuzuyla sürülür. In-process alıştırmalar uygulamanın gerçek
yardımcılarını çağırarak Türkçe/emoji DB-encoding round-trip'i, yükleme
doğrulayıcı kabul/ret kararlarını, anahtar kaynak sınıflandırmasını ve oturumlar
arası anahtar izolasyonunu doğrular. Yeni paket eklenmedi.

Dürüstlük sözleşmesi VM kanıt kapısıyla aynıdır: her zaman artifact üretilir
(`artifacts/soak/<timestamp>/`), eşik **etkin başarı oranına** uygulanır (kasıtlı
enjekte edilen faultlar hariç → beklenmeyen başarısızlıkları ölçer), ölçülemeyen
eşikler sessizce geçmez (`UNMEASURED`/`skipped_checks`), ve artifact'lar ham
anahtar/token/sır içermeyecek şekilde redaksiyondan + redaksiyon kendi-doğrulamasından
geçer. Statik + offline sözleşme koruması:
`tests/testthat/test-operational-soak-gate-contract.R`.

### Windows VM evidence gate milestone: 13/13 adım geçti

MERGEN Bilge'nin on-prem Windows VM doğrulamasında major readiness milestone kaydedildi ve **15 Haziran 2026** tarihinde yeniden doğrulandı. `tests/scripts/run_vm_evidence_gate.R` tam koşumu başarılı tamamlandı: `Toplam: 13 passed, 0 failed, 0 skipped`. Güncel statü özellikle şu adımları içerir: `full_testthat PASSED`, `browser_ux_smoke PASSED`, `vm_preflight_real PASSED`, `db_encoding_preflight PASSED`.

Başarılı koşumda tam izole testthat suite'i, VM preflight, transactional DB encoding preflight ve mandatory browser UX smoke kanıtı aynı gate altında geçti. Browser proof external-app modunda alındı: app ayrı pencerede `http://127.0.0.1:28081` üzerinde çalışırken gate `MERGEN_BROWSER_UX_BASE_URL=http://127.0.0.1:28081` ve `MERGEN_REQUIRE_BROWSER_UX_SMOKE=true` ile koşturuldu; browser smoke `UX_SMOKE_DONE:PASS` üretti. Son artifact: `artifacts/vm-evidence/20260615-130127/evidence.json`; genel artifact konumu `artifacts/vm-evidence/<timestamp>/evidence.json`.

Bu milestone, release/readiness açısından güçlü bir VM kanıtıdır; ancak yalnızca artifact içinde `passed` görünen adımlar için kanıt sayılır. Uzun süreli gerçek kullanıcı yükü, manuel kırılgan-akış QA'sı ve legacy DB satırlarının temizliği ayrıca değerlendirilmelidir. Operasyonel komutlar ve troubleshooting için [`../RUNBOOK.md`](../RUNBOOK.md) içindeki evidence gate bölümü izlenir.


### Karmaşıklık azaltma: plotly bağımlılığı çalışma zamanından tamamen kaldırıldı

Grafik render yolu highcharter'a indirildikten sonra plotly'nin tek kalan kullanımı, artık hiçbir grafik tarafından kullanılmayan bağımlılık-önyükleyiciydi. Bu önyükleyici de kaldırıldı: `R/server_outputs_downloads.R` içindeki `widgetDependencyOutputsInit()` artık yalnızca highcharter `deps_hc` yükleyicisini tanımlar (`deps_pl` ve kullanılmayan `plotly_html` çıktıları silindi) ve `ui.R` içindeki gizli `plotly::plotlyOutput("deps_pl")` yükleyicisi kaldırıldı. Sonuç olarak çalışma zamanı kodunda (`R/*.R`, `ui.R`, `server.R`) hiçbir plotly referansı kalmadı.

Davranış korunur: highcharter bağımlılık yükleyicisi (`deps_hc`) ve grafik render yolu değişmedi. Plotly zaten `required_packages` içinde değildi (opsiyonel yumuşak bağımlılıktı); on-prem `renv.lock`, plotly'yi düşürmek için VM tarafında yeniden snapshot edilmelidir (bulut oturumundan `renv.lock` üretilmez).

Koruma: `tests/testthat/test-downloads-outputs-behavior.R`, `widgetDependencyOutputsInit()`'in highcharter yokken hatasız çalıştığını ve hiçbir plotly çıktısı tanımlamadığını doğrular; `tests/testthat/test-chart-engine-highcharter-only-contract.R`'ye eklenen yeni tarama, tüm çalışma zamanı R + `ui.R` + `server.R` dosyalarında plotly kod referansı (`plotly::`, `plotlyOutput`, `renderPlotly`, `"plotly"`, `deps_pl`, `plotly_html`) bulunmadığını dondurur. Doğrulama: parse sanity + odaklı sözleşme/davranış testleri (`bash tools/ai_validate.sh cloud-quick`) yeşil; tam runtime/app boot, tarayıcı UX ve Windows VM/SSO/DB doğrulaması bu bulut oturumunda yapılmadı.

### Karmaşıklık azaltma: grafik render yolu tek motorlu (highcharter) hale getirildi

ChartLab grafikleri (`R/helpers_chartlab.R`) ve etkileşimli ChartLab modülü (`R/module_chartlab.R`) her zaman highcharter ile render edilir; eski `highcharter → plotly+ggplot2 → hata` fallback zinciri ulaşılamayan ölü koddu. Bu deployment'ta highcharter daima kuruludur (`ui.R` gizli bağımlılık yükleyicisi zaten `highcharter::highchartOutput` kullanır ve on-prem `renv.lock` highcharter'ı sabitler), dolayısıyla plotly+ggplot2 dalları gerçekte hiç çalışmıyordu.

Bu render fallback'i kaldırıldı: container seçimi artık highcharter varsa `highchartOutput`, yoksa `shiny::uiOutput`; `wire_chart_output()` / `render_one()` highcharter varsa `renderHighchart`, yoksa zarif bir `renderUI` hata mesajı üretir (çökme yok). Kullanılmayan `have_plotly_gg` / `have_highcharter` bayrakları `R/config_file_store.R`'den temizlendi. Toplam ~208 satır ölü/ulaşılamayan kod kaldırıldı (`helpers_chartlab.R` 449→345, `module_chartlab.R` 531→432, `config_file_store.R` −5); maintainability skoru 100/100 ve en büyük dosya metriği değişmedi.

Davranış korunur: canlı highcharter render dalı bu değişiklikle hiç değişmedi (kaynak düzeyinde highcharter render satırları HEAD ile birebir aynı). `R/server_outputs_downloads.R` + `ui.R` içindeki plotly bağımlılık-önyükleyicisine (`deps_pl`/`plotly_html`) dokunulmadı; bu ayrı bir önyükleme mekanizmasıdır ve `test-downloads-outputs-behavior.R` ile korunur. Plotly'yi tamamen kaldırmak (önyükleyici + highcharter'ı zorunlu pakete almak) ayrı bir takip işidir.

Koruma: yeni `tests/testthat/test-chart-engine-highcharter-only-contract.R` sözleşme testi, render dosyalarında plotly/ggplot2 render fallback işaretçilerinin (`plotly::`, `renderPlotly`, `ggplot(`, `geom_`, `have_pl(`) bulunmadığını, highcharter render yolunun (`highchartOutput`, `renderHighchart`) ve highcharter-yoksa zarif hata davranışının korunduğunu dondurur. Mevcut ChartLab/MCP grafik testleri yeşil kalır (81 geçti, 8 atlandı — atlananlar zaten highcharter/plotly kurulu olmayan ortamda atlanan testler). Doğrulama: parse sanity + odaklı sözleşme testleri (`bash tools/ai_validate.sh cloud-quick`) yeşil; tam runtime/app boot, tarayıcı UX ve Windows VM/SSO/DB doğrulaması bu bulut oturumunda yapılmadı.

### Karmaşıklık azaltma: Yapılandırma ayarları UI'si odaklı kart yapıcılarına bölündü

Ayarlar sayfasının "Yapılandırma" alt sekmesi UI'si tek bir 710 satırlık `settingsYapilandirmaUIImpl(id)` fonksiyonuydu; kod tabanındaki en büyük tek fonksiyondu ve gezinmesi zordu. Bu fonksiyon artık ince bir kompozitör olup her ayar kartını odaklı, saf bir `.syap_*(ns)` yapıcısına delege eder: `.syap_header_row`, `.syap_model_card`, `.syap_api_key_card`, `.syap_tools_card`, `.syap_claude_code_card`, `.syap_interface_shortcuts_row`, `.syap_audio_card`, `.syap_ai_expert_card`, `.syap_image_card`, `.syap_summarization_card`, `.syap_analysis_card`.

Bu yalnızca okunabilirlik (bilişsel yük) iyileştirmesidir; davranış birebir korunur. Bölme öncesi ve sonrası render edilen HTML **bayt-bayt aynıdır** (30.629 karakter) ve sunucuya bağlanan 47 Shiny input/output kimliğinin tümü değişmeden kalır. Dosya tek dosyada tutulduğu için kaynak manifesti, yükleme sırası veya yeni dosya sözleşmeleri etkilenmez. Fonksiyon başına bilişsel yük 1×710 satırdan 1 kompozitör + 11 küçük yapıcıya indi; dosya 710 → 758 satır oldu (raporun en büyük dosya metriği 760'ta kaldığından gerileme yoktur) ve maintainability skoru 100/100 korunur.

Koruma: yeni `tests/testthat/test-settings-yapilandirma-ui-id-surface-behavior.R` karakterizasyon testi UI'yi render edip 47 kimliğin tamamını, tüm kart başlıklarını ve özel yapıları (model `data-model-meta`, eşit yükseklik satırı, araç seçici, derin düşünme anahtarı) dondurur; herhangi bir kimliğin düşmesi/yeniden adlandırılması testi kırar. Mevcut `test-settings-yapilandirma-ui-refactor-contract.R` sözleşme testi yeşil kalır. Doğrulama: parse sanity + odaklı sözleşme testleri (`bash tools/ai_validate.sh cloud-quick`) yeşil; tam runtime/app boot, tarayıcı UX ve Windows VM/SSO/DB doğrulaması bu bulut oturumunda yapılmadı.

### Karmaşıklık azaltma: oluşturulan görsel kartı HTML'i tek kanonik yardımcıda toplandı

Oluşturulan görsel kartı işaretlemesi (görsel + `MERGEN Bilge` filigranı + indir/kopyala/yazdır butonları + isteğe bağlı açıklama) üç ayrı yerde birebir aynı şekilde tekrarlanıyordu: `R/module_image_generation.R` içindeki `render_generated_image_html()` ve `render_image_from_saved_path()` ile `R/helpers_chat_message_formatting.R` içindeki `db_message_render_image_html()` (kaydedilmiş söyleşi yeniden yükleme yolu). Bu çoğaltma, kart işaretlemesinde (buton ekleme, kaçış düzeltmesi, filigran metni) yapılacak her değişikliğin üç yeri birden gerektirdiği bir bakım ve XSS sınır riskiydi.

İşaretleme artık tek kanonik saf yardımcıda toplanır: `mergen_generated_image_card_html()`, `R/helpers_markdown_safety.R` içinde. Yardımcı `message_id` ve `description` değerlerini HTML kaçışına tabi tutar; çağıran tarafça güvenli kabul edilen `img_src`'yi `src` içine olduğu gibi yerleştirir. Her üç tüketici de kart işaretlemesini bu yardımcıya delege eder. Yardımcı, `R/helpers_chat_message_formatting.R` ve `R/module_image_generation.R`'den önce yüklenir.

Davranış korunur: kart çıktısı aynıdır. Tek fark, görsel oluşturma yolundaki kartlarda `message_id` artık (sohbet biçimlendirme yolunda zaten olduğu gibi) HTML kaçışına tabi tutulur; gerçek `message_id` değerleri ASCII zaman damgası/numara olduğu için bu, çıktıyı değiştirmeyen bir güvenlik sıkılaştırmasıdır. `db_message_render_image_html()` içindeki "dosya bulunamadı"/"yüklenemedi" yer tutucu dalları kasıtlı olarak farklıdır (görsel ve buton içermez) ve yerel kalır. Sonuç olarak `R/module_image_generation.R` 765 → 723 satıra inerek sıfır olan baş boşluğunu geri kazandı; maintainability skoru 100/100 korunur.

Koruma: yeni `tests/testthat/test-generated-image-card-html-contract.R`, hem yardımcının XSS-güvenli kart sözleşmesini dondurur hem de kart buton işaretlemesinin (`image-action-btn-modern`) yalnızca kanonik yardımcıda kalıp tüketicilerde yeniden inline edilmediğini doğrular. Mevcut `test-image-generation-module-behavior.R` ve `test-chat-message-formatting-refactor-contract.R` davranış testleri yeşil kalır. Doğrulama: parse sanity ve odaklı sözleşme testleri (`bash tools/ai_validate.sh cloud-quick`) çalıştırıldı; tam runtime/app boot, tarayıcı UX ve Windows VM/SSO/DB doğrulaması bu bulut oturumunda yapılmadı.

### Görsel yükleme/önizleme, görsel anlama (vision), toast süresi, Yenile butonları ve renv bağımlılık kilidi

Dosya Yönetimi ve Ana Söyleşi yükleme alanlarında görsel dosyalar (JPG, JPEG, PNG, GIF, WEBP, BMP, SVG) artık yüklenebilir ve tabloda listelenir; desteklenmeyen tür diske kopyalanmadan önce reddedildiği için "kaydedildi ama görünmüyor" sızıntısı giderildi. Yüklenen görseller Dosya Yönetimi önizlemesinde artık doğrudan görüntülenir. **Görsel anlama (vision) artık desteklenir:** Model Bağlamı'na eklenen bir görsel, seçili model görsel girişini (Image Input) destekliyorsa yapay zekâ isteğine OpenAI uyumlu çok-kipli (multimodal) parça olarak eklenir ve içeriği sorulabilir; model desteklemiyorsa metin yolu korunur ve açık bir Türkçe not eklenir. Hangi modellerin görsel desteklediği, yetenek tablosundan (model kataloğunda "Image Input" işaretli olanlar) belirlenir; dağıtımda `MERGEN_VISION_MODELS` ortam değişkeni (ve Kodlama Uzmanı derin düşünme modelleri) ile sürülür ve `MERGEN_ENABLE_VISION=false` ile tümüyle kapatılabilir (varsayılan açık, yetenek-öncelikli). Aynı oturumda yüklenen görsel için ardışık sorular da desteklenir; görsel anlama hattı, yeniden giriş gerektirmeden mevcut oturum dosya kaydını koruyarak sonraki sorularda aynı görseli tekrar isteğe ekleyebilir. Toast bildirimleri sabit kısa süre yerine mesaj uzunluğuna göre 5–12 sn görünür. Söyleşi Geçmişi, Kayıtlı Söyleşiler, Görsel Galerisi ve tüm Yönetici/Sistem Durumu sayfalarındaki "Yenile" butonları Dosya Yönetimi ile aynı koyu/açık tema stiline getirildi.

Ayrıca uygulama artık `renv` ile bağımlılık kilidi kullanır: `R/config_packages.R` insan-okunur manifest olarak kalır, kesin sürümler `renv.lock` içinde sabitlenir. Kilit dosyası çalışan Windows VM (R 4.6.0) ortamında `Rscript tools/renv_snapshot.R` ile üretilir; kök `.Rprofile` offline/üretim güvenlidir (renv yalnızca kilit ve dolu proje kütüphanesi hazırsa etkinleşir, aksi halde global kütüphaneyle normal çalışır). **Gerçek `renv.lock`, uygulamayı çalıştıran şirket içi (on-prem) Windows VM üretim deposunda commit edilmiştir; çevrimiçi GitHub deposunda (Claude Code / Codex bulut oturumlarının gördüğü kopyada) bilinçli olarak BULUNMAZ.** Bu yüzden bir bulut checkout'unda `renv.lock` görünmemesi normaldir, eksiklik değildir; `RENV_LOCK_STATUS.md` yalnızca bu durumu belgeleyen işaretçidir. Ayrıntı: `docs/dependency-locking.md`.

### Karşılama ekranı açık tema cilası

Ana Söyleşi modern karşılama ekranında açık tema cam yüzeyleri yeniden dengelendi. Karşılama kartı daha geçirgen bir glassmorphism görünümüne çekildi; hızlı işlem kartları solid beyaz yerine açık temanın sıcak krem/yellowish zeminine uyumlu cam yüzeylerle yumuşatıldı. Kişisel selamlama başlığındaki kontrast iyileştirildi ve sağdaki nöral ağ animasyon zemini açık tema paletiyle uyumlu hale getirildi. Nöral ağ etkileşimi de yalnızca animasyon bölgesi içindeki imleç hareketlerine tepki verecek şekilde sınırlandı; video, hızlı başlangıç kartları ve tarayıcı dışına/ikinci ekrana çıkış durumlarında son imleç noktası artık düğümleri çekmeye devam etmez.

### Destek ve Yenilikler ekranları açık tema cilası

Destek alanındaki açık tema deneyimi daha okunabilir ve tutarlı hale getirildi. “Geri Bildirim & Hata” sayfasındaki 0-10 NPS puan düğmelerinin pasif kenarlıkları açık temada görünür olacak şekilde netleştirildi. “Yenilikler” sayfasında sürüm rozetleri ve kart içi “Yeni” rozeti için yüksek kontrastlı açık tema stilleri tanımlandı; sürüm seçici rozetleri gerçek sınıfı olan `.destek-surum-tab` üzerinden kapsanır.

“Yenilikler” sayfasında üst bölümün daha kullanışlı kalması için hero alanı ve sürüm rozetleri sabit kalacak, yalnızca alttaki sürüm kartı alanı dikey kaydırılacak şekilde düzenlendi. Sürüm bildirim rozetindeki ince parlayan kenar efekti korunurken standart `mask` bildirimi WebKit uyumluluk bildirimiyle birlikte kullanılır; böylece GitHub uyarısı anlaşılır hale gelirken mevcut görsel UX kaybedilmez.

“Yardım Merkezi” içindeki Yardım Asistanı sohbetinde açık tema balon kontrastı iyileştirildi. Kullanıcı mesaj balonu, tema token’ındaki `--mb-brand-support-teal` rengiyle yeşil/teal yüzey alır; bot yanıtları açık kart yüzeyinde okunabilir kalır. Bot yanıtlarında Markdown’dan gelen `<strong>`, italik, başlık, liste ve satır içi kod içerikleri açık temada kontrast sorunları oluşturmadan gösterilir.

### Yardım Merkezi açık tema sohbet cilası

Yardım Merkezi içindeki Yardım Asistanı sohbet ekranında açık tema okunabilirliği güçlendirildi. Kullanıcı mesaj balonu artık kurumsal destek teal tonu (`--mb-brand-support-teal`) üzerinden belirgin bir yüzey kullanır; bot yanıtları ise açık temada okunabilir kart yüzeyiyle ayrışır. Markdown kaynaklı kalın metinler (`<strong>`), vurgu, başlık, liste ve satır içi kod görünümleri açık zeminde kontrast kaybetmeyecek şekilde dengelendi. Değişiklik yalnızca açık temaya uygulanır; koyu tema davranışı korunur.

### Yardım Merkezi e-posta kodlama düzeltmesi

Yardım Merkezi içindeki “E-posta Destek” bağlantısının konu ve gövde alanları artık UTF-8 bayt temelli percent-encoding ile oluşturulur. Bu sayede Outlook/mailto açılışında “İyi çalışmalar dilerim,” gibi Türkçe karakter içeren varsayılan destek metinleri Windows yerel kod sayfasına bağlı bozulmadan doğru gösterilir. Düzeltme yalnızca bağlantı üretim sınırını etkiler; Yardım Merkezi’nin görünümü ve kullanıcı akışı değişmez.

### Unicode test fikstürlerinde platform kararlılığı

DB Unicode kaçış davranışını doğrulayan odak testleri, konsol veya işletim sistemi kod sayfasına bağlı bozulmaları önlemek için artık emoji ve Latin-1 kapsamındaki örnek karakterleri kaynak içinde doğrudan taşımak yerine `intToUtf8(as.integer(codepoint))` ile deterministik olarak üretir. Bu düzenleme yalnızca test fikstürlerinin platformlar arası kararlılığını güçlendirir; DB istemci kodlaması, `[[MERGEN-U+...]]` kaçış biçimi, okuma sınırında geri açma davranışı ve görünür kullanıcı deneyimi değişmez.

### LLM araç sonuçlarında veri önizleme kararlılığı

LLM ikinci geçişine aktarılan MCP araç sonuçlarında dataframe önizlemesi artık Türkçe alan adı kodlamasına daha dayanıklıdır. MCP/LLM araç sonucu dataframe önizleme çıkarımı `R/helpers_llm_worker_tool_results_preview.R` içinde izole edilmiştir; bu küçük helper `sonuç_önizleme`, `sonuc_onizleme` ve `preview` alanlarını tek noktadan çözer. `R/helpers_llm_worker_tool_results.R` araç sonucu biçimlendirme sorumluluğunda kalır ve maintainability ratchet fonksiyon bütçesini korur.

Bu değişiklik görünür kullanıcı akışını değiştirmez. Araç sonucu hâlâ “VERİTABANINDAN GELEN GERÇEK VERİ” başlığı, markdown tablo, dönen satır/sütun bilgisi, `source_table` uyarısı/değer listesi ve boş dataframe uyarısı sözleşmesini korur. Amaç, Excel Analizi ve SQL/MCP araç çıktılarında ikinci LLM sentez geçişine giden gerçek veri bağlamını daha deterministik hâle getirmektir. Bu sınır `test-maintainability-ratchet.R`, `test-source-manifest-contract.R` ve `test-llm-worker-tool-results-refactor-contract.R` kapsamıyla korunur.

### API anahtarı seçim modalı kararlılık ve tarayıcı hijyeni

Kişisel API anahtarı bulunmayan kullanıcılar için gösterilen “API Anahtarı Seçimi” onboarding modalı, Shiny özel mesaj işleyici sözleşmesine ve tarayıcı parola-formu beklentilerine uyumlu olacak şekilde güçlendirildi. İstemci tarafındaki yardımcı artık Shiny mesajlarını tek argümanlı handler’larla karşılar, kontrol yüzeyini handler kayıtlarından önce hazırlar ve yalnızca hassas olmayan `api_key_onboarding_suppressed` tercih bayrağını bildirir.

Modal içindeki API anahtarı alanı görünür kullanıcı akışını değiştirmeden non-submit form içinde, `autocomplete="new-password"` ve gizli `username` alanı ile render edilir. Böylece Chrome DevTools parola-formu verbose uyarıları kaldırılırken aynı input id’leri, kaydet/temizle düğmeleri, kurum anahtarıyla devam akışı ve güvenli anahtar saklama/doğrulama sınırı korunur. Ham API anahtarı, varsayılan kurum anahtarı veya herhangi bir secret istemciye yazılmaz ve loglanmaz.

### TTS ve AI Uzman için kurum anahtarı uyumu

Sohbet dışı ses akışları artık sohbetle aynı etkin API anahtarı çözümleme sözleşmesini kullanır. `R/helpers_feature_api_key.R`, kişisel anahtar, özellik-özel servis anahtarı, izinli varsayılan kurum anahtarı ve eski fallback anahtarı küçük ve merkezi bir yardımcıyla çözer.

Bu sayede kişisel API anahtarı bulunmayan ve “Varsayılan kurum API anahtarıyla devam et” seçeneğini kullanan kullanıcılar için normal sohbetin yanı sıra “Yanıtları Seslendir” ve “AI Uzman Konuşması” da aynı kurumsal anahtar akışıyla çalışır. Değişiklik görünür kullanıcı deneyimini değiştirmez; ham anahtarlar istemciye, loglara veya doğrulama raporlarına yazılmaz.

### SSO güvenliği ve Türkçe yol dayanıklılığı

SSO güvenlik sınırı güçlendirildi: Keycloak üzerinden gelen JWT token’ları artık claim değerleri güvenilir kabul edilmeden önce JWKS genel anahtarlarıyla kriptografik olarak doğrulanır. `SSO_VALIDATE_SIGNATURE=TRUE` güvenli varsayılandır; gerekirse `SSO_JWKS_URL` ile JWKS uç noktası elle verilebilir ve `SSO_JWKS_CACHE_TTL` ile anahtar önbellek süresi yönetilir. Yetkilendirme tarafında DB bağlantısı veya sorgu hatası oluşursa erişim fail-closed biçimde reddedilir; hata durumunda varsayılan kullanıcı yetkisi verilmez.

Türkçe karakter içeren Windows/VM yol sınırları için mojibake tespiti ve onarımı merkezi yardımcılar üzerinden korunur. `R/utils_text_encoding.R` ve `R/utils_path_helpers.R` davranışları; `test-sso-jwt-signature.R`, `test-sso-authorization-failclosed.R`, `test-sso-signature-parsing.R` ve `test-path-helpers-mojibake-behavior.R` odaklı davranış testleriyle güvence altına alınmıştır. Bu güncelleme görünür kullanıcı akışını değiştirmekten çok üretim güvenliği, kodlama bütünlüğü ve işletim güvenilirliğini artırır.

### Davranışsal test kapsamının genişletilmesi ve iki gizli hata düzeltmesi

Modül ve çalışma-zamanı mantığı için davranışsal (input→output) test kapsamı belirgin biçimde genişletildi. Daha önce yalnızca yapısal/sözleşme tarayıcılarınca (kaynak sırası, fonksiyon varlığı, ratchet) anılan ama gerçek davranışı doğrulanmayan kaynaklar için; gerçek bir DB/LLM/tarayıcı gerektirmeyen, deterministik ve çevrimdışı testler eklendi. Bu çalışmada 23 yeni `tests/testthat/test-*-behavior.R` dosyası ve yaklaşık 442 doğrulama (assertion) eklendi; hepsi tekil ve toplu koşumda 0 hata / 0 uyarı / 0 atlama ile geçti.

Kapsama alınan başlıca alanlar:

- Modül davranışları: Dosya Yönetimi istemci ek-durum kaydı ve DT tablo runtime'ı, STT modal aç/iptal/onayla akışı ve paket kilidi, ChartLab otomatik grafik türü/eksen tahmini, Görsel Oluşturma çeviri kapısı/koruma yolları/HTML üretimi ve XSS kaçışı, Derin Uzay giriş ekranı UI ve deneyim-modu eşlemesi, AI Uzman `can_speak` kapısı ve konuşma akışı, Yönetici Hata Analizi sekme UI'si ile durum/öncelik etiket+renk eşlemesi.
- Saf yardımcılar: Türkçe büyük/küçük harf dönüşümü ve kimlik çözümü, müzik URL'lerinde UTF-8 percent-encoding (Ü→%C3%9C; native %DC asla üretilmez), sohbet okuyucularındaki kullanıcı-id/zaman damgası mantığı, mesaj/Markdown→HTML işleme, sürüm geçmişi yol çözümleyici, kenar çubuğu kullanıcı baş harfleri/avatarı, modern karşılama UI oluşturucuları, toleranslı takip-sorusu bayrağı, dosya içeriği okuma, sağlık paneli biçimlendiricileri, gerekli paket doğrulaması, Bilge Yolaç metin/UTF-8 normalize ve çıktı biçimleme, log dizini/eşiği çözümleyicileri ve rozet HTML üreticileri.

Bu kapsam çalışması sırasında, yalnızca yapısal kapsama sahip olduğu için gözden kaçmış **iki gerçek gizli hata** tespit edilip cerrahi biçimde düzeltildi ve birer regresyon testiyle korunmaya alındı:

- `R/module_chartlab.R` → `make_id()`: `as.integer(as.numeric(Sys.time()) * 1000)` ifadesi 32-bit tamsayı aralığını aştığı için her grafik eklemede `NA` üretiyor ve "NAs introduced by coercion" uyarısı çıkarıyordu; grafik kimliği zaman damgasını kaybediyordu. `sprintf("%.0f", ...)` ile taşmasız tam sayısal damgaya çevrildi (davranış ve satır bütçesi korunur).
- `R/helpers_db_chat_readers.R` → `.db_chat_as_numeric_timestamp()`: `as.POSIXct()` ayrıştırılamayan bir metinde uyarı değil **hata** fırlattığından, fonksiyonun tasarlanan `0` güvenli geri dönüşü ulaşılamıyor ve sohbet listesi sıralaması bozuk bir zaman damgasında çökebiliyordu; `tryCatch(..., error = NA)` ile `0` geri dönüşü güvenceye alındı.

Bu değişiklikler yalnızca test ve iki nokta atışı düzeltmedir; görünür kullanıcı deneyimi, kodlama sözleşmeleri ve kaynak sırası değişmez. Testler `new.env(parent = globalenv())` ile yalıtılır, ağ/DB/LLM gerektirmez ve Türkçe açıklamalarla yazılmıştır.

### DOCX önizleme yarış koşulu ve yeni davranış testleri

Büyük DOCX dosyalarının önizleme modalında asenkron base64 hazırlama sonucu artık oturum belirteciyle korunur. `R/module_file_preview.R` içindeki `docx_preview_seq` değeri her DOCX modal açılışında artırılır; başarı ve hata geri çağrıları yalnızca kendi açılış belirteci hâlâ güncelse `docx_preview_container` alanına yazar veya toast gösterir. Böylece önce açılan büyük bir DOCX dosyasının geç gelen sonucu, daha sonra açılan başka bir DOCX modalını ezmez. Eski sonuçlar kullanıcı arayüzüne basılmaz; uygun olduğunda yalnızca önbelleğe alınır.

Bu sınır `tests/testthat/test-file-preview-docx-async-clobber-behavior.R` ile korunur. Test gerçek büyük dosya gerektirmez; `future::future` deterministik biçimde stub'lanır ve olmayan bir datapath üzerinden asenkron dal tetiklenir.

Aynı güncellemede davranışsal test kapsamı da genişletildi: `call_llm_with_retry`, DER/TLV yardımcıları, dosya deposu mutasyon yardımcıları, kenar çubuğu kullanıcı paneli, Claude runtime kaynak dizini çözümleme ve DB kullanıcı profili okuma davranışları için çevrimdışı ve deterministik testler eklendi. MCP dosya çözümleyicide mutlak yol güvenlik sözleşmesi de kırılgan İngilizce debug metnine değil, kalıcı davranışa bağlandı: normal kullanıcı akışında mutlak dosya yolu argümanları kabul edilmez ve Türkçe ret mesajı korunur.

### Servis bağımlı davranış testleri ve API anahtarı kayıt kararlılığı

Servis bağımlı ve derin runtime alanları için çevrimdışı, deterministik davranışsal regresyon kapsamı genişletildi. Yeni testler gerçek DB, tarayıcı, LLM veya ağ bağlantısı gerektirmeden stub/mock verilerle çalışır; amaç görünür kullanıcı deneyimini değiştirmek değil, mevcut çıktı sözleşmelerini ve hassas yardımcı davranışlarını refaktörlere karşı korumaktır.

Kapsama alınan başlıca alanlar; Yönetici Paneli grafik ve tabloları (Genel Bakış, Gelişmiş Analizler, Geri Bildirim, Sohbet Kalitesi, YZ Performansı, Zaman Analizi ve Hata Detayı ekleri), Sistem Durumu probe/UI oluşturucuları, Bilge Yolaç eklenti paneli, dosya deposu ve SQL loader yardımcıları, UI asset manifest yardımcıları, destek/geri bildirim DB yardımcıları, görsel galeri akışları, MCP/Excel araç biçimlendiricileri, PK/RLS yetki çözümleme yardımcıları, modern karşılama hızlı işlem butonları ve worker monitor defteri davranışlarıdır.

Ayrıca kişisel API anahtarı kaydında aralıklı görülebilecek bir tuz üretimi hatası cerrahi biçimde giderildi. `openssl::rand_bytes()` tarafından üretilebilen `0x00` baytları, hash yolunda `rawToChar()` nedeniyle `embedded nul in string` hatasına yol açabiliyordu; `save_user_api_key()` artık tuzdaki NUL baytlarını hash öncesinde `0x01` değerine eşleyerek mevcut şifreleme/doğrulama akışını korur ve kayıt işleminin rastlantısal olarak çökmesini engeller.

### Asenkron istek güvenliği, giriş ekranı tutarlılığı ve dosya listesi yenileme

Görsel üretimi ve özetleme gibi uzun sürebilen asenkron işlemlerde bayat istek sonuçlarının yeni kullanıcı isteğinin arayüzünü, sohbet durumunu veya yazıyor göstergesini ezmemesi için aktif istek kimliği ve durdurma durumu denetimi güçlendirildi. Bu davranış, gerçek LLM, görsel servisi, DB veya tarayıcı gerektirmeyen deterministik davranış testleriyle korunur.

Derin Uzay giriş ekranında “girişi atla” akışı, deneyim modu seçim akışıyla aynı persona/nöral renk güncellemesini gönderecek şekilde hizalandı. Böylece seçili veya varsayılan persona rengi, giriş animasyonu atlandığında da nöral animasyon tarafında tutarlı uygulanır.

Dosya Yönetimi başlığına “Yenile” düğmesi eklendi. Bu düğme mevcut kalıcı kullanıcı klasörü okuma mekanizmasını kullanarak dosya tablosunu yeniden yükler; “Tümünü Temizle” akışı korunur. Koyu ve açık tema stilleri ayrı tutulur; yeni buton kırmızı temizleme aksiyonundan görsel olarak ayrışır.

Aynı kapsamda, Bilge Yolaç doküman yardımcılarının izole test/debug kaynaklama sırasında repo kökü, tests/testthat çalışma dizini ve MERGEN_REPO_ROOT ortam değişkeni üzerinden güvenli fallback yapması belgelenen sözleşmeye uygun hale getirildi. API model/araç runtime ayrımından sonra taşınan yardımcılar için davranış testlerinin doğru kaynak dosyasını yüklemesi sağlandı.

## AI Ajanları İçin Doğrulama Profilleri

MERGEN Bilge üzerinde Codex veya Claude Code gibi AI ajanları işlem yaptığında doğrulama komutları ortam yeteneklerine göre ayrılmıştır:

- Tam bağımlılıkların kurulabildiği yerel/CI ortamlarında normal hızlı doğrulama: `bash tools/ai_validate.sh quick`
- Runtime, SSO, DB, streaming, kaynak sırası veya üretim VM etkili riskli değişikliklerde güçlü doğrulama: `bash tools/ai_validate.sh full --boot-smoke`
- Codex/Claude bulut ortamlarında ağır derleme gerektiren paketler nedeniyle tam runtime doğrulama mümkün olmadığında bulut uyumlu geri dönüş doğrulaması: `bash tools/ai_validate.sh cloud-quick`

`cloud-quick` modu, `duckdb`, `arrow`, `odbc` ve `pool` gibi ağır/runtime kaynak paketlerinin bulut ortamında uzun süren derlemelerine takılmamak için tasarlanmıştır. Bu mod, app source smoke / tam runtime boot doğrulamasını bilinçli olarak atlar; parse sanity ve odak sözleşme testlerini çalıştırır. AI ajanları `cloud-quick` kullandığında bunun tam runtime/VM doğrulaması olmadığını açıkça belirtmelidir.

Yalnızca `README.md` / `CLAUDE.md` dokümantasyon değişikliklerinde R doğrulaması çalıştırılmaz; yalnızca markdown farkı incelenir.

### Kaynak manifesti CRLF parse kararlılığı

Kaynak manifesti parse doğrulaması, Windows CRLF ve eski Mac CR satır sonlarını gerçek LF karakterine normalize edecek şekilde güçlendirildi. Böylece geçerli çok satırlı R dosyaları doğrulama sırasında literal "n" karakterleriyle bozulmaz ve "unexpected symbol" türü hatalı parse sonuçları üretilmez. Değişiklik yalnızca manifest parse doğrulama sınırını etkiler; görünür kullanıcı akışı ve uygulama davranışı değişmez.

### Teknik güncelleme özeti

- **Açılış ve medya hazırlığı:** Açılış ilerleme çubuğu artık pseudo/zaman bazlı dolum yerine gerçek boot kontrol noktaları ve medya tamponlama ilerlemesiyle ilerler. Karakter videoları ve karşılama arka plan videoları sırayla tarayıcı HTTP önbelleğine ısıtılır; yüzde 100, medya/kimlik/dosya indeksi hazır olduğunda anlamlıdır. Bilge Yolaç CLI bağlantı testi de açılış kritik yolundan ertelenerek ilerleme çubuğunu dondurmaması sağlanmıştır.

- **Erişilebilirlik:** Ana söyleşi giriş alanı, ikon-yalnız kontroller, açılır menüler ve toast bildirimleri ekran okuyucu erişilebilirliği için `aria-label`, `aria-hidden`, `role` ve `aria-live` sözleşmeleriyle güçlendirildi. Gönder/Durdur düğmesinin erişilebilir etiketi, düğmenin aktif moduna göre güncellenir.

- **Tanılama ve güvenilirlik:** Yakalanmamış Shiny hataları ve true streaming kullanıcı mesajı DB kaydetme hataları artık sır-redakteli `[RUNTIME_ERROR]` kayıtlarıyla tanılanabilir. Bu değişiklik görünür kullanıcı akışını değiştirmekten çok üretim ortamında hata kök nedeni bulma kabiliyetini artırır.

- **Claude Code / Codex bulut bootstrap dayanıklılığı:** Claude Code web oturumları için `SessionStart` hook ve bulut `Setup Script` yolu netleştirildi. RSPM indirme yönlendirmesi nedeniyle `rspm-sync.rstudio.com` allowlist gereklidir; installer gerçek paket indirmesini doğrular ve gerekirse CRAN'a düşer. Bu alan uygulama runtime/VM/DB/SSO kanıtı değil, bulut bootstrap sürecini kolaylaştıran altyapıdır.

- **Davranışsal test kapsamı:** App loading/boot readiness, health, support, chat actions/search/export, admin UI/analytics/error analysis, image generation, STT, ChartLab, AI Expert, user identity, messaging render, DB chat readers, logging resolvers, music URL encoding ve version history resolver gibi çok sayıda modül ve yardımcı için çevrimdışı, deterministik davranışsal test kapsamı genişletildi. Ayrıca `message_search` `gregexpr` uyarısı, DB chat timestamp parsing güvenli varsayılanı ve ChartLab milisaniye ID overflow uyarısı gibi küçük cerrahi düzeltmeler testlerle korunur.

### Sürüm geçmişi dosya yolu çözümleme kararlılığı

`version_history.md` dosyası repo kökünde kalır; `R/config_version_history.R` içindeki `resolve_version_history_md_path()` önce mevcut çalışma dizinindeki yerel `version_history.md` dosyasını dikkate alır, sonra üst dizinlere doğru arama yapar. Bu davranış, `tests/testthat` altından çalışan sürüm etiketi testlerinin repo kökündeki gerçek dosyayı bulmasını sağlarken, `getwd()` altında sentetik `version_history.md` oluşturan ayrıştırma testlerinin kendi geçici dosyalarını kullanmasını korur; boş/geçici dizinde dosya yoksa beklenen uyarı ve varsayılan sürüm davranışı korunur. Görünür kullanıcı arayüzü değişikliği yoktur.

### Davranışsal test kapsamı güncellemesi

`32dd9afd0d993e3590b51db296999c9ca78dd1af` güncellemesi, görünür kullanıcı akışını değiştirmeden odaklı davranışsal regresyon kapsamını genişletti. Kapsam; AI Uzman metin parçalama davranışı, API anahtarı kimlik ve varsayılan kurum anahtarı çözümleme sınırı, Bilge Yolaç plugin bileşen tespiti, prompt yol güvenliği ve araç kullanımı HTML kaçışlama sınırı, derin düşünme model çözümleme, araç türü tespiti, dosya indeksi ipuçlu arama, Sistem Durumu saf biçimlendiricileri, LLM/SSE kaynak ayrıştırma ve kaynakça üretimi, araç sonucu kısa yanıt biçimlendirme, log redaksiyonu iç yardımcıları, kullanıcı ve global hız sınırlama, metin/kod ayrıştırma, özetleme kullanıcı promptu üretimi ve sürüm geçmişi ayrıştırma alanlarını korur. Bu odak testler, ürün davranışını sabit tutarken ilerideki refaktörlerin güvenli yapılmasına yardımcı olur.

`517f80406badfd8f393f9e0648793c3481520ea7` / PR #425 güncellemesi, 31.05.2026 Pazar günü eklenen 19 committen gelen 25 odak davranışsal regresyon test dosyasını yalnızca ekleme olarak ekledi; görünür ürün davranışını doğrudan değiştirmez. Kapsam kompakt olarak API anahtarı sahipliği, etkin anahtar önceliği, uç nokta/kimlik fallback'i ve araç modu model çözümlemesini; Bilge Yolaç model/konfigürasyon, doküman ayrıntı düzeyi, indirmeler, çalışma deposu taraması, akış ayrıştırıcıları, güvenlik ilkesi, yol kanonikleştirme ve oturum runtime deposunu; UTF-8, mojibake, mailto kodlama, DB görünür/teknik normalizasyon, metin/log/ağaç işaretleme, atomik yazımlar ve ortak metin yardımcılarını; yükleme doğrulayıcı iç guard'ları, MCP Excel özet/adayları, MCP UNC yol normalizasyonu ve Proje/Kaynak Analizi çekirdek yardımcılarını; AI Uzman telaffuz düzeltme, persona kimliği göçü, LLM streaming delta/reasoning çıkarımı, streaming olmayan metin paketi çıkarımı, hızlı aksiyon tanıtım mesajları ve sürüm geçmişi etiket kaynağını korur.

`tests/scripts/ci_install_packages.R` için Linux paket tipi sözleşmesi ayrıca statik olarak korunur: varsayılan `pkgType` değeri Linux ortamında `source` kalmalı, `MERGEN_AI_R_PKG_TYPE` yalnızca açıkça verildiğinde (`source`/`binary`) override edilmelidir. Bu sözleşme `tests/testthat/test-ai-package-bootstrap-contract.R` ile izlenir ve `tools/setup_ai_r_environment.sh` içindeki RSPM denetimi kırılgan token eşleştirmeleriyle değil, kararlı URL parçaları (`__linux__/noble/latest`, `__linux__/jammy/latest`) üzerinden doğrulanır.

### Windows VM test kapsamı ve UTF-8 yol/anahtar kararlılığı

Windows VM üzerinde daha önce ortam gerekçesiyle atlanan bazı odak testler artık gerçek koşum kapsamına alınmıştır. SQL loader saf yardımcı testleri, `query_library` varlığı nedeniyle helper fonksiyonların dosya sonunda temizlenmesine takılmamak için kaynaklama sınırını izole eder. Plotly zarif-düşüş testi, VM’de `plotly` kurulu olsa bile fallback dalını lexical `requireNamespace()` mock’u ile doğrular. `safe_windows_short_path()` için Windows’a özel davranış artık atlanmaz; boş yol, olmayan yol ve var olan geçici dosya senaryoları gerçek Windows ayracı davranışıyla test edilir.

Aynı kapsamda kişisel API anahtarı şifreleme/çözme sınırı Türkçe karakterler için güçlendirildi: anahtar metni şifreleme öncesinde açıkça UTF-8 baytlarına çevrilir ve çözme sonrası metin UTF-8 olarak geri işaretlenir. Windows kısa yol yardımcısı da tek ters slash ayracını doğru biçimde `/` standardına çevirir. Bu güncelleme görünür kullanıcı akışını değiştirmez; Windows VM’de test güvenilirliğini, Türkçe karakter bütünlüğünü ve yol normalizasyon sözleşmesini güçlendirir.

Sıkı offline runtime sözleşmesini yerel/VM koşumuna dahil etmek için:
- `Sys.setenv(MERGEN_STRICT_OFFLINE_TESTS = "true")`
- ardından ilgili `testthat::test_file(...)` veya tam `testthat::test_dir("tests/testthat")` koşumu çalıştırılır.

Yalnızca dokümantasyon değişikliklerinde R doğrulaması çalıştırılmaz; markdown farkının incelenmesi yeterlidir.

### Doğrulama doktoru

Profil karışıklığını azaltmak için hafif bir doğrulama rehberi eklenmiştir: `tests/scripts/validation_doctor.R` ve kolaylık sarmalayıcısı olarak `tools/validation_doctor.sh`. Bu yol ağır test çalıştırmaz; uygulamayı, gerçek DB bağlantısını veya tarayıcıyı başlatmaz. Bunun yerine ortam sınıflandırmasını, tarayıcı ikilisi bulunabilirliğini, hassas ortam değişkenlerini yalnızca var/yok, uzunluk ve boolean-tarzı metaveriyle (ham değer olmadan), önerilen komut sırasını, her komutun neyi kanıtlayıp neyi kanıtlamadığını ve bloklayıcı/uyarı niteliğindeki kontrolleri raporlar.

Temel kullanım:

- `Rscript tests/scripts/validation_doctor.R --profile cloud`
- `Rscript tests/scripts/validation_doctor.R --profile local`
- `Rscript tests/scripts/validation_doctor.R --profile vm`
- `Rscript tests/scripts/validation_doctor.R --profile all`
- `bash tools/validation_doctor.sh --profile all`
- `bash tools/validation_doctor.sh all`

Çıktı ayrıca `artifacts/validation-doctor/` altında küçük bir JSON özet artifact’i üretir. Bu rehber özellikle `cloud-quick` sonucunun tam runtime, gerçek browser veya VM/SSO/SQL Server doğrulaması gibi yorumlanmasını engellemek için kullanılmalıdır. Son proof-status güçlendirmesiyle doktor çıktısı/artifact’i `doctor_runs_heavy_checks=false`, `validation_execution_status="not_run_by_validation_doctor"` ve `doctor_execution_notes` alanlarını da açıkça taşır; bu kayıtlar artifact’in yürütüm kanıtı değil profil rehberi olduğunu belirtir. Gerçek güvence yine ilgili profillerin kendisinden gelir: `bash tools/ai_validate.sh cloud-quick`, `bash tools/ai_validate.sh quick`, `bash tools/ai_validate.sh full --boot-smoke`, `MERGEN_REQUIRE_BROWSER_UX_SMOKE=true bash tools/ai_validate.sh full --boot-smoke`, VM preflight scriptleri, SQL Server Türkçe kodlama preflight ve manuel fragile-flow kanıtı ayrı ayrı çalıştırılıp değerlendirilmelidir.

AI validation yürütüm artifact’i olan `artifacts/ai-validation/<timestamp>/summary.json`, doktor artifact’inden ayrı değerlendirilmelidir. Bu dosya `profile_requested`, `profile_effective`, `validation_execution_status`, git branch/SHA/dirty çalışma ağacı özeti, `focused_contract_tests_status`, `full_testthat_suite_status`, `cloud_quick_validation_status`, `quick_repo_validation_status`, `full_validation_status`, `app_source_smoke_status`, `app_boot_smoke_status`, `browser_ux_smoke_status`, `browser_required`, VM/SSO/DB ve SQL Server Türkçe kodlama preflight durumları, manuel fragile-flow durumu, `failed_step_labels`, `skipped_step_labels` ve `proof_boundary_notes` alanlarını taşır. Bu alanlar ham DSN, endpoint, token, key, secret, password, cookie veya auth header değeri yazmamalıdır.
Son sözleşme güçlendirmesi: `tests/testthat/test-validation-doctor-contract.R`, doğrulama doktorunun ham secret-benzeri ortam değerlerini sızdırmamasını daha sıkı korur. `LOCAL_LLM_ENDPOINT`, `MERGEN_BROWSER_BIN`, DSN, URL, anahtar, token, secret ve parola benzeri değerler yalnızca `present`, `nchar`, boolean/metaveri ve `value=<hidden>` biçiminde raporlanmalıdır. Aynı sözleşme `cloud-quick` yolunun `tools/ai_validate.sh` içinde yalnızca `quick` repo profiline bağlanan bir sarmalayıcı alias olarak kalmasını; `tests/scripts/ai_repo_check.R` içine ayrı bir üçüncü profil olarak taşınmamasını korur. Bu güçlendirme çalışma zamanı kullanıcı deneyimini değiştirmez; yalnızca doğrulama profillerinin yanlış yorumlanmasını azaltır.

### Codex bulut çıktılarının yorumu

Codex/AI bulut ortamındaki `cloud-quick` sonucu yararlıdır; ancak tek başına kurum içi çalışma zamanı doğrulamasının yerine geçmez. Bu ortamda `git status --short` çıktısının temiz olması yalnızca yerel çalışma ağacında değişiklik olmadığını gösterir; `origin` remote yoksa veya fetch yapılamıyorsa checkout'ın güncel GitHub `main` ile aynı olduğu kanıtlanmış sayılmaz. Böyle bir durumda çelişkili Codex çıktıları `STALE/INCONCLUSIVE` olarak değerlendirilmelidir.

### Yanlış doğrulama iddialarını önleme

- Gerçek yürütüm kanıtı yalnızca `artifacts/ai-validation/<timestamp>/summary.json` içindeki `ai_validate` özetidir.
- `artifacts/validation-doctor/` altındaki `validation_doctor` artifact’i yalnızca rehberdir; `validation_execution_status=not_run_by_validation_doctor` ve `doctor_runs_heavy_checks=false` alanları bunun yürütüm kanıtı olmadığını açıkça belirtir.
- `cloud-quick` sonucu yalnızca kendi hafif kapsamı için geçerlidir; full validation, app boot, browser UX, VM/SSO/DB, SQL Server Türkçe kodlama veya manual fragile-flow kanıtı olarak raporlanmamalıdır.
- Answer self-check, kanıt alanlarıyla çelişen “Full validation passed”, “All validation gates passed” ve “Validation doctor passed” gibi geniş iddiaları yakalayacak şekilde güçlendirilmiştir.
- Dokümantasyon-only değişikliklerde R doğrulaması çalıştırılmamalıdır; yalnızca metin farkı gözden geçirmesi yeterlidir. Kod/doğrulama mantığı değişirse ilgili `ai_validate` profilleri ayrı kanıt olarak çalıştırılmalıdır.

### Codex ve VM kanıtı birlikte nasıl yorumlanır

Codex/cloud ortamında `cloud-quick` sonucunun başarılı olması yararlı fakat sınırlı bir kanıttır. Bu sonuç yalnızca bulut-uyumlu parse ve odak sözleşme kapsamı için geçerlidir; app source smoke, Shiny HTTP boot, gerçek tarayıcı UX smoke, VM/SSO/DB, SQL Server Türkçe kodlama veya manuel kırılgan akış kanıtı yerine geçmez. Codex ortamında `quick` veya `full --boot-smoke` ağır paket bootstrap/derleme yoluna girip tamamlanamazsa, bu tek başına VM doğrulamasını geçersiz kılmaz; yalnızca Codex tarafında ilgili artifact üretilmediği anlamına gelir.

Runtime, SSO, DB ve Türkçe SQL Server kodlama sınırları için yetkili kanıt VM üzerinde alınan sonuçlardır. VM tarafında `bash tools/ai_validate.sh quick`, `bash tools/ai_validate.sh full --boot-smoke`, `tests/scripts/run_vm_preflight_real.R` ve `MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST=TRUE` ile `tests/scripts/run_vm_encoding_preflight_real.R` başarıyla geçtiyse, Codex `cloud-quick` sonucu yalnızca ek/supplementary kanıt olarak yorumlanmalıdır. `validation_doctor` çıktısı ise her durumda rehberdir; yürütüm kanıtı olarak raporlanmamalıdır.

Başarılı bir `cloud-quick` koşumunda beklenen özet şudur: `environment: OK`, `parse sanity: OK`, `app source smoke: SKIPPED`, `focused contract tests: OK`, `failed_steps: 0`, `skipped_steps: 1`. Bu sonuç yine de tam runtime boot, gerçek tarayıcı, VM/SSO, gerçek DB veya SQL Server Türkçe kodlama doğrulaması anlamına gelmez.

Son doğrulama kanıtı güncellemesiyle `artifacts/ai-validation/<timestamp>/summary.json` dosyası artık istenen profil ile etkin profil ayrımını ve hangi ağır kapıların gerçekten çalışmadığını daha açık gösterir. Cloud ortamında normal `quick` koşumu ağır/runtime paketleri (`arrow`, `duckdb`, `odbc`, `pool`, `shinyWidgets` vb.) nedeniyle app source smoke aşamasında durursa, `cloud-quick` güvenli geri dönüş yolu kullanılabilir. Bu durumda `failed_steps=0`, `skipped_steps=1`, `profile_requested="cloud-quick"`, `profile_effective="quick"` ve `app_source_smoke_status="skipped"` sonucu yalnızca parse/contract kapsamı için geçerli kanıttır; tam runtime, app boot, browser UX, VM/SSO/DB, SQL Server Türkçe kodlama veya manuel fragile-flow doğrulaması olarak yorumlanmamalıdır. Windows VM/RStudio altında child `Rscript.exe` environment probe aşamasında çökerse bu, uygulama regresyonu değil yerel doğrulama çalıştırma ortamı sınırlaması olarak raporlanmalı; ilgili VM/runtime kanıtı ayrı kapılarla alınmalıdır.

`R/helpers_db_connection.R` için güncel sözleşme, `odbc` ve `pool` paketlerinin top-level `library()` ile zorunlu yüklenmemesidir. Bu sayede `cloud-quick` ağır DB runtime paketlerine takılmadan test bootstrap yolunu source edebilir. Gerçek DB bağlantısı açan fonksiyonlar kendi içinde `requireNamespace()` ile net hata vermeye devam eder; VM/SSO ve SQL Server güvencesi ayrıca VM preflight scriptleriyle alınmalıdır.

Kurum içi sunucu/VM testleri başarıyla geçtiyse ve Codex bulut çıktısı checkout, remote veya bootstrap kısıtları nedeniyle çelişkili görünüyorsa, çalışan kurum içi kod yalnızca Codex çıktısı yüzünden değiştirilmemelidir. Önce Codex'in hangi commit'i ve hangi artifact'i kullandığı kanıtlanmalıdır.


### Tarayıcı UX smoke kapsamı

En kırılgan istemci tarafı akışları için hafif gerçek tarayıcı smoke yolu korunur. `www/smoke/ux-smoke.html`, aynı origin üzerinde çalışan uygulamayı iframe içinde açar ve smoke-only `www/smoke/ux-smoke-probes.js` yardımcısını yükler. Başarılı koşumun son işareti `UX_SMOKE_DONE:PASS` olmalıdır.

Bu smoke yolu; streaming init/delta/stale requestId/finalize yaşam döngüsünü, tehlikeli HTML benzeri içeriğin etkin HTML'e dönüşmemesini, action button geri dönüşünü, follow-up pending temizliğini ve yinelenen asistan mesajı oluşmamasını doğrular. Ayrıca TTS/STT müzik duck sahipliği, tek arka plan müzik kaynağı, kayıtlı sohbet yüklenirken eski TTS'in otomatik başlamaması, Bilge Yolaç ↔ Ana Söyleşi geçişinde aktif panel sızıntısı, URL hash sızıntısı, modal/backdrop kalıntısı ve audio/TTS sahipliği dahil stale tool/page state kalmaması, welcome video'nun gereksiz destroy/reinit edilmemesi ve `Türkçe_çalışma_özeti_İstanbul.pdf` gibi Dosya Yönetimi görünen adlarının sentetik yenilemede okunabilir kalması kapsanır.

Son güçlendirme: UX smoke kapsamı yalnızca çalıştırılmakla kalmaz; `tests/testthat/test-ux-smoke-browser-contract.R` ve `tests/testthat/test-browser-smoke-harness-contract.R` ile açık belirteçler üzerinden kilitlenir. Bu sözleşmeler parçalı streaming içinde `<script>`, `<img onerror>` ve `javascript:` benzeri tehlikeli içeriklerin etkin HTML'e dönüşmeden görünür metin olarak kalmasını; finalize sonrası state, eylem düğmeleri ve takip sorusu temizliğini; TTS/STT duck sahipliğini; Bilge Yolaç ↔ Ana Söyleşi geçiş temizliğini; welcome video destroy/reinit sayaçlarını ve sentetik Dosya Yönetimi Türkçe görünen ad yenilemesini korur.

Tarayıcı UX smoke doğrulaması iki katmanlıdır: `bash tools/ai_validate.sh full --boot-smoke` önce normal Shiny boot smoke adımını çalıştırır, ardından yerelde Chrome/Chromium/Edge ikilisi bulunursa `tests/scripts/ai_browser_ux_smoke.R` ile sunulan `/smoke/ux-smoke.html` rotasını headless tarayıcıda koşar. Gerçek tarayıcı koşumunda beklenen son işaret `UX_SMOKE_DONE:PASS` değeridir.

Normal `--boot-smoke` profilinde tarayıcı ikilisi bulunamazsa browser UX adımı bloklayıcı olmayan SKIP (exit 0) olarak geçebilir. Tarayıcının zorunlu olduğu VM/yerel senaryolarda bloklayıcı mod kullanılmalıdır: `MERGEN_REQUIRE_BROWSER_UX_SMOKE=true bash tools/ai_validate.sh full --boot-smoke` veya `Rscript tests/scripts/ai_browser_ux_smoke.R --require-browser`. Varsayılan keşif yolları dışında kurulumlarda açık tarayıcı yolu `MERGEN_BROWSER_BIN="/path/to/chrome-or-msedge"` ile verilebilir.

Bu yol üretim kullanıcı deneyimini değiştirmemelidir. Smoke arayüzleri yalnızca test amaçlı ve isim alanlıdır: `window.MergenStreamingSmoke`, `window.MergenAudioLifecycleSmoke`, `window.MergenWelcomeVideoSmoke`, `window.MergenUxSmokeProbes`. `www/smoke/ux-smoke-probes.js` üretim varlık manifestine (`R/config_ui_assets.R`) eklenmemelidir. Runner yalnızca yerel tarayıcı ikililerini kullanır; CDN, runtime download, npm, Playwright, Selenium, chromote veya RSelenium gibi ağır/harici otomasyon bağımlılıkları eklenmemelidir.

Doğrulamada yerel/VM sonucu esas alınır: `bash tools/ai_validate.sh quick`, `bash tools/ai_validate.sh full --boot-smoke` ve aynı-origin `/smoke/ux-smoke.html` koşumu `UX_SMOKE_DONE:PASS` ile tamamlanmalıdır. Linux/RSPM paket bootstrap yolunda varsayılan paket türü güvenli source-style kurulumdur; `MERGEN_AI_R_PKG_TYPE` yalnızca açık override olarak kullanılmalıdır. Codex/Claude bulut ortamlarında R paket bootstrap aşaması testler başlamadan önce `arrow`, `duckdb`, `odbc`, `pool`, `shinyWidgets` gibi paketlerde başarısız olursa bu durum kod/test hatası değil, ortam/bootstrap kısıtı olarak raporlanmalıdır.

Son kabul notu: bu güncelleme sonrasında gerçek tarayıcı smoke koşumu `UX_SMOKE_DONE:PASS` işaretiyle tamamlanmış ve tüm `testthat` testleri başarıyla geçmiştir. Gelecek riskli/runtime etkili değişikliklerde aynı güven düzeyi için `bash tools/ai_validate.sh full --boot-smoke`; normal hızlı doğrulamada ise `bash tools/ai_validate.sh quick` kullanılmalıdır.

---
---

## Yapay Zekâ Söyleşi Deneyimi

- Ana Söyleşi, hızlı eylem kartları, model bağlamı, canlı düşünce akışı, reasoning model davranışı ve kaydedilmiş sohbet geri yükleme notları bu değişiklik notları ile [`technical-reference.md`](technical-reference.md) içinde izlenir.
- Araç bazlı model çözümleme, düşünme modelleri ve LLM işçi çıktısı önizleme kararlılığı korunması gereken davranışsal sınırlar olarak [`../CLAUDE.md`](../CLAUDE.md) içinde otoritatif kalır.

## Görsel Yükleme, Görsel Anlama ve Dosya Akışları

- Görsel yükleme/önizleme, desteklenen görsel türleri, model bağlamına görsel ekleme ve `MERGEN_VISION_MODELS` ile sürülen model yetenekleri bu değişiklik notlarında izlenir.
- Görsel anlama ayrı bir dar kurulum dosyasına ayrılmadı; mimari bağlamı [`architecture-map.md`](architecture-map.md), operasyonel yapılandırma/troubleshooting bağlamı [`../RUNBOOK.md`](../RUNBOOK.md) ve ayrıntılı teknik referans [`technical-reference.md`](technical-reference.md) içinde tutulur.

## Dosya Yönetimi ve Önizleme

- Dosya Yönetimi, önizleme, kullanıcı izolasyonu, geçici dosya yaşam döngüsü, güvenli yol çözümleme, DOCX önizleme yarış koşulu ve dosya listesi yenileme notları korunmuştur.
- Dosya deposu sağlık kontrolleri ve üretim yolu yapılandırması için [`../RUNBOOK.md`](../RUNBOOK.md) okunmalıdır.

## API Anahtarı, Güvenlik ve SSO

- API anahtarı seçim modalı, kişisel/kurumsal anahtar önceliği, TTS/AI Uzman anahtar çözümleme davranışı ve servis bağımlı test caveat'leri burada özetlenir.
- Gerçek API anahtarları, token'lar, parolalar, DSN'ler veya özel uç noktalar bu belgede tutulmaz. Yapılandırma örneği için [`../.Renviron.example`](../.Renviron.example) yalnızca şablon olarak kullanılmalıdır.

## Türkçe Karakter, Kodlama ve Windows VM Kararlılığı

- Türkçe karakter bütünlüğü, mojibake önleme, DB read/write normalizasyonu, mailto kodlama, Windows-1254/UTF-8 sınırı, UNC yol ve SSO profil davranışları güvenlik-kritik kabul edilir.
- Kodlama sınırlarının otoritatif sözleşmesi [`../CLAUDE.md`](../CLAUDE.md), operasyonel bakım yönergeleri [`../RUNBOOK.md`](../RUNBOOK.md), mimari özet ise [`architecture-map.md`](architecture-map.md) içindedir.

## UI, Tema ve Erişilebilirlik İyileştirmeleri

- Açık tema karşılama ekranı, neural pointer sınırı, Destek/Yenilikler açık tema kontrastı, NPS düğmeleri, rozetler, yardım sohbeti balonları, toast davranışı ve tarayıcı konsol hijyeni notları bu değişiklik notlarında izlenir.
- Frontend asset sırası ve UX smoke sınırları için [`../CLAUDE.md`](../CLAUDE.md) ve [`architecture-map.md`](architecture-map.md) birlikte okunmalıdır.

## TTS, STT ve Ses Akışları

- TTS/STT, AI Uzman konuşma üretimi, chunking, audio ducking ve kaydedilmiş sohbet TTS autoplay sınırları değişiklik notlarında korunur.
- Anahtar çözümleme ve secret safety kuralları runtime sözleşmesi olarak [`../CLAUDE.md`](../CLAUDE.md) içinde kalır.

## Bilge Yolaç / Claude Code Alanı

- Bilge Yolaç web oturumları, güvenli CLI çalıştırma, çalışma dizini seçimi, plugin sistemi, doküman çıkarımı/indirme ve stream-poll davranışı derin dokümanlarda izlenir.
- Mimari harita, eklenti dizinlerini ve çalışma zamanı sınırlarını özetler; sıkı güvenlik sözleşmeleri için [`../CLAUDE.md`](../CLAUDE.md) esas alınır.

## Test, Doğrulama ve Maintainability

- `bash tools/ai_validate.sh quick`, `cloud-quick`, validation doctor, browser UX smoke, maintainability ratchet, frontend complexity doctor ve kanıt dürüstlüğü notları README yerine bu belge, [`../RUNBOOK.md`](../RUNBOOK.md) ve [`../CLAUDE.md`](../CLAUDE.md) altında izlenir.
- `cloud-quick` çıktısı, ağır runtime package bootstrap ve app source smoke kapsamı çalışmadan elde edilmiş olabilir; bu nedenle tam VM/üretim doğrulaması gibi sunulamaz.

## Dependency Locking / renv

- `R/config_packages.R` insan-okunur paket manifestidir; kesin sürüm kilidi Windows VM/on-prem kuralına bağlı `renv.lock` ile yönetilir.
- Bulut checkout'unda `renv.lock` bulunmaması bilinçli olabilir; ayrıntı [`../RENV_LOCK_STATUS.md`](../RENV_LOCK_STATUS.md) ve [`dependency-locking.md`](dependency-locking.md) içindedir.

## Bilinen Sınırlar ve Kanıt Dürüstlüğü

- README'deki eski PR tarzı doğrulama günlükleri, kullanıcıyı ilk girişte yormamak için buraya taşındı.
- Yalnızca gerçekten çalıştırılan komutların sonucu “geçti” olarak ifade edilir.
- Codex/Claude cloud kanıtı ile Windows VM/on-prem kanıtı aynı şey değildir; özellikle DB, SSO, encoding, UNC path, paket kilidi ve tarayıcı smoke alanlarında sınırlar açıkça belirtilmelidir.
