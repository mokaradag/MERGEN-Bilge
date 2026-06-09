# MERGEN Bilge Refactor Günlüğü

Bu günlük, kod davranışını değiştirmeden karmaşıklığı ve onboarding yükünü azaltmayı hedefleyen yapısal iyileştirmeleri kaydeder. Her giriş; seçilen iz(ler)i, değişen dosyaları, önce/sonra karmaşıklık notlarını, korunan davranış sözleşmelerini, eklenen/güncellenen testleri, gerçekten çalıştırılan doğrulamaları, kullanıcı için manuel QA listesini ve bilinen riskleri/atlanan doğrulamaları içerir.

Sıkı çalışma kuralları için İngilizce [`../CLAUDE.md`](../CLAUDE.md) otoritatif kalır.

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
