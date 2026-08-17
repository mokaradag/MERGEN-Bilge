# MERGEN Bilge Dokümantasyon Merkezi

Bu sayfa, MERGEN Bilge dokümantasyonunda doğru belgeye hızlı gitmek için hazırlanmış merkezdir. Ürün özeti için kök [`README.md`](../README.md) okunur; bakımcı/kodlama ajanı kuralları için İngilizce [`CLAUDE.md`](../CLAUDE.md) otoritatiftir.

## Nereden başlamalıyım?

| Ben kimim / ne yapıyorum? | İlk okuyacağım belge | Sonra okuyacağım belge |
|---|---|---|
| İlk kez MERGEN Bilge'yi tanıyorum | [`../README.md`](../README.md) | [`release-notes.md`](release-notes.md), [`../ai_rehber.md`](../ai_rehber.md) |
| İlk kez geliştirme yapacağım | [`architecture-map.md`](architecture-map.md) | [`database-schema.md`](database-schema.md), [`../CLAUDE.md`](../CLAUDE.md), [`technical-reference.md`](technical-reference.md) |
| Kodlama ajanıyım | [`../CLAUDE.md`](../CLAUDE.md) | [`../AGENTS.md`](../AGENTS.md), [`architecture-map.md`](architecture-map.md) |
| Üretim operatörüyüm | [`../RUNBOOK.md`](../RUNBOOK.md) | [`production-log-paths.md`](production-log-paths.md), [`dependency-locking.md`](dependency-locking.md), [`../RENV_LOCK_STATUS.md`](../RENV_LOCK_STATUS.md) |
| Windows VM sorunu debug ediyorum | [`../RUNBOOK.md`](../RUNBOOK.md) | [`production-log-paths.md`](production-log-paths.md), [`architecture-map.md`](architecture-map.md), [`../CLAUDE.md`](../CLAUDE.md) |
| VM evidence gate / browser proof çalıştırıyorum | [`../RUNBOOK.md`](../RUNBOOK.md) | [`vm-evidence-status.md`](vm-evidence-status.md), [`technical-reference.md`](technical-reference.md), [`release-notes.md`](release-notes.md) |
| Bağımlılık kilitlemeyi anlamak istiyorum | [`dependency-locking.md`](dependency-locking.md) | [`../RENV_LOCK_STATUS.md`](../RENV_LOCK_STATUS.md) |
| Asistan davranışını anlamak istiyorum | [`../ai_rehber.md`](../ai_rehber.md) | [`release-notes.md`](release-notes.md) |
| Release geçmişini inceliyorum | [`release-notes.md`](release-notes.md) | [`technical-reference.md`](technical-reference.md) |

## Önemli Belgeler

