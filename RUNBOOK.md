# MERGEN Bilge - Üretim Operasyon Kılavuzu (RUNBOOK)

Bu belge MERGEN Bilge için **kanonik operasyon kılavuzudur**. Windows VM / on-prem çalışma, SSO profili, bağımlılık geri yükleme, dağıtım, doğrulama, sağlık izleme, rollback ve güvenli sorun giderme adımları burada tutulur. README yalnızca ilk giriş belgesidir; üretim kararı verirken bu runbook, [`CLAUDE.md`](CLAUDE.md), [`docs/dependency-locking.md`](docs/dependency-locking.md) ve [`RENV_LOCK_STATUS.md`](RENV_LOCK_STATUS.md) birlikte okunmalıdır.

## 0. Hızlı Referans

| İhtiyaç | Komut / belge |
|---|---|
| Hafif ajan doğrulaması | `bash tools/ai_validate.sh quick` |
| Bulut/Codex fallback doğrulaması | `bash tools/ai_validate.sh cloud-quick` |
| Seam/bölge sahiplik doğrulaması | `bash tools/seam_doctor.sh` |
| Üretim launcher self-test | `powershell -ExecutionPolicy Bypass -File tools/test_mergen_prod_launcher.ps1` |
| Üretim başlangıcı | `run_mergen_prod.bat` veya `Rscript run_mergen_prod.R` |
| Son logu görüntüleme | `view_latest_mergen_app_log.bat` |
| `renv.lock` politikası | [`docs/dependency-locking.md`](docs/dependency-locking.md) |
| On-prem kilit durumu | [`RENV_LOCK_STATUS.md`](RENV_LOCK_STATUS.md) |
| Mimari yön bulma | [`docs/architecture-map.md`](docs/architecture-map.md) |
| Değişiklik notları | [`docs/release-notes.md`](docs/release-notes.md) |

## 1. Amaç ve Kapsam

Bu runbook şu kitleler içindir:

- Windows VM / on-prem ortamında MERGEN Bilge çalıştıran operatörler,
- SSO, DB, dosya deposu, API anahtarı veya paket sorunlarını inceleyen bakımcılar,
- üretime yakın doğrulama kanıtı toplayan geliştiriciler ve kodlama ajanları.

Bu belge uygulama davranışını değiştirmez; yalnızca güvenli çalıştırma ve doğrulama akışını açıklar.

## 2. Varsayımlar

- Üretim hedefi Windows VM / on-prem ortamıdır.
- SSO profili kullanılabilir; yerel geliştirme modu `SSO_ENABLED=FALSE` ile ayrı değerlendirilir.
- `renv.lock` üretimi, çalışan Windows VM R 4.6.0 ortamında yapılır; Linux/cloud/Codex ortamında kilit üretilmez.
- Ağ kısıtlı veya offline çalışma olasılığı vardır; `.Rprofile` bu yüzden koşullu/offline-güvenli tasarlanmıştır.
- Gerçek `.Renviron` dosyası repoya commit edilmez.
- DB, SSO, UNC path, Türkçe karakterli path ve encoding davranışı ancak uygun VM ortamında tam kanıtlanabilir.

## 3. İlk Başlangıç Kontrol Listesi

- [ ] Depo Windows VM üzerinde doğru çalışma dizinine alınmış.
- [ ] `.Renviron.example` incelenmiş ve gerçek `.Renviron` yerel/üretim ortamında oluşturulmuş.
- [ ] Gerçek secrets, API key, token, parola, DSN ve özel endpoint değerleri repoya eklenmemiş.
- [ ] `R/config_packages.R`, `docs/dependency-locking.md` ve `RENV_LOCK_STATUS.md` okunmuş.
- [ ] Uygun R oturumu ve kütüphane yolu kullanıldığı doğrulanmış.
- [ ] Dosya deposu, upload dizinleri ve log dizinleri Windows/UNC yol kurallarına göre erişilebilir.
- [ ] SSO kullanılacaksa Keycloak/JWKS/issuer yapılandırması ve fail-closed beklentisi kontrol edilmiş.

## 4. `.Renviron` Kontrol Listesi

`.Renviron.example` güvenli şablondur. Gerçek `.Renviron` için şu gruplar kontrol edilir:

- DB bağlantıları: `DB_CLIENT_ENCODING`, `DB_NAME_ENCODING`, DSN/server alanları.
- SSO: `SSO_ENABLED`, Keycloak URL/realm/client, issuer/expiry/signature doğrulama ve JWKS ayarları.
- API key güvenliği: `AI_KEYS_MASTER`, kurum varsayılan anahtar politikası ve feature-specific anahtarlar.
- LLM/model endpointleri: ana/alternatif endpoint, model adları ve araç modeli değişkenleri.
- Görsel anlama: `MERGEN_VISION_MODELS` ve gerekiyorsa `MERGEN_ENABLE_VISION`.
- Görsel üretimi: image generation endpoint/model/timeout ayarları.
- TTS/STT: endpoint, model, voice, timeout ve SSL doğrulama seçenekleri.
- Dosya deposu: `MCP_FILES_BASE`, `MERGEN_FILES_ROOT`, `MERGEN_UPLOADS_DIR`, `MERGEN_INDEX_PATH`, `MERGEN_MCP_BASE_DIR`, `MERGEN_LOG_DIR`.
- Bilge Yolaç: Claude Code CLI/Node path, çalışma dizini, izin modu ve tool listesi.

> Gerçek secret değerlerini dokümantasyona, PR açıklamasına, log kesitine veya validation artifact içine koymayın.

## 5. Bağımlılık Restore ve `renv` İş Akışı

`R/config_packages.R` insan-okunur paket manifestidir. Kesin sürüm kilidi `renv.lock` ile yönetilir; ancak bu kilit şirket içi Windows VM/on-prem üretim deposunda bulunabilir ve çevrimiçi GitHub/Codex kopyasında bilinçli olarak görünmeyebilir.

Temiz veya yeni VM ortamında:

```r
# renv kurulu değilse yalnızca VM'de ve kontrollü şekilde kurun
install.packages("renv")

# Kilit dosyası mevcutsa restore denenebilir
renv::restore(prompt = FALSE)
```

Kilit üretme/güncelleme yalnızca Windows VM R 4.6.0 ortamında:

```sh
Rscript tools/renv_snapshot.R
```

> **`renv::init()` çağırmayın.** Bu komut `.Rprofile` davranışını ezebilir ve offline/bulut güvenli akışı bozabilir.

Ayrıntı ve commit sınırları için [`docs/dependency-locking.md`](docs/dependency-locking.md) zorunlu referanstır.

## 6. Normal Uygulama Başlatma

Windows üretim başlangıcı için tercih edilen yol:

```bat
run_mergen_prod.bat
```

Alternatif Rscript yolu:

```sh
Rscript run_mergen_prod.R
```

Yerel geliştirme için R oturumundan:

```r
shiny::runApp()
```

Başlatma sonrası logları izlemek için:

```bat
view_latest_mergen_app_log.bat
```

## 7. Doğrulama İş Akışı

### 7.1 Dokümantasyon-only değişiklikler

Dokümantasyon-only değişikliklerde runtime davranışı değişmediyse tam R/testthat veya browser smoke çalıştırmak genellikle gerekli değildir. Ancak repo politikası final teknik yanıt öncesi en az hafif doğrulama ister:

```sh
bash tools/ai_validate.sh quick
```

