# Operasyonel Soak / Yük Test Kapısı

Bu belge, MERGEN Bilge için **operasyonel soak/yük testi kapısının** (Operational
Soak Gate) tasarımını, çalıştırma yöntemlerini, ürettiği kanıtı ve kanıt
sınırlarını açıklar. Hedef: uygulamanın operasyonel kırılganlığını **kullanıcılar
fark etmeden önce** keşfetmektir.

Bu kapı, Windows VM kanıt kapısının (`tests/scripts/run_vm_evidence_gate.R`)
**yerine geçmez**; ondan ayrı, tamamlayıcı bir kapıdır. VM kanıt kapısı
"yapı/sözleşme/boot/encoding doğru mu?" sorusunu, soak kapısı ise "uygulama yük
altında dayanıklı mı?" sorusunu yanıtlar.

İlgili dosyalar:

- Ana giriş: `tests/scripts/run_operational_soak_gate.R`
- Yardımcı modüller: `tests/scripts/soak_config.R`, `soak_metrics.R`,
  `soak_scenarios.R`, `soak_client.R`, `soak_interactive_lane.R`,
  `soak_artifacts.R`, `soak_secret_redaction.R`, `mock_llm_server.R`,
  `proxy_llm_server.R`
- Sözleşme testi: `tests/testthat/test-operational-soak-gate-contract.R`

---

## 1. Neden sahte (fake) LLM ve tek gerçek anahtar yalnız canary?

Geliştirme sırasında test için **yalnızca bir gerçek LLM API anahtarı**
bulunabilir. Bu, üretimde tek kurumsal anahtar olduğu anlamına **gelmez**:
gerçek kullanımda bazı kullanıcılar kendi kişisel anahtarlarını sağlar,
kişisel anahtarı olmayanlar ise politikaya göre varsayılan kurumsal anahtara
düşebilir.

Bu nedenle ana çok-kullanıcılı soak testi **tek gerçek anahtara bağlı olmamalıdır**:

- Tek gerçek anahtar, app-seviyesi soak'un **darboğazı** olmamalıdır.
- Gerçek sağlayıcıya yüzlerce eşzamanlı istek göndermek hem maliyetli hem de
  yanıltıcıdır (gerçek sağlayıcının throughput'u, MERGEN'in dayanıklılığını
  ölçmez).

Çözüm: **üç serit (lane)** mimarisi.

---

## 2. Üç serit (lane)

### Lane A — Fake LLM (ana yüksek-eşzamanlılık seridi)

- Yerel, OpenAI-uyumlu **sahte** LLM endpoint'i (`mock_llm_server.R`, `httpuv`).
- **SIFIR gerçek anahtar** kullanır.
- Ana yük seridi: Shiny oturumları, akış (streaming) UI, DB yazımları, dosya
  yaşam döngüsü, temp temizliği, futures/promises, encoding ve istek
  sonlandırmasını gerçek bir LLM sağlayıcısına ihtiyaç duymadan zorlar.
- Hata enjeksiyonu destekler: normal, slow, timeout, http500, http429, malformed,
  empty, interrupted-stream, long, markdown, code, table, turkish.
- Tek thread'li `httpuv` event loop'unda **bloklamayan** gecikme (`promises` +
  `later`) ile **gerçek eşzamanlılık** sağlar.

### Lane B — Proxy (kişisel anahtar yönlendirme/izolasyon kanıtı)

- Yerel proxy endpoint'i (`proxy_llm_server.R`).
- Çok sayıda **sahte kişisel anahtar** simüle eder: `sk-test-user001`,
  `sk-test-user002`, ...
- Her isteği **ham anahtar loglamadan** takma ad (pseudonym) ile kaydeder:
  kullanıcı/anahtar takma adı, kaynak (`personal` / `default` / `missing`),
  gecikme, model, durum.
- Varsayılan olarak **sahte yanıt** döner; opsiyonel olarak çok küçük, throttle'lı
  bir alt kümeyi tek gerçek anahtarla gerçek endpoint'e iletebilir.
- Kanıt: kullanıcı başına anahtar izolasyonu (1:1 eşleme), oturumlar arası anahtar
  sızmaması, ham anahtar artifact'a yazılmaması.

### Lane C — Real-canary (gerçek endpoint canary)

- Gerçek LLM endpoint'i, tek gerçek anahtar.
- **Çok düşük** eşzamanlılık (varsayılan 2–5 kullanıcı), pace'li (aralıklı) istek.
- Amaç: MERGEN'in üretim VM koşullarında gerçek LLM endpoint'iyle hâlâ
  konuşabildiğini doğrulamak.
- **50/100 kullanıcı throughput'unu tahmin etmek için KULLANILMAZ.**

### Lane D — Interactive (in-process etkileşimli oturum)

GET-only HTTP seridi (Lane A'nın uygulama-kök yükü) yalnızca tek-thread'li
`httpuv` index sayfası servisini ölçer; **sohbet/DB/streaming/stop yollarını
açmaz**. Etkileşimli serit bu boşluğu kapatır.

- `tests/scripts/soak_interactive_lane.R`; ana yük seridinden ayrı çalışır ve
  varsayılan AÇIK'tır (`MERGEN_SOAK_INTERACTIVE_LANE=true`).
- **Gerçek** uygulama yardımcılarını ve **işlem-güvenli DB havuzunu**
  (`R/helpers_db_pool.R`) **gerçek bir DBI arka ucuna** (RSQLite, geçici dosya)
  karşı çalıştırır; havuzu `init_db_pool_once(force = TRUE)` ile zorlar.
- Her "oturum" sohbet-benzeri bir eylem dizisi yürütür: oturum açma + anahtar
  izolasyonu, sohbet oluşturma (`with_db_transaction` INSERT), kullanıcı mesajı
  kaydetme, gerçek streaming-delta sınıflandırma
  (`mergen_stream_classify_poll_lines`), asistan mesajı kaydetme, stop/iptal
  kararı (`mergen_stream_abort_cleanup_plan`) + niyetli işlem ROLLBACK
  doğrulaması, küçük dosya yükleme doğrulaması (`validate_uploaded_file`),
  **gerçek dosya alım hattı** (`file_ingestion_plan_batch` +
  `file_ingestion_execute_batch`: iki dosyalık parti, gerçek kopyalama, bütünlük
  denetimi ve `user_<id>` kovası izolasyonu), kullanıcı-kapsamlı kayıtlı/geçmiş
  okuma ve oturum kapatma.
- Ölçülenler: eylem başarı oranı, p50/p95/p99 gecikme, throughput, **DB havuz
  sayaçları** (checkout/return/sızıntı, tx begin/commit/rollback), oturumlar
  arası izolasyon, Türkçe round-trip mojibake ve sır sızıntısı.
- Dosya alım kontrolü `interactive_file_ingestion` adıyla raporlanır ve
  **her zaman enforced**'tır (upload doğrulaması ve rollback gibi); sessiz bir
  alım regresyonu PASS geçemez. Alım seridi lane-yerel geçici bir MCP tabanı
  kullanır ve koşum sonunda temizler.
- **Sınır:** tek-süreçte **ardışık** oturumlardır (gerçek tarayıcı/websocket
  eşzamanlılığı DEĞİL), **lane-yerel SQLite** kullanır (üretim T-SQL/SQL Server
  DEĞİL) ve dosya alımını **in-process** ölçer — gerçek future worker
  eşzamanlılığı ya da UNC/ağ paylaşımı gecikmesi DEĞİL. Bu sınırlar
  `soak_evidence.json` içinde `does_not_prove` altında açıkça yazılır.

### Lane E — PK-analiz (Faz 6 bloklamayan yürütme)

Proje ve Kaynak Analizi'nin **bloklamayan yürütme** katmanı (iptal jetonu, duvar
saati son tarihi, boyut sınırlı LRU önbellek, sınırlı SQL getirimi, istek-kimliği
koruması ve işçi-güvenli anlık görüntü) **yük altında** çalıştırılır. İki-tarayıcı
mutlu-yol kontrolü iptal fırtınasını, bayat tamamlanmayı, önbellek/bağlantı
baskısını ve ardışık derin sorgu bütçesini **ölçemez**; Faz 6 planın en riskli
eşzamanlılık değişikliğidir.

- `tests/scripts/soak_pk_analysis_lane.R`; varsayılan AÇIK
  (`MERGEN_SOAK_PK_LANE=true`), gerçek LLM/SQL Server GEREKTİRMEZ.
- Her "oturum": istek kimliği üretimi → **işçi-güvenli anlık görüntü doğrulaması**
  (`pk_async_validate_request`) → önbellek yoklama (`pk_cache_get/put`, yetki
  imzalı anahtar) → **gerçek** sınırlı SQL getirimi (`pk_sql_execute_bounded`:
  `dbSendQuery` + parçalı `dbFetch` + parça arası iptal/son tarih yoklaması) →
  yetki farkında satır tavanı planı → **istek-kimliği koruması**
  (`pk_async_should_apply`).
- Üretilen baskılar: **iptal fırtınası** (her N. istek gerçek jeton dosyasıyla
  iptal edilir; turların **yarısı UÇUŞ-İÇİ** iptaldir — jeton getirim
  başladıktan sonra, parçalar arası kapıdan yazılır), **bayat tamamlanma**
  (daha yeni istek eski geri çağrıyı geçersiz kılar), **tekrarlayan/
  önbelleklenebilir istekler** (SICAK KÜME + SOĞUK KUYRUK deseniyle hem **hit**
  hem **tahliye**), **çoklu yetki kapsamı** (kullanıcılar arası önbellek
  izolasyonu, giriş başına kapsam sahibi işaretiyle doğrulanır) ve **Derin
  Düşünme bütçe bölüşümü** (gerçek `pk_deep_execute_sql` üzerinden).
- Gate-enforced eşikler (25): `pk_analysis_lane_available`,
  `pk_analysis_lane_enabled`, `pk_analysis_success_rate`, `pk_cancel_exercised`,
  `pk_cancel_inflight_exercised`, `pk_cancel_honoured`,
  `pk_cancelled_never_applied`, `pk_stale_exercised`, `pk_stale_never_applied`,
  `pk_fresh_always_applied`, `pk_snapshot_worker_safe`,
  `pk_deep_deadline_respected`, `pk_deep_budget_decreases`,
  `pk_deep_halts_between_queries`, `pk_connection_instrumented`,
  `pk_connection_usable_after_fetch`, `pk_bounded_fetch_complete`,
  `pk_cache_within_budget`, `pk_cache_hit_observed`,
  `pk_cache_eviction_observed`, `pk_cache_oversize_entry_rejected`,
  `pk_cache_scope_isolated`, `pk_connection_acquire_release_balanced`,
  `pk_psock_async_path`, `pk_psock_worker_bootstrap`.