| Belge | Açıklama |
|---|---|
| [`../README.md`](../README.md) | Kısa, Türkçe, ilk giriş belgesi: ürün, hızlı başlangıç, doğrulama ve belge haritası. |
| [`../CLAUDE.md`](../CLAUDE.md) | İngilizce ve bilinçli olarak korunmuş kodlama ajanı/bakımcı sözleşmesi. Detaylı kurallar burada otoritatiftir. |
| [`../AGENTS.md`](../AGENTS.md) | Ajanlar için kısa repo notu, doğrulama dürüstlüğü ve belge yönlendirmeleri. |
| [`../ai_rehber.md`](../ai_rehber.md) | Yardım Asistanı ve AI Uzman için kullanıcıya dönük davranış rehberi. |
| [`architecture-map.md`](architecture-map.md) | Uygulama katmanları, gerçek dosya/dizin haritası ve korunan mimari sınırlar. |
| [`feature-ownership-map.md`](feature-ownership-map.md) | Kritik özelliklerin (sohbet/streaming, dosya, DB/encoding, SSO, API anahtarı, görsel/vision, admin/sağlık, Bilge Yolaç, destek) birincil dosya/test/servis sahipliği ve sıradaki sertleştirme hedefleri. |
| [`database-schema.md`](database-schema.md) | Uygulama kaynaklarına göre DB tablo yapısı, ilişkiler ve tablo akış diyagramı. |
| [`../RUNBOOK.md`](../RUNBOOK.md) | Kanonik Windows VM/on-prem operasyon kılavuzu; `run_vm_evidence_gate.R`, mandatory browser UX smoke external-app workflow ve `artifacts/vm-evidence/<timestamp>/evidence.json` kanıt artifact'ları burada açıklanır. |
| [`production-log-paths.md`](production-log-paths.md) | `MERGEN_LOG_DIR` için kanonik odak belge: merkezî/UNC hedefin korunması, tek/çift geçişli mojibake onarımı, geçerli Unicode adların korunması, çok-worker başlangıç sözleşmesi ve operatör doğrulaması. |
| [`vm-evidence-status.md`](vm-evidence-status.md) | En son başarılı Windows VM evidence gate koşumu; 17 Ağustos 2026 tarihli 13/13 geçiş, artifact yolu, browser attach ayarı ve kanıt kapsamı. |
| [`operational-soak-gate.md`](operational-soak-gate.md) | Operasyonel soak/yük kapısı (`run_operational_soak_gate.R`); fake/proxy/real-canary/**interactive** serit tasarımı, profiller, anahtar yönlendirme/izolasyon kanıtı, `artifacts/soak/<timestamp>/` artifact'ları ve 1.000 kullanıcı rollout planı. |
| [`database-pooling.md`](database-pooling.md) | İşlem-güvenli, opt-in DB bağlantı havuzu (`R/helpers_db_pool.R`); `MERGEN_DB_POOL_*` yapılandırması, `with_db_transaction` sözleşmesi, encoding koruması ve Windows VM/SQL Server doğrulama adımları. |
| [`speech-operator-runbook.md`](speech-operator-runbook.md) | Hibrit VoxCPM2 konuşma varlıkları: kilitli persona referans sesleri, RStudio üretici komutları (aday→dinle→onayla→750 WAV→manifest), Git/yedekleme politikası ve varlıklar üretilmeden önceki fail-closed davranış. |
| [`performance-improvement-plan.md`](performance-improvement-plan.md) | Performans iş akışı: darboğaz hipotezleri, fazlar, DB havuzlama durumu ve kanıt tablosu. |
| [`proje-kaynak-analizi-master-plan.md`](proje-kaynak-analizi-master-plan.md) | Proje ve Kaynak Analizi aracının yeniden inşa iş emri: doğrulanmış kusur envanteri (`file:line` kanıtlı), hedef aşamalı mimari, sorgu metadata sözleşmesi, Türkçe varlık çözümleme, deterministik analiz paketi, Excel dışa aktarım ve fazlı teslim planı. |
| [`dependency-locking.md`](dependency-locking.md) | `renv`, `renv.lock`, Windows VM kilit üretimi ve CI/AI bootstrap davranışı. |
| [`../RENV_LOCK_STATUS.md`](../RENV_LOCK_STATUS.md) | `renv.lock` dosyasının on-prem üretim deposu ile GitHub/Codex görünürlüğü arasındaki fark. |
| [`release-notes.md`](release-notes.md) | Uzun değişiklik notları ve güncel bakım özeti. |
| [`technical-reference.md`](technical-reference.md) | Ayrıntılı teknik referans. |
| [`refactor-log.md`](refactor-log.md) | Davranışı değiştirmeden karmaşıklık/onboarding yükünü azaltan yapısal iyileştirmelerin günlüğü. |

## Kısa Uyarılar

- `CLAUDE.md` İngilizcedir ve bu durum bilinçlidir; kodlama ajanı/bakımcı davranışında otoritatif kaynak odur.
- `MERGEN_LOG_DIR` merkezî/UNC hedefini yerel `logs` dizinine sessizce yönlendirmeyin. Güçlü mojibake yol içinde yerinde onarılır; ayrıntılı ve kanonik sözleşme [`production-log-paths.md`](production-log-paths.md) içindedir.
- Üretim-kritik sınır sahipliği (seam kayıt defteri, `R/config_seam_registry.R`) ve frontend bölge sahipliği (`R/config_ui_asset_zones.R`) [`architecture-map.md`](architecture-map.md) içindeki yönetişim katmanı bölümünde haritalanır; yeni runtime R dosyası veya frontend varlığı eklerken oradaki disiplin kuralları geçerlidir (`bash tools/seam_doctor.sh` ile doğrulanabilir).
- Windows VM, SSO, DB encoding, dosya lifecycle ve `renv.lock` davranışları README'den değil runbook ve sözleşme belgelerinden yönetilir.
- Türkçe karakter bütünlüğü korunmalıdır; UTF-8 bozulmamalı, mojibake üretilmemelidir.
- Secrets, API key, token, parola, gerçek DSN ve private endpoint bilgileri dokümantasyona eklenmez.