Uzun teknik yanıt taslağı gerektiğinde:

```sh
bash tools/ai_validate.sh quick --answer .ai/proposed_answer.md
```

### 7.2 Bulut/Codex fallback doğrulaması

```sh
bash tools/ai_validate.sh cloud-quick
```

`cloud-quick`, ağır runtime paket bootstrap'ını ve app source smoke adımlarını bilinçli olarak atlayabilir. Bu mod çalıştıysa, “tam runtime/app boot doğrulaması yapılmadı” açıkça belirtilmelidir.

### 7.3 Riskli değişiklikler

Runtime, SSO, DB encoding, source-order, file lifecycle, streaming, frontend asset order, Bilge Yolaç/Claude Code, security-path-download veya production-VM etkili değişikliklerde daha geniş kapı gerekir:

```sh
bash tools/ai_validate.sh full --boot-smoke
```

Ek doğrulama araçları:

```sh
Rscript tests/testthat.R
Rscript tests/scripts/smoke_app_boot.R
Rscript tests/scripts/run_post_deploy_smoke.R
Rscript tests/scripts/validation_doctor.R
Rscript tests/scripts/frontend_complexity_doctor.R
Rscript tests/scripts/maintainability_report.R
Rscript tests/scripts/seam_doctor.R
```

Yalnızca gerçekten başarıyla biten komutlar için “geçti” denir.

### 7.4 Seam/bölge sahiplik doğrulaması (yapısal)

Üretim-kritik dikiş (seam) kayıt defteri ve frontend bölge sahiplik haritası, kaynak/varlık manifestleriyle birlikte yapısal olarak doğrulanır:

```sh
bash tools/seam_doctor.sh
# veya
Rscript tests/scripts/seam_doctor.R
```

- Çıktı `SEAM_DOCTOR_RESULT: OK` ile bitmeli ve `artifacts/seam-doctor/` altına JSON artifact yazılmalıdır.
- Yapısal sahiplik bozulmuşsa (sahipsiz manifest bölümü, sahipsiz `R/` dosyası, sahipsiz `www/css|js` varlığı, bilinmeyen seam/bölge referansı) komut sıfır-dışı çıkışla biter; bu durumda dağıtım öncesi `R/config_seam_registry.R` / `R/config_ui_asset_zones.R` güncellenmelidir.
- Bu araç ağır doğrulama ÇALIŞTIRMAZ: app boot, tarayıcı smoke, VM/SSO/DB veya Türkçe encoding preflight kanıtı yerine geçmez.

### 7.5 Tarayıcı smoke zorlaması

Tarayıcısı olan ortamlar (VM/yerel) browser UX smoke'u bloklayıcı çalıştırmalıdır:

```sh
MERGEN_REQUIRE_BROWSER_UX_SMOKE=true bash tools/ai_validate.sh full --boot-smoke
```

`MERGEN_BROWSER_BIN` açıkça ayarlanmışsa require modu OTOMATİK etkinleşir: sessiz SKIP devre dışıdır ve kullanılamayan binary yolu erken ve açık hata verir. Tarayıcı bildirilen bir ortamda browser smoke artık sessizce atlanamaz.


### 7.6 VM evidence gate (güncel release kanıtı)

15 Haziran 2026 tarihli son VM evidence gate koşumu başarılıdır: `Toplam: 13 passed, 0 failed, 0 skipped`. Son artifact `artifacts/vm-evidence/20260615-130127/evidence.json` altında beklenir; genel düzen `artifacts/vm-evidence/<timestamp>/evidence.json` olarak kalır.

PowerShell external-app akışı için uygulama ayrı pencerede `http://127.0.0.1:28081` üzerinde açıkken gate şu ortamla koşturulur:

```powershell
$env:MERGEN_BROWSER_UX_BASE_URL = "http://127.0.0.1:28081"
$env:MERGEN_REQUIRE_BROWSER_UX_SMOKE = "true"
& $rscript --vanilla tests/scripts/run_vm_evidence_gate.R
```

Geçerli release kanıtı sayılması için özet satırında `Toplam: 13 passed, 0 failed, 0 skipped` görülmeli ve `browser_ux_smoke`, `vm_preflight_real`, `db_encoding_preflight`, `full_testthat` adımları `PASSED` olmalıdır.

### 7.7 Operasyonel soak / yük kapısı (dayanıklılık kanıtı)

Operasyonel soak kapısı (`tests/scripts/run_operational_soak_gate.R`) VM kanıt
kapısından **ayrıdır** ve onun yerine geçmez. VM kanıt kapısı "yapı/boot/encoding
doğru mu?" sorusunu, soak kapısı "uygulama yük altında dayanıklı mı?" sorusunu
yanıtlar. Ayrıntılar: [`docs/operational-soak-gate.md`](docs/operational-soak-gate.md).

Üç serit: **fake** (ana yüksek-eşzamanlılık, sıfır gerçek anahtar), **proxy**
(kişisel anahtar yönlendirme/izolasyon kanıtı) ve **real-canary** (tek gerçek
anahtar, çok düşük eşzamanlılık). Tek gerçek geliştirici anahtarı yalnızca
canary/proxy içindir; ana çok-kullanıcılı soak ona bağlı değildir.

Windows VM üretim launcher attach portu `8009`'dur; operasyonel soak için
`MERGEN_SOAK_APP_URL=http://127.0.0.1:8009/` kullanın. Daha önce bazı external-app
browser-smoke akışlarında görülen `28081`, üretim app soak attach hedefi değildir.
`.Renviron` değerleri aktif PowerShell `$env:MERGEN_SOAK_*` değerleriyle override
edilebilir; kontrollü deneylerde env temizliği sonrası değerleri açıkça set edin.

Hızlı fake smoke (10 aktif kullanıcı / 30 saniye):

```powershell
Remove-Item Env:MERGEN_SOAK_PROFILE,Env:MERGEN_SOAK_LLM_MODE,Env:MERGEN_SOAK_CONCURRENT_USERS,Env:MERGEN_SOAK_DURATION_SECONDS,Env:MERGEN_SOAK_CAPACITY_CURVE -ErrorAction SilentlyContinue
$env:MERGEN_SOAK_APP_URL = "http://127.0.0.1:8009/"
$env:MERGEN_SOAK_PROFILE = "smoke"
$env:MERGEN_SOAK_LLM_MODE = "fake"
$env:MERGEN_SOAK_CONCURRENT_USERS = "10"
$env:MERGEN_SOAK_DURATION_SECONDS = "30"
$env:MERGEN_SOAK_CAPACITY_CURVE = "FALSE"
Rscript tests/scripts/run_operational_soak_gate.R
```

20 kullanıcı / 5 dakika fake-lane kanıt koşumu:

```powershell
$env:MERGEN_SOAK_APP_URL = "http://127.0.0.1:8009/"
$env:MERGEN_SOAK_PROFILE = "fake_llm"
$env:MERGEN_SOAK_LLM_MODE = "fake"
$env:MERGEN_SOAK_CONCURRENT_USERS = "20"
$env:MERGEN_SOAK_DURATION_SECONDS = "300"
$env:MERGEN_SOAK_CAPACITY_CURVE = "FALSE"
Rscript tests/scripts/run_operational_soak_gate.R
```

Proxy anahtar-yönlendirme/izolasyon temiz koşumu:

```powershell
$env:MERGEN_SOAK_APP_URL = "http://127.0.0.1:8009/"
$env:MERGEN_SOAK_PROFILE = "proxy_llm"
$env:MERGEN_SOAK_LLM_MODE = "proxy"
$env:MERGEN_SOAK_CONCURRENT_USERS = "10"
$env:MERGEN_SOAK_DURATION_SECONDS = "60"
$env:MERGEN_SOAK_CAPACITY_CURVE = "FALSE"
$env:MERGEN_SOAK_PROXY_FORWARD_REAL = "FALSE"
Rscript tests/scripts/run_operational_soak_gate.R
```

Real-canary diagnostik koşumu kapasite testi değildir; gateway erişimi ve upstream
policy ayrımı içindir. Diagnostik ayrıntı `artifacts/soak/<timestamp>/real_canary_diagnostics.jsonl`
altında, özellikle `response_preview` alanında incelenir. 2026-06-18 koşumunda
real-canary upstream gateway policy `ERR-234` ile BLOCKED kalmıştır; fake/proxy soak
kanıtını geçersiz kılmaz.

Artifact'lar `artifacts/soak/<timestamp>/` altında üretilir (her zaman, başarısızlıkta
bile). Eşik **etkin başarı oranına** (`effective_success_rate`) uygulanır; bu metrik
kasıtlı enjekte edilen faultları hariç tutar, böylece beklenmeyen başarısızlıkları
ölçer. Ölçülemeyen eşikler sessizce geçmez (`UNMEASURED` / `skipped_checks`). "1.000
kullanıcı" bir kullanıcı tabanıdır; ilk ciddi aktif-eşzamanlılık hedefi 50–100'dür.
Fake/proxy/canary koşumlarından gerçek 1.000 eşzamanlı kullanıcı hazırlığı iddia
edilmez.

2026-06-19 Windows VM soak özeti: tarihsel pre-index-cache fake-lane stabil kanıt
**22 aktif eşzamanlı kullanıcı / 300 saniye PASS** idi (408/408 başarı, 0 hata,
0 timeout, `effective_success_rate=1.000`). Root-page/index caching sonrası VM
console observed en güçlü fake-lane kanıt **1000 aktif eşzamanlı kullanıcı / 420
saniye PASS** (`artifacts/soak/20260619-205535/soak_evidence.json`, p95=8377.8 ms,
throughput=7931.4/dk, 0 hata, 0 timeout) ve ayrıca **250 aktif kullanıcı / 420
saniye PASS** (`artifacts/soak/20260619-204704/soak_evidence.json`, p95=1983.8 ms)
olarak güncellendi. Bu checkout içinde yeni `artifacts/soak/...` JSON dosyaları
bulunmadığı için değerler artifact JSON ile yeniden doğrulanmalıdır. `memory_growth_mb`
ve `browser_console_errors` UNMEASURED kaldı. Bu sonuç GET-only fake/proxy soak ve
warm `GET /` index-serving iyileşmesini gösterir; 1.000 gerçek aktif insan chat
oturumu, browser UX temizliği veya gerçek upstream LLM üretim hızlanması kanıtı değildir.

2026-06-20 limit-push notu: Windows VM üzerinde `proxy_llm` / `proxy` seridinde
**1000 aktif eşzamanlı kullanıcı / 5400 saniye (90 dakika)** attach koşumu
çalıştırıldı ve **FAIL** ile bitti (`artifacts/soak/20260620-111106/soak_evidence.json`,
VM console observed): 227285 istek, 132405 başarı, 0 hata, 94880 timeout,
`effective_success_rate=0.5826` < 0.98, p95=16965.9 ms, throughput=2524.9/dk.
Anahtar yönlendirme 5/5, key isolation TRUE, upload validation 7/7, encoding
round-trip 1, secret leak 0, mojibake 0 ve server crash yoktu; ancak sonuç
kapasite/readiness PASS değildir. Aynı oturumda VM evidence gate
`artifacts/vm-evidence/20260620-104919/evidence.json` ile `Toplam: 13 passed, 0 failed, 0 skipped`
olarak geçti; bu, uzun 1000-eşzamanlı proxy soak FAIL sonucunu geçersiz kılmaz.

## 8. Dağıtım Öncesi Kapılar

1. Değişiklik türünü sınıflandırın: docs-only, UI, runtime, DB, SSO, file lifecycle, streaming, Bilge Yolaç veya deployment.
2. Uygun doğrulama seviyesini seçin.
3. `.Renviron` ve secret hygiene kontrolü yapın.
4. Windows VM üzerinde path, encoding ve kütüphane yolu beklentilerini doğrulayın.
5. Eğer `renv.lock` değişiyorsa kilidin VM'de üretildiğini ve `renv/library` commit edilmediğini doğrulayın.
6. Deployment öncesi rollback planını hazır tutun.

## 9. Dağıtım Adımları (Windows VM / SSO)

