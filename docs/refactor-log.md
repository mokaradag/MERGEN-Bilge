# MERGEN Bilge Refactor Günlüğü

Bu günlük, kod davranışını değiştirmeden karmaşıklığı ve onboarding yükünü azaltmayı hedefleyen yapısal iyileştirmeleri kaydeder. Her giriş; seçilen iz(ler)i, değişen dosyaları, önce/sonra karmaşıklık notlarını, korunan davranış sözleşmelerini, eklenen/güncellenen testleri, gerçekten çalıştırılan doğrulamaları, kullanıcı için manuel QA listesini ve bilinen riskleri/atlanan doğrulamaları içerir.

Sıkı çalışma kuralları için İngilizce [`../CLAUDE.md`](../CLAUDE.md) otoritatif kalır.

---

## 2026-06-13 — Windows VM evidence gate rerun: güncel release kanıtı

`tests/scripts/run_vm_evidence_gate.R` tam Windows VM koşumu 13 Haziran 2026 tarihinde yeniden uçtan uca geçti: `Toplam: 13 passed, 0 failed, 0 skipped`. Güncel passed adımlar: `env_config`, `parse_sanity`, `app_boot_smoke`, `full_testthat`, `maintainability_report`, `frontend_ratchet`, `seam_doctor`, `source_manifest_contracts`, `ui_asset_manifest_contracts`, `browser_ux_smoke`, `vm_preflight_real`, `db_encoding_preflight`, `renv_status`. Son artifact: `artifacts/vm-evidence/20260613-120951/evidence.json`; kalıcı artifact düzeni `artifacts/vm-evidence/<timestamp>/evidence.json`.

Operasyonel olarak browser proof, external-app modunda alındı: uygulama ayrı pencerede `http://127.0.0.1:28081` üzerinde açık tutuldu, gate ikinci pencerede `MERGEN_BROWSER_UX_BASE_URL=http://127.0.0.1:28081` ve `MERGEN_REQUIRE_BROWSER_UX_SMOKE=true` ile çalıştırıldı. Bu mod `UX_SMOKE_DONE:PASS` üretmediği sürece blocking kabul edilir.

Milestone sırasında doğrulanan bakım iyileştirmeleri: isolated health UI testleri gerekli health table helper'larını source eder; LLM worker tool-result isolated testleri preview-dataframe helper'ını formatter'dan önce source eder; `run_full_testthat_isolated.R` start/end index aralığıyla devam koşumunu destekler; full testthat çocuk süreçleri browser UX evidence env leakage'a karşı korunur; VM preflight path handling Türkçe karakterli ve boşluklu mapped-drive / UNC-style path'ler için sertleştirildi.

Bu kayıt release/readiness kanıtıdır, davranış değişikliği iddiası değildir. Kanıt yalnızca `evidence.json` içinde `passed` görünen adımlar için geçerlidir; uzun süreli saha yükü ve manuel kırılgan-akış QA'sı ayrıca gerekir.

## 2026-06-10 — Seam kayıt defteri, frontend bölge sahipliği ve CSS kaskad kuralları (yönetişim katmanı)

### Seçilen iz(ler)
- **Track A — Üretim-kritik seam dağınıklığı:** Shiny runtime, DB/encoding, SSO/JWT, LLM streaming, dosya yaşam döngüsü, API anahtarları, medya/ses, yönetici panelleri ve Bilge Yolaç sınırlarının sahipliği tek makine-okur haritada toplandı.
- **Track B — Frontend kırılganlığı:** Sıralı CSS/JS katmanları, tema override zinciri, streaming handler sırası ve varlık sahipliği için bölge haritası + makine doğrulamalı CSS kaskad kuralları + tarayıcı smoke zorlaması sıkılaştırması eklendi.

### Özet ve gerekçe
Sahiplik bilgisi CLAUDE.md düzyazısına ve onlarca sözleşme testine dağılmıştı; "bu dosyaya kim bakar, hangi test korur?" sorusunun tek cevabı yoktu. Yeni runtime R dosyaları manifest'e, yeni frontend dosyaları manifest+rapora eklenebiliyor ama hiçbir katman sahiplik bildirimi ZORLAMIYORDU. Tema override zinciri (tokens → light → extras → modüller → overhaul → user_polish) yalnızca dondurulmuş vektör sırasıyla korunuyordu; JS'teki gibi anlamlı ikili sıra kuralları yoktu.

Çözüm runtime davranışını değiştirmeyen üç saf katman: (1) `R/config_seam_registry.R` — 12 seam'in bölüm/dosya/guard-test/odaklı-doğrulama sahipliği; (2) `R/config_ui_asset_zones.R` — manifestteki her CSS/JS varlığının tam olarak bir bölgeye (23 bölge) atanması + manifest dışı bilinçli varlıkların gerekçeli sahiplik kaydı; (3) `ui_asset_css_order_rules` + `ui_asset_validate_css_order()` — tema/Bilge Yolaç CSS kaskadının JS kuralları gibi hem boot'ta hem testte zorlanması. Operasyonel rapor için `tests/scripts/seam_doctor.R` (+ `tools/seam_doctor.sh`) eklendi. Tarayıcı smoke: `MERGEN_BROWSER_BIN` açıkça verilmişse require modu otomatik açılır ve kullanılamayan binary erken/net hata verir.