- **GERÇEK PSOCK turu:** serit ayrıca `pk_async_run_analysis()`'ı gerçek bir
  `multisession` işçisine gönderir (jeton önceden sinyallendiği için sonuç
  DETERMİNİSTİK olarak `cancelled`'dır; LLM/DB gerekmez). Bu prob olmadan serit,
  `MERGEN_PK_ASYNC=true` ile fiilen etkinleşen kodu — anlık görüntü
  serileştirme, temiz işçide bootstrap, future tamamlanma — hiç çalıştırmadan
  tüm eşikleri geçebilirdi. Nitekim eklendiğinde `pk_async_worker_globals()`
  paketinde bootstrap ÖNCESİ kullanılan iptal/son tarih yardımcılarının eksik
  olduğunu ortaya çıkardı. Yük/olay döngüsü kanıtı DEĞİLDİR; yalnızca DOĞRULUK.
- **Bağlantı muhasebesi:** her tur üretim şeklindeki bir al/bırak
  sarmalayıcısından geçer; `acquired`/`released` sayaçları dengelenmezse istek
  başına bağlantı sızıntısı var demektir ve kapı FAIL olur.
- **"Gerçekten çalıştırıldı mı" eşikleri kozmetik değildir:** sıfır iptal/bayat
  turunda `all(...)` boş vektör üzerinde `TRUE` döner ve serit hiçbir şey
  kanıtlamadan yeşil görünürdü. `*_exercised` / `*_observed` eşikleri bunu
  kapatır. Aynı nedenle iptal edilen tur **tam olarak `"cancelled"`** bitmelidir;
  `"deadline"` kabul edilseydi jetonu hiç okumayan bir regresyon geçerdi.
- **Önbellek bütçesi** `MERGEN_SOAK_PK_CACHE_MAX_MB` ile karşılaştırılır — bu,
  tek sonuç tavanı `MERGEN_SOAK_PK_MAX_RESULT_MB`'den **FARKLI** bir sınırdır.
  (Şeridin okuduğu değişkenler bunlardır; `MERGEN_PK_CACHE_MAX_MB` /
  `MERGEN_PK_MAX_RESULT_MB` UYGULAMA değişkenleridir ve kapı onları okumaz.)
- Serit **istendi ama çalışmadıysa** `pk_analysis_lane_available` FAIL olur;
  serit **KAPALI** ise (`MERGEN_SOAK_PK_LANE=false`) `pk_analysis_lane_enabled`
  FAIL olur. Atlanmış da kapatılmış da serit asla kanıt değildir.
- **Bilinçli opt-out:** `MERGEN_SOAK_FAIL_ON_PK_UNAVAILABLE=false` bu iki
  kontrolü FAIL yerine **UNMEASURED** (`expected = FALSE`, `actual = NA`) olarak
  raporlar. Varsayılan `true`'dur, yani varsayılan davranış FAIL'dir. Bayrak,
  seridin bağımlılıkları bulunmayan bir makinede kapının kendini düşürmesini
  önlemek içindir; UNMEASURED sonuç da **kanıt değildir** ve `MERGEN_PK_ASYNC`
  açılması için kullanılamaz.
- Kapının hangi güvenlik parametreleri altında geçtiği `config.json` içindeki
  `pk_safety` bloğuna yazılır (son tarih, SQL zaman aşımı, satır tavanı, sonuç
  tavanı, önbellek bütçeleri, derin sorgu tavanı), böylece kanıt sonradan
  yeniden kurulabilir.
- **Sınır:** tek-süreçte **ardışık** oturumlardır (gerçek tarayıcı/websocket
  eşzamanlılığı DEĞİL), **gerçek future işçi havuzu doygunluğu DEĞİL**, **gerçek
  LLM davranışı DEĞİL**, **lane-yerel SQLite** kullanır (üretim T-SQL/ODBC
  DEĞİL) ve **SQL Server sorgu zaman aşımı mekanizmasının gerçekten
  uygulandığını KANITLAMAZ**. Bu sınırlar `soak_evidence.json` içinde
  `pk_analysis_lane.does_not_prove` altında açıkça yazılır.

> **`MERGEN_PK_ASYNC=true` açılmadan ÖNCE en az bu seridin fake-lane smoke
> profilinde geçmesi gerekir** (master plan §8, Faz 6). Geçmesi, olay döngüsü
> yanıt verebilirliğini kanıtlamaz — o yalnızca Windows VM'de ölçülebilir.

---

> HTTP seridi `MERGEN_SOAK_HTTP_LANE=false` ile kapatılabilir; bu durumda kapı
> yalnızca in-process + etkileşimli seritleri çalıştırır ve **çalışan bir uygulama
> URL'sine ihtiyaç duymaz** (bulut/uygulamasız etkileşimli kanıt için). HTTP
> seridi atlandığında `effective_success_rate` ve `no_server_crash` `UNMEASURED`
> olur (kanıt değildir).

---

## 3. Profiller

`MERGEN_SOAK_PROFILE` ile seçilir (varsayılan: `smoke`).

| Profil | Varsayılan kullanıcı | Varsayılan süre | Serit | Kapasite eğrisi | Amaç |
|--------|----------------------|-----------------|-------|------------------|------|
| `smoke` | 3 | 5 dk | fake | kapalı | Geliştirici makinesi için güvenli hızlı duman testi |
| `pilot` | 15 | 30 dk | fake | kapalı | Küçük pilot yük |
| `org` | 100 | 120 dk | fake | açık | Kurum-ölçeği aktif kullanıcı hedefi |
| `stress` | 150 | 10 dk | fake | açık | Kapasite keşfi (varsayılan DEĞİL) |
| `fake_llm` | 15 | 15 dk | fake | kapalı | Açık fake endpoint serit modu |
| `proxy_llm` | 15 | 15 dk | proxy | kapalı | Sahte kişisel-anahtar/proxy serit modu |
| `real_llm` | 2 | 5 dk | real-canary | kapalı | Gerçek endpoint canary |

Tüm ortam değişkeni override'ları profil varsayılanlarını **geçersiz kılar**.
Hızlı kendi-doğrulama için `MERGEN_SOAK_DURATION_SECONDS` (saniye bazlı) dakika
hesabını geçersiz kılar.

> **Önemli:** "1.000 kullanıcı" bir kullanıcı **tabanıdır**, eşzamanlı aktif
> kullanıcı sayısı değildir. İlk ciddi aktif-eşzamanlılık hedefi **50–100**
> aktif kullanıcıdır. Daha yükseği `stress` profili + kapasite eğrisiyle
> keşfedilir.

---

## 4. Çalıştırma (Windows CMD)

Temel duman testi:

```bat
Rscript tests/scripts/run_operational_soak_gate.R
```

Pilot:

```bat
set MERGEN_SOAK_PROFILE=pilot
Rscript tests/scripts/run_operational_soak_gate.R
```

Org profili (kurum ölçeği, kapasite eğrisi):

```bat
set MERGEN_SOAK_PROFILE=org
set MERGEN_SOAK_CONCURRENT_USERS=100
set MERGEN_SOAK_DURATION_MINUTES=120
Rscript tests/scripts/run_operational_soak_gate.R
```

Fake LLM (açık serit):

```bat
set MERGEN_SOAK_PROFILE=fake_llm
set MERGEN_SOAK_LLM_MODE=fake
Rscript tests/scripts/run_operational_soak_gate.R
```

Proxy LLM (kişisel anahtar yönlendirme/izolasyon):

```bat
set MERGEN_SOAK_PROFILE=proxy_llm
set MERGEN_SOAK_LLM_MODE=proxy
set MERGEN_SOAK_PROXY_FORWARD_REAL=FALSE
Rscript tests/scripts/run_operational_soak_gate.R
```

Gerçek endpoint canary (yalnızca gerçek endpoint + anahtar yapılandırıldığında):

```bat
set MERGEN_SOAK_PROFILE=real_llm
set MERGEN_SOAK_LLM_MODE=real-canary
set MERGEN_SOAK_REAL_CANARY_USERS=2
set MERGEN_SOAK_REAL_CANARY_INTERVAL_SECONDS=60
set MERGEN_SOAK_REAL_ENDPOINT_URL=<gercek-endpoint>/v1/chat/completions
set MERGEN_SOAK_REAL_API_KEY=<gercek-anahtar>
Rscript tests/scripts/run_operational_soak_gate.R
```

> `real_llm` profili `MERGEN_SOAK_REAL_ENDPOINT_URL` ve `MERGEN_SOAK_REAL_API_KEY`
> yapılandırılmazsa HTTP serit **atlanır** (açıkça `skipped_checks` altında
> raporlanır) ve yalnızca in-process uygulama-yolu alıştırmaları çalışır.

Çalışan bir uygulamaya bağlanmak (attach modu, HTTP-düzeyi erişilebilirlik):

```bat
set MERGEN_SOAK_APP_URL=http://127.0.0.1:8009/
Rscript tests/scripts/run_operational_soak_gate.R
```

---

### 4.1 Windows PowerShell attach örnekleri (üretim launcher portu 8009)

Windows VM üretim launcher'ı MERGEN uygulamasını `8009` portunda açar. Canlı
uygulamaya attach modunda koşarken `MERGEN_SOAK_APP_URL` şu köke ayarlanmalıdır:
`http://127.0.0.1:8009/`. Daha önce bazı notlarda geçen `28081` değeri üretim
uygulaması için doğru değildir; `28081` yalnızca bazı external-app/browser-smoke
kanıt akışlarında geçici test portu olarak kullanılabilir.

> **Ortam override uyarısı:** `.Renviron` içindeki değerler, mevcut PowerShell
> oturumunda daha sonra set edilen `$env:...` değerleri tarafından override
> edilebilir. Kontrollü deneylerde önce ilgili değişkenleri temizleyin, ardından
> deney için gerekli `$env:MERGEN_SOAK_*` değerlerini açıkça yeniden set edin.

Quick fake smoke (10 kullanıcı / 30 saniye):

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
Remove-Item Env:MERGEN_SOAK_PROFILE,Env:MERGEN_SOAK_LLM_MODE,Env:MERGEN_SOAK_CONCURRENT_USERS,Env:MERGEN_SOAK_DURATION_SECONDS,Env:MERGEN_SOAK_CAPACITY_CURVE -ErrorAction SilentlyContinue
$env:MERGEN_SOAK_APP_URL = "http://127.0.0.1:8009/"
$env:MERGEN_SOAK_PROFILE = "fake_llm"
$env:MERGEN_SOAK_LLM_MODE = "fake"
$env:MERGEN_SOAK_CONCURRENT_USERS = "20"
$env:MERGEN_SOAK_DURATION_SECONDS = "300"
$env:MERGEN_SOAK_CAPACITY_CURVE = "FALSE"
Rscript tests/scripts/run_operational_soak_gate.R
```

Proxy/key-isolation temiz tek-yük koşumu:

```powershell
Remove-Item Env:MERGEN_SOAK_PROFILE,Env:MERGEN_SOAK_LLM_MODE,Env:MERGEN_SOAK_CONCURRENT_USERS,Env:MERGEN_SOAK_DURATION_SECONDS,Env:MERGEN_SOAK_CAPACITY_CURVE,Env:MERGEN_SOAK_PROXY_FORWARD_REAL -ErrorAction SilentlyContinue
$env:MERGEN_SOAK_APP_URL = "http://127.0.0.1:8009/"
$env:MERGEN_SOAK_PROFILE = "proxy_llm"
$env:MERGEN_SOAK_LLM_MODE = "proxy"
$env:MERGEN_SOAK_CONCURRENT_USERS = "10"
$env:MERGEN_SOAK_DURATION_SECONDS = "60"
$env:MERGEN_SOAK_CAPACITY_CURVE = "FALSE"
$env:MERGEN_SOAK_PROXY_FORWARD_REAL = "FALSE"
Rscript tests/scripts/run_operational_soak_gate.R
```

Real-canary diagnostik koşumu (throughput testi değildir; gerçek endpoint + gerçek
anahtar yalnız operatör ortamında set edilmelidir):

```powershell
Remove-Item Env:MERGEN_SOAK_PROFILE,Env:MERGEN_SOAK_LLM_MODE,Env:MERGEN_SOAK_CONCURRENT_USERS,Env:MERGEN_SOAK_DURATION_SECONDS,Env:MERGEN_SOAK_CAPACITY_CURVE -ErrorAction SilentlyContinue
$env:MERGEN_SOAK_APP_URL = "http://127.0.0.1:8009/"
$env:MERGEN_SOAK_PROFILE = "real_llm"
$env:MERGEN_SOAK_LLM_MODE = "real-canary"
$env:MERGEN_SOAK_REAL_CANARY_USERS = "2"
$env:MERGEN_SOAK_REAL_CANARY_INTERVAL_SECONDS = "60"
$env:MERGEN_SOAK_DURATION_SECONDS = "60"
$env:MERGEN_SOAK_CAPACITY_CURVE = "FALSE"
$env:MERGEN_SOAK_REAL_STREAM = "FALSE"
$env:MERGEN_SOAK_REAL_MAX_TOKENS = "64"
$env:MERGEN_SOAK_REAL_OMIT_TEMPERATURE = "TRUE"
$env:MERGEN_SOAK_REAL_AUTH_HEADER = "Authorization"
$env:MERGEN_SOAK_REAL_AUTH_SCHEME = "Bearer"
# Set only in the operator shell; never commit real values:
# $env:MERGEN_SOAK_REAL_ENDPOINT_URL = "<gateway>/v1/chat/completions"
# $env:MERGEN_SOAK_REAL_MODEL = "<real-model-name>"
# $env:MERGEN_SOAK_REAL_API_KEY = "<real-api-key>"
Rscript tests/scripts/run_operational_soak_gate.R
```

---

## 5. Ortam değişkenleri

### Profil ve yoğunluk

| Değişken | Açıklama |
|----------|----------|
| `MERGEN_SOAK_PROFILE` | smoke/pilot/org/stress/fake_llm/proxy_llm/real_llm |
| `MERGEN_SOAK_LLM_MODE` | fake / proxy / real-canary (serit override) |
| `MERGEN_SOAK_CONCURRENT_USERS` | aktif eşzamanlı kullanıcı sayısı |
| `MERGEN_SOAK_DURATION_MINUTES` | süre (dakika) |
| `MERGEN_SOAK_DURATION_SECONDS` | süre (saniye; dakikayı override eder; test/smoke için) |
| `MERGEN_SOAK_USER_BASE_TARGET` | kullanıcı tabanı hedefi (varsayılan 1000) |
| `MERGEN_SOAK_CLIENT_TIMEOUT_SECONDS` | istek başına client timeout |
| `MERGEN_SOAK_APP_URL` | attach modu: çalışan uygulama kökü |
| `MERGEN_SOAK_IN_PROCESS_EXERCISES` | in-process app-yolu alıştırmaları (varsayılan TRUE) |
| `MERGEN_SOAK_HTTP_LANE` | HTTP yük seridi (varsayılan TRUE; FALSE = yalnız in-process + interactive, uygulama URL'si gerekmez) |
| `MERGEN_SOAK_INTERACTIVE_LANE` | etkileşimli in-process oturum seridi (varsayılan TRUE) |
| `MERGEN_SOAK_INTERACTIVE_USERS` | etkileşimli oturum sayısı (varsayılan `min(max(users,8),50)`) |
| `MERGEN_SOAK_INTERACTIVE_ITERATIONS` | oturum kümesinin tekrar sayısı (varsayılan 1) |

### PK-analiz seridi (Faz 6)

| Değişken | Varsayılan | Açıklama |
|---|---|---|
| `MERGEN_SOAK_PK_LANE` | `true` | PK-analiz seridini aç/kapat. Kapatmak Faz 6 kapsamını KAYBEDER (varsayılanda FAIL). |
| `MERGEN_SOAK_FAIL_ON_PK_UNAVAILABLE` | `true` | Serit istenmiş ama çalışmamışsa / kapalıysa FAIL üretilsin mi? `false` bunu UNMEASURED yapar; UNMEASURED de kanıt DEĞİLDİR. |
| `MERGEN_SOAK_PK_SESSIONS` | `max(users*3, 60)` (≤400) | Analiz oturumu sayısı. |
| `MERGEN_SOAK_PK_DISTINCT_USERS` | `6` | Farklı yetki kapsamı sayısı (önbellek izolasyonu). |
| `MERGEN_SOAK_PK_DEADLINE_SEC` | `300` | Analiz duvar-saati bütçesi. |
| `MERGEN_SOAK_PK_SQL_TIMEOUT_SEC` | `120` | Yapılandırılmış SQL zaman aşımı. |
| `MERGEN_SOAK_PK_ROW_CAP` | `50000` | Satır tavanı planı girdisi. |
| `MERGEN_SOAK_PK_ROWS_PER_QUERY` | `4000` | Sorgu başına satır (getirim baskısı). |
| `MERGEN_SOAK_PK_CHUNK_ROWS` | `1000` | Parça başına satır. |
| `MERGEN_SOAK_PK_MAX_RESULT_MB` | `512` | TEK sonuç bayt tavanı (önbellek TOPLAM bütçesi `MERGEN_SOAK_PK_CACHE_MAX_MB`'den FARKLIDIR). |
| `MERGEN_SOAK_PK_CANCEL_EVERY` | `7` | Her N. istek gerçekten iptal edilir. |
| `MERGEN_SOAK_PK_STALE_EVERY` | `5` | Her N. istek bayat tamamlanma üretir. |
| `MERGEN_SOAK_PK_DEEP_EVERY` | `9` | Her N. istek Derin Düşünme olur. |
| `MERGEN_SOAK_PK_DEEP_MAX_QUERIES` | `5` | Derin sıralı-küme tavanı (bütçe bölüşümü). |
| `MERGEN_SOAK_PK_CACHE_MAX_MB` | `512` | Önbellek TOPLAM bayt bütçesi (tek sonuç tavanı `MERGEN_SOAK_PK_MAX_RESULT_MB`'den FARKLIDIR). |
| `MERGEN_SOAK_PK_CACHE_MAX_ENTRY_MB` | `128` | Önbellek GİRDİ BAŞINA bayt tavanı; üstündeki girdi hiç önbelleklenmez. |

### Kapasite eğrisi

| Değişken | Açıklama |
|----------|----------|
| `MERGEN_SOAK_CAPACITY_CURVE` | eğriyi aç/kapat (stress/org'da varsayılan açık) |
| `MERGEN_SOAK_CAPACITY_USERS` | virgülle ayrılmış kullanıcı adımları (örn. `10,25,50,100`) |
| `MERGEN_SOAK_CAPACITY_STEP_SECONDS` | adım başına süre |

### Fake endpoint davranışı

| Değişken | Varsayılan |
|----------|------------|
| `MERGEN_SOAK_FAKE_LATENCY_MS_MIN` | 80 |
| `MERGEN_SOAK_FAKE_LATENCY_MS_MAX` | 600 |
| `MERGEN_SOAK_FAKE_ERROR_RATE` | 0.02 |
| `MERGEN_SOAK_FAKE_TIMEOUT_RATE` | 0.01 |
| `MERGEN_SOAK_FAKE_STREAM` | TRUE |
| `MERGEN_SOAK_FAKE_LONG_RESPONSE_RATE` | 0.05 |
| `MERGEN_SOAK_FAKE_STREAM_CHUNKS` | 12 |

### Proxy ve real-canary

| Değişken | Varsayılan |
|----------|------------|
| `MERGEN_SOAK_PROXY_FORWARD_REAL` | FALSE |
| `MERGEN_SOAK_MAX_REAL_LLM_RPM` | 3 |
| `MERGEN_SOAK_REAL_CANARY_USERS` | 2 |
| `MERGEN_SOAK_REAL_CANARY_INTERVAL_SECONDS` | 60 |
| `MERGEN_SOAK_REAL_ENDPOINT_URL` | (yalnız gerektiğinde) |
| `MERGEN_SOAK_REAL_MODEL` | gerçek canary model adı |
| `MERGEN_SOAK_REAL_API_KEY` | (yalnız gerektiğinde; gerçek değer artifact/PR/docs içine yazılmaz) |
| `MERGEN_SOAK_REAL_STREAM` | FALSE |
| `MERGEN_SOAK_REAL_MAX_TOKENS` | 64 |
| `MERGEN_SOAK_REAL_OMIT_TEMPERATURE` | TRUE |
| `MERGEN_SOAK_REAL_AUTH_HEADER` | Authorization; gateway için `api-key`, `x-api-key`, `Ocp-Apim-Subscription-Key` denenebilir |
| `MERGEN_SOAK_REAL_AUTH_SCHEME` | Bearer; header key değerini çıplak bekliyorsa `none` |

### Eşik değerleri

| Değişken | Açıklama |
|----------|----------|
| `MERGEN_SOAK_SUCCESS_RATE_MIN` | etkin başarı oranı alt sınırı (smoke 0.95, diğerleri 0.98) |
| `MERGEN_SOAK_P95_LATENCY_MS_MAX` | p95 gecikme üst sınırı (0 = raporla, eşik uygulama) |
| `MERGEN_SOAK_MEMORY_GROWTH_MB_MAX` | bellek büyüme üst sınırı (<0 = raporla, eşik yok) |
| `MERGEN_SOAK_TEMP_GROWTH_MB_MAX` | temp dizin büyüme üst sınırı (<0 = raporla, eşik yok) |
| `MERGEN_SOAK_FAIL_ON_MOJIBAKE` | mojibake bulunursa fail (varsayılan TRUE) |
| `MERGEN_SOAK_FAIL_ON_SECRET_LEAK` | sır sızıntısı bulunursa fail (varsayılan TRUE) |
| `MERGEN_SOAK_FAIL_ON_BROWSER_CONSOLE_ERRORS` | tarayıcı konsol hatası fail bayrağı (bu kapı ölçmez) |
| `MERGEN_SOAK_FAIL_ON_INTERACTIVE_DB_LEAK` | etkileşimli seritte DB bağlantı sızıntısı/izolasyon ihlali fail (varsayılan TRUE) |

---

## 6. Artifact'lar

Çıktı dizini: `artifacts/soak/<timestamp>/` (git tarafından yok sayılır).

| Dosya | İçerik |
|-------|--------|
| `soak_evidence.json` | Makinece okunabilir kanıt (şema + does_prove/does_not_prove + `interactive_lane` bloğu: oturum/eylem sayısı, DB havuz sayaçları, izolasyon/rollback/upload/mojibake) |
| `summary.md` | İnsan-okunur özet |
| `metrics.csv` | İstek başına metrikler (zaman, serit, senaryo, gecikme, durum, kaynak) |
| `failures.jsonl` | Başarısız istekler (redakteli) |
| `config.json` | Secret-safe yapılandırma (ham endpoint/key YOK) |
| `key_routing_summary.json` | Anahtar yönlendirme + izolasyon özeti |
| `interactive_metrics.csv` | Etkileşimli serit eylem başına metrikleri (varsa) |
| `capacity_curve.csv` | Kapasite eğrisi (varsa) |
| `logs/fake_llm.log` / `logs/proxy_llm.log` | Sunucu logları (redakteli) |
| `logs/proxy_requests.jsonl` | Proxy istek kayıtları (takma adlı, ham anahtar YOK) |
| `real_canary_diagnostics.jsonl` | Real-canary HTTP/payload/gateway ayrımı için redakteli diagnostik; `response_preview` alanı model/auth/gateway hatalarını ayırmak için kullanılır |

Tüm metin artifact'ları redaksiyondan geçer; ardından dizin genelinde
**redaksiyon kendi-doğrulaması** (`soak_redaction_self_check`) çalışır. Sızıntı
bulunursa kapı (varsayılan) FAIL olur.

---

## 7. Pass/Fail yorumu

- **Etkin başarı oranı (`effective_success_rate`)** eşiğe tabidir. Bu metrik,
  sunucunun **kasıtlı enjekte ettiği** faultları (http500/http429/timeout) hariç
  tutar; böylece **beklenmeyen** (app/transport kaynaklı) başarısızlıkları ölçer.
  Hata-enjeksiyon test koşumu kendi eşiğini düşürmez.
- **Ham başarı oranı (`raw_success_rate`)** ayrıca raporlanır (enjekte faultlar
  dahil), ancak eşiğe tabi değildir.
- **Ölçülemeyen eşikler sessizce geçmez:** `UNMEASURED` olarak işaretlenir ve
  `skipped_checks` altında listelenir. Örneğin tarayıcı konsol hataları bu kapıda
  ölçülmez (UX smoke ayrı kapıdır).
- Genel sonuç PASS ise, yalnızca **PASS** olarak raporlanan kontroller kanıttır.
  Atlanan/ölçülemeyen kontroller kanıt değildir.
- Hata durumunda bile kanıt üretilir; gerçek başarısızlıkta `stop()` ile sıfır-dışı
  çıkış kodu döner.

---

## 8. Bu kapı NEYİ kanıtlar / kanıtlamaz

**Kanıtlar (does_prove):**

- Uygulama/sunucu, yapılandırılan aktif eşzamanlılıkla fake/proxy seritte
  istekleri istenen süre boyunca işledi (başarı oranı + gecikme + throughput).
- DB-encoding helper round-trip'i Türkçe + emoji metni korudu (escape/restore +
  mojibake tespiti).
- Kişisel/varsayılan/eksik anahtar kaynak yönlendirmesi ham anahtar sızdırmadan
  doğrulandı; oturumlar arası anahtar izolasyonu çalıştı.
- Yükleme doğrulayıcısı traversal/uzantı/kontrol-byte dosya adlarını reddetti.
- Proxy serit çok sayıda ayrı sahte kişisel anahtarı 1:1 izledi (izolasyon).
- **Etkileşimli serit:** in-process sohbet-benzeri oturumlar **gerçek DB havuzu**
  üzerinde sohbet/mesaj yazma, streaming-delta işleme, stop/iptal ve geçmiş okuma
  yaptı; havuz checkout/return dengeli (**bağlantı sızıntısı yok**), işlem
  commit/rollback doğru (niyetli rollback satır bırakmadı), oturumlar arası
  izolasyon korundu ve Türkçe metin mojibake'siz round-trip edildi.

**Kanıtlamaz (does_not_prove):**

- 1.000 gerçek eşzamanlı aktif kullanıcıyı kanıtlamaz.
- Gerçek LLM sağlayıcısının bu eşzamanlılık için üretim throughput'unu
  kanıtlamaz.
- Windows VM dışındaki gerçek ağlardaki üretim gecikmesini kanıtlamaz.
- Tam-yığın tarayıcı/websocket Shiny oturum eşzamanlılığını kanıtlamaz
  (in-process alıştırmalar **helper-düzeyidir**; etkileşimli serit de tek-süreçte
  **ardışık** oturumlardır, gerçek websocket eşzamanlılığı değildir).
- Gerçek SQL Server'a Türkçe yazımının at-rest doğruluğunu kanıtlamaz (ayrı VM
  kodlama preflight kapısıdır: `run_vm_encoding_preflight_real.R`). Etkileşimli
  serit **lane-yerel SQLite** kullanır; üretim T-SQL/SQL Server davranışını
  kanıtlamaz.

---

## 9. 1.000 kullanıcı tabanı için önerilen rollout planı

| Faz | İçerik |
|-----|--------|
| Faz 1 | 25 fake kullanıcı, fake endpoint, 2 saat |
| Faz 2 | 50 fake kullanıcı, fake endpoint, 6 saat |
| Faz 3 | 5–10 fake-kişisel-anahtar kullanıcı (proxy), 2 saat |
| Faz 4 | 2 gerçek-endpoint kullanıcı (paylaşılan gerçek anahtar), 1 saat |
| Faz 5 | gece boyu fake endpoint, 12 saat, hata enjeksiyonlu |
| Faz 6 | 100 fake kullanıcı, fake endpoint, 2 saat, kapasite eğrisi açık |

> En az **fake endpoint org profili** ve **proxy anahtar-yönlendirme profili**
> geçene kadar uygulama geniş iç dağıtıma hazır işaretlenmemelidir.

Faz 5 örneği (gece boyu, hata enjeksiyonlu — enjeksiyon `effective_success_rate`
eşiğini düşürmez):

```bat
set MERGEN_SOAK_PROFILE=org
set MERGEN_SOAK_CONCURRENT_USERS=50
set MERGEN_SOAK_DURATION_MINUTES=720
set MERGEN_SOAK_FAKE_ERROR_RATE=0.05
set MERGEN_SOAK_FAKE_TIMEOUT_RATE=0.02
Rscript tests/scripts/run_operational_soak_gate.R
```

---

## 10. VM kanıt kapısıyla ilişki

- Soak kapısı, VM kanıt kapısının **yerine geçmez**.
- Normal sıralama: önce `bash tools/ai_validate.sh quick` / `full --boot-smoke`,
  sonra (VM'de) `bash tools/vm_evidence_gate.sh`, ardından operasyonel soak.
- Soak kapısı VM'de veya yük üretebilen herhangi bir ortamda çalıştırılabilir;
  cloud/CI'de fake/proxy seritleri tamamen offline çalışır.
- Soak kanıt dizini yalnızca PASS olarak raporladığı kontroller için yürütme
  kanıtıdır.

---

## 11. Mimari notlar (bakım)

- Operasyonel betikler **bilerek ASCII-güvenlidir** (Türkçe özel karakter yok);
  farklı locale'lerde `source`/`Rscript` ile çalıştırılır. Çalışma zamanı Türkçe
  metin yükleri `\u` kaçışlarıyla üretilir (parser-stability).
- Fake/proxy sunucular `httpuv` + `promises` + `later` ile **bloklamayan**
  gecikme uygular; tek thread'li event loop'ta gerçek eşzamanlılık sağlar.
- Eşzamanlı yük `curl` multi-handle havuzu ile sürülür (`host_con` eşzamanlılık
  kadar yükseltilir; aksi halde varsayılan 6 ile serileşir).
- In-process alıştırmalar uygulamanın **gerçek** yardımcı fonksiyonlarını çağırır
  (`normalize_db_visible_value`, `validate_uploaded_file`,
  `mb_api_key_get_effective_key`, ...); repo köküne göre çözümlenir
  (`soak_find_repo_root`), çalışma-dizininden bağımsızdır.
- Yeni paket eklenmedi; tümü mevcut bağımlılıklarla çalışır (`httpuv`, `curl`,
  `jsonlite`, `callr`, `later`, `promises`, `openssl`/`digest`).

---

## 12. 2026-06-19 Windows VM Operational Soak Results

Bu bölüm, 18-19 Haziran 2026 tarihlerinde Windows VM üzerinde canlı MERGEN
uygulamasına attach edilerek alınan operasyonel soak/load-test bulgularını
kaydeder. Attach kökü `MERGEN_SOAK_APP_URL=http://127.0.0.1:8009/` olarak
kullanılmıştır; üretim launcher portu `8009`'dur. Daha önce kullanılan `28081`
değeri üretim uygulaması için yanlış hedef kabul edilmelidir. 19 Haziran
kanıtları `MERGEN_SOAK_PROFILE=smoke`, `MERGEN_SOAK_LLM_MODE=fake`, fake LLM
endpoint'i `/v1/chat/completions`, kullanıcı tabanı hedefi `1000`, kapasite
ramp'i kapalı ve etkin başarı eşiği `0.98` ile alınmıştır.

### Fake-lane kapasite sınırı ve index-cache sonrası durum

19 Haziran 2026 günü index/root-page caching optimizasyonundan **önce** fake-LLM
smoke operasyonel soak kapısında en güçlü sürdürülebilir kanıt **22 aktif
eşzamanlı kullanıcı / 300 saniye PASS** idi. Bu tarihsel baseline korunur:
24 aktif eşzamanlı kullanıcı ve üzeri, pre-cache koşullarda `effective_success_rate`
0.98 eşiğinin altına düştüğü için bu smoke/fake şeridin belgelenmiş güvenilir
işletim zarfının dışındaydı. 25 aktif eşzamanlı kullanıcı / 30 saniye PASS ise
yalnızca kısa spike gözlemi olarak kaydedilir; sürdürülebilir kapasite diye
belgelenmemelidir.

Index-cache optimizasyonundan sonra daha yüksek kısa fake/proxy gözlemleri alınmış
olsa da release/readiness anlatısında artık tek seferde 1000'e atlama yerine
2026-06-25 kademeli merdiven kanıtı esas alınır. Aşağıdaki tablo tarihsel
pre-index-cache baseline olarak korunur; güncel staged milestone için bölüm 13'e
bakın.

#### Tarihsel pre-index-cache fake-lane baseline

| Aktif eşzamanlı kullanıcı | Süre | Sonuç | Not |
|---:|---:|---|---|
| 10 | 30 sn | PASS | 2026-06-18 short smoke sanity; `MERGEN_SOAK_DURATION_SECONDS` override doğrulandı. |
| 15 | 60 sn | PASS | 2026-06-18 kısa VM sanity için temiz kanıt. |
| 20 | 300 sn | PASS | 2026-06-18 önceki stabil kanıt: 418 istek, 418 başarı, 0 hata, 0 timeout, `effective_success_rate=1.000`. |
| 22 | 300 sn | PASS | **Tarihsel pre-index-cache sürdürülebilir fake-lane kanıtı:** `artifacts/soak/20260619-153052/soak_evidence.json`; 408 istek, 408 başarı, 0 hata, 0 timeout, `effective_success_rate=1.000`, `raw_success_rate=1.000`, p50/p95/p99 = 16983.3/18386.2/18791.0 ms, throughput 81.4 istek/dk, `secret_leak=0`, `no_server_crash=TRUE`. |
| 23 | 60 sn | PASS | 2026-06-19 kısa sınır kanıtı: `artifacts/soak/20260619-152901/soak_evidence.json`; 100 istek, 100 başarı, 0 hata, 0 timeout, `effective_success_rate=1.000`, p50/p95/p99 = 16784.2/18948.5/19362.5 ms, throughput 100 istek/dk. |
| 24 | 60 sn | FAIL | 2026-06-19 pre-cache guardrail: `artifacts/soak/20260619-152715/soak_evidence.json`; 98 istek, 88 başarı, 10 timeout, `effective_success_rate=0.898` < 0.98. |
| 24 | 300 sn | FAIL | 2026-06-19 pre-cache guardrail: `artifacts/soak/20260619-153656/soak_evidence.json`; 383 istek, 49 başarı, 334 timeout, `effective_success_rate=0.1279` < 0.98. |
| 25 | 30 sn | PASS | 2026-06-19 kısa spike gözlemi: `artifacts/soak/20260619-145315/soak_evidence.json`; 65 istek, 65 başarı, 0 hata, 0 timeout, throughput yaklaşık 129.4 istek/dk. **Sürdürülebilir kapasite kanıtı değildir.** |
| 26 | 30 sn | FAIL | 2026-06-19 pre-cache guardrail: `artifacts/soak/20260619-152033/soak_evidence.json`; 561 istek, 12 başarı, 549 hata, `effective_success_rate=0.0214` < 0.98. |
| 30 | 60 sn | FAIL | 2026-06-18 timeout saturasyonu. |
| 100 | 30 sn | FAIL | 2026-06-18 timeout saturasyonu; kapasite iddiası değildir. |

22/300 sn ve 23/60 sn PASS koşularında doğruluk/güvenlik kontrolleri temizdi:
anahtar yönlendirme 5/5, upload validation 7/7, encoding round-trip pass rate 1,
cross-session key isolation `TRUE`, secret leak 0, server crash yok,
`mojibake_hits=0`, redaction verified `TRUE`. `temp_growth_mb` yaklaşık 0.31 MB
ile PASS'ti. `memory_growth_mb` ve `browser_console_errors` bu koşularda
`UNMEASURED` olduğundan ölçülmüş PASS olarak sunulmamalıdır.

### 2026-06-19 Windows VM Post-Index-Cache Soak Results

#### Root-page GET `/` cold-build / warm-cache timing

Root timing reproduction command on the production Windows VM:

```powershell
curl.exe -w "%{time_total}`n" -o NUL -s http://127.0.0.1:8009/
```

| Metric | Before | After | Interpretation |
|---|---:|---:|---|
| GET `/` isolated median | ~0.64 s | ~0.007 s warm cache | ~80x-90x faster warm root-page response. |
| Cold index render | not separately logged | 740 ms `cache=miss_build` | First render/build still expensive, then cached. |
| Warm root-page requests | ~0.62-0.67 s | ~0.006-0.008 s | Index cache removes repeated serialization cost. |

Post-cache VM console timings for repeated isolated `GET /` were:
`0.014524`, `0.006657`, `0.007306`, `0.008227`, `0.008083`, `0.007448`,
`0.006910`, `0.006994`, `0.007290`, `0.006726`, `0.007211`, `0.008023`,
`0.007856`, `0.006822`, `0.006620`, `0.007287`, `0.006228`. The first request
was about 14.5 ms; warm repeated requests were mostly 6-8 ms with a median near
7 ms. The observed log line `[PERF] event=index_render elapsed_ms=740
cache=miss_build bytes=311206` shows the cold-build cost remains about 740 ms,
while subsequent root-page requests appear to be served from cache very quickly.

#### Post-index-cache soak table

Because this repository checkout does not contain `artifacts/soak/`, the following
rows are documented from VM console output and must be treated as **VM console
observed** until the listed `soak_evidence.json` files are copied into the repo and
verified.

| Artifact path | Profile / mode / LLM | Concurrent users / duration | Result | Requests / success / errors / timeouts | p50 / p95 / p99 ms | Throughput |
|---|---|---:|---|---:|---:|---:|
| `artifacts/soak/20260619-204455/soak_evidence.json` (VM console observed; JSON not present in this checkout) | smoke / serial / fake | 1000 / 30 s | PASS | 4393 / 4393 / 0 / 0 | 7069.6 / 9427.6 / 9683.7 | 8532.4/min |
| `artifacts/soak/20260619-204704/soak_evidence.json` (VM console observed; JSON not present in this checkout) | smoke / serial / fake | 250 / 420 s | PASS | 56157 / 56157 / 0 / 0 | 1763.0 / 1983.8 / 2134.6 | 8016.8/min |
| `artifacts/soak/20260619-205535/soak_evidence.json` (VM console observed; JSON not present in this checkout) | smoke / serial / fake | 1000 / 420 s | PASS | 55652 / 55652 / 0 / 0 | 7156.4 / 8377.8 / 8859.8 | 7931.4/min |
| `artifacts/soak/20260619-210427/soak_evidence.json` (VM console observed; JSON not present in this checkout) | stress / serial / proxy | final summary | PASS | 16077 / 16077 / 0 / 0 | 277.8 / 734.5 / 803.7 | 8029.2/min |

Guardrails reported PASS for these post-cache VM console observations:
`effective_success_rate=1`, `raw_success_rate=1`, `mojibake_hits=0`,
`encoding_roundtrip_pass_rate=1`, `key_routing_correct=5/5`,
`cross_session_key_isolation=TRUE`, `upload_validation_correct=7/7`,
`secret_leak=0`, `no_server_crash=TRUE`, and `temp_growth_mb=0.31`. Keep
`memory_growth_mb` and `browser_console_errors` explicitly **UNMEASURED**; they are
not clean PASS evidence.

The proxy/stress ramp in `artifacts/soak/20260619-210427/soak_evidence.json` was
also VM console observed as: 10 users / 30 s -> 3970 requests, 3970 success,
p95=81.9 ms, throughput=7940/min; 25 users / 30 s -> 4007 requests, 4007 success,
p95=196.9 ms, throughput=8014/min; 50 users / 30 s -> 4047 requests, 4047 success,
p95=389.5 ms, throughput=8094/min; 100 users / 30 s -> 4053 requests, 4053 success,
p95=793.5 ms, throughput=8106/min.

Operational soak reproduction uses the existing documented command pattern:

```bash
Rscript tests/scripts/run_operational_soak_gate.R
```

Set the documented `MERGEN_SOAK_PROFILE`, `MERGEN_SOAK_LLM_MODE`, duration,
concurrency, attach URL, and ramp environment variables as needed; do not treat
fake/proxy lanes as real LLM generation evidence.

#### What this proves / does not prove

These post-index-cache observations **prove** or strongly support, subject to JSON
kanıt verification where noted:

- Warm `GET /` root-page serving improved dramatically.
- The previous root-page/index serialization bottleneck was real.
- The operational fake-lane soak envelope is now much larger than the earlier
  22-user sustained baseline.
- VM evidence now includes PASS observations at 250 concurrent users for 420 s and
  1000 concurrent users for 420 s in smoke/fake mode, subject to kanıt JSON
  verification.
- Proxy/stress ramp showed low p95 at 10/25/50/100 users and a final p95 around
  734.5 ms.

These observations **do not prove**:

- Real upstream LLM/model generation is faster.
- Browser console errors are clean, because `browser_console_errors` remains
  `UNMEASURED`.
- Memory growth is proven clean, because `memory_growth_mb` remains `UNMEASURED`.
- Production capacity for arbitrary real-user workloads is 1000 concurrent human
  chat sessions.
- DB pooling is unnecessary forever; only that current evidence does not show DB
  open/close as the dominant bottleneck.

Keep the distinction between the soak/index-serving path and the real chat/LLM path:
pre-cache `GET /` was about 0.64 s and explained the 22-user p50/p95 cliff; after
index caching, warm `GET /` is about 7 ms and high-concurrency fake-lane soak passes.
Real chat still needs separate browser/session/LLM evidence.

### Proxy-lane ve stress bulguları

### Real-canary gateway blocker

`real_llm` / `real-canary` bir app kapasite testi değildir; yalnızca Windows VM'nin
gerçek LLM endpoint'ine erişip erişemediğini düşük hızda doğrulayan canary'dir.
Doğru gerçek model adı kullanıldıktan sonra canary hâlâ upstream gateway policy
nedeniyle bloke kalmıştır. Diagnostik artifact:
`artifacts/soak/<timestamp>/real_canary_diagnostics.jsonl`. Bu dosyadaki
`response_preview`, payload/model/auth/gateway hata ayrımını yapmak için
kullanılmalıdır.

Gözlenen upstream yanıtı: HTTP 500, `faultCode` / `FaultCode` = `ERR-234`,
`faultString` / `FaultString` = `Endpoint Rate Limit policy failed Error message is: null`,
`faultStatusCode=500`, `responseFromApi` boş. Bu, gerçek gateway'e ulaşıldığını,
ancak model yanıtı üretilmeden önce upstream rate-limit/auth/consumer policy'nin
başarısız olduğunu gösterir. Bu bir MERGEN app load failure değildir.

Olası nedenler:

- API key gateway'e `Authorization: Bearer` yerine gateway-specific header ile
gönderilmelidir.
- Gateway `api-key`, `x-api-key`, `Ocp-Apim-Subscription-Key` veya başka bir
consumer identity header bekliyor olabilir.
- API key ilgili endpoint/product/rate-limit policy'ye map edilmemiş olabilir.
- Gateway bu durum için ideal olarak 401/403/429 dönmeli; mevcut 500/`ERR-234`
operatör/admin tarafında yorumlanmalıdır.

Gateway/admin escalation note:

> A minimal OpenAI-compatible POST to `/v1/chat/completions` reaches the gateway
> but returns HTTP 500 / ERR-234: Endpoint Rate Limit policy failed. Please confirm
> which header the rate-limit policy uses as consumer/key identity and whether the
> API key is mapped to the endpoint/product/rate-limit policy.

### Kanıt dürüstlüğü

Bu koşumlar **kanıtlar**:

- Operasyonel soak gate Windows VM'de çalışır.
- Attach mode, çalışan uygulama köküne HTTP üzerinden ulaşır.
- Pre-index-cache fake LLM lane, 22 aktif eşzamanlı kullanıcıyı 5 dakika boyunca sıfır hata ve
sıfır timeout ile sürdürebiliyordu.
- 2026-06-25 staged VM gözlemlerinde 50 aktif proxy kullanıcı / 1800 sn PASS,
100 ve 250 aktif proxy kullanıcı / 90 dk kademeleri PASS, 10 gerçek tarayıcı
oturumu browser concurrency lane PASS olarak kaydedildi.
- Key routing, cross-session key isolation, upload validation, secret-redaction,
telemetri ve encoding helper kontrolleri ilgili lane kapsamlarında geçti.

Bu koşumlar **kanıtlamaz**:

- 1.000 gerçek aktif eşzamanlı kullanıcı.
- Üretim ağı üzerinde gerçek insan iş yükü throughput garantisi.
- Browser/websocket Shiny session concurrency.
- Gerçek LLM provider throughput veya real-canary throughput.
- VM dışı production network latency.
- At-rest SQL Server encoding davranışı.
---

## 13. 2026-06-25 Windows VM staged soak findings

Önceki 1000-kullanıcı sınır-zorlama notları release/readiness anlatısından
çıkarılmıştır. Kapasite hedefi artık kademeli yürütülür: son stabil kademeyi
kanıtla, bir sonraki kademeye geç, 1000 hedefini ancak ara kademeler PASS olduktan
sonra milestone olarak ele al. Hiçbir proxy/fake/canary koşumu 1.000 gerçek aktif
insan chat oturumu veya gerçek upstream LLM throughput'u olarak sunulmaz.

Son VM console observed bulguları:

| Lane / koşum | Artifact | Sonuç | Özet |
| --- | --- | --- | --- |
| Proxy soak, 50 kullanıcı, 1800 sn | `artifacts/soak/20260625-111352` | PASS | 115535/115535 başarı, 0 hata, 0 timeout, `effective_success_rate=1.000`, p95≈1113.5 ms, throughput≈3850.4/dk, CPU max≈%33. |
| Browser concurrency, 10 oturum | `artifacts/browser-concurrency/20260625-115948` | PASS | Microsoft Edge ile 10/10 oturum PASS, websocket TRUE, konsol hata sayısı 0. |
| Capacity ladder, 100→250→500→1000, 5400 sn/adım | `artifacts/soak/20260625-121812` | 100 ve 250 PASS | 100 kullanıcı: `effective_success_rate=1`, p95≈5151.2 ms, throughput≈2099.6/dk, CPU max≈%42. 250 kullanıcı: `effective_success_rate=0.9807`, p95≈24234.6 ms, throughput≈928.9/dk, CPU max≈%27. |

Geçerli staged milestone yorumu:

- Son stabil kapasite: **250 aktif proxy kullanıcı / 90 dakika**.
- Sonraki hedef: **500 aktif proxy kullanıcı / 90 dakika**; PASS olmadan 1000
  readiness iddiası yapılmaz.
- Browser lane şu an **10 gerçek tarayıcı oturumu** için websocket ve konsol-hata
  kanıtı sağlar; 1000 gerçek tarayıcı oturumu kanıtı değildir.
- `memory_growth_mb` gibi UNMEASURED alanlar ölçülmüş PASS gibi raporlanmaz.

---

## 13A. 2026-06-26/27 Windows VM proxy attach soak failure findings

Bu bölüm, kullanıcının paylaştığı en son Windows VM ekran görüntülerinden
aktarılmıştır. Artifact yolu ekran görüntülerinde `artifacts/soak/20260626-212908`
ve kanıt dosyası `artifacts/soak/20260626-212908/soak_evidence.json` olarak
görünür; bu checkout içinde kanıt dosyası bulunmadığından değerler **VM console
observed / screenshot-transcribed** kabul edilmelidir. Ekran görüntülerindeki JSON
`created_at` alanı `2026-06-27T02:01:24Z` değerini gösterir.

### Koşum yapılandırması

- Çalıştırma yolu: `Rscript --vanilla tests/scripts/run_operational_soak_gate.R`.
- Uygulama attach URL: `http://127.0.0.1:8009/`.
- Profil / lane: `proxy_llm`; `MERGEN_SOAK_LLM_MODE=proxy`; `proxied_llm=true`;
  `real_llm=false`; real-canary kapalı.
- Proxy forwarding: kapalı (`forward_real_enabled=false`, `max_real_rpm=3`,
  proxy lane requests=0); sahte/proxy LLM sunucusu koşum sonunda canlı kaldı.
- Süre: hedef `18000` saniye, gerçek yaklaşık `16275` saniye.
- Eşzamanlı aktif kullanıcı: `50`; kullanıcı tabanı hedefi: `1000`.
- Kapasite merdiveni: açık; `MERGEN_SOAK_CAPACITY_USERS=100,300,450,600,750`;
  kademe süresi `5400` saniye; stabil eşik `0.98`; ilk başarısız adımda durdurma
  açık.
- Sistem telemetrisi: açık; ekran görüntüsünde yaklaşık `531` örnek raporlandı.
- Kapı genel sonucu: **FAIL**. Başarısızlık nedenleri:
  `effective_success_rate` ve `capacity_ladder_all_steps_pass`.

### Ana HTTP/proxy seridi metrikleri

- Toplam istek: `325001`; başarılı: `276788`; hata: `0`; timeout: `48213`.
- Ham ve efektif başarı oranı: `0.8517`; enjekte fault yok (`injected_fault_count=0`).
- Gecikme: p50≈`2506.1` ms; p95≈`16566.6` ms; p99≈`29921.8` ms; maksimum
  gecikme yaklaşık `49288.6` ms.
- Throughput: yaklaşık `1202.9` başarılı operasyon/dakika.
- HTTP kodları: `200=276788`; durum sayımları `ok=276788`, `timeout=48213`.
- Timeout attribution: toplam `48213`; `connection_timeout=47763`;
  `response_timeout=450`. En yavaş senaryolar yaklaşık:
  `app_http_chat_short` count≈`68847`, p95≈`16639.4` ms;
  `app_http_chat_table` count≈`27599`, p95≈`16593` ms;
  `app_http_chat_turkish` count≈`5507`, p95≈`16589.5` ms;
  `app_http_chat_code` count≈`41562`, p95≈`16583.2` ms;
  `app_http_chat_markdown` count≈`32909`, p95≈`16530.3` ms.
- Sistem telemetrisi: CPU üst sınırı yaklaşık `%29`; R süreç CPU üst sınırı yaklaşık
  `%9.8`; maksimum toplam bellek kullanımı yaklaşık `17102.1` MiB; maksimum app
  port TCP bağlantısı yaklaşık `425`. SQL Server CPU/bellek alanları `0` olarak
  göründü; yorumlarken SQL Server süreç eşleşmesinin ölçülüp ölçülmediği ayrıca
  kontrol edilmelidir.
- Bellek/temp: `memory_growth_mb` ölçülmedi (`UNMEASURED`, value NA);
  `temp_growth_mb=0.34` PASS.

### Etkileşimli serit ve güvenlik/encoding kontrolleri

- Etkileşimli lane: kullanılabilir; `50` oturum, `400` eylem; `400/400` başarı;
  success_rate=`1`; p50≈`6.2` ms; p95≈`11.2` ms; p99≈`17.5` ms;
  throughput≈`8462.9` op/dk. Senaryo sayımları: her biri `50` adet
  `interactive_assistant_msg_save`, `interactive_chat_create`,
  `interactive_file_upload`, `interactive_history_read`, `interactive_session_open`,
  `interactive_stop_cancel`, `interactive_stream_process`,
  `interactive_tx_rollback_probe`, `interactive_user_msg_save`.
- DB havuzu: checkout=`451`, return=`451`, outstanding=`0`; tx begin=`250`,
  commit=`200`, rollback=`50`; sızıntı yok.
- İzolasyon: `cross_session_key_isolation=true`; `isolation_excludes_other_user=true`;
  `key_owner_mismatch_rejected=true`.
- Anahtar kaynakları / routing: `personal=2`, `default=1`, `missing=2`, `error=0`;
  routing satırları `5/5` doğru.
- Upload validation: `7/7` PASS; etkileşimli upload validation PASS.
- Secret leak: `0`; raw key/prompt leak sayıları `0`; redaksiyon doğrulandı.
- Encoding/mojibake: `mojibake_hits=0`; DB-encoding helper round-trip PASS;
  Türkçe + emoji escape/restore helper round-trip PASS; etkileşimli mojibake hits `0`.
- Browser console errors: ölçülmedi (`UNMEASURED`) çünkü bu koşum browser lane değildir.
- Server alive at end: TRUE; server crash yok.

### Kapasite merdiveni bulgusu

Kapasite merdiveni `100,300,450,600,750` adımları için planlandı; ilk başarısız
adımda durdurma açık olduğu için 450 kullanıcı adımından sonra durdu. Sonuç
`all_steps_pass=false`; `stable_capacity_users=300`; `first_failed_capacity_users=450`;
`recommended_next_target=450`; darboğaz ipucu
`timeout_saturation_without_clear_resource_signal`.

| Kademe | Süre | İstek | Başarı | Timeout | Raw/effective başarı | p50 | p95 | p99 | Throughput | CPU max | TCP max | Sonuç |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 100 kullanıcı | 5400 sn | 191973 | 191973 | 0 | 1.0000 | ≈1714.4 ms | ≈5018.2 ms | ≈5340.1 ms | ≈2133/dk | ≈%29 | ≈302 | PASS |
| 300 kullanıcı | 5400 sn | 83613 | 83335 | 278 | ≈0.9967 | ≈13431.7 ms | ≈27566.5 ms | ≈31732 ms | ≈929/dk | ≈%29 | ≈302 | PASS |
| 450 kullanıcı | 5400 sn | 49415 | 450 | 47935 | ≈0.03 effective / ≈0.008 raw | ≈24643 ms | ≈44028.8 ms | belirtilmedi | ≈549.1/dk | ≈%21 | ≈425 | FAIL |

Yorum: 300 aktif proxy kullanıcı / 90 dakika bu koşumun son stabil kademesidir.
450 kullanıcı adımı net timeout doygunluğuna girmiştir; CPU üst sınırı düşük/orta
göründüğü için darboğaz yalnız CPU tüketimiyle açıklanmamaktadır. Connection timeout
sınıfının baskın olması, app port bağlantı kabul/backlog, tek süreç/event-loop
yığılması, Windows TCP ephemeral port/backlog/keepalive davranışı, httpuv kabul kuyruğu
veya istemci tarafı connection pool/timeout ayarları gibi kaynak-dışı görünen
doygunluk ihtimallerinin incelenmesini gerektirir.

### Kanıt sınırları ve takip işleri

Bu koşum; 50 eşzamanlı simüle kullanıcı ile uzun proxy seridinde key routing,
izolasyon, redaksiyon, upload validation, etkileşimli DB havuzu ve encoding
kontrollerinin çalıştığını; kapasite merdiveninde 300 aktif proxy kullanıcı / 90
dakika seviyesinin stabil kaldığını gösterir. **Fail** sonucu saklanmalıdır: genel
soak kapısı geçmedi ve 450 kullanıcı adımı readiness değildir.

Bu koşum şunları kanıtlamaz: 1000 gerçek eşzamanlı aktif insan, gerçek üretim LLM
throughput'u, gerçek tarayıcı/websocket eşzamanlılığı, gerçek SQL Server T-SQL
at-rest encoding davranışı veya üretim ağı uçtan uca kapasitesi. Browser console
errors ve memory growth bu koşumda ölçülmediği için PASS gibi sunulmamalıdır.

Önerilen iyileştirme odakları:

1. 450 kullanıcı adımındaki `connection_timeout` baskınlığını app-port backlog,
   httpuv/Shiny accept loop, Windows TCP sınırları ve istemci timeout/pool davranışı
   açısından incelemek.
2. 300→450 aralığını daraltmak için 350/400/425 gibi ara kademelerle aynı 90 dk
   proxy attach merdivenini tekrar koşmak.
3. CPU düşükken timeout artışını açıklamak için telemetriye app port accept backlog,
   established/syn-sent/time-wait dağılımı, request queue depth ve per-scenario
   connection reuse sinyali eklemek.
4. Ayrı browser concurrency lane'i yeniden koşarak browser console errors ve gerçek
   websocket oturum davranışını bu bulgudan bağımsız ölçmek.
5. SQL Server preflight/at-rest encoding kapısını ayrı çalıştırmak; bu proxy koşumu
   SQL Server üretim havuzu kanıtı değildir.

---

## 13B. 2026-06-27 Windows VM proxy attach retest: 400 stable, 425 first failure

Bu bölüm, kullanıcının paylaştığı en yeni Windows VM ekran görüntülerinden
aktarılmıştır. Artifact dizini `artifacts/soak/20260627-093805` ve kanıt dosyası
`artifacts/soak/20260627-093805/soak_evidence.json` olarak görünür; bu checkout
içinde kanıt dosyası bulunmadığından değerler **VM console observed /
screenshot-transcribed** kabul edilmelidir. JSON `created_at` değeri
`2026-06-27T10:29:30Z` olarak görünür.

### Koşum yapılandırması

- Çalıştırma yolu: `Rscript --vanilla tests/scripts/run_operational_soak_gate.R`.
- Uygulama attach URL: `http://127.0.0.1:8009/`.
- Profil / lane: `proxy_llm`; `mock=FALSE`, `proxy=TRUE`, `real-canary=FALSE`; proxy
  sahte kişisel-anahtar/proxy serit modunda çalıştı.
- Eşzamanlı aktif kullanıcı: `50`; kullanıcı tabanı hedefi: `1000`.
- Süre: hedef `1800` saniye, gerçek yaklaşık `3065` saniye.
- Yük deseni: `burst`; `ramp=0s`; `connection_reuse=TRUE`; HTTP yük üretici
  telemetrisi kapalı/atlanmış görünüyor.
- Kapasite merdiveni: açık; ekran görüntülerinde koşulan adımlar `100,300,350,400,425`
  olarak görünür; stabil eşik `0.98`; ilk başarısız adımda durdurma açık.
- Sistem telemetrisi: açık; `97` örnek raporlandı.
- Kapı genel sonucu: **FAIL**. Başarısızlık nedenleri:
  `effective_success_rate` ve `capacity_ladder_all_steps_pass`.

### Ana HTTP/proxy seridi metrikleri

- Toplam istek: `136185`; başarılı: `132043`; hata: `0`; timeout: `4142`.
- Ham/efektif başarı oranı: `0.9696`; eşik `0.98` altında kaldığı için FAIL.
- Gecikme: p50≈`1969.7` ms; p95≈`11611.8` ms; p99≈`13087.5` ms; maksimum
  gecikme ekran görüntüsünde ≈`32532.8` ms.
- Throughput: yaklaşık `2710.6` başarılı operasyon/dakika.
- HTTP kodları: `200=132043`; durum sayımları `ok=132043`, `timeout=4142`.
- curl zamanlama: connect p50/p95 `0/0` ms; TTFB p50/p95≈`835.6/8539.6` ms.
  Bu koşumda bağlantı kurma fazı değil, ilk-byte/app-side bekleme fazı daha görünürdür;
  yine de terminal darboğaz ipucu app-port kabul/backlog doygunluğunu işaret ettiğinden
  TCP state/accept-loop ölçümleriyle birlikte yorumlanmalıdır.
- Timeout attribution: toplam `4142`; `connection_timeout=3723`;
  `response_timeout=419`. Baskın timeout sınıfı hâlâ `connection_timeout`.
- Sistem telemetrisi: CPU üst sınırı yaklaşık `%41`; maksimum toplam bellek kullanımı
  yaklaşık `17458.5` MiB; maksimum R süreç bellek yaklaşık `3355.1` MiB; maksimum
  app-port TCP bağlantısı `425`. App-port TCP durum maksimumları:
  `established=424`, `syn_recv=0`, `syn_sent=0`, `time_wait=0`, `close_wait=0`,
  `listen=1`.
- Bellek/temp: `memory_growth_mb` ölçülmedi (`UNMEASURED`, value NA);
  `temp_growth_mb=0.34` PASS.

### Etkileşimli serit ve güvenlik/encoding kontrolleri

- Etkileşimli lane: `50` oturum, `400` eylem; `400/400` başarı; success_rate=`1`;
  p50≈`6.2` ms; p95≈`10.9` ms; p99≈`13.1` ms; throughput≈`8497.7` op/dk.
- DB havuzu: checkout=`451`, return=`451`, outstanding=`0`; tx begin=`250`,
  commit=`200`, rollback=`50`; sızıntı yok.
- Anahtar yönlendirme: `5/5` doğru; kaynak sayıları `personal=2`, `default=1`,
  `missing=2`, `error=0`; oturumlar arası anahtar izolasyonu TRUE.
- İzolasyon/güvenlik: cross-session isolation, başka kullanıcının sohbet/mesajını
  görmeme, yabancı sahipli anahtar reddi, secret leak `0`, raw key/prompt leak `0` PASS.
- Upload validation: `7/7` PASS; traversal/uzantı/kontrol-byte adları reddedildi;
  etkileşimli upload validation PASS.
- Encoding/mojibake: DB-encoding helper round-trip, Türkçe+emoji escape/restore ve
  etkileşimli Türkçe yazma/okuma mojibake'siz PASS; `mojibake_hits=0`.
- Browser console errors: ölçülmedi (`UNMEASURED`) çünkü bu koşum browser lane değildir.
- Server alive at end: TRUE; server crash yok.

### Kapasite merdiveni bulgusu

Bu retest, önceki 300→450 aralığını daraltmıştır. Sonuç `all_steps_pass=false`;
`stable_capacity_users=400`; `first_failed_capacity_users=425`;
`recommended_next_target=425`; önerilen ara kademeler `410,415,420`;
`bottleneck_hint` ve birincil ipucu `possible_connection_accept_or_backlog_saturation`;
`loadgen_saturation_hint=loadgen_loop_lag_high`; baskın timeout sınıfı
`connection_timeout`.

| Kademe | Süre | İstek | Başarı | Timeout | Effective başarı | p50 | p95 | p99 | Throughput | CPU max | TCP max | Sonuç |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 100 kullanıcı | 600 sn | 6747 | 6747 | 0 | 1.0000 | ≈715.9 ms | ≈910.3 ms | ≈2486.1 ms | ≈6714.7/dk | ≈%41 | ≈102 | PASS |
| 300 kullanıcı | 600 sn | 18958 | 18958 | 0 | 1.0000 | ≈7247.2 ms | ≈9113.7 ms | ≈9358.6 ms | ≈1895.8/dk | ≈%15 | ≈297 | PASS |
| 350 kullanıcı | 600 sn | 18936 | 18936 | 0 | 1.0000 | ≈8508.2 ms | ≈10681.2 ms | ≈11006.1 ms | ≈1893.6/dk | ≈%21 | ≈344 | PASS |
| 400 kullanıcı | 600 sn | 18801 | 18801 | 0 | 1.0000 | ≈9848.6 ms | ≈12366.7 ms | ≈12737.5 ms | ≈1880.1/dk | ≈%30 | ≈402 | PASS |
| 425 kullanıcı | 600 sn | 12243 | 8201 | 4142 | ≈0.6644 | ≈10783.2 ms | ≈19467.8 ms | ≈27949.3 ms | ≈1234.3/dk | ≈%16 | ≈425 | FAIL |

Yorum: bu retest son stabil staged kapasiteyi **400 aktif proxy kullanıcı / 10 dakika**
olarak günceller ve ilk başarısız adımı **425 aktif proxy kullanıcı** olarak daraltır.
Ancak genel koşum yine FAIL olduğu için 425 readiness değildir; ayrıca 400 adımı yalnız
10 dakika sürdüğünden önceki **300 aktif proxy kullanıcı / 90 dakika** kanıtından farklı
bir dayanıklılık düzeyidir. Üretim kararı verirken iki ifade ayrı tutulmalıdır:

- En uzun süreli stabil proxy attach kanıtı: **300 aktif proxy kullanıcı / 90 dakika**.
- En yeni daraltılmış kısa merdiven stabil adımı: **400 aktif proxy kullanıcı / 10 dakika**;
  ilk başarısız adım **425**.

Bu koşum şunları kanıtlamaz: 1000 gerçek eşzamanlı aktif insan, gerçek LLM sağlayıcı
throughput'u, gerçek browser/websocket concurrency, SQL Server at-rest encoding veya
üretim ağ gecikmesi. `browser_console_errors` ve `memory_growth_mb` ölçülmediği için
PASS gibi sunulmamalıdır.

Önerilen takip işleri:

1. `410,415,420,425` ara kademelerini aynı port/attach koşullarında koşarak 400→425
   kırılma eşiğini daraltmak.
2. `MERGEN_SOAK_RAMP_UP_SECONDS` ve `MERGEN_SOAK_MAX_NEW_PER_TICK` ile aynı merdiveni
   tekrarlayıp burst bağlantı fırtınası ile kararlı-durum kapasitesini ayırmak.
3. `loadgen_loop_lag_high` görüldüğü için yük üreticiyi ayrı makine/süreç, daha düşük
   batch veya paced arrival ile karşılaştırmak; yük üretici doygunluğunu app kapasitesi
   sanmamak.
4. App-port accept/backlog/httpuv/Shiny event-loop ve Windows TCP limitlerini,
   `established≈424`, `syn_recv=0`, `time_wait=0` gözlemleriyle birlikte incelemek.
5. Browser concurrency lane ve SQL Server at-rest preflight'ı ayrı koşarak bu proxy
   attach bulgusunun kapsamadığı kanıtları tamamlamak.

---

## 14. 2026-06-22 Interactive lane + transaction-safe DB pool (cloud evidence)

Bu bölüm, GET-only soak boşluğunu kapatmak için eklenen **etkileşimli (interactive)
serit** ve **işlem-güvenli DB bağlantı havuzu** (`R/helpers_db_pool.R`) için bulut
oturumunda alınan kanıtı kaydeder.

**Çalıştırma (bulut/uygulamasız; HTTP seridi kapalı):**

```bash
LC_ALL=C.UTF-8 MERGEN_SOAK_HTTP_LANE=false MERGEN_SOAK_INTERACTIVE_USERS=15 \
  Rscript tests/scripts/run_operational_soak_gate.R
```

Gözlenen sonuç (genel **PASS**): etkileşimli serit 15 in-process oturum / 120 eylem,
`success_rate=1`, p95≈4 ms, throughput≈19.655/dk. DB havuzu: checkout=121,
return=121, **outstanding=0 (bağlantı sızıntısı yok)**, tx commit=45, rollback=15.
Eşik kontrolleri: `interactive_success_rate=PASS`, `interactive_db_no_leak=PASS`,
`interactive_cross_session_isolation=PASS`, `interactive_tx_rollback_clean=PASS`,
`interactive_mojibake_hits=PASS (0)`. `effective_success_rate` ve `no_server_crash`
HTTP seridi kapalı olduğu için `UNMEASURED` (kanıt değildir). `soak_evidence.json`
ham DSN/dosya yolu/anahtar sızdırmadı (redaksiyon self-check temiz).

**Kanıtlar:** işlem-güvenli havuz katmanının checkout/return/commit/rollback ve
no-leak davranışı, oturumlar arası izolasyon ve Türkçe round-trip gerçek bir DBI
arka ucuna karşı yük altında doğrulandı.

**Kanıtlamaz:** gerçek tarayıcı/websocket eşzamanlılığı, gerçek SQL Server T-SQL
at-rest davranışı ve gerçek LLM throughput'u. Bunlar Windows VM gate'lerinde
(`run_vm_preflight_real.R`, `run_vm_encoding_preflight_real.R`, browser UX smoke)
ve canlı uygulamaya attach soak koşumunda ayrıca doğrulanmalıdır.

---

## 16. Soak Readiness Hardening (2026-06-24): telemetri, kademeli merdiven, hata atfı, ayrı lane'ler

Bu bölüm, 50 → 100 → 250 → 500 → 1000 aktif kullanıcı hedefine **kademeli**
ilerlemek, her adımda son stabil kapasiteyi ölçmek ve olası darboğazları telemetriyle
teşhis etmek için eklenen sertleştirmeyi açıklar. Hiçbir eşik
düşürülmemiştir; UNMEASURED kontroller hâlâ sessizce PASS sayılmaz.

### 16.1 Sistem telemetrisi (CPU / bellek / TCP)

Soak sırasında ayrı bir arka süreç (`tests/scripts/soak_system_telemetry.R`,
`callr` ile) sistemi periyodik örnekler. Yük seridini **bloklamaz** ve OS
sayaçları okunamazsa soak'u **kırmaz** (UNMEASURED raporlanır).

- Açık/kapalı: `MERGEN_SOAK_TELEMETRY_ENABLED` (varsayılan TRUE),
  aralık: `MERGEN_SOAK_TELEMETRY_INTERVAL_SECONDS` (varsayılan 5 sn).
- Windows: PowerShell (`Get-CimInstance`, `Get-Process`, `Get-NetTCPConnection`/
  `netstat`). Unix/cloud: `/proc` + `ps` + `ss`/`netstat`.
- Toplanan (hepsi gizlilik-güvenli sayısal): toplam CPU%, R/SQL Server/yük-üretici
  süreç CPU%/bellek, toplam/kullanılan/boş bellek, app portuna (8009) TCP bağlantı
  sayısı.
- Artifact: `system_telemetry.csv` (örnek başına satır) + `system_telemetry_summary.json`.
- `soak_evidence.json` içinde `system_telemetry` bloğu: `telemetry_available`,
  `max_total_cpu_percent`, `max_r_process_memory_mb`, `max_sqlserver_memory_mb`,
  `max_tcp_connections_to_app`, `telemetry_warnings`.

> CPU% delta hesabı için en az iki örnek gerekir; çok kısa koşumlarda tek örnek
> alınır ve CPU% `NA` (UNMEASURED) kalır. Bu dürüsttür, hata değildir.

### 16.2 Kademeli kapasite merdiveni (staged capacity ladder)

Doğrudan 1000'e atlamak yerine adım adım ölçer ve **son stabil adımı** dürüstçe
belirler.

| Değişken | Varsayılan | Açıklama |
|----------|------------|----------|
| `MERGEN_SOAK_CAPACITY_LADDER` | FALSE | TRUE -> kademeli merdiven modu |
| `MERGEN_SOAK_CAPACITY_USERS` | `50,100,150,250,500,750,1000` | adım kullanıcı sayıları |
| `MERGEN_SOAK_CAPACITY_STEP_SECONDS` | 600 | adım başına süre |
| `MERGEN_SOAK_STOP_ON_FIRST_FAILED_STEP` | TRUE | ilk başarısız adımda dur |
| `MERGEN_SOAK_STABLE_SUCCESS_RATE_MIN` | 0.98 | adımın "stabil" sayılma eşiği |

- Her adım için: kullanıcı sayısı, süre, istek/başarı/hata/timeout,
  `raw_success_rate`, `effective_success_rate`, p50/p95/p99, throughput, o adımın
  telemetri penceresi özeti ve PASS/FAIL kaydedilir.
- Artifact: `capacity_ladder.csv` + `capacity_ladder_summary.json`.
- `soak_evidence.json` içinde `capacity_ladder` bloğu: `stable_capacity_users`,
  `first_failed_capacity_users`, `recommended_next_target`, `bottleneck_hints`,
  `all_steps_pass`, adım dizisi.
- Eşik: `capacity_ladder_all_steps_pass` **ek ve daha katı** bir kontroldür
  (hiçbir eşik düşürmez). Çalıştırılan bir adım stabil eşiğin altına düşerse kapı
  FAIL olur; son stabil adım yine de dürüstçe raporlanır. Merdiven istendi ama
  çalışmadıysa kontrol UNMEASURED'dır (sessiz PASS değil).

> **Önemli sınır:** attach modunda çalışan uygulamanın DB havuz sayaçları soak
> sürücü sürecinden **görünmez**; bu yüzden merdiven adımlarında `db_pool = null`
> (yanıltıcı sayaç yazılmaz). Havuzun at-rest davranışı ayrı VM preflight ile
> doğrulanır (16.5).

Darboğaz ipuçları (`bottleneck_hints`) korumacıdır:

- `possible_cpu_saturation`: başarısızlık sırasında telemetri CPU ≥ %85.
- `possible_app_or_event_loop_queueing`: p95 keskin yükseldi (≥1.8x) ama CPU < %70.
- `possible_sql_server_contention`: SQL Server süreç CPU ≥ %80.
- `possible_load_generator_limit`: R süreç CPU ≥ %90 ama toplam CPU < %85.
- `possible_db_pool_contention`: yalnız adımda gerçek havuz sayacı varsa (taken=max).
- `unknown_timeout_saturation`: telemetri yoksa (kanıt yetersiz; dürüst UNMEASURED).

### 16.3 Hata atfı (timeout attribution)

Başarısızlıklar artık sınıflandırılır; `failures.jsonl` her başarısız istek için
`timeout_class`, `endpoint_kind`, `http_status` ve `retryable` taşır.
`soak_evidence.json` içinde `timeout_attribution`: `timeout_breakdown` (sınıf ->
sayı), `top_failure_classes`, `top_slow_scenarios`.

Sınıflar: `connection_timeout` (bağlantı kurulamadı), `response_timeout` (app yanıt
veremedi), `fake_llm_timeout`/`proxy_llm_timeout`/`real_llm_timeout` (LLM endpoint
yavaş), `rate_limited` (429), `app_http_error` (app 4xx/5xx),
`real_llm_gateway_error`, `connection_error`, `unknown_timeout`/`unknown_error`.

> Yorumlama: `connection_timeout` baskınsa accept-kuyruğu/soket doygunluğu;
> `response_timeout` baskınsa tek Shiny event-loop işleme darboğazı; LLM endpoint
> timeout'ları ise upstream yavaşlığıdır (app değil).

### 16.4 Gerçek tarayıcı/websocket eşzamanlılık lane'i (ayrı betik)

`tests/scripts/run_browser_concurrency_lane.R` N gerçek headless tarayıcı
oturumunu **aynı anda** açar; her oturum uygulamayla websocket/Shiny oturumu
kurar, UX smoke akışını koşar ve konsol hatalarını DOM'a döker. Böylece
`browser_console_errors` bu lane **çalıştığında ÖLÇÜLÜR** (yoksa UNMEASURED).

| Değişken | Varsayılan |
|----------|------------|
| `MERGEN_BROWSER_CONCURRENCY_ENABLED` | FALSE |
| `MERGEN_BROWSER_CONCURRENCY_USERS` | 10 |
| `MERGEN_BROWSER_CONCURRENCY_MAX_USERS` | 50 (sert tavan; uygulama VM'inde 1000 tarayıcı çalıştırmayın) |
| `MERGEN_BROWSER_CONCURRENCY_DURATION_SECONDS` | 300 |
| `MERGEN_BROWSER_CONCURRENCY_BASE_URL` | http://127.0.0.1:8009/ |
| `MERGEN_BROWSER_CONCURRENCY_HEADLESS` | TRUE |

- Artifact: `browser_concurrency_summary.json`, `browser_console_errors.jsonl`,
  `browser_session_metrics.csv`.
- **Kanıtlar:** N eşzamanlı gerçek tarayıcı oturumu uygulamayla websocket kurdu,
  başlattı ve UX smoke'u PASS bildirdi; bloklayıcı konsol hatası görülmedi.
- **Kanıtlamaz:** sürekli (sustained) gerçek insan iş yükü; 1000 eşzamanlı insan
  oturumu; gerçek LLM throughput'u. Bunlar **kısa-ömürlü** oturumlardır.
- 10/25/50 oturum yararlıdır; CDN/Playwright/Selenium/chromote **eklenmez**
  (yalnız yerel kurulu tarayıcı + processx).

### 16.5 Gerçek SQL Server havuzlu at-rest preflight (VM-only)

`tests/scripts/run_vm_sqlserver_pool_preflight_real.R` havuzun (`R/helpers_db_pool.R`)
gerçek SQL Server'a karşı doğru davrandığını doğrular: havuz init, checkout/return
dengesi (sızıntı yok), `with_db_transaction` commit, rollback'in satır bırakmaması
ve Türkçe metnin parametre + (yazma testinde) **at-rest** round-trip'i.

- Guard: `MERGEN_DB_POOL_ENABLED=TRUE` + `MERGEN_SQLSERVER_POOL_PREFLIGHT_REAL=TRUE`;
  yazma probe'ları yalnız `MERGEN_SQLSERVER_POOL_WRITE_TEST=TRUE` iken.
- Yıkıcı değildir: yazma testi tek, **benzersiz etiketli** bir tablo oluşturur,
  commit/rollback/at-rest probe'larını yapar ve tabloyu **DROP** eder.
- Bulut/offline (pool/odbc/DB_DSN yok) **güvenle atlar** (`skipped_reason`).
- Artifact: `artifacts/sqlserver-pool-preflight/<timestamp>/evidence.json` + `summary.md`.
  Alanlar: `sqlserver_pool_preflight_passed`, `turkish_at_rest_roundtrip_passed`,
  `tx_rollback_clean`, `pool_outstanding_checkouts`, `mojibake_hits`,
  `skipped_reason`. Ham DSN/secret yazılmaz; `DB_CLIENT_ENCODING`/`DB_NAME_ENCODING`
  değerleri (sır değil) gösterilir.

> Havuzlu SQL Server üretim hazırlığı iddiası için bu preflight PASS olmalıdır.
> Offline RSQLite testleri (`test-db-pool-behavior.R`, interactive lane) T-SQL
> at-rest davranışını kanıtlamaz.

### 16.5A Havuz mekanik + gözlemlenebilirlik + fail-fast preflight (VM-only, 2026-06-27)

`tests/scripts/run_vm_db_pool_preflight_real.R`, 16.5'teki at-rest/encoding
kapısını **tamamlar**: havuzun **mekanik + gözlemlenebilirlik + fail-fast**
davranışına odaklanır ve **varsayılan olarak yıkıcı değildir** (DDL gerektirmez,
tekrar tekrar güvenle koşulur).

- Guard: `MERGEN_DB_POOL_ENABLED=TRUE` + `DB_DSN` (yoksa **güvenle SKIP**).
- Doğrular: havuz init, **çoklu** checkout/return döngüsü (varsayılan 5,
  `MERGEN_DB_POOL_PREFLIGHT_CYCLES`), tam snapshot alanları
  (`outstanding_checkouts`, `tx_begin/commit/rollback`, `direct_fallback`,
  `init_failed`...), `with_db_transaction` commit (no-op `SELECT 1`) + rollback
  (niyetli hata → bağlantı iade), `checkout==returned`, ve Türkçe parametre
  round-trip'i (YAZMA YOK).
- Opsiyonel `MERGEN_DB_POOL_WRITE_TEST=TRUE`: tek, **benzersiz etiketli** tablo
  ile Türkçe at-rest commit/rollback + **DROP** (hafif at-rest kontrolü; kapsamlı
  encoding kapısı yine 16.5'tir).
- `MERGEN_DB_POOL_FAIL_FAST=TRUE` iken havuz kurulamazsa **HARD FAIL** (operatörün
  istediği davranış); varsayılan fail-open'da preflight FAIL raporlar ama uygulama
  doğrudan-bağlantı yoluyla çalışmaya devam eder.
- Artifact: `artifacts/db-pool-preflight/<timestamp>/evidence.json` + `summary.md`.
  Ham DSN/secret yazılmaz (`db_dsn_present` yalnız boolean). **UNMEASURED (NA)
  bir alan ASLA PASS sayılmaz.**

> Bu kapı **kapasite/throughput kazanımı kanıtlamaz**; yalnız havuzlu DB yolunun
> mekaniğini ve gözlemlenebilirliğini doğrular. Canlı sayaçlar ayrıca `/readyz`
> (`db_pool` bloğu) üzerinden sır-güvenli izlenir.

### 16.6 Gerçek LLM throughput ayrı tutulur

Real-canary yanıtları artık aşamalara sınıflandırılır
(`app_reachable`/`gateway_reachable`/`auth_rejected`/`model_or_route_not_found`/
`rate_limited`/`gateway_policy_failed`/`generation_completed`/`streaming_completed`).
ERR-234 / "Rate Limit policy failed" **gateway_policy_failed** olarak işaretlenir;
bu bir MERGEN app yük hatası **değildir**. `soak_evidence.json` ->
`real_canary_classification`.

Opsiyonel, **kullanıcı tavanlı** (varsayılan 5) küçük gerçek-LLM throughput probe
(`MERGEN_REAL_LLM_THROUGHPUT_PROBE=TRUE`) ayrı bir metrik nesnesiyle ölçülür
(`real_llm_throughput`). Bu app kapasitesi **değildir**, 50/100 kullanıcıyı
**tahmin etmez** ve fake/proxy serit sonuçlarıyla **karıştırılmaz**.

### 16.7 Önerilen kademeli VM komut dizisi (PowerShell, attach portu 8009)

Sırasıyla; bir adım PASS olmadan sonrakine geçmeyin. Her koşumdan sonra
`soak_evidence.json` içindeki `effective_success_rate`, `capacity_ladder`,
`timeout_attribution` ve `system_telemetry` alanlarını okuyun.

**1) 50 aktif proxy kullanıcı / 30 dk (ilk gerçekçi hedef):**

```powershell
Remove-Item Env:MERGEN_SOAK_PROFILE,Env:MERGEN_SOAK_LLM_MODE,Env:MERGEN_SOAK_CONCURRENT_USERS,Env:MERGEN_SOAK_DURATION_MINUTES,Env:MERGEN_SOAK_CAPACITY_CURVE,Env:MERGEN_SOAK_CAPACITY_LADDER -ErrorAction SilentlyContinue
$env:MERGEN_SOAK_APP_URL = "http://127.0.0.1:8009/"
$env:MERGEN_SOAK_PROFILE = "proxy_llm"
$env:MERGEN_SOAK_LLM_MODE = "proxy"
$env:MERGEN_SOAK_CONCURRENT_USERS = "50"
$env:MERGEN_SOAK_DURATION_MINUTES = "30"
$env:MERGEN_SOAK_CAPACITY_CURVE = "FALSE"
$env:MERGEN_SOAK_TELEMETRY_ENABLED = "TRUE"
Rscript tests/scripts/run_operational_soak_gate.R
```

**2-5) Kademeli merdiven (100 → 250 → 500 → 1000, her adım 90 dk):**

Tek koşumda merdiven modu kademeleri sırayla dener ve ilk başarısız adımda durur;
son stabil adımı raporlar:

```powershell
Remove-Item Env:MERGEN_SOAK_PROFILE,Env:MERGEN_SOAK_LLM_MODE,Env:MERGEN_SOAK_CONCURRENT_USERS,Env:MERGEN_SOAK_DURATION_MINUTES,Env:MERGEN_SOAK_CAPACITY_CURVE,Env:MERGEN_SOAK_CAPACITY_LADDER -ErrorAction SilentlyContinue
$env:MERGEN_SOAK_APP_URL = "http://127.0.0.1:8009/"
$env:MERGEN_SOAK_PROFILE = "proxy_llm"
$env:MERGEN_SOAK_LLM_MODE = "proxy"
$env:MERGEN_SOAK_CAPACITY_LADDER = "TRUE"
$env:MERGEN_SOAK_CAPACITY_USERS = "100,250,500,1000"
$env:MERGEN_SOAK_CAPACITY_STEP_SECONDS = "5400"   # 90 dk/adim
$env:MERGEN_SOAK_STOP_ON_FIRST_FAILED_STEP = "TRUE"
$env:MERGEN_SOAK_STABLE_SUCCESS_RATE_MIN = "0.98"
$env:MERGEN_SOAK_TELEMETRY_ENABLED = "TRUE"
Rscript tests/scripts/run_operational_soak_gate.R
```

> Çok uzun tek koşumdan kaçınmak isterseniz her kademeyi ayrı ayrı da
> çalıştırabilirsiniz: `MERGEN_SOAK_CAPACITY_LADDER=TRUE` +
> `MERGEN_SOAK_CAPACITY_USERS=100` (tek adım), sonra `=250`, vb.

**DB havuzunu açmak (kademeli koşumlardan önce, VM `.Renviron`):**

```powershell
$env:MERGEN_DB_POOL_ENABLED = "TRUE"
$env:MERGEN_DB_POOL_MIN_SIZE = "1"
$env:MERGEN_DB_POOL_MAX_SIZE = "8"
# Tam R sürecini yeniden başlatın (tarayıcı yenileme yetmez).
```

**Havuz mekanik + gözlemlenebilirlik preflight'i (önce; hafif, yıkıcı değil):**

```powershell
$env:MERGEN_DB_POOL_ENABLED = "TRUE"
$env:MERGEN_DB_POOL_MIN_SIZE = "1"
$env:MERGEN_DB_POOL_MAX_SIZE = "8"
$env:MERGEN_DB_POOL_IDLE_TIMEOUT = "600"
Rscript --vanilla tests/scripts/run_vm_db_pool_preflight_real.R
```

**SQL Server havuz at-rest preflight (havuzu kalıcı açmadan önce):**

```powershell
$env:MERGEN_DB_POOL_ENABLED = "TRUE"
$env:MERGEN_SQLSERVER_POOL_PREFLIGHT_REAL = "TRUE"
$env:MERGEN_SQLSERVER_POOL_WRITE_TEST = "TRUE"
Rscript tests/scripts/run_vm_sqlserver_pool_preflight_real.R
```

**Gerçek tarayıcı/websocket eşzamanlılık lane'i (uygulama 8009'da çalışırken):**