1. Repo çalışma kopyasını güncelleyin.
2. `.Renviron` dosyasını gerçek üretim değerleriyle, secret sızdırmadan doğrulayın.
3. Gerekirse paket restore/kurulum adımlarını çalıştırın.
4. Launcher self-test çalıştırın:

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools/test_mergen_prod_launcher.ps1
   ```

5. Uygulamayı başlatın:

   ```bat
   run_mergen_prod.bat
   ```

6. Logları ve sağlık panelini izleyin.
7. Post-deploy smoke testlerini tamamlayın.

## 10. Dağıtım Sonrası Smoke Testleri

- Ana sayfa açılıyor mu?
- Yerel/SSO kullanıcı kimliği beklenen şekilde çözülüyor mu?
- Türkçe karakterli kullanıcı adı, dosya adı ve mesajlar bozulmadan görünüyor mu?
- Basit sohbet isteği beklenen model/API key sınırıyla yanıtlıyor mu?
- Dosya yükleme, listeleme ve önizleme çalışıyor mu?
- Görsel anlama kullanılacaksa seçili model yeteneği ve `MERGEN_VISION_MODELS` uyumlu mu?
- Destek/Yenilikler sayfaları açılıyor mu?
- Sistem Durumu / Health paneli anlamlı sinyal veriyor mu?
- Bilge Yolaç kullanılacaksa çalışma dizini, CLI path ve güvenlik politikası beklenen şekilde mi?

Script tabanlı post-deploy smoke için:

```sh
Rscript tests/scripts/run_post_deploy_smoke.R
```

## 11. Sağlık Paneli, Loglar ve İzleme

- Health panel, dosya deposu, log dizini, runtime ve sistem sinyallerini değerlendirmek için kullanılır.
- Log dizini `.Renviron` içindeki `MERGEN_LOG_DIR` veya uygulama varsayımlarıyla belirlenir.
- Son uygulama logunu görüntülemek için `view_latest_mergen_app_log.bat` kullanılabilir.
- Loglarda secret, token, API key, auth header veya parola bulunmamalıdır.
- **Sistem Durumu > Doğrulama Kanıtı sekmesi:** Operatör, uygulamayı kapatmadan en
  son doğrulama kanıtlarını görebilir. Sekme `R/helpers_release_evidence.R` saf
  okuyucusuyla `artifacts/vm-evidence/<ts>/evidence.json` ve
  `artifacts/ai-validation/<ts>/summary.json` artifact'larının secret-safe özetini
  ve bugünkü `mergen_*.log` ERROR/WARN sayaçlarını gösterir. "Günlük Log Sağlığı"
  kartı ayrıca secret-safe iki ek özet içerir: ERROR satırlarının bağlam (context)
  kategorileri ve `log_ai_call` "AI Call: ... duration=<sn>s ... success=..."
  satırlarından çıkarılan **AI çağrı istek-süresi (latency)** özeti (çağrı sayısı,
  medyan/ortalama, en düşük/en yüksek, başarılı/başarısız). Latency özeti yalnızca
  sayısaldır; kullanıcı/model kimliği veya log içeriği taşınmaz. Varsayılan olarak en
  yeni `vm-evidence/<ts>` koşusu gösterilir; birden fazla koşu varsa zaman damgalı
  bir koşu seçici (dropdown) ile eski koşulara da bakılabilir. Yalnızca
  `passed` görünen adımlar ilgili kapsam için kanıttır; "Atlandı" (SKIP) kanıt
  değildir, "Bulunamadı" başarı sayılmaz. Sekme ham artifact yolu veya log
  içeriği göstermez (savunma derinliği); günlük log byte-safe okunur, böylece
  Windows VM'deki ANSI/`WINDOWS-1254` log baytları sekmeyi boşa düşürmez. Cloud
  profili koşumları VM/SSO/DB/SQL Server Türkçe kodlama kanıtı üretmez; bu sekme
  bunu açıkça not eder.

## 12. Geri Alma (Rollback)

1. Son bilinen iyi commit/tag/dağıtım paketini belirleyin.
2. `.Renviron` gibi ortam dosyalarının yanlışlıkla değişmediğini kontrol edin.
3. Eğer paket kilidi değiştiyse, ilgili `renv.lock` ve kütüphane durumunu birlikte geri alın.
4. Uygulamayı tekrar başlatın.
5. Smoke testlerini ve health panelini yeniden kontrol edin.
6. Rollback kanıtını tarih/saat ve çalıştırılan komutlarla kaydedin; çalıştırılmayan testler için başarı iddiasında bulunmayın.

## 13. Türkçe Kodlama / Mojibake Bakımı

- UTF-8 Markdown ve R kaynakları korunmalıdır.
- DB write/read normalizasyon helper'ları bypass edilmemelidir.
- Legacy veride mojibake görülmesi, guard'ları zayıflatma gerekçesi değildir.
- Toplu DB repair veya destructive düzeltme yalnızca bilinçli, yedekli ve kapsamı açık operasyon olarak yapılmalıdır.
- Mailto, JSON, log, file path ve tarayıcı rendering sınırlarında merkezi helper yaklaşımı korunmalıdır.
- Türkçe karakterli dosya adları ve UNC path davranışı VM üzerinde doğrulanmalıdır.

## 14. Yaygın Hatalar ve Kontrol Noktaları

| Senaryo | Kontrol et |
|---|---|
| Paket eksik | Doğru R oturumu/kütüphane yolu, `R/config_packages.R`, `renv::restore()`, `docs/dependency-locking.md`. |
| `renv.lock` karışıklığı | Kilidin GitHub/Codex kopyasında olmamasının bilinçli olabileceğini `RENV_LOCK_STATUS.md` ile doğrula. |
| Boş renv library | `.Rprofile` koşullarını, `renv/activate.R`, kilit dosyası ve kurulu `renv` paketini kontrol et. |
| Yanlış R session/library | `.libPaths()`, Windows VM R sürümü ve launcher'ın kullandığı R yolu. |
| Türkçe karakter bozulması | Encoding helper sırası, DB client/name encoding, dosya okuma/yazma sınırı, tarayıcı fallback. |
| DB bağlantı sorunu | DSN/server ayarları, network, driver, `DB_CLIENT_ENCODING`, `DB_NAME_ENCODING`. |
| API key sorunu | Kişisel anahtar, kurum varsayılan anahtar politikası, feature-specific TTS/STT anahtarları, log sızıntısı. |
| SSO/JWT sorunu | `SSO_ENABLED`, issuer/realm/client, JWKS erişimi, signature/expiry doğrulama. |
| Shiny başlangıç hatası | `run_mergen_prod.R`, `run_mergen_prod.bat`, paketler, `.Renviron`, son log. |
| Türkçe karakterli file path sorunu | UNC erişimi, safe path helper'ları, dosya deposu dizinleri. |
| UNC path / launcher sorunu | Launcher self-test, çalışma dizini, ağ paylaşımı erişimi. |
| Vision/model capability sorunu | `MERGEN_VISION_MODELS`, `MERGEN_ENABLE_VISION`, seçili modelin Image Input desteği. |
| Cloud validation sınırı | `cloud-quick` çıktısını tam VM/app boot kanıtı gibi sunma. |

## 15. Güvenli Sorun Giderme İlkeleri

- Önce gözlemle: log, health panel, validation artifact ve exact command output topla.
- Reprodüksiyon adımlarını küçük tut.
- Secrets içeren çıktı paylaşma; gerekirse redaction uygula.
- DB veya dosya deposu üzerinde destructive işlem yapmadan önce yedek ve rollback planı hazırla.
- Encoding guard'larını geçici “kolay çözüm” olarak kaldırma.
- Load-order sorunlarında manifestleri ve helper bootstrap sırasını birlikte değerlendir.
- Kanıt dürüstlüğü koru: çalıştırılmayan test için başarı iddia etme.

## 16. Ne Yapılmamalı?

- Linux/cloud/Codex ortamında `renv.lock` üretmeyin.
- `renv::init()` ile `.Rprofile`'ı ezmeyin.
- `renv/library`, cache, staging veya sandbox dizinlerini commit etmeyin.
- Secrets, API keys, token'lar, parolalar, gerçek DSN'ler veya private endpoint'leri dokümantasyona/loglara eklemeyin.
- DB'ye körlemesine UTF-8 yazmaya zorlamayın; merkezi DB encoding helper sınırını kullanın.
- Destructive DB repair işlemini günlük troubleshooting gibi çalıştırmayın.
- Legacy veri kirli diye mojibake guard'larını zayıflatmayın.
- Yalnızca `cloud-quick` çalıştıysa tam doğrulama veya app boot geçti demeyin.
- Dokümantasyon-only görevde runtime davranışı değiştirmeyin.

## 17. İlgili Belgeler

- İlk giriş: [`README.md`](README.md)
- Kodlama ajanı sözleşmesi: [`CLAUDE.md`](CLAUDE.md)
- Ajan özeti: [`AGENTS.md`](AGENTS.md)
- Mimari harita: [`docs/architecture-map.md`](docs/architecture-map.md)
- Bağımlılık kilitleme: [`docs/dependency-locking.md`](docs/dependency-locking.md)
- On-prem kilit durumu: [`RENV_LOCK_STATUS.md`](RENV_LOCK_STATUS.md)
- Değişiklik notları: [`docs/release-notes.md`](docs/release-notes.md)
- Dokümantasyon hub'ı: [`docs/README.md`](docs/README.md)

---

## Ek: Önceki Runbook'tan Korunan Operasyonel Notlar

Aşağıdaki bölüm önceki runbook'un ana operasyonel ruhunu korumak için bırakılmıştır; yukarıdaki yapı kanonik navigasyondur.


# MERGEN Bilge - Üretim Operasyon Kılavuzu (RUNBOOK)

Bu dosya, MERGEN Bilge'nin Windows VM / SSO üretim profilinde **dağıtım, doğrulama,
izleme, olay müdahalesi ve geri alma** adımlarını tek bir operatör kaynağında toplar.

Amaç: doğrulama betikleri ve operasyonel bilgi `CLAUDE.md` ile çok sayıda script
arasına dağılmış durumda. Bu kılavuz, bir dağıtım sırasında hangi kapının ne
kanıtladığını ve hangi adımın hangi sırayla yapılacağını net biçimde gösterir.

> Kanıt dürüstlüğü ilkesi: Bu kılavuzdaki hiçbir komut "tam doğrulama yapıldı"
> demek için kullanılamaz. Her kapı yalnızca kendi kapsamını kanıtlar. Bkz.
> [Kanıt Sınırları](#7-kanıt-sınırları-ne-neyi-kanıtlar).

---

## 0. Hızlı Referans

| Aşama | Komut / Eylem | Ortam |
|------|----------------|-------|
| Bulut/parse doğrulaması | `bash tools/ai_validate.sh cloud-quick` | Codex/bulut |
| Normal doğrulama | `bash tools/ai_validate.sh quick` | Yerel/CI |
| Riskli/runtime doğrulaması | `bash tools/ai_validate.sh full --boot-smoke` | Yerel/VM |
| **Tek kanıt kapısı (önerilen)** | `bash tools/vm_evidence_gate.sh` | Yerel/VM (profil otomatik) |
| Üretim adayı kapısı | `Rscript tests/scripts/run_release_candidate_gate.R` | Yerel/VM |
| VM gerçek preflight | `Rscript tests/scripts/run_vm_preflight_real.R` | VM (SSO açık) |
| VM Türkçe kodlama preflight | `Rscript tests/scripts/run_vm_encoding_preflight_real.R` | VM (DB erişimli) |
| Dağıtım | `C:\MergenLauncher\start_mergen_prod.bat` | VM |
| Dağıtım sonrası duman testi | `Rscript tests/scripts/run_post_deploy_smoke.R` | VM (uygulama ayakta) |
| Canlı log izleme | `view_latest_mergen_app_log.bat` | VM |
| Sağlık paneli | Uygulama içi "Sistem Durumu" | Tarayıcı |

---

## 1. Dağıtım Öncesi Doğrulama Kapıları (sıra önemlidir)

Aşağıdaki kapılar **artan güven** sırasıyla çalıştırılır. Bir önceki kapı
geçmeden bir sonrakine geçmeyin.

1. **Parse / sözleşme (bulut güvenli):** `bash tools/ai_validate.sh cloud-quick`
   - Kanıtlar: parse sanity + odak sözleşme testleri.
   - Kanıtlamaz: app source smoke, runtime boot, tarayıcı, VM/SSO/DB, SQL Server Türkçe kodlama.

2. **Normal doğrulama:** `bash tools/ai_validate.sh quick`
   - Tam bağımlılıkların kurulabildiği yerel/CI ortamında çalıştırılır.

3. **Riskli/runtime doğrulaması (kod, kaynak sırası, SSO, DB, streaming değişiklikleri):**
   `bash tools/ai_validate.sh full --boot-smoke`
   - Shiny boot smoke; yerel tarayıcı varsa UX smoke fırsatçı çalışır.
   - Tarayıcı zorunluluğu için: `MERGEN_REQUIRE_BROWSER_UX_SMOKE=true bash tools/ai_validate.sh full --boot-smoke`.

4. **VM gerçek preflight (üretim profili):** `Rscript tests/scripts/run_vm_preflight_real.R`
   - `MERGEN_PREFLIGHT_REQUIRE_SSO=TRUE` varsayılandır; `SSO_ENABLED=TRUE` değilse başarısız olur.
   - Zorunlu env: `LOCAL_LLM_ENDPOINT`, `DB_DSN`, `AI_KEYS_MASTER`; SSO açıkken ayrıca `SSO_KEYCLOAK_URL`.
   - Çıkarken değiştirdiği env değişkenlerini geri yükler.

5. **VM Türkçe kodlama preflight (DB yazma sınırı):**
   ```bat
   set MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST=TRUE
   set MERGEN_PREFLIGHT_FAIL_ON_LEGACY_MOJIBAKE=FALSE
   Rscript tests/scripts/run_vm_encoding_preflight_real.R
   ```
   - Transactional yeni-yazım probu yapar ve geri sarar (rollback).
   - Eski (legacy) mojibake satırları varsayılan olarak yalnızca uyarıdır; yeni yazım regresyonu kesin kapıdır.

6. **Üretim adayı kapısı:** `Rscript tests/scripts/run_release_candidate_gate.R`
   - Önce yerel hardening kapısını (`run_hardening_gate_local.R`) çalıştırır.
   - Ardından maintainability skorunu minimum eşikle doğrular (`MERGEN_MIN_MAINTAINABILITY_SCORE`).

Manuel ama zorunlu: kırılgan akışlar için
`Rscript tests/scripts/run_fragile_flow_manual_preflight.R` ile akış kontrol listesini
kaydedin (streaming start/stop, yükleme kalıcılığı, kayıtlı söyleşi TTS, Türkçe dosya adı, TTS/STT/müzik).

### 1A. Tek tekrarlanabilir kanıt kapısı: `run_vm_evidence_gate.R`

Yukarıdaki kapıları tek bir tekrarlanabilir koşumda toplayan ve secret-güvenli,
makinece okunabilir kanıt artifact'ı üreten kapı `tests/scripts/run_vm_evidence_gate.R`
betiğidir. Wrapper olarak `bash tools/vm_evidence_gate.sh` kullanılabilir; Windows VM
operasyonu için normal tam koşum repo kökünden doğrudan Rscript ile çalıştırılır.

#### Milestone: tam Windows VM evidence gate geçti

2026-06-12 tarihinde Windows VM üzerinde tam evidence gate milestone'u kaydedildi; son başarılı yeniden doğrulama 2026-06-15 tarihinde alındı:

- `Toplam: 13 passed, 0 failed, 0 skipped`
- `full_testthat PASSED` — tam izole testthat suite geçti.
- `browser_ux_smoke PASSED` — mandatory browser proof gerçek tarayıcıda `UX_SMOKE_DONE:PASS` üretti.
- `vm_preflight_real PASSED` — VM/SSO/DB/LLM üretim-benzeri preflight geçti.
- `db_encoding_preflight PASSED` — transactional Türkçe DB encoding preflight geçti.
- Başarılı koşum örneği: `artifacts/vm-evidence/20260615-130127/evidence.json`.

Bu, MERGEN Bilge'nin on-prem Windows VM readiness/release doğrulaması için önemli bir
kilometre taşıdır. Kanıt kapısı yalnızca `evidence.json` içinde `passed` görünen adımlar
için kanıt sağlar; uzun süreli saha yükü, manuel kırılgan-akış QA'sı veya eski legacy DB
satırlarının temizliği gibi kapsamları otomatik olarak kanıtlamaz.

#### Standart tam evidence gate komutu

Repo kökünden tüm yapılandırılmış evidence adımlarını çalıştırmak için:

```powershell
$repo = "U:\Primavera\PYB\04 - Geliştirme\MERGEN Bilge"
Set-Location $repo

