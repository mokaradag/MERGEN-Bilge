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
