# MERGEN Bilge

MERGEN Bilge; Türkçe odaklı kurumsal kullanım için tasarlanmış, R/Shiny tabanlı bir yapay zekâ asistanı ve çalışma alanıdır. Sohbet, dosya analizi, görsel üretimi/görsel anlama, sesli etkileşim, destek akışları, yönetim panelleri ve Bilge Yolaç adlı kod odaklı Claude Code deneyimini tek uygulamada birleştirir.

> **Kısa not:** Bu README bilinçli olarak ilk giriş belgesidir. Üretim, Windows VM, SSO, Türkçe kodlama, DB sınırları, `renv` ve doğrulama ayrıntıları için aşağıdaki dokümantasyon haritasındaki derin belgelere geçin.

## MERGEN Bilge nedir?

MERGEN Bilge, kurum içi/on-prem ortamlarda çalışmaya uygun bir yapay zekâ deneyim katmanıdır. Kullanıcılar doğal Türkçe ile sohbet edebilir, dosyaları bağlama ekleyebilir, görsel ve medya iş akışlarını kullanabilir, destek bilgilerine ulaşabilir ve uygun yetkilerle yönetim/sağlık ekranlarını izleyebilir. Geliştiriciler ve bakım ajanları için uygulama; kaynak manifestleri, test kapıları, operasyon kılavuzu ve kodlama ajanı sözleşmeleriyle korunur.

## Kimler için?

| Kitle | Bu README'den sonra önerilen belge |
|---|---|
| İlk kez gören kullanıcı veya paydaş | [`ai_rehber.md`](ai_rehber.md), [`docs/release-notes.md`](docs/release-notes.md) |
| İlk kez katkı veren geliştirici | [`docs/architecture-map.md`](docs/architecture-map.md), [`CLAUDE.md`](CLAUDE.md) |
| Kodlama ajanı / bakımcı | [`CLAUDE.md`](CLAUDE.md), [`AGENTS.md`](AGENTS.md) |
| Windows VM / üretim operatörü | [`RUNBOOK.md`](RUNBOOK.md), [`docs/dependency-locking.md`](docs/dependency-locking.md) |
| Bağımlılık kilitleme sorumlusu | [`docs/dependency-locking.md`](docs/dependency-locking.md), [`RENV_LOCK_STATUS.md`](RENV_LOCK_STATUS.md) |

## Temel yetenekler

- Türkçe odaklı yapay zekâ söyleşi deneyimi ve persona sistemi.
- Dosya yükleme, dosya yönetimi, önizleme, tablo/veri okuma ve analiz akışları.
- Görsel üretimi, görsel galerisi ve desteklenen modellerde görsel anlama (image input / vision).
- TTS, STT, karşılama medyası ve sesli rehberlik bileşenleri.
- Destek Merkezi, Geri Bildirim & Hata, Yenilikler ve Hakkında sayfaları.
- Yönetici/Sistem Durumu ekranları ve sağlık/operasyon sinyalleri.
- Bilge Yolaç: Claude Code ile web üzerinden çalışan kodlama ajanı alanı ve eklenti sistemi.
- SSO/Keycloak hazır kimlik doğrulama sınırı ve yerel geliştirme modu.

## Modern persona sistemi

MERGEN Bilge, farklı çalışma tarzlarını temsil eden beş modern ve kurgusal Türk AI persona'sı kullanır. Bu çerçeve kullanıcıya uygun yanıt tarzını seçilebilir kılar.

| Persona | Rol |
|---|---|
| Emre Onat | Ana Asistan; dengeli, pragmatik ve profesyonel varsayılan yardımcı. |
| Selin Sezgin | Yapıcı Uzman; çözüm odaklı ve ilerletici değerlendirme yapar. |
| Deniz Özgün | Stratejist; uzun vadeli, yapısal düşünür ve karar çerçevesi kurar. |
| Can Yalın | Eleştirel Eş; varsayımları, riskleri ve eksik verileri görünür kılar. |
| İpek Duru | Rehber; karmaşık konuları küçük adımlara böler ve sade örneklerle anlatır. |

## Hızlı başlangıç

### 1. Depoyu açın ve yapılandırmayı inceleyin

```sh
cd MERGEN-Bilge
cp .Renviron.example .Renviron
```

`.Renviron.example` yalnızca güvenli örnek değerler içerir. Gerçek `.Renviron` içine kurum ortamına ait değerler yazılabilir; **secrets, API anahtarları, token'lar, DSN'ler veya parolalar commit edilmez**.

### 2. Bağımlılık politikasını okuyun

Bu repo `renv` politikasına sahiptir; ancak `renv.lock` üretimi Windows VM/on-prem kurallarına bağlıdır. Bulut/Linux/Codex ortamında `renv.lock` üretmeyin. Ayrıntılar: [`docs/dependency-locking.md`](docs/dependency-locking.md) ve [`RENV_LOCK_STATUS.md`](RENV_LOCK_STATUS.md).