$rscript = "C:\Program Files\R\R-4.6.0\bin\Rscript.exe"
if (!(Test-Path $rscript)) { $rscript = "C:\Program Files\R\R-4.6.0\bin\x64\Rscript.exe" }

Remove-Item Env:\MERGEN_EVIDENCE_STEPS -ErrorAction SilentlyContinue

& $rscript --vanilla tests/scripts/run_vm_evidence_gate.R
```

Bu komut tüm yapılandırılmış evidence adımlarını çalıştırır. Browser UX smoke zorunlu
değilse ve ortam tarayıcı kanıtı üretemiyorsa yapılandırmaya bağlı olarak gerekçeli SKIP
olabilir. Mandatory browser proof için aşağıdaki external-app workflow kullanılmalıdır.

Kanıt artifact'ı her koşumda `artifacts/vm-evidence/<timestamp>/evidence.json` ve aynı
dizin altında adım logları olarak yazılır. Adımlar temiz çocuk R oturumlarında koşulur;
ham secret, DSN, endpoint, token veya key değerleri artifact/log içine yazılmamalıdır.
Kapsam: `env_config`, `parse_sanity`, `app_boot_smoke`, `full_testthat`,
`maintainability_report`, `frontend_ratchet`, `seam_doctor`,
`source_manifest_contracts`, `ui_asset_manifest_contracts`, `browser_ux_smoke`,
`vm_preflight_real`, `db_encoding_preflight`, `renv_status`.

#### Mandatory browser UX smoke: external-app iki-pencere workflow

Kilitli Windows/VDI ortamlarında mandatory browser proof için VM-stable önerilen akış,
uygulamayı ayrı bir PowerShell penceresinde açık tutup evidence gate'e çalışan app URL'ini
vermektir.

**Window 1 — app'i başlatın ve açık bırakın:**

```powershell
$repo = "U:\Primavera\PYB\04 - Geliştirme\MERGEN Bilge"
Set-Location $repo