```powershell
$env:MERGEN_BROWSER_CONCURRENCY_ENABLED = "true"
$env:MERGEN_BROWSER_CONCURRENCY_USERS = "10"
$env:MERGEN_BROWSER_CONCURRENCY_BASE_URL = "http://127.0.0.1:8009/"
Rscript tests/scripts/run_browser_concurrency_lane.R
```

**Gerçek LLM canary + (opsiyonel) küçük throughput probe:**

```powershell
$env:MERGEN_SOAK_PROFILE = "real_llm"
$env:MERGEN_SOAK_LLM_MODE = "real-canary"
$env:MERGEN_REAL_LLM_THROUGHPUT_PROBE = "true"
$env:MERGEN_REAL_LLM_THROUGHPUT_USERS = "2"
# Gerçek endpoint/anahtar yalnız operatör kabuğunda; artifact/PR/docs'a yazılmaz.
Rscript tests/scripts/run_operational_soak_gate.R
```

### 16.8 CPU / çekirdek ölçeklendirme yorumu

**Daha fazla çekirdek MUHTEMELEN yardımcı olur** (telemetri ile kanıtlanırsa):

- Toplam CPU başarısızlık sırasında doygun (`possible_cpu_saturation`, CPU ≥ %85).
- Yük üretici CPU-bound (`possible_load_generator_limit`) — yük üreticiyi ayrı
  makineye taşıyın.