### Değişen dosyalar
**Kaynak (yeni)**
- `R/config_seam_registry.R` (539 satır / 6 fonksiyon) — 12 seam kaydı + `mergen_seam_registry_validate()` (bölüm tekil sahiplik, guard-test/dosya varlığı, bölge sahibi çapraz kontrolü) + `mergen_seam_runtime_allowlist()` (manifest dışı runtime R dosyaları için TEK allowlist).
- `R/config_ui_asset_zones.R` (764 satır / 10 fonksiyon) — 23 bölge, `ui_asset_zones_validate()` (çift yönlü tam bölümleme), `ui_asset_unmanifested_ownership` (app_loading*, admin_analytics.css, smoke dosyaları), `ui_asset_frontend_ownership_gaps()` (fiziksel www/css|js kapsama).
- `tests/scripts/seam_doctor.R`, `tools/seam_doctor.sh` — yapısal doğrulama + secret-safe JSON artifact (`artifacts/seam-doctor/`); `source(...)`-güvenli (quit yok, drift'te `stop()`).

**Kaynak (güncellenen)**
- `R/config_source_manifest.R` — `config_ui_assets` bölümüne bölge haritası eklendi (n: 1→2); yeni `architecture_governance` bölümü (`R/config_seam_registry.R`); toplam 258→260 dosya.
- `R/config_ui_assets.R` — `ui_asset_css_order_rules` (21 kural: variables→tokens→light→extras→refinements→6 tema modülü→overhaul→phase2→user_polish→v2; tema-sonrası brand_title/sidebar_user_panel/tool_backgrounds; welcome_modern→theme_light_welcome; Bilge Yolaç CSS zinciri) + `ui_asset_validate_css_order()` `ui_asset_validate(...)` zincirine bağlandı. Üretilen tag çıktısı bayt-denk değişmedi.
- `tests/scripts/ai_browser_ux_smoke.R` — explicit `MERGEN_BROWSER_BIN` ⇒ require modu otomatik + kullanılamayan binary için erken `MERGEN_BROWSER_BIN kullanılamıyor` hatası.
- `tests/scripts/ai_repo_check.R` — quick profiline 4 yeni sözleşme testi eklendi (sections, seam-registry, ui-asset-zones, seam-doctor).
- `.gitignore` — `artifacts/seam-doctor/`, `artifacts/frontend-complexity-doctor/`, `artifacts/validation-doctor/` eklendi.

**Test**
- `tests/testthat/test-seam-registry-contract.R` (yeni, 6 test / 12 assertion) — dondurulmuş seam id listesi, manifest/bölge/dosya gerçekliği doğrulaması, bölüm→seam tekil sahiplik, R/ sahipsiz dosya yasağı, kök giriş dosyaları sahipliği, erişim yardımcıları.
- `tests/testthat/test-ui-asset-zones-contract.R` (yeni, 7 test / 13 assertion) — dondurulmuş bölge id listesi, manifest tam bölümleme, fiziksel sahiplik boşluğu yasağı, bölge sahiplerinin gerçek seam olması, seam→bölge türetimi, smoke sızıntı yasağı, bilinmeyen grup referansı hataları.
- `tests/testthat/test-seam-doctor-contract.R` (yeni, 2 test / 6 assertion) — statik hafiflik/secret-safety/source-güvenlik sözleşmesi + doctor'ın gerçek repoda sorunsuz çalışıp artifact üretmesi (warn seviyesi test sonunda geri yüklenir).
- `tests/testthat/test-ui-asset-manifest-contract.R` — yeni CSS kural bloğu (kural çapaları, gerçek manifestte sağlama, sentetik ihlal yakalama, validate zinciri bağlılığı): 178→233 assertion.
- `tests/testthat/test-source-manifest-sections-contract.R` — bölüm anahtarları + çapalar + toplam (260) bilinçli güncellendi.
- `tests/testthat/test-browser-ux-smoke-runner-contract.R` — yeni zorlama tokenları (`browser_bin_explicit`, `MERGEN_BROWSER_BIN kullanılamıyor`) donduruldu.
- `tests/testthat/test-maintainability-ratchet.R` — yönetişim dosyalarına dosya-özel bütçe: zones 780L/12F, registry 580L/8F.

**Dokümantasyon**
- `CLAUDE.md` — yeni "Seam registry and frontend ownership zone contract" bölümü; manifest ekleme kurallarına seam sahipliği maddesi; UI asset sözleşmesine bölge + CSS kural maddeleri; tema sözleşmesine yürütülebilir kaskad notu; browser smoke kurallarına explicit-bin zorlaması; "Where to go next" işaretçisi.
- `docs/architecture-map.md` — yönetişim katmanı bölümü (seam tablosu, disiplin kuralları, CSS kaskad notu); kritik sınırlar ve "önce oku" tabloları güncellendi.
- `RUNBOOK.md` — hızlı referans + 7.4 seam/bölge doğrulaması + 7.5 tarayıcı smoke zorlaması.
- `docs/technical-reference.md`, `docs/README.md` — yönetişim katmanı referansları.

### Önce / sonra karmaşıklık notları
- Önce: 35 manifest bölümü ve 215 manifest frontend varlığı için sahiplik yalnızca düzyazıda; R/ ve www/ altına sahipsiz dosya eklemek mümkündü; tema kaskadı yalnızca dondurulmuş vektörle korunuyordu; tarayıcı bildiren ortamda smoke sessizce atlanabiliyordu.
- Sonra: 36 bölüm → 12 seam (tekil sahiplik, testle zorlanır); 95 CSS + 120 JS manifest varlığı → 23 bölge (çift yönlü tam bölümleme); www/css|js fiziksel kapsama + R/ sahipsiz dosya yasağı; 21 yürütülebilir CSS kaskad kuralı boot+test seviyesinde; explicit browser yapılandırması bloklayıcı. Maintainability skoru 100/100 korunur; yeni dosyalar dosya-özel bütçeyle kilitli.

### Korunan davranış sözleşmeleri
- Çalışma zamanı UX bayt-denk: yönetişim dosyaları saf veri+fonksiyon tanımlar, boot'ta doğrulama çağrılmaz (CSS sıra doğrulayıcısı hariç — o da mevcut `ui_asset_validate(...)` kalıbının genişletilmesidir ve gerçek manifestte sessiz geçer).
- Yükleme sırası sahipliği değişmedi: kaynak sırası `R/config_source_manifest.R`, varlık sırası `R/config_ui_assets.R`.
- Hiçbir mevcut test/ratchet/guard zayıflatılmadı; sections sözleşmesi bilinçli genişletildi, ratchet bütçeleri yalnızca SIKILAŞTIRILDI.
- Smoke-only dosyalar üretim manifestine eklenmedi; CDN/ağ bağımlılığı yok; secret yazılmadı.

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- `Rscript tests/testthat.R` (tam strict suite, `stop_on_failure`/`stop_on_warning`) → **exit 0**; 0 FAIL / 0 WARN; 5 ortam-koşullu SKIP (Windows-only .cmd testi, openxlsx kurulu değil ×3, strict-offline opt-in) — tümü önceden var olan, dokümante skip semantiği.
- Odaklı testler (0 FAIL / 0 WARN / 0 SKIP): seam-registry (12), ui-asset-zones (13), seam-doctor (6), sections (154), source-manifest (165), global-manifest (12), ui-asset-manifest (233), maintainability-ratchet (174), frontend-ratchet (86), all-runtime-parse (2), production-contracts (21), secret-leak (8), network-boundary (2), browser-ux-runner (5), e2e-boot-welcome (29).
- `Rscript tests/scripts/parse_sanity_check.R` → 744 dosya parse OK.
- `Rscript tests/scripts/maintainability_report.R` → skor 100/100; 0 refactor adayı; 800+/25+ dosya yok.
- `Rscript tests/scripts/frontend_complexity_doctor.R` → artifact üretildi; manifest dışı app-owned varlık 0.
- `Rscript tests/scripts/seam_doctor.R` → `SEAM_DOCTOR_RESULT: OK`, 12 seam / 36 bölüm / 23 bölge / 9 manifest-dışı sahipli dosya; artifact yazıldı.
- App boot smoke: `source("app.R")` + `validate_boot_state()` → OK; seam registry + bölge haritası runtime'da yüklü (CSS sıra doğrulayıcısı boot zincirinde sessiz geçti).
- `bash tools/ai_validate.sh full --boot-smoke` → **geçti**: 6/6 adım OK (`environment`, `parse sanity`, `app source smoke`, `full testthat suite` 111.3s, `shiny boot smoke`, `browser UX smoke` adımı), `failed_steps: 0`, `skipped_steps: 0`, `full_testthat_suite_status: "passed"`, `shiny_boot_smoke_status: "passed"`; `browser_smoke_status: "skipped"` — adım çalıştı ama konteynerde tarayıcı binary'si olmadığından kendi içinde bloklamayan SKIP üretti. Artifact: `artifacts/ai-validation/20260610-155750/summary.json`.
- Tüm komutlar `LANG=C.utf8` ile çalıştırıldı.

### Manuel QA (kullanıcı/VM tarafı)
- Windows VM'de SSO ile normal başlatma: karşılama ekranı, koyu/açık tema geçişi (özellikle açık tema cilası: navbar şeridi, chat baloncukları, Bilge Yolaç yüzeyleri), hızlı eylemler ve Bilge Yolaç akışının görsel olarak değişmediğini doğrulayın.
- Tarayıcılı ortamda `MERGEN_REQUIRE_BROWSER_UX_SMOKE=true bash tools/ai_validate.sh full --boot-smoke` ile `UX_SMOKE_DONE:PASS` alın; `MERGEN_BROWSER_BIN` ayarlıysa artık otomatik bloklayıcı olduğunu bilin.
- `bash tools/seam_doctor.sh` çalıştırıp `SEAM_DOCTOR_RESULT: OK` görün.

### Bilinen riskler / atlanan doğrulamalar
- Browser UX smoke bu oturumda gerçek tarayıcıyla ÇALIŞTIRILMADI (konteynerde Chrome/Chromium/Edge yok); statik harness/runner sözleşmeleri geçti. VM'de bloklayıcı modda koşulmalıdır.
- VM/SSO/gerçek DB/SQL Server Türkçe encoding kapıları bu oturumun kapsamı dışındadır (runtime davranışı değişmedi); normal VM preflight rutini yeterlidir.

---

## 2026-06-09 — Sidebar kullanıcı paneli saf görünüm yardımcılarının ayrılması

### Seçilen iz(ler)
- **Track B — Complex runtime kodundan saf yardımcı çıkarımı** (`R/module_sidebar_user_panel.R` → `R/helpers_sidebar_user_display.R`).
- Tamamlayıcı: dosya, 24-fonksiyon küresel ratchet tavanında oturan üç dosyadan biriydi; bölünme bu dosyayı tavandan indirir ve korunan Departman/tema/iskelet sözleşmelerine bağımsız test edilebilir bir sahip verir.

### Özet ve gerekçe
`R/module_sidebar_user_panel.R` (581 satır / 24 fonksiyon) saf görünüm kararlarını (Türkçe-güvenli baş harf üretimi, avatar URL placeholder reddi, korunan `Departman → departman → department` seçim sırası, tema anahtarı/kontrol satırı/kullanıcı rozeti HTML üreticileri) Shiny render/observer orkestrasyonuyla aynı dosyada taşıyordu. Dosya küresel 24-fonksiyon tavanında oturduğundan, panele eklenecek herhangi bir küçük yardımcı küresel ratchet'i kırardı.

Altı saf yardımcı (`mb_sidebar_user_initials`, `mb_sidebar_user_avatar_url`, `mb_sidebar_user_department`, `mb_sidebar_theme_switch`, `mb_sidebar_controls_row`, `mb_sidebar_user_badge_ui`) birebir `R/helpers_sidebar_user_display.R` dosyasına taşındı. Modül; UI kabuğu (`mb_sidebar_user_panel_ui`), logout olayı (`mb_sidebar_handle_logout_event`) ve server render (`mb_sidebar_user_panel_server`) sorumluluklarına odaklı kaldı. Üretilen tag ağacı, sınıf adları, logout onclick JS'i ve iskelet davranışı bayt-denk korunur.

### Değişen dosyalar
**Kaynak**
- `R/helpers_sidebar_user_display.R` (yeni, 285 satır / 9 fonksiyon) — altı saf görünüm yardımcısı, roxygen açıklamalarıyla birlikte birebir taşındı.
- `R/module_sidebar_user_panel.R` — taşınan tanımlar kaldırıldı; başlığa yeni sahiplik notu eklendi. **581 → 316 satır / 24 → 15 fonksiyon.**
- `R/config_source_manifest.R` — `module_identity_startup` bölümüne helper, modülden hemen önce eklendi (10 → 11 dosya).

**Test**
- `tests/testthat/test-sidebar-user-display-split-contract.R` (yeni, 32 assertion) — helper varlığı/yüzeyi, manifest sırası (helper → modül), taşınan tanımların modüle geri dönmemesi, modülün orkestrasyon sorumluluklarını korunması, helper'ın Shiny-bağsız kalması ve davranış sözleşmeleri (Türkçe baş harf, Departman sırası, Mudurluk reddi, placeholder avatar reddi).
- `tests/testthat/test-sidebar-user-panel-behavior.R` — bootstrap'e helper source eklendi (12 assertion değişmeden geçer).
- `tests/testthat/test-sidebar-departman-contract.R` — izole yükleyici helper'ı da source eder; `pick("Departman")` statik taraması yeni sahibe (helper dosyası) yönlendirildi; Mudurluk negatif taraması her İKİ dosyada da korunur (16 assertion).
- `tests/testthat/test-sidebar-theme-sync-contract.R` — tema butonu attribute taraması yeni sahibe yönlendirildi (19 assertion).
- `tests/testthat/test-source-manifest-sections-contract.R` — `module_identity_startup` n 10→11, toplam 257→258.
- `tests/testthat/test-maintainability-ratchet.R` — yeni dosya-özel bütçeler: modül 360L/17F, helper 320L/11F (24-fonksiyon tavanına geri tırmanma kilitlendi).

**Dokümantasyon**
- `CLAUDE.md` — sidebar ownership satırı iki dosyalı yapıya güncellendi; korunan test listesine split sözleşmesi eklendi.
- `docs/technical-reference.md` — sidebar notuna saf yardımcı sınırı eklendi.
- `docs/refactor-log.md` — bu giriş.

### Önce / sonra karmaşıklık notları
- Önce: tek dosyada saf karar + Shiny orkestrasyon karışımı; dosya 24-fonksiyon küresel tavanında; Departman/tema sözleşmeleri yalnızca modül-dosyası statik taramasıyla korunuyordu.
- Sonra: saf yardımcılar Shiny olmadan source edilip test edilebilir; modül 15 fonksiyona indi; her iki dosya dosya-özel bütçeyle kilitli. Küresel 24-fonksiyon tavanı İKİ başka dosya (`helpers_file_manager_runtime.R`, `helpers_health_formatters.R`) tarafından tutulduğu için küresel değer BİLEREK sıkılaştırılmadı (dürüst sınır: bu oturum yalnızca sidebar'ı tavandan indirir).

### Korunan davranış sözleşmeleri
- Üretilen HTML/tag ağacı, sınıf adları (`mb-sidebar-*`, `theme-switch-*`), `data-mergen-theme-toggle` attribute'u, logout onclick JS'i ve `mergen_sidebar_logout` Shiny olayı birebir aynı.
- Departman seçim sırası `Departman → departman → department`; `Mudurluk` görünür alan olarak ASLA seçilmez (statik + davranışsal olarak iki dosyada da doğrulanır).
- İskelet/instant-render sözleşmesi: `mb-sidebar-user-skeleton`, `mb-sidebar-controls-skeleton`, slot-output sınıfları ve `mb_sidebar_controls_row(show_logout = FALSE)` çağrısı modülde kaldı (test anchorsları değişmedi).
- Görünür sürüm tek kaynağı `get_app_version_label()` modülde; tema senkronizasyonu, SSO auth-ready yeniden render ve `suspendWhenHidden = FALSE` davranışı dokunulmadı.

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- Odak testler tek tek geçti (0 FAIL / 0 WARN / 0 SKIP): yeni split sözleşmesi (32), sidebar davranış (12), sidebar server davranış (20), departman (16), tema-sync (19), instant-render (11), version-single-source (11), logout-url (33), source manifest (165), sections (150), global manifest (12), maintainability ratchet (168), network boundary (2), secret leak (8), production contracts (21), e2e boot/welcome (29), UX guardrails (28).
- İlk tam koşu, taşınan tanımlara modül dosyasında bakan iki ek statik sözleşmeyi yakaladı (`test-logout-url-contract.R` çıkış-butonu taraması ve `test-sidebar-user-panel-server-behavior.R` izole source); her ikisi yeni sahibe yönlendirildi/bootstrap'e helper eklendi — davranış sözleşmeleri zayıflatılmadı.
- `bash tools/ai_validate.sh full --boot-smoke` (düzeltme sonrası) → geçti; **tam strict testthat suite geçti**, Shiny boot smoke geçti, `failed_steps: 0`, `skipped_steps: 0` (browser UX smoke container'da tarayıcı olmadığından bloklamayan SKIP). Artifact: `artifacts/ai-validation/20260610-031858/summary.json`.
- `Rscript tests/scripts/maintainability_report.R` → skor 100/100; modül 316/15, helper 285/9.
- Tüm komutlar `LANG=C.UTF-8 LC_ALL=C.UTF-8` ile çalıştırıldı.

### Manuel QA (kullanıcı/VM tarafı)
- Uygulamayı normal Windows VM launcher ile başlatın; sol menü altındaki kullanıcı panelinin İLK renderda iskeletle birlikte geldiğini doğrulayın.
- SSO girişi sonrası ad/avatar ve Departman değerinin (MB_Users) doğru göründüğünü; Türkçe karakterli adların baş harflerinin bozulmadığını doğrulayın.
- Tema düğmesine tıklayın: koyu/açık geçişin çalıştığını ve etiketin güncellendiğini doğrulayın; sidebar yeniden render sonrası düğmenin çalışmaya devam ettiğini kontrol edin.
- `MERGEN_LOGOUT_URL` tanımlıysa çıkış butonunun göründüğünü, tıklayınca konsola logout logunun düştüğünü ve tarayıcının hedef URL'ye gittiğini doğrulayın.
- Sürüm satırının doğru sürümü gösterdiğini kontrol edin.

### Bilinen riskler / atlanan doğrulamalar
- Küresel 24-fonksiyon ratchet değeri sıkılaştırılMAdı; tavanı hâlâ `helpers_file_manager_runtime.R` ve `helpers_health_formatters.R` tutuyor (her ikisi de belgelenmiş yoğun-tasarım dosyaları; ayrı oturum kararı gerektirir).
- Windows VM launcher ve gerçek tarayıcı/SSO doğrulaması bu cloud oturumunda çalıştırılmadı; sidebar SSO yeniden render davranışı için kullanıcı tarafı QA gereklidir.

---

## 2026-06-09 — config_api.R baş boşluğu: Derin Düşünme kayıt konsolidasyonu + API anahtarı kripto katmanı ayrımı

### Seçilen iz(ler)
- **Track E — Duplicate mechanism consolidation**: `config_api.R` içinde İKİ ayrı source-time blok olarak yaşayan Derin Düşünme yetenek/endpoint kayıt mekanizması tek saf yardımcıda birleştirildi (`R/helpers_deep_thinking_model_capabilities.R`).
- **Track B/A — Cohesive boundary extraction**: kullanıcı API anahtarı şifreli saklama katmanı (~152 satır) `R/helpers_api_key_crypto.R` dosyasına taşındı.
- Tamamlayıcı cerrahi düzeltme: bir önceki oturumda "bilinen risk" olarak belgelenen `decode_stream_delta_payload()` skaler dönüş ucu kapatıldı.

### Özet ve gerekçe
`R/config_api.R` repodaki EN sıkışık dosyaydı: 699 satır / 700 satırlık dosya-özel ratchet bütçesi — yani 1 satır boşluk. Her yeni model, env değişkeni veya yetenek alanı bu dosyaya dokunmak zorunda olduğundan, ilk masum değişiklik plansız bir refactor'ü başka birinin görevine zorlamış olacaktı.

İki yapısal sorun çözüldü: (1) Derin Düşünme model kayıt mantığı dosyada iki ayrı blokta yaşıyordu — biri tabloda olmayan modele şablon + endpoint ekleyen erken blok, diğeri dosya sonunda `modifyList` ile eksik alanları tamamlayan ikinci blok. İki mekanizmanın bileşimi belgesizdi ve gelecekte tek tarafın değiştirilmesi sessiz davranış kayması üretirdi. Mekanizma, vision işaretleme deseniyle birebir aynı şekilde (`config_api.R`'den ÖNCE yüklenen saf helper + guard'lı çağrı) tek sahibe indirildi; birleşik davranışın eski iki-blok bileşimiyle **birebir aynı** olduğu hem test içi denklik fixture'larıyla hem de oturum içi git-HEAD diferansiyel karşılaştırmasıyla kanıtlandı (4 env senaryosunda `identical(api_config_eski, api_config_yeni) == TRUE`: varsayılan, bilinmeyen deep modeller, vision+deep birlikte, boş deep env). (2) Anahtar şifreleme/saklama katmanı (API_KEYS_DIR, hash, AES-GCM/CBC, save/load/exists/verify) yapılandırma dosyasının içinde yaşıyordu; kendi başına tutarlı bir sorumluluk olarak ayrı dosyaya taşındı (kod birebir, davranış değişikliği yok).

### Değişen dosyalar
**Kaynak**
- `R/helpers_deep_thinking_model_capabilities.R` (yeni, 113 satır) — `collect_deep_thinking_model_ids()`, `apply_deep_thinking_model_capabilities()`; Shiny/DB/ağ/dosya yan etkisi yok.
- `R/helpers_api_key_crypto.R` (yeni, 167 satır) — kripto/saklama katmanı `config_api.R`'den birebir taşındı; NUL-tuz regresyon guard'ı, UTF-8 gidiş-dönüş ve atomik JSON yazımı korunur.
- `R/config_api.R` — iki Derin Düşünme bloğu guard'lı tek helper çağrısıyla değiştirildi; kripto bloğu kaldırıldı (yerinde yönlendirme yorumu). **699 → 468 satır / 12 → 2 fonksiyon (rapor metriği).**
- `R/helpers_llm_stream_io.R` — `decode_stream_delta_payload()` artık her girişte skaler karakter döndürür; bozuk satırdan gelen `[]`/NA alan şekilleri `if()` içinde NA üretemez. Geçerli b64/düz metin davranışı değişmedi.
- `R/config_source_manifest.R` — `config_api_model_keys` bölümü: deep helper vision sonrası/config_api öncesi, kripto helper tool-runtime sonrası/api_key_identity öncesi eklendi (7 → 9 dosya).

**Test**
- `tests/testthat/test-deep-thinking-model-capabilities-behavior.R` (yeni, 28 assertion) — kimlik toplama, bilinmeyen model varsayılanları, açık tanımın kazanması, endpoint onarımı, boş/geçersiz girişler ve eski iki-blok mekanizmasına karşı 4 fixture'lı birebir denklik.
- `tests/testthat/test-config-api-split-contract.R` (yeni, 36 assertion) — iki helper'ın varlığı/yüzeyi, manifest sırası (vision → deep → config_api → crypto → identity), guard'lı delegasyon, taşınan mantığın `config_api.R`'ye geri dönmemesi, deep helper'ın yan-etkisizliği.
- `tests/testthat/test-config-api-key-crypto-behavior.R` — bootstrap artık `config_api.R` yerine doğrudan `helpers_api_key_crypto.R` source eder (32 assertion değişmeden geçer).
- `tests/testthat/test-api-model-config-refactor-contract.R` ve `tests/testthat/test-llm-reasoning-request-overrides.R` — izole `config_api.R` source bağlamlarına deep helper ön-yüklemesi eklendi (belgelenmiş izole-test deseni).
- `tests/testthat/test-llm-stream-io-contract.R` — decode skaler dönüş regresyon testleri eklendi (bozuk `[]`/NA şekilleri, NULL/alansız payload, Türkçe b64 round-trip, b64 önceliği).
- `tests/testthat/test-source-manifest-sections-contract.R` — `config_api_model_keys` n 7→9, toplam 255→257.
- `tests/testthat/test-maintainability-ratchet.R` — `R/config_api.R` bütçesi 700L/14F → **520L/6F** sıkılaştırıldı; iki yeni helper için 160L/4F ve 220L/12F bütçeleri eklendi.

**Dokümantasyon**
- `CLAUDE.md` — "API model configuration contract" bölümü yeni kaynak sırası ve iki helper sorumluluğuyla güncellendi; vision bölümündeki 700-satır bütçe referansı 520/6 olarak düzeltildi; Group 2 yükleme listesi güncellendi.
- `docs/architecture-map.md` — model yeteneği ve API anahtarı ownership satırları yeni dosyaları gösterir.
- `docs/technical-reference.md` — Derin Düşünme kayıt tek-sahip notu, kripto taşıma notu ve decode skaler garanti notu eklendi.
- `docs/refactor-log.md` — bu giriş.

### Önce / sonra karmaşıklık notları
- Önce: `config_api.R` 699/700 satır (1 satır boşluk); Derin Düşünme kaydı iki kopya mekanizmada; kripto katmanı yapılandırma dosyasına gömülü; decode ucu belgelenmiş ama açık.
- Sonra: `config_api.R` 468 satır / 2 fonksiyon (≈%33 küçülme, yeni bütçeyle ~52 satır gerçek boşluk + bütçe kilidi); kayıt mekanizması tek saf sahip + 28 deterministik assertion; kripto katmanı kendi dosyasında aynı davranış testleriyle; decode her zaman skaler.

### Korunan davranış sözleşmeleri
- `api_config` nesnesi 4 env senaryosunda git-HEAD sürümüyle `identical()` — model yetenekleri, endpoint haritası, tool-mode yapılandırması, TTS/STT yapılandırması bayt-denk.
- Kripto fonksiyon adları/davranışı değişmedi; çağıranlar (`R/module_api_key.R`, `R/module_settings_yapilandirma.R`) dokunulmadı. NUL-tuz guard'ı, AES-GCM→CBC düşüşü, UTF-8 anahtar gidiş-dönüşü, atomik yazım aynen.
- `validate_api_key()` orkestrasyonu, `user_config`, `SERVICE_DESK`, endpoint/env okuma config_api.R'de kaldı.
- Streaming: geçerli b64/düz metin decode çıktıları birebir aynı; üretim yazıcısının boş metin yazmama guard'ı zaten koruyordu, okuyucu artık ek olarak sağlam.
- DB, SSO, dosya yaşam döngüsü, frontend varlıkları, Shiny ID'leri ve UX'e dokunulmadı.

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- Git-HEAD diferansiyeli (oturum içi geçici script): eski `config_api.R` (HEAD) + vision helper ile yeni zincir (vision + deep helper + yeni config_api) 4 env senaryosunda `identical(api_config) == TRUE`.
- Odak testler tek tek geçti (0 FAIL / 0 WARN / 0 SKIP): yeni davranış (28), yeni split sözleşmesi (36), kripto davranış (32), api-model-config refactor (35), llm-reasoning overrides (14), stream-io (19), source manifest (165), sections (150), global manifest (12), maintainability ratchet (162), deep-thinking model resolution (16), runtime model resolution (24), api-key effective/identity resolution (35+37), streaming poll lifecycle (67+25), utf8 stream decoder (30), secret leak (8), network boundary (2), production contracts (21), production env policy (8).
- `bash tools/ai_validate.sh full --boot-smoke` → geçti; **tam strict testthat suite dahil**, `failed_steps: 0`, `skipped_steps: 0` (browser UX smoke bu container'da tarayıcı olmadığından bloklamayan SKIP). Artifact yolu aşağıdaki commit mesajında ve `artifacts/ai-validation/` altında.
- `Rscript tests/scripts/maintainability_report.R` → skor 100/100; `config_api.R` 468/2.
- Tüm komutlar `LANG=C.UTF-8 LC_ALL=C.UTF-8` ile çalıştırıldı (container'ın C-locale varsayılanı, koddan bağımsız ortam kısıtı).

### Manuel QA (kullanıcı/VM tarafı)
- Uygulamayı normal Windows VM launcher ile başlatın; başlangıçta kırmızı hata olmadığını ve modellerin Model Değiştir/Yapılandırma listelerinde göründüğünü doğrulayın.
- Excel Analizi ve Kodlama Desteği araçlarında Derin Düşünme düğmesini düşük/yüksek seviyelerde açın; Düşünce Akışı rozetinin beklenen deep modeli gösterdiğini ve yanıtın aktığını doğrulayın.
- Yapılandırma → kişisel API anahtarı kaydedin (sahte/test anahtarı değil, gerçek akışınız neyse o); kaydet → doğrula → temizle akışının çalıştığını, Türkçe karakter içeren bir anahtar değerinin kaydet/yükle sonrası bozulmadığını doğrulayın.
- `api_keys/<kullanıcı>_api_key` dosyasının oluştuğunu ve düz metin anahtar içermediğini (şifreli JSON) doğrulayın.
- Var olan kayıtlı anahtarın (bu değişiklikten önce kaydedilmiş) yeniden yüklenebildiğini doğrulayın (format değişmedi; geriye dönük uyum beklenir).
- Normal Türkçe sohbet + streaming + Durdur akışını bir kez doğrulayın (config_api zinciri her istekte kullanılır).

### Bilinen riskler / atlanan doğrulamalar
- `helpers_api_key_crypto.R` kaynak anında `getwd()/api_keys` klasörünü oluşturur (config_api.R'deki davranışın birebir taşınması). Manifest yük sırası içinde `getwd()` uygulama köküdür; davranış değişmedi.
- Windows VM launcher, gerçek tarayıcı smoke, VM/SSO/gerçek DB preflight ve SQL Server Türkçe encoding preflight bu cloud oturumunda çalıştırılmadı; kullanıcı tarafı manuel QA gereklidir.
- `.Renviron`'daki gerçek üretim deep model kimlikleri cloud'da görünmez; VM'de Derin Düşünme rozet/akış kontrolü önerilir (yukarıdaki QA maddesi).

---

## 2026-06-09 — True streaming yoklama döngüsü kararlarının saf yardımcıya çıkarılması

### Seçilen iz(ler)
- **Track B — Complex runtime kodundan saf yardımcı çıkarımı** (`R/server_handler_true_streaming.R` → `R/helpers_streaming_poll_lifecycle.R`).
- Tamamlayıcı: var olan streaming yaşam döngüsü desenini (`R/helpers_streaming_abort_lifecycle.R` / `mergen_stream_abort_cleanup_plan()`) yoklama tarafına genişletir.

### Özet ve gerekçe
`handle_true_streaming_mode()` içindeki yoklama (poll) observer'ı; akış JSONL satırlarının delta / akıl yürütme / debug olarak sınıflandırılmasını, worker dönüşünde gelen reasoning metninin canlı panelle uzlaştırılmasını (tam metin mi, eksik kuyruk mu, hiçbir şey mi gönderileceği kararı), yoklama aralığı normalizasyonunu ve ertelenen sohbet kalıcılaştırma gecikmesi kararını Shiny observer gövdesine gömülü taşıyordu. Bu kararlar kullanıcıya en görünür regresyon yüzeyidir (akış metni, Düşünce Akışı paneli, `MB_Messages.ReasoningContent` kalıcılığı) ama hiçbiri Shiny/DB/LLM başlatmadan test edilemiyordu.

Dört saf yardımcı `R/helpers_streaming_poll_lifecycle.R` dosyasına çıkarıldı: `mergen_stream_classify_poll_lines()` (satır sınıflandırma; bozuk/yarım satırlar sessizce atlanır, sıra korunur), `mergen_stream_reasoning_recovery_plan()` (none / replace_full / append_suffix kararı; reasoning'in yalnızca final chunk'ta geldiği uçlarda DB'de ReasoningContent'in NULL kalmasını engelleyen yolun saf çekirdeği), `mergen_stream_poll_interval_ms()` ve `mergen_stream_persist_delay()`. Handler aynı custom message payload'larını (`streamingReasoningDelta`, `streamingDelta`, `streamingUpdate`) aynı sırayla gönderen ince bir orkestratöre dönüştü; tüm statik sözleşme çapaları (request-id, finalize/cleanup, reasoning alanları) yerinde kaldı.

### Değişen dosyalar
**Kaynak**
- `R/helpers_streaming_poll_lifecycle.R` (yeni, ~203 satır) — dört saf karar yardımcısı; Shiny/DB/dosya/LLM yan etkisi yok.
- `R/server_handler_true_streaming.R` — inline sınıflandırma döngüsü, reasoning geri kazanım bloğu, poll aralığı ve persist gecikmesi karar satırları helper çağrılarıyla değiştirildi. **690 → 647 satır.**
- `R/config_source_manifest.R` — yeni helper `chat_send_message_runtime` bölümüne `R/helpers_streaming_abort_lifecycle.R` sonrasına eklendi; bölüm yorumu güncellendi.

**Test**
- `tests/testthat/test-streaming-poll-lifecycle-behavior.R` (yeni) — 67 assertion: satır sınıflandırma (bozuk JSON/boş delta/bilinmeyen tip atlanır, sıra korunur, gerçek `decode_stream_delta_payload` ile Türkçe + emoji base64 round-trip), reasoning geri kazanım planının tüm dalları (UTF-8 çok baytlı önek/kuyruk sınırı dahil), yoklama aralığı ve persist gecikmesi kararları.
- `tests/testthat/test-streaming-poll-lifecycle-contract.R` (yeni) — 25 assertion: helper dosyası varlığı ve fonksiyon yüzeyi, manifest sırası (abort → poll → handler), handler delegasyonu, inline mantığın geri dönmemesi, helper'ın yan-etkisiz kalması.
- `tests/testthat/test-source-manifest-sections-contract.R` — `chat_send_message_runtime` bölüm sayısı 8→9, toplam kaynak sayısı 254→255 güncellendi.

**Dokümantasyon**
- `CLAUDE.md` — UX sözleşmeleri bölümüne poll-loop delegasyon kuralı eklendi; kaynak manifest sözleşmesindeki yükleme sırası notu iki streaming helper'ı kapsayacak şekilde genişletildi.
- `docs/architecture-map.md` — LLM/model entegrasyonu ownership satırı ve `chat_send_message_runtime` bölüm satırı `R/helpers_streaming_*` ailesini gösterir.
- `docs/technical-reference.md` — streaming notlarına yoklama döngüsü saf yardımcı sınırı eklendi.
- `docs/refactor-log.md` — bu giriş.

### Önce / sonra karmaşıklık notları
- Önce: satır sınıflandırma + accumulate + ilk-delta logu + custom message gönderimi tek observer gövdesinde iç içeydi; reasoning geri kazanım kararı yalnızca canlı SSE akışıyla uçtan uca tetiklenebiliyordu.
- Sonra: karar mantığı (hangi satır hangi kanala, hangi reasoning parçası gönderilecek, hangi aralık/gecikme) saf fonksiyonlarda; observer yalnızca state yazma ve mesaj gönderme yan etkilerini taşır. 92 yeni deterministik assertion bu kararları offline karakterize eder.
- Maintainability skoru 100/100 korunur; handler 690→647 satıra indi, yeni helper bütçe eşiklerinin çok altında.

### Korunan davranış sözleşmeleri
- Custom message adları, payload alanları ve gönderim sırası değişmedi: reasoning batch'i delta batch'inden önce gönderilir; `started` bayrağı, `requestId` ve mesaj id alanları birebir aynı.
- `test-true-streaming-reset-ui-contract.R`, `test-e2e-premium-reasoning-ui-regression.R`, `test-e2e-streaming-client-request-id-regression.R`, `test-sse-worker-export-contract.R` çapalarının tamamı yerinde (hepsi bu oturumda yeşil).
- Stop/cancel davranışı, `mergen_stream_abort_cleanup_plan()` delegasyonu, stop dosyası üretimi ve `reset_chat_state_fn()` çağrı yolu değişmedi.
- Türkçe/emoji akış metni davranışı korunur: sınıflandırma `decode_stream_delta_payload` (base64 + UTF-8) üzerinden aynı çözücüyle çalışır; davranış testi Türkçe + emoji round-trip'i kanıtlar.
- DB şeması, SSO, dosya yaşam döngüsü, frontend asset/source manifest yükleme davranışı değişmedi (manifest yalnızca yeni helper satırı kazandı).

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- `Rscript -e "testthat::test_file('tests/testthat/test-streaming-poll-lifecycle-behavior.R')"` → geçti (67 PASS / 0 FAIL / 0 WARN / 0 SKIP).
- `Rscript -e "testthat::test_file('tests/testthat/test-streaming-poll-lifecycle-contract.R')"` → geçti (25 PASS).
- Korunan streaming/manifest sözleşmeleri tek tek çalıştırıldı ve geçti: `test-true-streaming-reset-ui-contract.R` (6), `test-e2e-premium-reasoning-ui-regression.R` (40), `test-e2e-streaming-client-request-id-regression.R` (5), `test-sse-worker-export-contract.R` (3), `test-source-manifest-contract.R` (165), `test-source-manifest-sections-contract.R` (150), `test-global-source-manifest-contract.R` (12), `test-send-message-request-lifecycle-contract.R` (42), `test-streaming-abort-lifecycle-smoke.R` (16), `test-e2e-quick-actions-streaming-regression.R` (75), `test-maintainability-ratchet.R` (156), `test-production-contracts.R` (21); tümünde 0 FAIL / 0 WARN.
- Diferansiyel parite kontrolleri (oturum içi geçici script, repoya eklenmedi): eski inline sınıflandırma algoritması ile `mergen_stream_classify_poll_lines()` 300 rastgele fixture denemesinde (Türkçe, emoji, satır sonu, bozuk JSON, boş metin, bilinmeyen tip, base64/düz karışık) 0 uyumsuzluk; eski inline reasoning geri kazanım dalları ile `mergen_stream_reasoning_recovery_plan()` 84 kombinasyonda 0 uyumsuzluk.
- `Rscript tests/scripts/maintainability_report.R` → skor 100/100, refactor adayı yok (260→261 dosya).
- `source("tests/scripts/parse_sanity_check.R")` → OK (732 dosya parse edildi).
- `bash tools/ai_validate.sh quick` → geçti; `failed_steps: 0`, `skipped_steps: 0`. Artifact: `artifacts/ai-validation/20260609-181259/summary.json`.
- `bash tools/ai_validate.sh full --boot-smoke` → geçti; environment OK, parse sanity OK, app source smoke OK, **tam strict testthat suite geçti (132.7 sn)**, Shiny boot smoke geçti; browser UX smoke bu container'da tarayıcı ikilisi olmadığı için bloklamayan SKIP (beklenen davranış). `failed_steps: 0`, `skipped_steps: 0`, `full_validation_status: "passed"`. Artifact: `artifacts/ai-validation/20260609-181405/summary.json`.
- Not: bu cloud container'da R oturumu varsayılan olarak "C" locale ile başlıyor; tüm komutlar `LANG=C.UTF-8 LC_ALL=C.UTF-8` ile çalıştırıldı (önceden var olan ortam kısıtı, kod değişikliğiyle ilgisiz; önceki oturumda görülen unrelated tam-suite hataları bu locale ile yeniden üretilmedi).

### Manuel QA (kullanıcı/VM tarafı)
- Uygulamayı normal Windows VM launcher ile başlatın; kırmızı hata ve yeni browser console hatası olmadığını doğrulayın.
- Ana Söyleşi'de `ç ğ ı İ ö ş ü` içeren basit bir Türkçe mesaj gönderin; akış metninin doğru render edildiğini ve geçmişe doğru kaydedildiğini doğrulayın.
- Uzun bir yanıt başlatıp Durdur'a basın; gönder düğmesinin normale döndüğünü, typing/streaming durumunun takılı kalmadığını ve sonrasında yeni mesajın çalıştığını doğrulayın.
- Düşünme destekli bir modelle (Düşünüyorum=TRUE) soru sorun; Düşünce Akışı panelinin canlı aktığını, yanıt bitince panelin arşiv olarak kaldığını ve kayıtlı sohbeti yeniden yüklediğinizde reasoning arşivinin göründüğünü (SSMS'te `MB_Messages.ReasoningContent` dolu) doğrulayın.
- Reasoning'i yalnızca yanıt sonunda üreten bir uç durum varsa (kısa yanıt + uzun düşünme), panelin yine dolduğunu doğrulayın (geri kazanım yolu).
- Hızlı profil yollarını (Kodlama Desteği hızlı akışı) bir kez deneyin; ilk parçaların gecikmeden aktığını doğrulayın.
- Saved chat reload sonrası eski TTS otomatik oynatma olmadığını teyit edin.

### Bilinen riskler / atlanan doğrulamalar
- Davranış birebir korunacak şekilde tasarlandı; tek bilinçli mikro fark, aynı poll tick'i içinde `stream_debug` log satırlarının artık delta loglarından önce yazılması (yalnızca tanılama log sırası; UI/DB/payload etkisi yok).
- Windows VM launcher, gerçek tarayıcı smoke (`UX_SMOKE_DONE:PASS`), VM/SSO/gerçek DB preflight, SQL Server Türkçe encoding preflight ve gerçek SSE uç noktasıyla canlı akış bu cloud/container oturumunda çalıştırılmadı (summary.json bu sınırları `not_performed_by_ai_validate` olarak işaretler); kullanıcı tarafı manuel QA gereklidir.
- `decode_stream_delta_payload()` içinde önceden var olan bir uç durum gözlemlendi (boş metnin base64'ü `text_b64` alanında `[]`'e dönüşürse `if` koşulu NA üretebilir); üretim yazıcısı `create_stream_line_appender()` boş metni hiç yazmadığı için bu uç gerçek akışta oluşmaz, eski ve yeni yol aynı çözücüyü aynı şekilde çağırır. Bilerek bu oturumda dokunulmadı (cerrahi kapsam); ileride ayrı küçük bir görev olarak ele alınabilir.

---

## 2026-06-09 — Dosya Yönetimi görünen dosya adı normalizasyon sınırı

### Seçilen iz(ler)
- **Track B — Complex runtime kodundan saf yardımcı çıkarımı** (`R/helpers_file_manager_state_runtime.R` yükleme yolu → `R/helpers_file_manager_table.R::fm_normalize_uploaded_file_info()`).
- **Track E — Duplicate mechanism consolidation** (upload state ve tablo satırı görünen ad temizliği artık aynı kanonik helper zincirini kullanır).

### Özet ve gerekçe
Dosya Yönetimi içinde yükleme state yolu, storage-prefix taşıyan kalıcı dosya adlarını elle `recover_display_name_from_storage_name()` ile temizliyordu; tablo satırı yolu ise `fm_clean_file_display_name()` üzerinden benzer fallback zinciri taşıyordu. Bu iki mekanizma aynı görünür davranışı hedeflediği halde farklı noktalarda tutulduğu için Türkçe dosya adı, storage-prefix ve `display` metadata önceliği bakımında gizli coupling oluşturuyordu.

`fm_normalize_uploaded_file_info()` adlı saf yardımcı eklendi. Yardımcı, mümkün olduğunda kanonik `normalize_file_display_name()` davranışına delege eder; `display` metadata önceliğini, storage-prefix temizliğini ve UTF-8/Türkçe karakter onarımını tek sınırda toplar. `fm_clean_file_display_name()` geriye uyumlu wrapper olarak korundu ve aynı yardımcıya bağlandı. `process_uploaded_file()` artık kendi dosya adı temizleme bloğunu taşımıyor; normalize edilmiş `file_info` ve `file_name` değerlerini saf yardımcıdan alıyor.

### Değişen dosyalar
**Kaynak**
- `R/helpers_file_manager_table.R` — `fm_normalize_uploaded_file_info()` eklendi; `fm_clean_file_display_name()` uyumluluk wrapper'ı aynı helper'a delege edecek şekilde sadeleştirildi.
- `R/helpers_file_manager_state_runtime.R` — upload işleme yolundaki yerel storage-prefix temizleme bloğu kaldırıldı ve yeni saf helper çağrısına indirildi.

**Test**
- `tests/testthat/test-file-manager-table-contract.R` — dosya deposu normalizasyon helper'ı test ortamına yüklendi; Türkçe storage-prefix temizliği ve `display` metadata önceliği için deterministik saf helper testleri eklendi.

**Dokümantasyon**
- `docs/architecture-map.md` — Dosya Yönetimi ownership satırı, görünen dosya adı sınırını ve kanonik helper delegasyonunu açıklar.
- `docs/technical-reference.md` — Dosya Yönetimi runtime notlarına upload/tablo görünen ad normalizasyon sınırı eklendi.
- `docs/refactor-log.md` — bu giriş.

### Önce / sonra karmaşıklık notları
- Önce: upload state yolu ve tablo yolu benzer görünen ad temizleme kararlarını ayrı bloklarda taşıyordu.
- Sonra: storage-prefix temizliği, `display` metadata önceliği ve UTF-8/Türkçe onarım tek saf yardımcıyla karakterize edildi; wrapper adı korundu.
- Runtime modül davranışı değişmeden, side-effect içeren `process_uploaded_file()` dosya adı kararından arındırıldı ve daha ince bir orkestratöre dönüştü.

### Korunan davranış sözleşmeleri
- Dosya Yönetimi tablo kolonları, HTML class/selector değerleri, Shiny download/attach ID kalıpları değişmedi.
- Storage-prefix kullanıcıya gösterilmez; `İhale_çalışması.pdf` gibi Türkçe karakterli dosya adları korunur.
- Explicit `display` metadata, storage dosya adından öncelikli kalır.
- File upload/list/preview/analyze, Excel MCP yolu, DB schema, SSO ve frontend asset/source manifest sırası değiştirilmedi.

### Eklenen / güncellenen testler
- `test-file-manager-table-contract.R` içindeki yeni testler:
  - `fm_normalize_uploaded_file_info()` storage-prefix içeren Türkçe dosya adını okunabilir kullanıcı adına indirger.
  - `fm_clean_file_display_name()` compatibility wrapper'ı aynı sonucu üretir.
  - Explicit `display` metadata storage dosya adına üstün gelir.

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- `Rscript tests/scripts/maintainability_report.R` → geçti; skor 100/100, refactor adayı eşiği ihlali yok.
- `Rscript -e "testthat::test_file('tests/testthat/test-file-manager-table-contract.R')"` → geçti.
- `Rscript -e "testthat::test_file('tests/testthat/test-file-lifecycle-hardening-contract.R'); testthat::test_file('tests/testthat/test-file-manager-table-contract.R'); testthat::test_file('tests/testthat/test-file-manager-state-runtime-contract.R')"` → geçti.
- `bash tools/ai_validate.sh quick` → geçti; `failed_steps: 0`, `skipped_steps: 0`.
- `Rscript tests/testthat.R` → başarısız; bu oturumda unrelated environment/repo fixture failures görüldü (`test-claude-code-security-policy-contract.R`, `.Renviron` logout URL fixture, eksik vendored UI assets, upload-validator fixture path). Odak Dosya Yönetimi testleri aynı oturumda geçti.
- `bash tools/ai_validate.sh full --boot-smoke` → başarısız; full suite adımında yukarıdaki unrelated testthat failure sınıfı nedeniyle `failed_steps: 1`. Boot-smoke adımına geçilemedi. Artifact: `artifacts/ai-validation/20260609-143057/summary.json`.

### Manuel QA (kullanıcı/VM tarafı)
- Uygulamayı normal Windows VM launcher ile başlatın; kırmızı hata ve yeni browser console hatası olmadığını doğrulayın.
- Dosya Yönetimi sekmesine gidin.
- `İhale_çalışması_çğıİöşü.txt` gibi Türkçe karakterli bir TXT yükleyin; listede ve preview/attach davranışında okunabilir kaldığını doğrulayın.
- CSV/TXT içinde Türkçe karakterler yükleyip önizleme ve bağlama ekleme davranışını doğrulayın.
- Aynı isimli dosya tekrar yükleme davranışının değişmediğini kontrol edin.
- Excel dosyası yükleyin; yanlış özetleme yoluna girmediğini ve amaçlanan Excel/MCP analiz yolu için kullanılabilir kaldığını kontrol edin.
- Kaydedilmiş söyleşiye dosya referansı ekleyip reload/history sonrasında görünen adın ve Türkçe karakterlerin korunduğunu doğrulayın.

### Bilinen riskler / atlanan doğrulamalar
- Bu refactor dosya adı kararını saf helper'a taşıdı; DB schema, frontend varlıkları, SSO ve Excel okuyucu davranışı bilerek değiştirilmedi.
- Windows VM launcher ve gerçek tarayıcı smoke bu cloud/container oturumunda çalıştırılmadı; kullanıcı tarafı manuel QA gereklidir.

---


## 2026-06-09 — Proje/Kaynak Analizi sezgisel sorgu skorlamasının saf yardımcıya çıkarılması

### Seçilen iz(ler)
- **Track B — Complex runtime kodundan saf yardımcı çıkarımı** (`R/module_proje_kaynak_analizi.R` → `R/helpers_pk_analysis_query_selection.R`).
- Tamamlayıcı: var olan PK helper bölme desenini (core/filters/security-summary) sürdürür.

### Özet ve gerekçe
`select_smart_query()` içindeki "Akıllı Sorgu Seçici" sezgisel skorlama mantığı (isim alt-dize +50, isim kelime ×10, açıklama kelime ×2, yedi Türkçe alan anahtar kelime bonusu +8, max'a göre %100 normalizasyon, `THRESHOLD_RAW=2`/`THRESHOLD_PCT=30` eşiği) limite yakın bir modülün (717 satır) içinde, AI çağrısı + `cat` + oturum yan etkileriyle iç içe gömülüydü ve **hiç testi yoktu**. Bu, ileride bir bakımcının ağırlıkları/anahtar kelimeleri değiştirmesi durumunda sessiz regresyon riski taşıyan, gerçek iş kuralı içeren bir karar mantığıdır.

Skorlama ve skor-tablosu raporlaması saf bir yardımcı dosyaya çıkarıldı; `select_smart_query()` orkestratör olarak modülde kaldı (AI seçimi + `find_best_query_with_ai()` çağrısı + `cat` + sonuç montajı) ve artık çıkarılan saf yardımcıları çağırıyor. Davranış birebir korunur.

### Değişen dosyalar
**Kaynak**
- `R/helpers_pk_analysis_query_selection.R` (yeni, ~140 satır) — `pk_init_query_score_table()`, `pk_score_query_relevance()`, `pk_compute_heuristic_query_scores()` ve taşınan `print_score_table()`.
- `R/module_proje_kaynak_analizi.R` — `pk_required_helpers` fallback listesine yeni helper eklendi; `select_smart_query()` skorlama bloğu helper çağrılarıyla değiştirildi; `print_score_table()` modülden kaldırıldı. **717 → 633 satır.**
- `R/config_source_manifest.R` — yeni helper `analysis_helpers` bölümüne (filters sonrası, modül öncesi) eklendi.

**Test**
- `tests/testthat/test-pk-analysis-query-selection-behavior.R` (yeni) — saf skorlama kurallarını elle hesaplanmış beklenen değerlerle karakterize eder (önceden testsizdi).
- `tests/testthat/test-pk-analysis-query-selection-refactor-contract.R` (yeni) — dosya varlığı, helper'ların açığa çıkması, kaynak sırası (filters → query_selection → module), modülün artık taşınan helper'ları içermemesi, fallback referansının korunması ve helper'ın yan-etki-hafif olması.
- `tests/testthat/test-source-manifest-sections-contract.R` — `analysis_helpers` çapası (`last`/`n` 4→5) ve toplam dosya sayısı (253→254) güncellendi.

**Dokümantasyon**
- `CLAUDE.md` — yeni "Proje/Kaynak Analizi query-selection modularization contract" bölümü; `global.R` yükleme sırası listesine helper eklendi.
- `docs/refactor-log.md` — bu giriş.

### Önce / sonra karmaşıklık notları
- `R/module_proje_kaynak_analizi.R`: 717 → 633 satır (limite-yakın dosyada ~84 satır rahatlama).
- Önceden testsiz, gömülü sezgisel skorlama → adlandırılmış, saf, deterministik test edilen üç yardımcı.
- Maintainability skoru: 100/100 (değişmedi); değerlendirilen dosya 259 → 260; en büyük dosya satırı 760 ve en yüksek fonksiyon sayısı 24 (etkilenmedi).

### Korunan davranış sözleşmeleri
- Skorlama formülü ve `all_scores` tablo yapısı birebir korunur; yedi Türkçe alan-bonus `grepl()` deseni bayt-bayt aynı (UTF-8).
- `select_smart_query()` orkestratör olarak modülde kalır; `R/helpers_deep_analysis.R` çağrısı etkilenmez.
- AI seçim dalı, eşik kararı, heuristic seçim metodu/gerekçesi ve `cat` çıktıları korunur.
- Türkçe karakter bütünlüğü ve UTF-8 korunur; mojibake yok.

### Eklenen / güncellenen testler
- Yukarıdaki iki yeni test + bölüm sözleşmesi güncellemesi.

### Gerçekten çalıştırılan doğrulamalar (bu cloud oturumunda)
- **Eşdeğerlik kanıtı (en güçlü):** geçici bir koşum aracıyla HEAD orijinal modül vs refactor edilmiş (helper + modül) `select_smart_query()` sezgisel sonuçları **72 (3 kütüphane × 24 prompt) vakada birebir aynı** (`FULL_EQUIVALENCE_OK`); ayrıca 8 vakalık baseline `EQUIVALENCE_OK`. Bu araç commit edilmedi.
- `Rscript tests/scripts/parse_sanity_check.R` → `OK: 729 dosya parse edildi.`
- `Rscript tests/scripts/maintainability_report.R` → Skor 100/100, 0 eşik ihlali.
- Odaklı testler (C.utf8 locale ile, app helper yüklemeden doğrudan source): `test-pk-analysis-query-selection-behavior.R`, `test-pk-analysis-query-selection-refactor-contract.R`, `test-source-manifest-sections-contract.R`, `test-source-manifest-contract.R`, `test-pk-analysis-maintainability-contract.R`, `test-pk-analysis-filters-refactor-contract.R`, `test-pk-analysis-core-refactor-contract.R`, `test-pk-analysis-security-summary-contract.R`, `test-maintainability-ratchet.R`, `test-global-source-manifest-contract.R`, `test-production-contracts.R` → hepsi geçti, başarısızlık yok.
- `bash tools/ai_validate.sh cloud-quick` → `failed_steps: 0`, `skipped_steps: 1`; `summary.json`: `profile_requested="cloud-quick"`, `profile_effective="quick"`, `parse sanity: OK`, `app source smoke: SKIPPED`, `focused contract tests: passed`.

### Manuel QA (kullanıcı/VM tarafı)
- Uygulamayı normal Windows VM başlatıcısıyla başlatın; kırmızı hata olmadan açıldığını doğrulayın.
- "Proje ve Kaynak Analizi" hızlı eylemini açın; Türkçe bir analiz sorusu sorun (ör. "proje bütçe durumu nedir", "aktivite gecikme süresi", "kaynak personel atama").
- Konsol/loglarda `SORGU İLGİLİLİK SKORLARI` tablosunun ve `Heuristic EN IYI ESLESME` / `Hicbir sorgu yeterli skora ulasamadi` mesajlarının eskisiyle aynı davrandığını doğrulayın.
- AI tabanlı sorgu seçiminin (gerçek LLM ile) ve heuristic'e düşüş yolunun çalıştığını doğrulayın.
- Türkçe karakterlerin (ç, ğ, ı, İ, ö, ş, ü) doğru render edildiğini doğrulayın.

### Bilinen riskler / bilinçli atlanan doğrulamalar
- Bu cloud checkout'unda tam strict suite (`tests/testthat.R`) ortam nedeniyle (locale `C`, eksik `.Renviron`/`www` varlıkları; `helper-load-app.R` app boot'u başarısız) eksiksiz tamamlanmaz. Odaklı testler bu nedenle minimum kurulumla `C.utf8` locale altında doğrudan source edilerek çalıştırıldı; sonuçlar geçerlidir.
- `cloud-quick` tam runtime/app boot, gerçek tarayıcı UX, VM/SSO/DB veya SQL Server Türkçe encoding doğrulaması DEĞİLDİR; bunlar VM tarafı gate'leridir ve bu oturumda çalıştırılmadı.
- **Tespit edilen, kapsam dışı bırakılan ön-var olan kenar durumu (refactor kaynaklı değil):** hem HEAD hem refactor, bir sorgu kaydının `name = NULL` olması durumunda `grepl(name_clean, ...)` ile aynı şekilde hata verir (`tolower(NULL)` → `character(0)`). Skorlama `%||%` ile korunmamıştır; gerçek kütüphanede isimler her zaman dolu olduğundan davranış değiştirilmedi (davranış-koruma ilkesi). İleride istenirse ayrı bir bugfix olarak ele alınabilir.

---

## 2026-06-09 — Kaynak manifestinin özellik bölümlerine ayrılması

### Seçilen iz(ler)
- **Track D — Manifest sectioning without load-order change** (`R/config_source_manifest.R`).
- Tamamlayıcı doküman tarafı: özellik sahipliği haritası (`docs/architecture-map.md`).

### Özet ve gerekçe
255+ R dosyası içeren depoda en çok okunan "içindekiler" dosyası, çalışma zamanı kaynak manifestidir. Manifest daha önce yalnızca boş satırlarla gruplanmış, etiketsiz ve düz bir liste (`source_manifest_after_future_paths`) idi; bir bakımcı "X özelliği hangi dosyalarda?" sorusunu yanıtlamak için tek tek grep yapmak zorundaydı.

Manifest artık özellik/katman ailelerine göre adlandırılmış, açıklamalı **35 bölümden** oluşan tek bir sıralı liste (`source_manifest_sections`) olarak düzenlendi. Çalışma zamanı yükleme sırası **birebir korunur**: üç kanonik nesne bu bölümlerden türetilir ve `unlist(source_manifest_sections, use.names = FALSE)` değeri eski `source_manifest_runtime_paths` ile bayt bayt aynıdır.

Bu, davranışsal olarak sıfır risk taşır (yalnızca yorumlar ve adlandırılmış bölümleme eklenir; yükleme sırası değişmez) ama onboarding için yüksek kaldıraçlıdır.

### Değişen dosyalar
**Kaynak**
- `R/config_source_manifest.R` — düz `c(...)` listesi, adlandırılmış bölüm listesi (`source_manifest_sections`) + türetme olarak yeniden yapılandırıldı. Üç kanonik nesne (`source_manifest_group_1_paths`, `source_manifest_after_future_paths`, `source_manifest_runtime_paths`) korunur ve bölümlerden türetilir.

**Test**
- `tests/testthat/test-source-manifest-sections-contract.R` (yeni) — bölüm sırasını, türetme bütünlüğünü, bölüm sınır dosyalarını (ilk/son çapaları) ve toplam dosya sayısını dondurur.

**Dokümantasyon**
- `docs/architecture-map.md` — "Özellik bölümleri (onboarding haritası)" alt bölümü eklendi (bölüm → özellik → giriş noktası tablosu).
- `CLAUDE.md` — kaynak manifesti sözleşmesi, bölümlenmiş yapıyı ve yeni testi yansıtacak şekilde cerrahi olarak güncellendi.
- `docs/refactor-log.md` (yeni) — bu günlük oluşturuldu.

### Önce / sonra karmaşıklık notları
- Önce: 283 satır, etiketsiz boş-satır grupları, tek düz `after_future` vektörü; özellik sınırları örtük.
- Sonra: 484 satır, 35 adlandırılmış özellik/katman bölümü, her bölümde kısa Türkçe açıklama; özellik sahipliği açık ve greplenebilir.
- Yükleme sırası: değişmedi (bayt bayt aynı 253 yol; doğrulandı).
- Maintainability skoru: 100/100 (değişmedi); manifest fonksiyon sayısı 0 (değişmedi); en büyük dosya satırı 760 (etkilenmedi; manifest sınırın çok altında).

### Korunan davranış sözleşmeleri
- Üç kanonik manifest nesnesi adları ve değerleri birebir korunur.
- `source_manifest_runtime_paths == c(source_manifest_group_1_paths, source_manifest_after_future_paths)` değişmez.
- `global.R` bootstrap/yükleme çağrıları değişmedi (`source_manifest_load(source_manifest_group_1_paths)` / `... after_future`).
- `R/bootstrap_source_manifest.R` doğrulaması (nesne varlığı, tekrar, eksik dosya, parse, sıra kuralları) aynen geçerli.
- Tüm yol dize literalleri dosya metninde korunduğu için metin tabanlı sözleşme testleri (logout, ui-asset, streaming-markdown vb.) etkilenmez.
- Türkçe karakter bütünlüğü ve UTF-8 korunur; mojibake yok.

### Eklenen / güncellenen testler
- `tests/testthat/test-source-manifest-sections-contract.R`: dondurulmuş bölüm sırası (35 anahtar), bölüm başına ilk/son dosya ve eleman sayısı çapaları, türetme bütünlüğü (`group_1 = foundation`, `after_future = unlist(sections[-1L])`, `runtime = c(...)`, `unlist(sections) = runtime`), tekrar yok ve toplam 253 dosya.

### Gerçekten çalıştırılan doğrulamalar (bu cloud oturumunda)
- `bash tools/ai_validate.sh cloud-quick` → `failed_steps: 0`, `skipped_steps: 1`; `summary.json`: `profile_requested="cloud-quick"`, `profile_effective="quick"`, `parse sanity: OK`, `app source smoke: SKIPPED`, `focused contract tests: passed`.
- `testthat::test_file("tests/testthat/test-source-manifest-sections-contract.R")` → PASS.
- `testthat::test_file("tests/testthat/test-source-manifest-contract.R")` → 165 PASS / 0 FAIL.
- `testthat::test_file("tests/testthat/test-global-source-manifest-contract.R")` → 12 PASS / 0 FAIL.
- `testthat::test_file("tests/testthat/test-production-contracts.R")` → 21 PASS / 0 FAIL.
- `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")` → 156 PASS / 0 FAIL.
- R ile bayt bayt yükleme sırası karşılaştırması: yeni manifest `source_manifest_runtime_paths` == eski (HEAD) sürüm (TRUE).
- `R/bootstrap_source_manifest.R` `source_manifest_try_parse_file` + `source_manifest_validate_config_objects`: PARSE_OK + CONFIG_OBJECTS_OK.

### Manuel QA (kullanıcı/VM tarafı)
Bu değişiklik runtime davranışını değiştirmez, ancak boot manifestine dokunduğu için VM'de bir kez doğrulanması önerilir:
- Uygulamayı normal Windows VM başlatıcısıyla başlatın; kırmızı hata olmadan açıldığını doğrulayın.
- Ana Söyleşi karşılama ekranı, hızlı eylemler, Dosya Yönetimi, Bilge Yolaç ve Yönetici/Sistem Durumu sayfalarının yüklendiğini doğrulayın.
- Türkçe karakter içeren bir mesaj gönderip yanıtın doğru render edildiğini doğrulayın.
- (İsteğe bağlı) VM'de `bash tools/ai_validate.sh full --boot-smoke` ile boot smoke çalıştırın.

### Bilinen riskler / bilinçli atlanan doğrulamalar
- Bu cloud checkout'unda `.Renviron` ve bazı `www` varlıkları bulunmadığından tam strict suite (`tests/testthat.R`) eksiksiz tamamlanmaz. `test-logout-url-contract.R` (2), `test-ui-asset-manifest-contract.R` (1) ve `test-claude-code-security-policy-contract.R` (2) başarısızlıkları ORİJİNAL manifestle de birebir oluşur; bu değişiklikten kaynaklanmaz (CLAUDE.md cloud notlarıyla uyumlu, ortam kaynaklı).
- `cloud-quick` tam runtime/app boot, gerçek tarayıcı UX, VM/SSO/DB veya SQL Server Türkçe encoding doğrulaması DEĞİLDİR; bunlar VM tarafı gate'leridir ve bu oturumda çalıştırılmadı.

---

## 2026-06-09 — UI asset manifest sectioning without order change

### Seçilen iz(ler)
- **Track D — Manifest Sectioning Without Load-Order Change** (`R/config_ui_assets.R` CSS `page` ve JS `deferred` listeleri).

### Özet ve gerekçe
`R/config_ui_assets.R` içinde en uzun onboarding yükü, tek blok hâlindeki `page` CSS listesi ve `deferred` JS listesindeydi. Bu listeler çalışma zamanı açısından hassas olduğu için dosya taşımak, selector değiştirmek veya asset sırasını değiştirmek yerine yalnızca manifestin okunabilirlik sınırı iyileştirildi.

CSS `page` listesi tema tabanı, light theme modülleri, light override katmanları, layout temeli, navigasyon/araç yüzeyleri, feature yüzeyleri ve enterprise/Bilge Yolaç katmanı olarak adlandırıldı. JS `deferred` listesi code/table, welcome/media, modal/analysis tools ve admin/enterprise alt bölümlerine ayrıldı. Her iki yol da `ui_asset_flatten_groups()` ile aynı adsız vektöre indirildiği için UI tag üretimi, `defer` planı ve tarayıcı yükleme sırası değişmedi.

### Değişen dosyalar
**Kaynak**
- `R/config_ui_assets.R` — `ui_asset_flatten_groups()` helper'ı manifest listelerinden önce tanımlandı; uzun `page` CSS ve `deferred` JS listeleri named alt bölümlere ayrıldı; `ui_asset_public_root()` içindeki unreachable duplicate `return(root)` temizlendi.

**Test**
- `tests/testthat/test-ui-asset-manifest-contract.R` — sectioning refactor'ının `ui_asset_css_groups$page` ve `ui_asset_js_groups$deferred` vektörlerini birebir değiştirmediğini doğrulayan sıra sözleşmesi eklendi.

**Dokümantasyon**
- `docs/architecture-map.md` — UI asset manifestinin bölümleme/onboarding sınırı ve order-stability testi açıklandı.
- `docs/technical-reference.md` — sectioning'in runtime/tag/defer sözleşmesini değiştirmediği ve ilgili test koruması eklendi.
- `docs/refactor-log.md` — bu giriş.

### Önce / sonra karmaşıklık notları
- Önce: maintainer'ın uzun CSS/JS vektörlerinde tema, feature, media, admin ve Bilge Yolaç assetlerini tek listede zihinsel olarak ayırması gerekiyordu.
- Sonra: uzun listeler feature/layer başlıklarıyla okunuyor; final vektör tek kaynakta kalıyor ve order stability testle donduruluyor.
- Runtime dosyaları, frontend selector'ları, Shiny input/output ID'leri, browser message adları veya asset dosya adları değiştirilmedi.

### Korunan davranış sözleşmeleri
- CSS/JS dosya sırası ve `ui_asset_all_css()` / `ui_asset_all_js()` çıktıları korunur.
- `ui_asset_js_render_plan`, `ui_asset_deferred_js_groups`, `defer` davranışı ve `ui_asset_js_order_rules` korunur.
- Encoding, streaming markdown safety, TTS/STT/media, SSO, Bilge Yolaç, admin/health ve tema assetleri aynı dosya yollarıyla yüklenmeye devam eder.
- Türkçe dokümantasyon metni UTF-8 korunarak yazıldı; DB schema, renv.lock, source manifest ve runtime davranışı değiştirilmedi.

### Eklenen / güncellenen testler
- `test-ui-asset-manifest-contract.R` içindeki yeni test:
  - `ui_asset_css_groups$page` tam vektörünün sectioning sonrası beklenen sırayla birebir aynı kaldığını doğrular.
  - `ui_asset_js_groups$deferred` tam vektörünün sectioning sonrası beklenen sırayla birebir aynı kaldığını doğrular.
  - Flatten edilmiş manifest vektörlerinde isim sızıntısı olmadığını doğrular.

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- `Rscript tests/scripts/maintainability_report.R` → geçti; skor 100/100.
- `Rscript -e "source('R/config_ui_assets.R', encoding='UTF-8'); ui_asset_validate(root='.', check_files=FALSE); cat(length(ui_asset_all_css()), length(ui_asset_all_js()), '\n')"` → geçti; CSS/JS sayıları `95 120`.
- `Rscript -e "testthat::test_file('tests/testthat/test-ui-asset-manifest-contract.R')"` → başarısız; yeni sıra testi geçti, ancak mevcut fixture ortamında vendored `www/codemirror`, `www/lib/threejs` ve `www/css/all.min.css` dosyaları eksik olduğu için aynı test dosyasının `check_files = TRUE` offline asset varlık kontrolü başarısız oldu.
- `Rscript tests/testthat.R` → başarısız; mevcut fixture/env sınıfında Bilge Yolaç security prompt traversal beklentisi, eksik `.Renviron` logout URL fixture'ı, eksik vendored UI assets ve upload-validator fixture path kontrolleri fail verdi. Yeni UI manifest sıra testi bu koşuda geçti (`ui-asset-manifest-contract: ....5.6.....................` çıktı nokta/başarılı assertion akışında yeni test assertion'larını içerir), ancak dosyanın mevcut asset varlık kontrolü aynı eksik vendored assetlerle başarısız kaldı.
- `bash tools/ai_validate.sh quick` → geçti; `failed_steps: 0`, `skipped_steps: 0`, artifact: `artifacts/ai-validation/20260609-153404/summary.json`.

### Manuel QA (kullanıcı/VM tarafı)
- Uygulamayı normal Windows VM launcher ile başlatın; kırmızı hata ve yeni browser console hatası olmadığını doğrulayın.
- Hard refresh yapın; dark theme ve welcome ekranının aynı render edildiğini kontrol edin.
- Light theme destekleniyorsa açık temaya geçin; welcome, chat, modal, Dosya Yönetimi, admin/health, destek ve Bilge Yolaç yüzeylerinde yeni koyu/leaky yüzey olmadığını kontrol edin.
- Ana Söyleşi'de Türkçe karakterli bir mesaj (`ç, ğ, ı, İ, ö, ş, ü`) gönderin; streaming ve Stop davranışını kontrol edin.
- Dosya Yönetimi'nde Türkçe adlı TXT/CSV yükleyin; liste/önizleme görünümünün değişmediğini kontrol edin.
- Bilge Yolaç sekmesini açın; arayüz ve streaming/cancel davranışında console hatası olmadığını kontrol edin.

### Bilinen riskler / atlanan doğrulamalar
- Bu refactor frontend dosyalarının içeriğine dokunmadı; browser smoke manuel VM QA'ya bırakıldı.
- `check_files = TRUE` asset varlık testi mevcut cloud/container fixture'ında eksik vendored assetler nedeniyle başarısız olabiliyor; Windows/on-prem paketlenmiş asset ortamında ayrıca doğrulanmalıdır.
- Source manifest, DB schema/encoding, SSO, file lifecycle, streaming logic ve `renv.lock` bilerek değiştirilmedi.

## 2026-06-11 — Açık tema mimarisinin alan-odaklı konsolidasyonu (13 dosyalık override zincirinin kaldırılması)

### Sorun
Açık tema, 13 dosyalık sıralı bir override/patch zinciriydi (`theme_light.css` + `extras` + `refinements` + 6 modül + `polish` + `overhaul` + `overhaul_phase2` + `user_polish` + `user_polish_v2`): toplam ~10.7k satır (tüm CSS'in ~%33'ü), aynı seçici 5-8 kez yeniden tanımlanıyor, ~2.480 `!important` bildirimi katmanlar arası savaşıyordu. Kaskad analizi iki yapısal sorunu kanıtladı: (1) tüm bildirimlerin %25'i (2.485/9.943) sonraki katmanlarca ezilen ÖLÜ bildirimdi; (2) benzersiz 2.334 (media, seçici) anahtarının 1.082'si (%46) DOM'da hiç var olmamış HAYALET sınıf/attribute'lara bağlıydı (`.fm-drop-zone`, `.file-preview-modal`, `.yenilikler-page`, `[data-cc-badge]`, `[data-thinking-toggle]` vb. — runtime R/JS kaynaklarında adı geçmeyen, tahminle yazılmış seçiciler). "Bazı açık tema seçenekleri beklendiği gibi davranmıyor" şikayetinin kök nedeni buydu: cila katmanları kısmen hiç eşleşmeyen seçicilere yazılmıştı.

### Yapılan
- Zincirin kaskad sonucu (media bağlamı + özgüllük + `!important` + kaynak sırası hesaplanarak) anahtar başına KAZANAN bildirim kümesi olarak çıkarıldı; bağımsız bir doğrulayıcı ile eski zincir ↔ yeni dosyalar birebir eşdeğer kanıtlandı (0 kayıp anahtar, 0 kazanan-bildirim farkı, 0 dosyalar-arası sıra riski).
- Hayalet seçiciler iki aşamalı güvenlik filtresiyle ayıklandı: tam-ad grep (R/, www/js, www/smoke, kök R dosyaları, tema dışı CSS) + dinamik üretim öneki koruması (`paste0("health-status-", ...)`, `'cc-message-' +`, `toast-${...}` aileleri ASLA silinmedi) + vendor sınıf desenleri (Bootstrap/DataTables/Shiny/highcharts/CodeMirror) korundu.
- Kalan 1.252 anahtar YEDİ alan dosyasına yerleştirildi (her seçici tam BİR kez): `theme_light_core.css` (kabuk), `welcome`, `chat`, `modals`, `bilge_yolac`, `personalization`, `pages`. En sık literal renkler token'lara bağlandı (`var(--mb-brand-primary)` vb.).
- Plotly grid CSS'i (motor runtime'dan kaldırılmıştı) ve yalnızca hayalet kurallarca kullanılan `@keyframes mergen-cpu-core-pulse` ölü kod olarak silindi.
- Manifest (`R/config_ui_assets.R` grupları + `ui_asset_css_order_rules`), bölge haritası (`R/config_ui_asset_zones.R` `tema` bölgesi), CLAUDE.md tema sözleşmesi, `docs/architecture-map.md` ve `docs/technical-reference.md` yeni mimariye güncellendi.
- Gelecek koruması: `test-theme-light-modular-contract.R` yeniden yazıldı (dondurulmuş dosya kümesi + 8 eski dosya adı için tombstone + tema dosyaları arası TEK-TANIM sözleşmesi + `html[data-theme="light"]` kapsam disiplini ve belgeli kapsamsız allowlist + yalnızca GERÇEK seçici çapaları). `frontend_maintainability_report.R` artık tema bölgesi toplam satırını, dosyalar-arası light-tekrar seçici sayısını ve tombstone ihlalini raporluyor; `test-frontend-maintainability-ratchet.R` bunları bütçeyle bağlıyor (light-tekrar ≤ 44, tema bölgesi ≤ 6.400 satır, tombstone = 0).
- `test-ui-asset-manifest-contract.R` ve `test-tool-background-lifecycle-contract.R` yeni zincire göre güncellendi; `module_saved_chats.R` / `module_image_gallery.R` içindeki bayat dosya-adı yorumları düzeltildi.

### Sonuç
- Tema bölgesi: ~10.7k → 5.6k satır (%48 küçülme); CSS toplamı ~32.0k → ~27.1k satır.
- `html[data-theme="light"]` kapsamlı dosyalar-arası tekrar seçici: ~150+ çoklu-katman kopyasından 44 adede (tamamı bilinçli tema+bileşen 2x çifti) indi; tema dosyaları İÇİNDE tekrar 0.
- Eski testin bazı çapalarının (örn. `blur(18px)`) hiç uygulanmayan ölü metin olduğu kanıtlandı; yeni test gerçek kazanan değerlere (`blur(10px) saturate(132%)`) çapalandı.
- JS denetimi: manifest JS dosyalarında ölü dosya bulunamadı; tema-düşmanı inline renk ataması yok; `theme_manager.js` R senkronizasyonu sağlam. JS tarafında riskli cerrahi gerekmedi.

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- Node tabanlı kaskad eşdeğerlik doğrulayıcısı → `EŞDEĞER ✓` (0 kayıp / 0 fark / 0 sıra riski).
- `Rscript tests/scripts/parse_sanity_check.R` → OK (749 dosya).
- `testthat::test_file` yeşil: theme-light-modular (96), ui-asset-manifest (224), ui-asset-zones (17), frontend-maintainability-ratchet (89, yeni disiplin testi dahil), frontend-selector (80), tool-background-lifecycle (21), brand-title (22), sidebar-theme-sync (19), ux-regression-guardrails (28), accessibility (38), tool-backgrounds (39), browser-smoke-harness (12), smoke-probes (6), runtime-network-boundary (2), e2e-boot-welcome (29; `logger` paketi kurulduktan sonra tam geçti — ilk hata bu cloud ortamındaki eksik paketti, kod regresyonu değildi).
- `bash tools/ai_validate.sh quick` → geçti; `failed_steps: 0`, `skipped_steps: 0`, app source smoke dahil. Artifact: `artifacts/ai-validation/20260611-185513/summary.json`.

### Manuel QA (kullanıcı/VM tarafı)
- Açık temaya geçin ve şu yüzeyleri gezin: karşılama ekranı (cam kart + hızlı eylemler + son konuşmalar), Ana Söyleşi (baloncuklar, giriş alanı, mesaj eylemleri, derin düşünme), modallar (geri bildirim, STT, dosya önizleme, API anahtarı), Bilge Yolaç (AJAN/karakter rozetleri, tool blokları), Kişiselleştirme + Yapılandırma, Dosya Yönetimi, Söyleşi Geçmişi/Kayıtlı/Galeri (ay grupları), Destek sayfaları (NPS butonları, Yenilikler rozetleri), Yönetici panelleri ve Sistem Durumu.
- Koyu temada aynı yüzeylerde değişiklik OLMAMALI (kapsamsız taban kurallar korunmuştur).
- Tema geçiş butonunu birkaç kez ileri-geri kullanın; sayfa yenilemesi sonrası tema kalıcılığını doğrulayın.

### Bilinen riskler / atlanan doğrulamalar
- Eşdeğerlik kanıtı statik kaskad düzeyindedir; gerçek tarayıcı görsel doğrulaması bu cloud ortamında yapılamadı (tarayıcı yok) ve VM manuel QA'ya bırakıldı.
- Hayalet seçici silme kararı tam-ad + üretim-öneki + vendor-desen taramasına dayanır; teorik kalan risk, kaynak dışından (ör. tarayıcı eklentisi) eklenen sınıflar içindir ve üretimde beklenmez.
- Bileşen CSS dosyalarındaki (chat_header, sidebar_user_panel, surum_bilgilendirme vb.) component-owned light kuralları bilinçli yerinde bırakıldı; 44 adetlik 2x tema+bileşen çifti ratchet bütçesiyle sınırlandı.
- `code_highlighting.css` içindeki `hljs-*` kuralları (highlight.min.js yalnızca on-prem VM kopyasında mevcut) ve `health_check.css` mirası bu kapsamda BİLEREK değiştirilmedi; ayrı değerlendirme gerektirir.

## 2026-06-11 — Bileşen CSS hayalet seçici temizliği ve kalıcı orphan taraması (Faz H)

### Sorun
Açık tema konsolidasyonu hayalet seçicilerin tema zinciriyle sınırlı olmadığını gösterdi. Aynı denetimli yöntem (tam-ad corpus taraması + İNCELENMİŞ dinamik üretim önekleri + vendor desenleri) tüm bileşen CSS'ine uygulandığında: tamamı ölü 3 dosya (`capabilities.css`, `health_check.css`, `recent_chats_custom.css` — modern karşılama öncesi eski welcome ailesi ve legacy sağlık stilleri) ve 29 dosyada ~149 ölü kural bulundu (eski welcome ekranı kalıntıları, BS4-stili kullanılmayan spacing utility'leri, var olmayan modal/sınıf adlarına yazılmış kurallar).

### Kritik metodoloji bulgusu
İlk önek listesi orta-string birleştirmeleri kaçırıyordu: `paste0("destek-tag-btn destek-tag-", renk)`, `"alo-ch alo-tok-" + tok.c`, `paste0("cc-dir-item cc-dir-", tip)`, `'... destek-chatbot-message-' + tip` gibi aileler corpus genelinde "önek-ile-biten string literal" taramasıyla TEK TEK incelenip korumaya alındı; `health-`/`index-health-` eşleşmelerinin tempfile pattern'i olduğu (sınıf üretimi OLMADIĞI) doğrulandı. İtilmiş tema konsolidasyonu bu sıkı listeye karşı yeniden doğrulandı: yanlış silinen kural YOK (0).

### Yapılan
- 3 tamamı-ölü dosya silindi; manifest (`navigation_and_tools`), bölge haritası (`sohbet_girisi_mesajlar`, `karsilama_intro`, `yonetici_saglik`) ve `test-ui-asset-manifest-contract.R` listesi birlikte güncellendi; `test-e2e-health-dashboard-regression.R` canlı stil kaynağına (`health_dashboard.css`) yeniden çapalandı.
- 29 dosyada 149 ölü kural yerinde silindi (span-koruyucu araç: hayatta kalan kurallar bayt-bayt aynı; kurala bitişik yorumlar birlikte kaldırıldı; boşalan @media blokları temizlendi). Grup içinde canlı üyesi olan seçiciler BİLİNÇLİ bırakıldı (kural canlı).
- BİLİNÇLİ atlananlar: `brand_title.css` (10 ölü kural — sözleşme testi ölü `.mergen-brand-*` sınıflarını metin olarak sabitliyor; bilinçli sözleşme güncellemesi gerektirir), `theme_tokens.css` (tek orphan grup üyesi), `tool-bg-caret` benzeri sözleşme-yorumunda anılan tarihsel sınıflar yalnızca test yorumunun izin verdiği biçimde kaldırıldı.
- Kalıcılaştırma: hayalet seçici taraması `tests/scripts/frontend_maintainability_report.R` içine taşındı (runtime corpus + vendor desenleri + incelenmiş `frontend_orphan_constructed_prefixes` listesi); `test-frontend-maintainability-ratchet.R` toplamı bütçeyle bağladı: global ölü seçici ≤ 42 (taban: brand_title 18 + canlı-grup kalıntıları), tema alan dosyaları ≤ 7.

### Sonuç
- CSS ~26.9k → ~26.0k satır; tamamı-ölü kural kalan tek dosya bilinçli atlanan `brand_title.css`.
- Yeni hayalet seçici eklemek artık ratchet kırar; yeni dinamik sınıf ailesi eklerken önek listesine bilinçli kayıt gerekir.

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- Odaklı süitler yeşil: frontend-maintainability-ratchet (92), ui-asset-manifest (224), ui-asset-zones (17), theme-light-modular (96), e2e-health-dashboard (45), tool-background-lifecycle (21), frontend-selector (80).
- `bash tools/ai_validate.sh full --boot-smoke` bu girdinin yazıldığı sırada arka planda koşuyordu; sonucu commit mesajında ve oturum raporunda beyan edilir.

### Manuel QA (kullanıcı/VM tarafı)
- Sistem Durumu panosunu açın (stil kaynağı artık yalnız `health_dashboard.css`); kart/tooltip görünümünü iki temada doğrulayın.
- Dosya Yönetimi başlığı ("Yüklenen Dosyalar" `.section-title`), karşılama ekranı, Yenilikler rozeti ve Bilge Yolaç yüzeylerinde değişiklik OLMAMALI.

### Bilinen riskler / atlanan doğrulamalar
- Tarayıcı görsel doğrulaması yine cloud'da yapılamadı; silinen her kural "DOM'da eşleşmesi imkânsız" kanıtına dayanır (sınıf hiçbir runtime kaynağında yok + dinamik üretim önekleri korunmuş).
- `brand_title.css` ölü kuralları ve `code_highlighting.css` hljs bloğu bilinçli yerinde; ayrı sözleşme kararı gerektirir.

## 2026-06-12 — brand_title.css hayalet sınıf API'sinin kaldırılması ve sözleşmenin token mekanizmasına yeniden çapalanması

### Karar
`test-brand-title-single-source-contract.R`, DOM'da hiç var olmamış `.mergen-brand-title*` paralel sınıf API'sini metin olarak sabitliyordu. İnceleme, tek-kaynak hizalamanın GERÇEK mekanizmasının `--mergen-brand-*` token ailesi olduğunu doğruladı: üç canlı marka yüzeyi (`.brand-text`, `#app-loading-overlay .alo-wordmark`, `.deep-space-branding .deep-space-title`) aynı `var(--mergen-brand-font-stack)` tokenini tüketir. Bilinçli sözleşme güncellemesi yapıldı:
- 10 ölü kural kaldırıldı (`.mergen-brand-title*`, `.mergen-brand-mark`, hayalet `.ds-modal-*` / `.ds-version-modal-*` ailesi, `.deep-space-title-accent`, `.deep-space-version-text`); brand_title.css 314 → 237 satır.
- Test, token tanımları + üç canlı yüzeyin token TÜKETİMİ (≥3 `var(--mergen-brand-font-stack)`) üzerine yeniden çapalandı ve hayalet sınıf ailesinin geri eklenmesini açıkça YASAKLAYAN bir assertion eklendi.
- Hayalet seçici ratchet tabanı 42 → 26'ya İNDİRİLDİ (kalan 26'nın tamamı canlı kuralların grup üyesi kalıntılarıdır; tek başına ölü kural kalmadı).

### hljs doğrulaması (kayıt)
`highlight.min.js` / `hljs` için R çalışma zamanı kaynaklarında (R/, ui.R, server.R, global.R) SIFIR yükleyici referansı doğrulandı: repo içinden bu dosyayı yükleyen hiçbir mekanizma yoktur; `code_highlighting.css` hljs bloğu repo-kanıtıyla ölüdür. Dosya yalnızca on-prem VM kopyasında fiziksel olarak bulunduğu için bloğun kaldırılması VM-doğrulamalı bir oturuma bırakılmıştır (vendor desenleri ratchet'te zaten korumalıdır; acil risk yok).

### Doğrulamalar
- `test-brand-title-single-source-contract.R` → 23 PASS / 0 FAIL.
- Hayalet tarama yeni tabanı: toplam 26 (tema: 7).
- Tam kapı (`ai_validate full --boot-smoke`) bu commit öncesi yeniden koşuldu; sonuç commit mesajında.

## 2026-06-12 — Grup üyesi ölü seçicilerin budanması: hayalet seçici tabanı SIFIR

Canlı kuralların grubunda kalan son 26 ölü seçici (hiçbir zaman eşleşemeyen grup üyeleri) 12 dosyadan budandı (kural gövdeleri bayt-bayt korunur; tamamen ölü kural 0 doğrulandı). `frontend_maintainability_report.R` hayalet taraması artık 0/0 raporlar ve ratchet bütçeleri SIFIRA indirildi (`MERGEN_TEST_MAX_FRONTEND_DEAD_SELECTORS=0`, `MERGEN_TEST_MAX_THEME_DEAD_SELECTORS=0`): bundan sonra eklenen HER hayalet seçici CI'da yakalanır. Odaklı süitler yeşil (ratchet 92, theme-modular 96, brand 23, manifest 224, tool-bg 21); tam kapı sonucu commit mesajında.