$rscript = "C:\Program Files\R\R-4.6.0\bin\Rscript.exe"
if (!(Test-Path $rscript)) { $rscript = "C:\Program Files\R\R-4.6.0\bin\x64\Rscript.exe" }

& $rscript -e "if (file.exists('.Renviron')) readRenviron('.Renviron'); Sys.setenv(MERGEN_RUN_APP='false', MERGEN_DISABLE_FUTURES='true', TZ='UTC'); cat('START_APP_BOOT_TEST\n'); source('app.R', encoding='UTF-8'); cat('SOURCE_OK\n'); run_mergen_app(host='127.0.0.1', port=28081L, launch.browser=FALSE, quiet=FALSE)"
```

Beklenen:

- Pencere açık kalır.
- App `http://127.0.0.1:28081` üzerinde dinler.
- Smoke sayfası `http://127.0.0.1:28081/smoke/ux-smoke.html` olur.

**Window 2 — mandatory browser proof ile tam evidence gate'i çalıştırın:**

```powershell
$repo = "U:\Primavera\PYB\04 - Geliştirme\MERGEN Bilge"
Set-Location $repo

$rscript = "C:\Program Files\R\R-4.6.0\bin\Rscript.exe"
if (!(Test-Path $rscript)) { $rscript = "C:\Program Files\R\R-4.6.0\bin\x64\Rscript.exe" }

Remove-Item Env:\MERGEN_EVIDENCE_STEPS -ErrorAction SilentlyContinue

$env:MERGEN_BROWSER_UX_BASE_URL = "http://127.0.0.1:28081"
$env:MERGEN_REQUIRE_BROWSER_UX_SMOKE = "true"

& $rscript --vanilla tests/scripts/run_vm_evidence_gate.R

Remove-Item Env:\MERGEN_BROWSER_UX_BASE_URL -ErrorAction SilentlyContinue
Remove-Item Env:\MERGEN_REQUIRE_BROWSER_UX_SMOKE -ErrorAction SilentlyContinue
```

- `MERGEN_BROWSER_UX_BASE_URL`, `ai_browser_ux_smoke.R` betiğine kendi geçici Shiny
  child process'ini başlatmak yerine zaten çalışan app'i test etmesini söyler.
- `MERGEN_REQUIRE_BROWSER_UX_SMOKE=true`, browser UX smoke'u bloklayıcı yapar.
- Window 1'deki app evidence gate bitene kadar açık kalmalıdır.
- Koşum bitince Window 1'de app'i `Ctrl+C` ile durdurun.

#### Browser smoke davranışı

- Varsayılan durumda browser UX smoke opsiyonel/non-blocking olabilir.
- `MERGEN_REQUIRE_BROWSER_UX_SMOKE=true` ile bloklayıcıdır ve `UX_SMOKE_DONE:PASS`
  üretmelidir.
- `MERGEN_BROWSER_UX_BASE_URL` set edilmişse o base URL'de app önceden çalışıyor olmalıdır.
- Elle çalışan background app normalde gerekli değildir; ancak kilitli Windows/VDI
  ortamlarında mandatory browser proof için önerilen VM-stable workflow budur.
- `MERGEN_BROWSER_BIN` açıkça tanımlıysa require modu otomatik etkinleşir; kullanılamayan
  binary yolu erken hata verir.

#### Full isolated testthat davranışı

`full_testthat`, `tests/scripts/run_full_testthat_isolated.R` betiğini kullanır. Bu betik
`tests/testthat/test-*.R` dosyalarını alfabetik sıralı liste üzerinden tek tek temiz
`Rscript --vanilla` çocuk süreçlerinde çalıştırır.

- RStudio console testthat koşumundan daha yavaştır.
- Daha güvenilirdir; sıcak RStudio oturumunun gizleyebileceği eksik per-test bağımlılıkları yakalar.
- Bu milestone sırasında bir dizi isolated-test dependency sorunu giderildi.

Hata sonrası devamı hızlandırmak için aralık koşumu kullanılabilir; indexler alfabetik
sıralanmış `tests/testthat/test-*.R` dosya listesine göre hesaplanır:

```powershell
$env:MERGEN_TESTTHAT_START_INDEX = "243"
$env:MERGEN_TESTTHAT_END_INDEX = "441"

& $rscript --vanilla tests/scripts/run_full_testthat_isolated.R

Remove-Item Env:\MERGEN_TESTTHAT_START_INDEX -ErrorAction SilentlyContinue
Remove-Item Env:\MERGEN_TESTTHAT_END_INDEX -ErrorAction SilentlyContinue
```

#### Milestone sırasında doğrulanan önemli düzeltmeler

- Health runtime/tab UI isolated testleri gerekli health table helper'larını source eder.
- LLM worker tool-result isolated testleri formatter'dan önce preview-dataframe helper'ını source eder.
- `run_full_testthat_isolated.R`, hata sonrası hızlı devam için start/end index aralıklarını destekler.
- Browser UX smoke, `MERGEN_BROWSER_UX_BASE_URL` ile external app modunu destekler.
- Browser UX smoke, `MERGEN_REQUIRE_BROWSER_UX_SMOKE` değerine göre opsiyonel veya bloklayıcıdır.
- Full testthat çocuk süreçleri browser UX evidence-gating environment leakage'a karşı korunur.
- VM preflight path handling, Türkçe karakterli ve boşluklu Windows mapped-drive / UNC-style path'ler için sertleştirildi.
- Evidence gate logları ve artifact'ları `artifacts/vm-evidence/<timestamp>/` altında kalır.

#### Troubleshooting / gotchas

