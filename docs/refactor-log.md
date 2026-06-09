# MERGEN Bilge Refactor Günlüğü

Bu günlük, kod davranışını değiştirmeden karmaşıklığı ve onboarding yükünü azaltmayı hedefleyen yapısal iyileştirmeleri kaydeder. Her giriş; seçilen iz(ler)i, değişen dosyaları, önce/sonra karmaşıklık notlarını, korunan davranış sözleşmelerini, eklenen/güncellenen testleri, gerçekten çalıştırılan doğrulamaları, kullanıcı için manuel QA listesini ve bilinen riskleri/atlanan doğrulamaları içerir.

Sıkı çalışma kuralları için İngilizce [`../CLAUDE.md`](../CLAUDE.md) otoritatif kalır.

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