### 3. Uygulamayı başlatın

Yerel R oturumundan:

```r
shiny::runApp()
```

Üretim/Windows VM başlangıcı için depoda iki giriş noktası vardır:

```bat
run_mergen_prod.bat
```

```sh
Rscript run_mergen_prod.R
```

Windows VM, UNC yol, SSO, log, sağlık paneli ve rollback akışları için kısa README yerine [`RUNBOOK.md`](RUNBOOK.md) izlenmelidir.

## Temel doğrulama komutları

Kodlama ajanları için normal hafif kapı:

```sh
bash tools/ai_validate.sh quick
```

Bulut/Codex fallback kapısı:

```sh
bash tools/ai_validate.sh cloud-quick
```

`cloud-quick`, ağır runtime paket bootstrap'ını ve app source smoke kapsamını bilinçli olarak atlayabilir; tam Windows VM/üretim kanıtı yerine geçmez. Riskli runtime, SSO, DB encoding, source-order, file lifecycle, streaming, frontend asset order, Bilge Yolaç/Claude Code, security-path-download veya production-VM etkili değişikliklerde repo sözleşmelerine göre daha geniş doğrulama gerekir.

### Windows VM evidence gate milestone

MERGEN Bilge'nin on-prem Windows VM doğrulamasında önemli bir readiness/release kilometre taşı kaydedildi ve **15 Haziran 2026** tarihinde yeniden doğrulandı: `tests/scripts/run_vm_evidence_gate.R` tam koşumu VM üzerinde uçtan uca geçti. Son başarılı koşumda `Toplam: 13 passed, 0 failed, 0 skipped` görüldü; özellikle `full_testthat`, `browser_ux_smoke`, `vm_preflight_real` ve `db_encoding_preflight` adımları `PASSED` oldu. Son kanıt artifact'ı: `artifacts/vm-evidence/20260615-130127/evidence.json`.

Bu kanıt kapısı `artifacts/vm-evidence/<timestamp>/evidence.json` altında secret-safe makine-okunur sonuç üretir. Güncel durum; tam izole testthat suite'inin, VM preflight'ın, DB encoding preflight'ın ve gerçek browser UX smoke kanıtının aynı VM koşumunda geçtiğini gösterir. Browser proof external-app modunda `http://127.0.0.1:28081` üzerinden, `MERGEN_BROWSER_UX_BASE_URL=http://127.0.0.1:28081` ve `MERGEN_REQUIRE_BROWSER_UX_SMOKE=true` ile alınmıştır. Uzun süreli saha yükü, manuel kırılgan-akış QA'sı veya eski legacy DB satırlarının temizliği gibi kapsamları otomatik olarak kanıtlamaz; ayrıntılı komutlar ve zorunlu browser UX smoke iki-pencere akışı için [`RUNBOOK.md`](RUNBOOK.md) izlenmelidir.

### DB bağlantı havuzu ve etkileşimli soak seridi (2026-06-22)

İşlem-güvenli, **opt-in** bir DB bağlantı havuzu eklendi (`R/helpers_db_pool.R`; `MERGEN_DB_POOL_ENABLED`, varsayılan KAPALI). Okuma yolları otomatik havuzlanır; çok-ifadeli işlemler (`save_message_to_db`) gerçek `poolCheckout()` ile işlem-güvenli yürütülür ve bağlantı iade edilmeden önce rollback edilir. Operasyonel soak kapısına, GET-only HTTP seridinin açmadığı sohbet/DB/streaming/stop yollarını **gerçek DB havuzu** üzerinde alıştıran bir **etkileşimli (interactive) serit** eklendi; kanıt artifact'ı havuz checkout/return/sızıntı ve oturumlar-arası izolasyon sayaçlarını içerir. Bunlar bulutta/offline (gerçek SQLite) doğrulanmıştır; **SQL Server'a karşı üretim doğrulaması, gerçek websocket eşzamanlılığı ve gerçek LLM throughput'u Windows VM'de ayrıca doğrulanmalıdır**. Ayrıntı: [`docs/database-pooling.md`](docs/database-pooling.md) ve [`docs/operational-soak-gate.md`](docs/operational-soak-gate.md).

27 Haziran 2026 Windows VM proxy attach soak güncellemesi: en uzun süreli stabil proxy attach kanıtı hâlâ 300 aktif proxy kullanıcı / 90 dk; en yeni daraltılmış kısa merdiven retestinde 100, 300, 350 ve 400 aktif proxy kullanıcı adımları 10 dk/adımda PASS, 425 aktif proxy kullanıcı ilk başarısız adım olarak kaydedildi. Bu sonuçlar 425/1000 gerçek aktif insan readiness, gerçek upstream LLM throughput'u, gerçek browser/websocket concurrency veya SQL Server at-rest encoding kanıtı değildir; ayrıntılar operational soak belgesindedir.