- `testthat` eksikse gate'in kullandığı aynı Rscript için paketlerin kurulu/restored olduğundan emin olun.
- Relative test path yok diyorsa PowerShell'in repo kökünde olduğunu doğrulayın.
- External browser smoke “Could not connect to server” diyorsa Window 1'deki app gerçekten çalışmıyordur.
- App boot eksik env var nedeniyle düşerse `.Renviron` yüklendiğini veya şu değişkenlerin tanımlı olduğunu kontrol edin: `LOCAL_LLM_ENDPOINT`, `DB_DSN`, `AI_KEYS_MASTER`.
- Tam gate amaçlanıyorsa `MERGEN_EVIDENCE_STEPS` set edilmiş bırakılmamalıdır.
- `MERGEN_REQUIRE_BROWSER_UX_SMOKE=true` değişkenini niyetli değilseniz ad-hoc testthat koşumlarına sızdırmayın.

Yapısal sözleşme: `tests/testthat/test-vm-evidence-gate-contract.R` (adım listesi,
secret-güvenlik, çocuk-oturum izolasyonu, quit() yasağı). Bu kapı mevcut kapıların yerine
geçmez; onları tek artifact'ta birleştirir. Manuel kırılgan-akış kontrol listesi ayrı
bir kanıt kapısı olarak kalır.

---

## 2. Dağıtım Adımları (Windows VM / SSO)