- SQL Server CPU-bound (`possible_sql_server_contention`).
- Birden fazla süreç/worker çekirdekleri gerçekten kullanabiliyor.

**Daha fazla çekirdek MUHTEMELEN yardımcı OLMAZ:**

- Tek Shiny event-loop darboğazı (`possible_app_or_event_loop_queueing`: p95
  patlarken CPU düşük) — bu, dikey çekirdek değil mimari/asenkron iyileştirme ister.
- DB bloklama/bekleme (havuz/lock).
- Client timeout çok kısa (gerçek darboğaz değil; `MERGEN_SOAK_CLIENT_TIMEOUT_SECONDS`).
- Gateway/rate-limit hatası (`gateway_policy_failed`).
- Yük üretici doygunluğu (sonucu app kapasitesi sanmayın).

### 16.9 Bu sertleştirmeden sonra hâlâ VM-only / UNMEASURED kalan

- Gerçek tarayıcı konsol hataları yalnız browser concurrency lane çalıştığında ölçülür.
- Gerçek SQL Server havuzlu at-rest davranışı yalnız VM preflight ile kanıtlanır
  (16.5 encoding kapısı + 16.5A mekanik/gözlemlenebilirlik kapısı).
- Havuzu açmanın **gerçek-sohbet kapasite/throughput etkisi** yalnız havuz açık/kapalı
  attach soak karşılaştırmasıyla ölçülür; preflight'lar bunu kanıtlamaz.