## Depo haritası

| Yol | Amaç |
|---|---|
| `app.R`, `global.R`, `ui.R`, `server.R` | R/Shiny uygulama kabuğu ve ana çalışma zamanı girişleri. |
| `R/` | Modüller, yardımcılar, LLM entegrasyonu, DB/SSO/file-store sınırları ve kaynak manifestleri. |
| `www/` | CSS, JS, medya, karakter varlıkları ve tarayıcı tarafı davranış. |
| `docs/` | Mimari, değişiklik notları, bağımlılık kilitleme ve dokümantasyon merkezi. |
| `tests/` | `testthat` testleri, script tabanlı doğrulama, smoke ve davranışsal regresyon araçları. |
| `tools/` | AI doğrulama, `renv` snapshot, ortam hazırlama ve üretim launcher self-test araçları. |
| `bilge_yolac_plugins/` | Bilge Yolaç eklenti sistemi ve hazır eklentiler. |
| `MergenLauncher/` | Windows/launcher ilişkili yardımcı alan. |
| `.Renviron.example` | Güvenli örnek yapılandırma şablonu. |

## Dokümantasyon haritası

| Belge | Ne zaman okunmalı? |
|---|---|
| [`docs/README.md`](docs/README.md) | Tüm dokümantasyon için merkez/hub. |
| [`CLAUDE.md`](CLAUDE.md) | Kodlama ajanı veya bakımcı olarak çalışmadan önce; İngilizce ve otoritatiftir. |
| [`AGENTS.md`](AGENTS.md) | Ajanlar için kısa repo özeti ve doğrulama hatırlatmaları. |
| [`ai_rehber.md`](ai_rehber.md) | Kullanıcıya görünen Yardım Asistanı ve AI Uzman davranışları. |
| [`docs/architecture-map.md`](docs/architecture-map.md) | Kod veya dokümantasyon değişikliğinden önce mimari yön bulma. |
| [`docs/database-schema.md`](docs/database-schema.md) | Güncel uygulama kaynaklarına göre DB tablo yapısı ve tablo akışları. |
| [`RUNBOOK.md`](RUNBOOK.md) | Windows VM/on-prem operasyon, dağıtım, doğrulama ve sorun giderme. |
| [`docs/operational-soak-gate.md`](docs/operational-soak-gate.md) | Operasyonel soak/yük kapısı: fake/proxy/real-canary/interactive seritleri, profiller, anahtar yönlendirme kanıtı ve 1.000 kullanıcı rollout planı. |
| [`docs/database-pooling.md`](docs/database-pooling.md) | İşlem-güvenli, opt-in DB bağlantı havuzu: `MERGEN_DB_POOL_*` ayarları, `with_db_transaction` sözleşmesi ve VM/SQL Server doğrulama adımları. |
| [`docs/dependency-locking.md`](docs/dependency-locking.md) | `renv`, `renv.lock`, VM kilit üretimi ve bağımlılık politikası. |
| [`RENV_LOCK_STATUS.md`](RENV_LOCK_STATUS.md) | `renv.lock` dosyasının on-prem/GitHub görünürlüğü. |
| [`docs/release-notes.md`](docs/release-notes.md) | Uzun güncelleme/değişiklik notları. |
| [`docs/technical-reference.md`](docs/technical-reference.md) | Ayrıntılı teknik referans. |

## En önemli güvenlik ve bakım notları

- **Türkçe karakter bütünlüğü kritiktir.** UTF-8 korunmalı, mojibake üretilmemeli ve DB okuma/yazma normalizasyon sınırları zayıflatılmamalıdır.
- **Secrets commit edilmez.** API anahtarları, token'lar, parolalar, gerçek DSN'ler ve özel uç noktalar dokümantasyona veya loglara eklenmez.
- **`renv.lock` özel kurallara bağlıdır.** Windows VM/on-prem kilit üretimi dışında Linux/cloud/Codex ortamında kilit üretmeyin.
- **Dokümantasyon-only değişiklikler runtime davranışını değiştirmez.** Repo politikası gereği en az hafif doğrulama çalıştırılır; sadece çalıştırılan doğrulamanın kanıtı iddia edilir.
- **Üretim/on-prem/Windows VM davranışı özel kısıtlara sahiptir.** Operasyonel kararlar için README değil [`RUNBOOK.md`](RUNBOOK.md), [`CLAUDE.md`](CLAUDE.md) ve [`docs/dependency-locking.md`](docs/dependency-locking.md) esas alınmalıdır.