1. **Kaynağı güncelle:** üretim app klasöründe hedef sürüme geç
   (`git fetch`, ardından doğrulanmış etiket/commit'e `git checkout`).
2. **`.Renviron` doğrula:** en az şunlar tanımlı olmalı:
   - `MERGEN_PORT=8009`, `MERGEN_HOST=0.0.0.0`, `SSO_ENABLED=TRUE`
   - `LOCAL_LLM_ENDPOINT`, `DB_DSN`, `AI_KEYS_MASTER`, `SSO_KEYCLOAK_URL`
   - `DB_CLIENT_ENCODING=WINDOWS-1254` ve `DB_NAME_ENCODING=WINDOWS-1254`
3. **Tam R sürecini yeniden başlat:** kodlama değişkenleri için tarayıcı yenilemesi yetmez,
   R süreci yeniden başlatılmalıdır.
4. **Başlat:** masaüstü kısayolu `C:\MergenLauncher\start_mergen_prod.bat` hedefler.
   Bu yerel başlatıcı, `\\rehisds\uygulamalar` UNC yolunu geçici bir sürücü harfine
   eşler ve uygulama klasöründeki `run_mergen_prod.bat` -> `run_mergen_prod.R`
   zincirini çağırır.
   - UNC yolundaki BAT'ı doğrudan kısayola koymayın; `cmd.exe` UNC'yi geçerli dizin
     olarak güvenilir kullanamaz.
5. **Başlangıç tanılaması:** sorun olursa launcher konsolu ve
   `logs/run_mergen_prod_console.log` (Rscript, paket preflight, boot, stdout/stderr) incelenir.

Doğrulama: launcher self-testi (uygulamayı BAŞLATMADAN ortamı kontrol eder)
`C:\MergenLauncher\test_mergen_prod_launcher.bat`; beklenen sonuç `[RESULT] PASSED`.

---

## 3. Dağıtım Sonrası Duman Testi (NEW)

Uygulama ayağa kalktıktan sonra **gerçekten hizmet verip vermediğini** doğrulayın.

1. **Otomatik sağlık kapısı:**
   ```bat
   Rscript tests/scripts/run_post_deploy_smoke.R
   ```
   - Sağlık kontrollerini (`health_collect_checks()`) toplar ve
     `mergen_post_deploy_smoke_evaluate()` ile genel durumu hesaplar.
   - `critical` durumda kritik bir kontrol varsa süreç **sıfırdan farklı** çıkış kodu döndürür.
   - Sırları redakte ederek özet basar; ham DSN/anahtar/token yazmaz.
   - Yapılandırma: `MERGEN_SMOKE_CRITICAL_IDS` (virgülle), `MERGEN_SMOKE_FAIL_ON_UNKNOWN=TRUE/FALSE`.
2. **Tarayıcı duman testi:** uygulama köküyle aynı origin üzerinden `/smoke/ux-smoke.html`
   açın; beklenen sonuç `UX_SMOKE_DONE:PASS`. SSO/Keycloak login route'u üzerinden ÇAPRAZ
   origin ile açmayın.
3. **Sağlık paneli:** "Sistem Durumu" sayfasında DB, LLM, depolama, SSO satırlarının
   yeşil/uygun olduğunu görsel doğrulayın.
4. **Türkçe akış kontrolü:** bir sohbet açıp `Türkçe test: ç ğ ı İ ö ş ü` yazın;
   yeni yanıt akışı, kayıt/yeniden yükleme ve SSMS'te temiz satır oluştuğunu doğrulayın.

---

## 4. İzleme ve Olay Müdahalesi

- **Canlı log:** `view_latest_mergen_app_log.bat` en yeni `logs/mergen_YYYYMMDD.log`
  dosyasını salt-okunur izler (uygulamayı durdurmaz).
- **Başlangıç tanılaması:** `logs/run_mergen_prod_console.log`.
- **Yapılandırılmış hata kaydı:** runtime hataları artık tek satır halinde
  `[RUNTIME_ERROR]` etiketiyle (bağlam + redakte edilmiş mesaj + hata sınıfı + zaman damgası)
  loglanır. Olay incelemesinde önce bu satırları arayın.
- **Sağlık paneli triyajı:**
  - `critical` DB/LLM -> servis/endpoint erişimini ve `.Renviron` değerlerini kontrol et.
  - `critical` depolama -> disk boş alanı ve `MERGEN_FILES_ROOT`/`MERGEN_INDEX_PATH` yazılabilirliği.
  - `unknown`/`not_configured` -> opsiyonel entegrasyon; çoğu durumda bloklamaz.
- **Sır güvenliği:** loglarda ham anahtar/token/parola/DSN görürseniz bunu bir güvenlik
  olayı olarak ele alın; redaksiyon `R/utils_log_redact.R` üzerinden merkezîdir.

---

## 5. Geri Alma (Rollback)

Bir dağıtım üretimi bozarsa:

1. **Kararlı sürüme dön:** üretim app klasöründe bilinen iyi etiket/commit'e
   `git checkout <onceki-stabil>` yapın (kod geri alma).
2. **`.Renviron` koru:** kodlama ve SSO değişkenleri (özellikle
   `DB_CLIENT_ENCODING=WINDOWS-1254`) değişmeden kalmalıdır.
3. **Tam R sürecini yeniden başlat** ve `start_mergen_prod.bat` ile yeniden başlatın.
4. **Doğrula:** [Dağıtım Sonrası Duman Testi](#3-dağıtım-sonrası-duman-testi-new) adımlarını tekrarlayın.
5. **DB notu:** rollback yalnızca uygulama kodunu geri alır. Eski mojibake satırları
   otomatik düzeltilmez; veri onarımı ayrı ve yedek onaylı bir süreçtir (Bölüm 6).

---

## 6. Türkçe Kodlama / Mojibake Bakımı

Yeni yazım regresyonu ile geçmiş (legacy) bozuk satırlar **ayrı konulardır**.

- **Yeni yazımlar** post-insert guard ile korunur; `MessageContent`/`ReasoningContent`
  içinde mojibake tespit edilirse işlem geri sarılır. Bu davranışı zayıflatmayın.
- **Eski bozuk satırlar** için tek seferlik onarım planı:
  1. **DB yedeği alın** (zorunlu).
  2. Önce **kuru çalıştırma**:
     ```bat
     set MERGEN_REPAIR_MOJIBAKE_APPLY=FALSE
     Rscript tests/scripts/repair_mb_messages_mojibake.R
     ```
     Çıktıyı (`DRY_RUN`) inceleyin.
  3. Yalnızca yedek + onay sonrası uygulama:
     ```bat
     set MERGEN_REPAIR_MOJIBAKE_APPLY=TRUE
     Rscript tests/scripts/repair_mb_messages_mojibake.R
     ```
  - Bu betik `source(...)` ile güvenli çalışır, `quit()` çağırmaz ve garanti migrasyon değildir.
- **Başlangıçta otomatik migrasyon ÇALIŞTIRMAYIN.**

SSMS doğrulaması: en yeni `MB_Messages`, `MB_Chats.ChatTitle`, `MB_Feedback` satırlarında
`Ã§`, `Ä±`, `Ã¶`, `ÅŸ`, `ÄŸ`, `TÃ¼rkiye`, `NasÄ±l`, `yardÄ±mcÄ±` gibi yeni mojibake görülürse
dağıtımı reddedin.

---

## 7. Kanıt Sınırları (ne neyi kanıtlar)

| Kanıt kaynağı | Kanıtlar | KANITLAMAZ |
|---------------|----------|------------|
| `cloud-quick` | parse sanity + odak sözleşme testleri | app boot, tarayıcı, VM/SSO/DB, SQL Server Türkçe kodlama |
| `quick` | yerel testthat + app source smoke | tarayıcı UX, VM/SSO, gerçek DB/LLM |
| `full --boot-smoke` | Shiny boot smoke (+ varsa tarayıcı smoke) | gerçek VM/SSO/DB üretim yükü |
| `run_vm_preflight_real.R` | VM/SSO kimliği, DB sağlığı, yazılabilir yollar, LLM erişimi | uzun süreli üretim yükü, tarayıcı UX |
| `run_vm_encoding_preflight_real.R` | transactional yeni Türkçe yazım/okuma/rollback | eski legacy satırların temizliği |
| `run_post_deploy_smoke.R` | çalışan uygulamanın hizmet sağlık durumu | UX akış doğruluğu, uzun süreli kararlılık |
| `validation_doctor` | yalnızca rehberlik/sınıflandırma | HİÇBİR yürütme kanıtı (gate değildir) |
| `artifacts/ai-validation/<ts>/summary.json` | yalnızca "ran" diyen alanlar için yürütme kanıtı | alanların "passed" demediği hiçbir kapsam |

Kural: bir alan açıkça `passed` demeden "tam doğrulama", "app boot edildi", "tarayıcı UX",
"VM/SSO/DB" veya "SQL Server Türkçe kodlama" kanıtı olduğunu iddia etmeyin.

---

## 8. Üretim Olgunluğu Notu

Otomatik kapılar güçlüdür, ancak **üretim olgunluğunun** bir bölümü yalnızca zamanla
kazanılır: gerçek kullanıcı yükü, eşzamanlılık, olay-ve-kurtarma geçmişi. Bu kılavuz
operasyonel olgunluğu (tekrarlanabilir dağıtım, dağıtım sonrası doğrulama, geri alma,
izlenebilir hatalar) artırır; ancak hiçbir commit "saha denenmişliği" üretemez.

---

## 9. Claude Code Web Oturumları (Bulut R Ortamı)

Claude Code'un web/bulut oturumlarında testleri çalıştırabilmesi için R çalışma
zamanı oturum başında kurulur. Bu, **üretim VM'i değildir**; yalnızca ajan
doğrulaması (parse + testthat) için izole bir bulut ortamıdır.

**Bir kez yapılacak bulut ayarları** (Claude Code web → "Update cloud environment"
→ `MERGEN-Bilge` ortamı). Değişiklikler **sonraki** oturumda (önbellek yeniden
oluşturulurken) devreye girer, çalışan oturumu etkilemez:

1. **Network access → Custom**: `packagemanager.posit.co` ve `cloud.r-project.org`
   ekleyin; "ortak paket yöneticileri varsayılan listesi" işaretli kalsın. R
   varsayılan Trusted listesinde yoktur → bu olmadan paket depoları HTTP 403 döner.
2. **Setup script** alanı: `bash tools/setup_ai_r_environment.sh`. Kurulum bir kez
   çalışır ve dosya sistemi anlık görüntüsü (snapshot) önbelleğe alınır; sonraki
   oturumlar yeniden kurmaz. (Paket kurulumu jeton/token harcamaz; testler yalnızca
   açıkça veya değişiklik varsa `Stop` hook ile çalışır, her komutta değil.)

**Repo tarafı parçalar** (commit'li): `.claude/hooks/session-start.sh` (SessionStart
hook, env değişkenlerini yazar + idempotent kurulum çağrısı) ve
`tools/setup_ai_r_environment.sh` (tek kurucu; paket listesini
`R/config_packages.R`'den okur).

**R sürüm uyumu:** kurucu varsayılan olarak en güncel R'yi CRAN apt deposundan
kurar (on-prem VM ile uyum; şu an R 4.5.1). Erişilemezse dağıtım `r-base`'ine geri
düşer. Sabitlemek için `MERGEN_AI_INSTALL_LATEST_R=false`.

**Kanıt sınırı:** bir bulut oturumunun geçmesi yalnızca parse + sözleşme/birim test
kapsamını kanıtlar; runtime/VM/SSO/DB ve SQL Server Türkçe kodlama hâlâ bu kılavuzun
1-3. bölümlerindeki VM kapılarıyla doğrulanmalıdır. Ayrıntılı operatör notları:
`.claude/web-environment.md`.

## 10. Bağımlılık Kilitleme (renv)

MERGEN Bilge, kesin paket sürümlerini `renv.lock` ile sabitler. **`renv.lock`
ÇALIŞAN Windows VM'inizden (R 4.6.0 + güncel kütüphane) üretilmelidir;**
Linux/bulut ortamında ÜRETMEYİN.

- İnsan-okunur manifest: `R/config_packages.R` (açılış doğrulaması korunur).
- Kesin sürüm kaynağı: `renv.lock`.
- Otomatik yükleyici: kök `.Rprofile` → `renv/activate.R` (yalnızca kilit + renv
  varsa etkinleşir; offline/üretim güvenli).

**Windows VM'de ilk kilit (repo kökünde, R 4.6.0):**

```r
install.packages("renv")          # bir kez
# renv::init() ÇAĞIRMAYIN — .Rprofile'ı ezer.
```

```bat
Rscript tools/renv_snapshot.R     :: renv.lock üretir (global kütüphaneden)
Rscript -e "renv::restore(prompt = FALSE)"   :: temiz ortamda doğrula (önerilir)
Rscript tests/testthat.R          :: testler
```

Sonra R oturumunu yeniden başlatın ve `renv.lock`'u commit edin (`renv/library`
ASLA commit edilmez). Paket yükseltmesinden sonra kilidi `tools/renv_snapshot.R`
ile yeniden üretin. Tam rehber ve kontrol listesi: **`docs/dependency-locking.md`**.

CI/AI önyükleme: `tests/scripts/ci_install_packages.R`, `renv.lock` varsa
`renv::restore()` tercih eder; yoksa mevcut RSPM/CRAN akışına geri düşer.