- Gerçek LLM throughput yalnız küçük, tavanlı probe ile gözlemlenir (kapasite değil).
- Bellek büyümesi/telemetri ancak OS sayaçları okunabildiğinde ölçülür.
- 1000 gerçek sürekli insan oturumu hiçbir lane tarafından kanıtlanmaz.

---

## 17. Bağlantı-timeout teşhis sertleştirmesi (2026-06-27 450-kullanıcı bulgusuna yanıt)

Bu bölüm, 13A'daki **450 kullanıcı / connection_timeout doygunluğu** bulgusunu
(CPU düşük ~%21-29, R süreç CPU ~%9.8, app-port TCP ~425) bir sonraki VM koşumunda
**kesin teşhis edebilmek** için eklenen yük-sürücüsü realizm anahtarlarını,
telemetri genişletmesini ve merdiven teşhis alanlarını açıklar. **Hiçbir eşik
düşürülmemiştir; UNMEASURED kontroller hâlâ sessizce PASS sayılmaz.** Bu değişiklik
yalnız teşhis/gözlemlenebilirlik içindir; mevcut pass/fail anlamı korunur.

### 17.1 Kök neden hipotezi

450 kullanıcı adımında baskın hata sınıfı `connection_timeout` (47763) idi;
`response_timeout` yalnız 450 idi. CPU doygun değildi ve kök sayfa GET `/`
yanıtı zaten önbelleklidir (`R/helpers_index_page_cache.R`; her istek önceden
render edilmiş `httpResponse`'tan sunulur) ve attach seridi yalnız GET'tir
(websocket Shiny oturumu kurulmaz). Bu yüzden darboğaz **uygulama UI render veya
oturum başlatma** değildir; en olası adaylar: TCP kabul/backlog doygunluğu, tek
süreç/event-loop kabul kuyruğu, Windows TCP ephemeral-port/TIME_WAIT davranışı,
ya da yük-sürücüsünün her adım başında 450 bağlantıyı **aynı anda (burst)** açması.

### 17.2 Yük sürücüsü realizm anahtarları (varsayılan = mevcut davranış)

`tests/scripts/soak_client.R` kapalı-döngü sürücüsü artık config ile şekillenir.
**Tüm varsayılanlar mevcut "burst" davranışını birebir korur** (ramp yok, tavan
yok, think yok, bağlantı yeniden-kullanım açık); böylece geçmiş pass/fail anlamı
sessizce değişmez. Anahtarlar `config.json` ve `soak_evidence.json` içine
`load_driver` olarak yazılır ve `load_pattern` (burst/ramped/paced/ramped_paced)
açıkça raporlanır:

| Env | Varsayılan | Etki |
| --- | --- | --- |
| `MERGEN_SOAK_RAMP_UP_SECONDS` | `0` | Aktif eşzamanlılığı 1→N'e bu süre boyunca büyütür (0 = ani burst). |
| `MERGEN_SOAK_MAX_NEW_PER_TICK` | `0` | Her poll turunda açılan yeni istek tavanı (0 = sınırsız). |
| `MERGEN_SOAK_THINK_TIME_MS_MIN` / `_MAX` | `0` | Tamamlanan istek ile aynı kullanıcının sonraki isteği arasında jitter'lı bekleme. |
| `MERGEN_SOAK_CONNECTION_REUSE` | `TRUE` | FALSE her isteği taze bağlantıya zorlar (`forbid_reuse`/`fresh_connect`); bağlantı-kurulum maliyetini izole eder. |

Yorumlama: bir sonraki VM koşumunda **rampa eklenince** 450 adımındaki
`connection_timeout` doygunluğu kaybolursa darboğaz "ani bağlantı fırtınası"dır
(kabul/backlog); rampa ile **devam ederse** darboğaz kararlı-durum doygunluğudur
(event-loop/TCP). `connection_reuse=FALSE` ile connect süresi belirgin artarsa
darboğaz bağlantı-kurulum tarafındadır.

### 17.3 Telemetri genişletmesi (TCP durum dağılımı + curl zamanlama + yük-üretici)

- **App-port TCP durum dağılımı**: `soak_system_telemetry.R` artık yalnız toplam
  bağlantı sayısını değil, durum bazında `established / syn_sent / syn_recv /
  time_wait / close_wait / listen` maksimumlarını da örnekler
  (`app_tcp_max_by_state`). Windows'ta `Get-NetTCPConnection -LocalPort` State
  ile, Unix'te `ss -tan` / `netstat` durum kolonuyla. **`syn_recv` yüksekliği
  kabul-kuyruğu (accept backlog) doygunluğunun**, **`time_wait` yüksekliği
  ephemeral-port/TIME_WAIT baskısının** doğrudan göstergesidir.
- **curl zamanlama**: yük sürücüsü tamamlanan her istekten `connect`
  ve uygulama/ilk-byte sürelerini toplar (`metrics$connect_ms_p95`,
  `metrics$ttfb_ms_p95`). `metrics$ttfb_ms_*`, curl `starttransfer` değerinden
  varsa `appconnect`, yoksa `pretransfer`, o da yoksa `connect` çıkarılarak
  hesaplanır; bu nedenle TLS el sıkışması app/TTFB diye sınıflandırılmaz. **connect yüksek +
  ttfb düşük → bağlantı/backlog
  darboğazı; ttfb yüksek → app/event-loop işleme darboğazı.** (Yalnız tamamlanan
  istekler; bağlantı-timeout'unda curl zamanlama gelmez.)
- **Yük-üretici (load generator) telemetrisi**: `launched`, `completed`,
  `max_inflight`, `loop_iters`, `max_loop_lag_ms`, `scheduled_per_sec` ve
  `saturation_hint` (`loadgen_sustained_target` / `loadgen_below_target_concurrency`
  / `loadgen_loop_lag_high`). Bu, darboğazın **istemci/loop tarafı mı yoksa sunucu
  tarafı mı** olduğunu ayırt eder (CLAUDE.md: yük-üretici doygunluğu app kapasitesi
  sanılmamalı).

`ss`/`netstat`/`Get-NetTCPConnection` okunamazsa bu alanlar **UNMEASURED** (NA)
kalır; sessizce PASS sayılmaz.

### 17.4 Kademeli merdiven teşhis alanları

`capacity_ladder` kanıtı artık şunları da içerir:

- `recommended_probe_steps`: stabil=300 / ilk_başarısız=450 ise **350/400/425** gibi
  daraltma kademeleri önerir (doğrudan 450'yi tekrar denemek yerine).
- `dominant_timeout_class`: ilk başarısız adımın baskın hata sınıfı.
- `loadgen_saturation_hint`, `app_tcp_max_by_state`: ilk başarısız adımın yük-üretici
  ve TCP-durum özeti.
- `bottleneck_hint` (tekil) ve genişletilmiş `bottleneck_hints`: baskın sınıf
  `connection_timeout` + düşük CPU ise `possible_connection_accept_or_backlog_saturation`;
  yüksek `syn_recv` ise `possible_accept_backlog_saturation`; yüksek `time_wait` ise
  `possible_time_wait_port_pressure`; yük-üretici hedefin altındaysa
  `possible_load_generator_limit`.

### 17.5 Hâlâ geçerli son kanıtlanmış kilometre taşı

**300 aktif proxy kullanıcı / 90 dakika** hâlâ en uzun süreli stabil proxy attach kanıtıdır.
En yeni kısa merdiven retestinde **400 aktif proxy kullanıcı / 10 dakika** PASS,
**425 aktif proxy kullanıcı** ilk başarısız adım olarak gözlenmiştir. Bu sertleştirme bir kod teşhis katmanıdır;
tek başına 425/450 readiness, 1000 gerçek insan, gerçek LLM throughput, gerçek
tarayıcı/websocket eşzamanlılığı veya SQL Server at-rest encoding KANITLAMAZ.

### 17.6 Önerilen bir sonraki VM koşumu (PowerShell, attach portu 8009)

Önce 300→450 aralığını daraltan kademeli merdiveni telemetri açıkken koş:

```powershell
Remove-Item Env:MERGEN_SOAK_PROFILE,Env:MERGEN_SOAK_LLM_MODE,Env:MERGEN_SOAK_CONCURRENT_USERS,Env:MERGEN_SOAK_DURATION_SECONDS,Env:MERGEN_SOAK_DURATION_MINUTES,Env:MERGEN_SOAK_CAPACITY_CURVE,Env:MERGEN_SOAK_CAPACITY_LADDER,Env:MERGEN_SOAK_CAPACITY_USERS,Env:MERGEN_SOAK_CAPACITY_STEP_SECONDS,Env:MERGEN_SOAK_STOP_ON_FIRST_FAILED_STEP,Env:MERGEN_SOAK_STABLE_SUCCESS_RATE_MIN,Env:MERGEN_SOAK_HTTP_LANE,Env:MERGEN_SOAK_INTERACTIVE_LANE,Env:MERGEN_SOAK_INTERACTIVE_USERS,Env:MERGEN_SOAK_INTERACTIVE_ITERATIONS,Env:MERGEN_SOAK_RAMP_UP_SECONDS,Env:MERGEN_SOAK_MAX_NEW_PER_TICK,Env:MERGEN_SOAK_THINK_TIME_MS_MIN,Env:MERGEN_SOAK_THINK_TIME_MS_MAX,Env:MERGEN_SOAK_CONNECTION_REUSE,Env:MERGEN_SOAK_TELEMETRY_ENABLED,Env:MERGEN_SOAK_TELEMETRY_INTERVAL_SECONDS -ErrorAction SilentlyContinue

$env:MERGEN_SOAK_APP_URL = "http://127.0.0.1:8009/"
$env:MERGEN_SOAK_PROFILE = "proxy_llm"
$env:MERGEN_SOAK_LLM_MODE = "proxy"
$env:MERGEN_SOAK_PROXY_FORWARD_REAL = "FALSE"
$env:MERGEN_SOAK_CAPACITY_LADDER = "TRUE"
$env:MERGEN_SOAK_CAPACITY_USERS = "100,300,350,400,410,415,420,425"
$env:MERGEN_SOAK_CAPACITY_STEP_SECONDS = "5400"
$env:MERGEN_SOAK_STABLE_SUCCESS_RATE_MIN = "0.98"
$env:MERGEN_SOAK_STOP_ON_FIRST_FAILED_STEP = "TRUE"
$env:MERGEN_SOAK_TELEMETRY_ENABLED = "TRUE"

Rscript --vanilla tests/scripts/run_operational_soak_gate.R
```

Ardından darboğazı "burst mü kararlı-durum mu" diye ayırmak için aynı merdiveni
**rampa + bağlantı çeşitliliği** ile tekrarla (eşikler aynı; yalnız arrival deseni
değişir). Örnek ek anahtarlar:

```powershell
$env:MERGEN_SOAK_RAMP_UP_SECONDS = "120"     # her adımda 1->N'e 120 sn rampa
$env:MERGEN_SOAK_MAX_NEW_PER_TICK = "25"      # bağlantı fırtınasını yumuşat
# Opsiyonel: bağlantı-kurulum maliyetini izole etmek için
# $env:MERGEN_SOAK_CONNECTION_REUSE = "FALSE"
```

Kanıtı oku: `soak_evidence.json` içinde `capacity_ladder.bottleneck_hint`,
`capacity_ladder.dominant_timeout_class`, `system_telemetry.app_tcp_max_by_state`
ve `metrics.connect_ms_p95` / `metrics.ttfb_ms_p95`. `ttfb_ms_p95` TLS/pretransfer-sonrası
ilk-byte bileşenidir. `connect_ms_p95` büyük + `ttfb_ms_p95` küçük ise darboğaz
bağlantı/backlog; tersi ise app işleme.

---

## 18. 2026-06-27 Çalışma-zamanı performans/yatay-ölçekleme katmanı (425 bulgusuna yanıt)

§17 yalnız teşhis/gözlemlenebilirlik ekledi. Bu bölüm, 13A/§17 bulgusuna
(`connection_timeout` baskın, CPU düşük, app-port TCP ~425, kök sayfa zaten
önbellekli, attach seridi yalnız GET) yanıt olarak eklenen **gerçek çalışma-zamanı
uygulama değişikliklerini** ve önerilen VM rerun'ını açıklar. **Hiçbir soak eşiği
düşürülmedi; soak gate pass/fail mantığı, kapasite-merdiveni, timeout-atfı ve
UNMEASURED dürüstlüğü DEĞİŞMEDİ.** Güvenlik/anahtar-izolasyon/redaksiyon/upload/
DB-işlem/encoding kontrolleri korundu.

### 18.1 Kök neden ve dürüst çözüm

Darboğaz uygulama UI render veya oturum başlatma değildir (kök sayfa
`R/helpers_index_page_cache.R` ile önbellekli; attach seridi websocket Shiny
oturumu kurmaz). Baskın `connection_timeout` + düşük CPU, **tek httpuv sürecinin
TCP kabul/backlog doygunluğuna** işaret eder. Bunun dürüst çözümü **yatay
ölçeklemedir** (birden çok worker süreci, her biri kendi kabul döngüsüyle, bir
yük-dengeleyici arkasında). Tek süreçte 1000 kullanıcı kanıtlanmaya çalışılmaz.

### 18.2 Eklenen çalışma-zamanı değişiklikleri

- **Sağlık/hazırlık uç noktaları** — `GET /healthz` (canlılık), `GET /readyz`
  (sır-güvenli hazırlık + uygulama-içi metrik anlık görüntüsü). DB/oturum işi
  yapmaz. `R/helpers_app_http_routes.R`; `uiPattern` yalnız `/`, `/healthz`,
  `/readyz` eşler. `MERGEN_HEALTH_ENDPOINT=false` ile kapatılabilir.
- **Çok-worker başlatıcı** — `tools/run_mergen_workers.R`. `MERGEN_WORKERS=N` ile
  N worker (`MERGEN_PORT` = base..base+N-1). Yalnız `processx`. Varsayılan 1
  (mevcut tek-süreç davranışı).
- **Backpressure** — `R/helpers_request_backpressure.R`, süreç-geneli eşzamanlı
  pahalı-işlem üst-sınırı, TTL-ile-kendi-iyileşen. **Varsayılan KAPALI**
  (`MERGEN_MAX_CONCURRENT_LLM=0` -> no-op). Açıkken aşım, uzun gizli timeout
  yerine hızlı/dostça "sunucu yoğun" verir.
- **Süreç-içi metrikler** — `R/helpers_runtime_metrics.R`, sır-güvenli sayaçlar;
  `/readyz` ile süreç dışına açılır (attach seridi bunları doğrudan göremez).

### 18.3 Uygulama-içi iyileşmeyi gözlemleme (attach modu)

Attach modlu yük sürücüsü uygulamanın iç sayaçlarını göremez. Worker'ın
`/readyz` çıktısını periyodik okuyarak kök sayfa önbellek isabeti, backpressure
admit/reject ve DB havuz sayaçları gözlemlenebilir (sır içermez):

```powershell
curl.exe -s http://127.0.0.1:8009/readyz
```

### 18.4 Yatay ölçekleme dağıtımı (Windows VM)

```powershell
# N worker'i farkli portlarda baslat (kurumsal ters-vekil arkasinda):
$env:MERGEN_WORKERS = "4"          # 8009,8010,8011,8012
$env:MERGEN_BASE_PORT = "8009"
$env:MERGEN_HOST = "0.0.0.0"
Rscript tools/run_mergen_workers.R
```

Yük-dengeleyici, her worker'i `GET /healthz` ile canlilik, `GET /readyz` ile
hazirlik kontrolune tabi tutmalidir. Tek-surec dagitimi (run_mergen_prod.bat)
degismeden kalir.

### 18.5 Önerilen VM rerun (300→425 daraltma, telemetri açık)

Mevcut son stabil kademe **300 aktif proxy kullanıcı / 90 dakika**. Bu katman tek
başına 425 readiness, 1000 gerçek insan, gerçek LLM throughput veya gerçek
tarayıcı/websocket eşzamanlılığı KANITLAMAZ. Aşağıdaki kademeli merdiveni
(100,300,350,400,425) Windows VM'de canlı uygulamaya attach ederek tekrar koşun:

```powershell
$env:MERGEN_SOAK_APP_URL = "http://127.0.0.1:8009/"
$env:MERGEN_SOAK_PROFILE = "proxy_llm"
$env:MERGEN_SOAK_LLM_MODE = "proxy"
$env:MERGEN_SOAK_PROXY_FORWARD_REAL = "FALSE"
$env:MERGEN_SOAK_CAPACITY_LADDER = "TRUE"
$env:MERGEN_SOAK_CAPACITY_USERS = "100,300,350,400,425"
$env:MERGEN_SOAK_CAPACITY_STEP_SECONDS = "600"
$env:MERGEN_SOAK_STABLE_SUCCESS_RATE_MIN = "0.98"
$env:MERGEN_SOAK_STOP_ON_FIRST_FAILED_STEP = "TRUE"
$env:MERGEN_SOAK_TELEMETRY_ENABLED = "TRUE"
Rscript --vanilla tests/scripts/run_operational_soak_gate.R
```

Çok-worker dağıtımda (önerilen): aynı merdiveni yük-dengeleyici kök URL'sine
attach ederek koşun ve `effective_success_rate` ile `capacity_ladder`'ın 425'te
PASS olup olmadığını okuyun. Başarı kriteri ya 425'te `>= 0.98`, ya da
`connection_timeout`'un belirgin azalması + kalan darboğazın app-dışı (tek-süreç
httpuv / yük-üretici loop doygunluğu) olduğunun telemetriyle kanıtlanmasıdır.


### 18.6 Cumartesi doğrudan iki-worker bölünmüş yük kanıtı (2026-06-27)

**Cumartesi 2026-06-27 doğrudan bölünmüş yük sonucu:** 8008 ve 8009 üzerinde
çalışan iki yerel MERGEN worker'ı, elle bölünmüş 750 toplam aktif proxy
kullanıcılık arka uç yükünü 30 dakika (375+375) boyunca sürdürdü; iki koşum da
PASS verdi ve hata/timeout sayısı sıfırdı. Bu sonuç yatay-ölçekleme/backlog
hipotezini maddi olarak destekler; ancak henüz tek URL'li Keycloak/ters-vekil
yük-dengeleme kanıtı değildir. Sonraki resmi kanıt, gerçek bir yük-dengelemeli URL
yapılandırıp merdiveni bu URL üzerinden tekrarlamaktır.

Bağlam ve kapsam:

- Cumartesi günü IT, gerçek Keycloak/ters-vekil ön-kapı URL'sini
  (`https://mergen.com.tr/bilge`) yük-dengelemeli rota olarak yapılandırmak için
  uygun değildi.
- Operatörler bunun yerine iki arka uç worker'ı yerel olarak başlattı ve doğrudan
  hedefledi: worker A `http://127.0.0.1:8008/`, worker B
  `http://127.0.0.1:8009/`.
- Bu nedenle bu sonuç **doğrudan bölünmüş yük arka uç kanıtıdır**; gerçek tek
  URL'li yük-dengeleme kanıtı değildir.
- Önceki tek-worker proxy attach testleri 400-425 aktif kullanıcı sınırında
  `connection_timeout`/backlog belirtileriyle başarısız olurken iki worker'ın 750
  toplam doğrudan bölünmüş aktif proxy kullanıcıyı 30 dakika boyunca sıfır
  hata/timeout ile sürdürmesi yatay-ölçekleme hipotezini destekler.

Windows VM ekran görüntülerinden gözlenen kilometre taşları:

| Birleşik hedef | Bölüşüm | Süre | Sonuç | Kanıt notları |
|---:|---:|---:|---|---|
| 425 aktif proxy kullanıcı | 8008 üzerinde 212 + 8009 üzerinde 213 | 600 sn | PASS/PASS | 8008 `artifacts/soak/20260627-141848`: 66718/66718 başarı, 0 hata, 0 timeout, p50/p95/p99 ~= 1549.2/1884.5/4781.9 ms, iş hacmi ~= 6656.2 ops/dk, max CPU ~= %41, max app-port TCP ~= 214. 8009 `artifacts/soak/20260627-141858`: 66690/66690 başarı, 0 hata, 0 timeout, p50/p95/p99 ~= 1554.1/1899.8/4766.8 ms, iş hacmi ~= 6651.1 ops/dk, max CPU ~= %43, max app-port TCP ~= 215. |
| 600 aktif proxy kullanıcı | 8008 üzerinde 300 + 8009 üzerinde 300 | 600 sn | PASS/PASS | 8008 `artifacts/soak/20260627-143534`: 66610/66610 başarı, 0 hata, 0 timeout, p50/p95/p99 ~= 2219.3/2724.3/6399 ms, iş hacmi ~= 6627.7 ops/dk, max CPU ~= %43, max app-port TCP ~= 302. 8009 `artifacts/soak/20260627-143541`: 66697/66697 başarı, 0 hata, 0 timeout, p50/p95/p99 ~= 2189.5/2705.9/6673.1 ms, iş hacmi ~= 6629.8 ops/dk, max CPU ~= %50, max app-port TCP ~= 302. |
| **750 aktif proxy kullanıcı** | **8008 üzerinde 375 + 8009 üzerinde 375** | **1800 sn** | **PASS/PASS** | **En güçlü Cumartesi arka uç bölünmüş yük kanıtı.** 8008 `artifacts/soak/20260627-144755`: 103848/103848 başarı, 0 hata, 0 timeout, p50/p95/p99 ~= 3061.3/11044.5/11624.6 ms, iş hacmi ~= 3457.1 ops/dk, max CPU ~= %53, max app-port TCP ~= 377, anahtar yönlendirme 5/5 doğru, sır sızıntısı 0, sunucu çökmedi TRUE, mojibake hits 0. 8009 `artifacts/soak/20260627-144759`: 103804/103804 başarı, 0 hata, 0 timeout, p50/p95/p99 ~= 3113.6/11025.1/11595.8 ms, iş hacmi ~= 3451.3 ops/dk, connect p50/p95 0/0 ms, ttfb p50/p95 ~= 1985.1/6433.7 ms, max CPU ~= %54, max app-port TCP 377, app TCP max established=376/syn_recv=0/syn_sent=0/time_wait=0/close_wait=0/listen=1. |

375-kullanıcı/30-dakika eş koşumundaki 8009 kanıt dizini için ek ayrıntılar:
`load_driver.pattern=burst`, `target_users=375`, `max_inflight=375`,
`completed=103804`, `max_loop_lag_ms~=6656.7` ve
`saturation_hint=loadgen_loop_lag_high`. Bu loop-lag ipucu, 375-per-worker
seviyesinde yük üreticinin de baskıya katkı yapabileceği anlamına gelir; doğrudan
bölünmüş arka uç kanıtının ötesine taşan iddialarda bulunmayın. Aynı kanıt DB
havuzu için checkout=451, returned=451, outstanding/leak=0, tx commit=200,
rollback=50; etkileşimli serit için 50 oturum, 400 eylem, success_rate=1.000, DB
leak=0, rollback clean TRUE, upload TRUE, mojibake=0 raporladı.

Kanıt dürüstlüğü / kanıtlamaz:

- Üretim Keycloak/ters-vekil rotasının iki worker arasında zaten yük-dengelemeli
  olduğunu **kanıtlamaz**.
- Bu ölçekte gerçek tarayıcı/websocket eşzamanlılığını veya gerçek insan Shiny
  oturumlarını **kanıtlamaz**.
- Gerçek LLM sağlayıcı iş hacmini **kanıtlamaz**.
- 1000 gerçek eşzamanlı aktif kullanıcıyı **kanıtlamaz**.
- 90 dakikalık üretim-benzeri readiness/sertifikasyon kapısının yerine **geçmez**.
- Mevcut VM/DB kapılarının ötesinde SQL Server at-rest Türkçe encoding kanıtı
  **eklemez**.


### 18.7 2026-06-27/28 uzun split proxy soak: kapasite kapısı FAIL, doğruluk/gizlilik kontrolleri PASS

**Kaynak durumu:** Bu kayıt operatör ekran görüntülerinden yazılmıştır; bu checkout
içinde `artifacts/soak/20260627-180246/soak_evidence.json` ve
`artifacts/soak/20260627-180302/soak_evidence.json` bulunamadı. Ham JSON artifact
sonradan eklenirse, aşağıdaki ekran-transkripsiyon değerleri raw artifact ile
yeniden doğrulanmalıdır. Operatör koşumu “375+375 / 18h” olarak tarif etti;
yakalanan artifact/ekran değerleri ise lane başına `MERGEN_SOAK_CONCURRENT_USERS=350`
ve hedef süre `MERGEN_SOAK_DURATION_SECONDS=86400` gösteriyor, gerçek duvar süresi
yaklaşık 86.5k saniye. Raw evidence daha sonra aksini kanıtlamadıkça artifact
değerleri kaynak gerçek kabul edilir.

Koşum profili: gate `run_operational_soak_gate`, profile `proxy_llm`, niyet
sahte kişisel-anahtar/proxy-şerit modu, `MERGEN_SOAK_LLM_MODE=proxy`, real LLM
forwarding `FALSE`, load pattern `burst`, connection reuse `TRUE`, ramp-up `0`
saniye, think time `0` ms, hedef kullanıcı tabanı `1000`, yakalanan lane başına
aktif kullanıcı `350`. Kapasite merdiveni bu artifact'ta çalışmadı/kapalıydı; bu
nedenle 50→100→250→500→1000 staged stable kapasite kanıtı türetilemez.

| Artifact / tarih | Port / lane | Profil | Configured users | Wall seconds | Requests | Successes | Timeouts | Effective success rate | Threshold | Result | Dominant failure reason |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| `artifacts/soak/20260627-180246/` (ekran; raw JSON bu checkout'ta yok) | `http://127.0.0.1:8008/` | `proxy_llm` / proxy | 350 | ≈86496.9 | 627226 | 256467 | 370759 | ≈0.4089 | 0.98 | **FAIL** | `effective_success_rate` düşük; baskın `connection_timeout` (`370441`) + `response_timeout` (`318`) |
| `artifacts/soak/20260627-180302/` (ekran; raw JSON bu checkout'ta yok) | `http://127.0.0.1:8009/` | `proxy_llm` / proxy | 350 | ≈86505 | 627007 | 248673 | 378334 | ≈0.3965 | 0.98 | **FAIL** | `effective_success_rate` düşük; `connection_timeout` baskın (`connection_timeout` yaklaşık `378136`, `response_timeout` yaklaşık `398`) |

Kısa yorum: Privacy, routing, isolation, DB-pool hygiene, encoding helper
round-trip, and interactive action checks passed under the captured proxy soak.
The gate failed because success rate collapsed under connection timeout pressure,
with loadgen loop lag high. This artifact should be treated as a failed capacity
proof but a useful negative/diagnostic soak record. Bu **kapasite/throughput kapısı
başarısızlığıdır**; ekranlarda uygulama doğruluğu, gizlilik veya anahtar izolasyonu
başarısızlığı görünmemektedir. Her iki lane'de `errors=0`; p95 gecikme yaklaşık
26.0 s, p99 yaklaşık 27.2 s, throughput yaklaşık 435 op/dk/lane olarak gözlendi.

Yük üretici / doygunluk sinyali: ekranlar `mean_loop_lag_ms≈21998`,
`max_loop_lag_ms≈61429` ve `saturation_hint=loadgen_loop_lag_high` gösteriyor. Bu
kanıt, baskın darboğaz sinyalinin yük sürücüsü / üretilen bağlantı basıncı / proxy
lane doygunluğu tarafında olduğunu düşündürür; üretim kapasitesi olarak
ilerletilmemelidir.

Geçen pozitif kontroller (ekran-transkripsiyon): sunucu koşum sonunda canlıydı;
`raw_key_leak_count=0`, `raw_prompt_leak_count=0`; personal/default/missing key
routing sınıflaması geçti; cross-session isolation geçti; key-owner mismatch
reddedildi; upload validation geçti; Turkish + emoji DB encoding helper
round-trip geçti; `mojibake_hits=0`; redaction validated `TRUE`; interactive lane
50 oturum / 400 eylem / success ratio 1.0 ve p50/p95/p99 yaklaşık 5.9/10.4/16 ms;
DB pool checkout=451, return=451, outstanding/sızıntı=0, tx_commit=200,
tx_rollback=50 ve leaked rollback row yok. Sistem telemetrisi örneklendi: max
toplam CPU yaklaşık %56, max bellek yaklaşık 18866 MB, max R process memory
yaklaşık 3929 MB, max app-port TCP yaklaşık 352, established yaklaşık 351; server
crash görünmedi.

**Kanıtlamaz / Does not prove:**

- 1000 gerçek aktif kullanıcıyı kanıtlamaz.
- Production real-LLM throughput'u kanıtlamaz; bu `proxy_llm` / fake proxy-strip
  modudur ve real forwarding kapalıdır.
- Gerçek tarayıcı/websocket Shiny concurrency kanıtı değildir.
- Production SQL Server'da Turkish at-rest correctness kanıtı değildir.
- Gözlenen loadgen davranışı dışında Windows VM kapasitesini kanıtlamaz.
- Capacity ladder kapalı/çalışmadığı için 50→100→250→500→1000 staged stable
  capacity ladder kanıtı değildir.
- Bazı DB veya interactive kontroller local/in-process/helper-level simülasyon
  kullandıysa real SQL Server davranışını kanıtlamaz.
- `browser_console_errors` unmeasured/NA olduğu yerde tarayıcı konsolu temizliğini
  kanıtlamaz.

Pazartesi IT / platform sahipleri takip işi:

- Mevcut `https://mergen.com.tr/bilge` ön-kapı/Keycloak/ters-vekil rotasını veya
  `/bilge-lb-test` gibi geçici bir rotayı `8008` ve `8009` arasında dağıtacak
  şekilde yapılandırın; onay sonrası ek worker portları da havuza alınabilir.
- Gerekli proxy davranışı: `GET /healthz` sağlık kontrolü, `GET /readyz`
  hazırlık kontrolü, websocket upgrade desteği, uzun okuma/gönderme timeout'ları,
  gerçek Shiny kullanıcıları için yapışkan oturum/oturum yakınlığı ve
  en-az-bağlantı veya round-robin dengeleme.

Önerilen sonraki resmi kanıt:

1. Keycloak/proxy rotasına karşı gerçek tek URL'li yük-dengelemeli soak koşumu yapın.
2. İlk hedefler olarak 425, 600 ve 750 aktif proxy kullanıcıyla başlayın.
3. Önce 10 dakikalık merdiven, ardından en güçlü geçen hedefte 30 dakikalık
   doğrulama ve ancak daha sonra 90 dakikalık sertifikasyon kapısı koşun.

## 19. 2026-06-29 — Akış olay-döngüsü sertleştirmesi + 450-kullanıcı merdiveni PASS

**Kaynak durumu:** Operatör konsolundan gözlemlendi; bu checkout'ta
`artifacts/soak/20260629-082244/soak_evidence.json` bulunmuyor. Ham JSON sonradan
eklenirse aşağıdaki değerler raw artifact ile yeniden doğrulanmalıdır.

Koşum: `run_operational_soak_gate.R`, profil `proxy_llm`, `MERGEN_SOAK_LLM_MODE=proxy`,
`MERGEN_SOAK_PROXY_FORWARD_REAL=FALSE` (gerçek LLM yönlendirme KAPALI), kapasite
merdiveni `100,300,350,400,425,450`, adım `300s`, `MERGEN_SOAK_STABLE_SUCCESS_RATE_MIN=0.98`,
yük hedefi `http://127.0.0.1:8009/` (tek worker, GET-only index), in-process
interactive şerit + proxy LLM şeridi aynı süreçte.

| Adım (kullanıcı) | İstek | eff | p95 (ms) | tput (/dk) | cpu_max | Sonuç |
|---:|---:|---:|---:|---:|---:|---|
| 100 | 37832 | 1.0 | 854.1 | 7566.4 | %28 | PASS |
| 300 | 28642 | 1.0 | 2966.1 | 5728.4 | %21 | PASS |
| 350 | 9372 | 1.0 | 10996.4 | 1874.4 | %29 | PASS |
| 400 | 9377 | 1.0 | 12545.3 | 1875.4 | %31 | PASS |
| 425 | 9436 | 0.9826 | 13384.2 | 1887.2 | %11 | PASS |
| 450 | 9383 | 1.0 | 14254.2 | 1876.6 | %16 | PASS |

Genel: `stabil=450`, `ilk_basarisiz=NA`, `onerilen_sonraki=450`; toplam istek 104042,
başarı 103878 (0.9984), errors=0, timeout=164 (tümü `connection_timeout`),
p50/p95/p99=2407/12504.8/13880 ms. Anahtar yönlendirme 5/5, izolasyon TRUE,
`mojibake_hits=0`, `secret_leak=0`, redaksiyon doğrulandı; interactive lane
DB-no-leak/isolation/rollback PASS. **Genel sonuç: PASS.**

Dürüst yorum: Merdiven 450'ye kadar geçse de, ~300 kullanıcıdan sonra **throughput
çöküyor (7566→1874/dk) ve p95 ~14 s'ye tırmanıyor; CPU ise %21–31'de kalıyor.** Düşük
CPU + throughput çöküşü, **tek httpuv/Shiny olay-döngüsünde index-sunumu
serileştirmesi** imzasıdır (CPU darboğazı değil). Kalan kaldıraç, yalnızca **8009 +
8008** üzerinden yük-dengelemeli bir URL ve bu PR'ın olay-döngüsü anahtarlarıdır.

**Kanıtlamaz / Does not prove:** 1000 gerçek aktif kullanıcı; production real-LLM
throughput (`PROXY_FORWARD_REAL=FALSE`); gerçek tarayıcı/websocket Shiny concurrency;
production SQL Server Turkish at-rest correctness. Bu kanıt yalnızca proxy + GET-only
HTTP + in-process interactive şeritlerine aittir ve tek worker (8009) ile alınmıştır.

### 19.1 Akış olay-döngüsü sertleştirme anahtarları (varsayılan = mevcut davranış)

Bu PR, `R/server_handler_true_streaming.R` yoklama döngüsünü hafifletir: artımlı akış
dosyası okuma (her yoklamada tüm dosya yeniden okunmaz), opsiyonel uyarlanır yoklama
geri çekilmesi, daha geniş delta taşımacılığı, takip (follow-up) üretimini yük altında
kısma/atlama, kaydedilen-sohbet yenilemesi debounce'u, araç-ailesine göre backpressure
türleri ve savunmacı akış/akıl yürütme metin üst sınırları. Tüm anahtarlar **varsayılan
KAPALI/no-op**'tur; yalnızca açıkça ayarlanınca devreye girer:

```
MERGEN_STREAM_POLL_IDLE_BACKOFF=true
MERGEN_STREAM_POLL_MIN_MS=25
MERGEN_STREAM_POLL_MAX_MS=250
MERGEN_STREAM_POLL_BACKOFF_FACTOR=1.5
MERGEN_STREAM_DELTA_DEFAULT=true
MERGEN_MAX_CONCURRENT_LLM=50
MERGEN_MAX_CONCURRENT_SQL_ANALYSIS=10
MERGEN_MAX_CONCURRENT_MCP_EXCEL=8
MERGEN_MAX_CONCURRENT_SUMMARIZATION=10
MERGEN_MAX_CONCURRENT_FOLLOWUPS=5
MERGEN_DISABLE_FOLLOWUPS_UNDER_BACKPRESSURE=true
MERGEN_FOLLOWUP_DELAY_SECONDS=1
MERGEN_SAVED_CHATS_REFRESH_DEBOUNCE_MS=1000
MERGEN_MAX_STREAM_CHARS=120000
MERGEN_MAX_REASONING_CHARS=80000
```

Yeni sayaçlar `/readyz` anlık görüntüsünde (yalnızca sayısal, sır-güvenli) görünür:
`stream_poll_file_read_calls/fallback/bytes`, `stream_poll_idle_backoff_count`,
`stream_poll_delta_reset_count`, `stream_text_truncated`, `stream_reasoning_truncated`,
`followups_*`, `saved_chats_refresh_*`. Geri alma: yeni ortam değişkenlerini kaldırmak
önceki davranışa döndürür. Bu, port sayısını değiştirmez — uygulama yalnızca **8009 ve
8008** ile sınırlıdır.
