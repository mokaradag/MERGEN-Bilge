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
  `soak_scenarios.R`, `soak_client.R`, `soak_artifacts.R`,
  `soak_secret_redaction.R`, `mock_llm_server.R`, `proxy_llm_server.R`
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

---

## 6. Artifact'lar

Çıktı dizini: `artifacts/soak/<timestamp>/` (git tarafından yok sayılır).

| Dosya | İçerik |
|-------|--------|
| `soak_evidence.json` | Makinece okunabilir kanıt (şema + does_prove/does_not_prove) |
| `summary.md` | İnsan-okunur özet |
| `metrics.csv` | İstek başına metrikler (zaman, serit, senaryo, gecikme, durum, kaynak) |
| `failures.jsonl` | Başarısız istekler (redakteli) |
| `config.json` | Secret-safe yapılandırma (ham endpoint/key YOK) |
| `key_routing_summary.json` | Anahtar yönlendirme + izolasyon özeti |
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
- Hata durumunda bile artifact üretilir; gerçek başarısızlıkta `stop()` ile sıfır-dışı
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

**Kanıtlamaz (does_not_prove):**

- 1.000 gerçek eşzamanlı aktif kullanıcıyı kanıtlamaz.
- Gerçek LLM sağlayıcısının bu eşzamanlılık için üretim throughput'unu
  kanıtlamaz.
- Windows VM dışındaki gerçek ağlardaki üretim gecikmesini kanıtlamaz.
- Tam-yığın tarayıcı/websocket Shiny oturum eşzamanlılığını kanıtlamaz
  (in-process alıştırmalar **helper-düzeyidir**).
- Gerçek SQL Server'a Türkçe yazımının at-rest doğruluğunu kanıtlamaz (ayrı VM
  kodlama preflight kapısıdır: `run_vm_encoding_preflight_real.R`).

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
- Soak artifact'ı yalnızca PASS olarak raporladığı kontroller için yürütme
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

### Fake-lane kapasite sınırı

19 Haziran 2026 itibarıyla fake-LLM smoke operasyonel soak kapısında mütevazı
bir kapasite/performance iyileşmesi gözlenmiştir: **22 aktif eşzamanlı kullanıcı
/ 300 saniye PASS** artık en güçlü sürdürülebilir fake-lane kanıtıdır; **23 aktif
eşzamanlı kullanıcı / 60 saniye PASS** ise yalnızca kısa süreli sınır kanıtıdır.
**24 aktif eşzamanlı kullanıcı ve üzeri**, `effective_success_rate` 0.98 eşiğinin
altına düştüğü için bu smoke/fake seridin belgelenmiş güvenilir işletim zarfının
dışındadır. **25 aktif eşzamanlı kullanıcı / 30 saniye PASS** yalnızca kısa spike
gözlemi olarak kaydedilir; sürdürülebilir kapasite diye belgelenmemelidir.

| Aktif eşzamanlı kullanıcı | Süre | Sonuç | Not |
|---:|---:|---|---|
| 10 | 30 sn | PASS | 2026-06-18 short smoke sanity; `MERGEN_SOAK_DURATION_SECONDS` override doğrulandı. |
| 15 | 60 sn | PASS | 2026-06-18 kısa VM sanity için temiz kanıt. |
| 20 | 300 sn | PASS | 2026-06-18 önceki stabil kanıt: 418 istek, 418 başarı, 0 hata, 0 timeout, `effective_success_rate=1.000`. |
| 22 | 300 sn | PASS | **2026-06-19 en güçlü sürdürülebilir fake-lane kanıtı:** `artifacts/soak/20260619-153052/soak_evidence.json`; 408 istek, 408 başarı, 0 hata, 0 timeout, `effective_success_rate=1.000`, `raw_success_rate=1.000`, p50/p95/p99 = 16983.3/18386.2/18791.0 ms, throughput 81.4 istek/dk, `secret_leak=0`, `no_server_crash=TRUE`. |
| 23 | 60 sn | PASS | 2026-06-19 kısa sınır kanıtı: `artifacts/soak/20260619-152901/soak_evidence.json`; 100 istek, 100 başarı, 0 hata, 0 timeout, `effective_success_rate=1.000`, p50/p95/p99 = 16784.2/18948.5/19362.5 ms, throughput 100 istek/dk. |
| 24 | 60 sn | FAIL | 2026-06-19 guardrail: `artifacts/soak/20260619-152715/soak_evidence.json`; 98 istek, 88 başarı, 10 timeout, `effective_success_rate=0.898` < 0.98. |
| 24 | 300 sn | FAIL | 2026-06-19 guardrail: `artifacts/soak/20260619-153656/soak_evidence.json`; 383 istek, 49 başarı, 334 timeout, `effective_success_rate=0.1279` < 0.98. |
| 25 | 30 sn | PASS | 2026-06-19 kısa spike gözlemi: `artifacts/soak/20260619-145315/soak_evidence.json`; 65 istek, 65 başarı, 0 hata, 0 timeout, throughput yaklaşık 129.4 istek/dk. **Sürdürülebilir kapasite kanıtı değildir.** |
| 26 | 30 sn | FAIL | 2026-06-19 guardrail: `artifacts/soak/20260619-152033/soak_evidence.json`; 561 istek, 12 başarı, 549 hata, `effective_success_rate=0.0214` < 0.98. |
| 30 | 60 sn | FAIL | 2026-06-18 timeout saturasyonu. |
| 100 | 30 sn | FAIL | 2026-06-18 timeout saturasyonu; kapasite iddiası değildir. |

22/300 sn ve 23/60 sn PASS koşularında doğruluk/güvenlik kontrolleri temizdir:
anahtar yönlendirme 5/5, upload validation 7/7, encoding round-trip pass rate 1,
cross-session key isolation `TRUE`, secret leak 0, server crash yok,
`mojibake_hits=0`, redaction verified `TRUE`. `temp_growth_mb` yaklaşık 0.31 MB
ile PASS'tir. `memory_growth_mb` ve `browser_console_errors` bu koşularda
`UNMEASURED` olduğundan ölçülmüş PASS olarak sunulmamalıdır.

Önerilen işletim yorumu:

- Günlük hızlı sanity: **10 aktif kullanıcı / 30 saniye**.
- Daha güçlü VM sanity: **15 aktif kullanıcı / 60 saniye**.
- Mevcut güvenli test edilmiş fake-lane kapasite: **22 aktif eşzamanlı kullanıcı / 300 saniye PASS**.
- Kısa edge gözlemi: **23 aktif eşzamanlı kullanıcı / 60 saniye PASS**; sustained kapasite diye sunulmaz.
- Başlayan failure bölgesi: **24 aktif eşzamanlı kullanıcı ve üzeri FAIL** (`effective_success_rate` 0.98 eşiğinin altına düşer).

### Proxy-lane ve stress bulguları

Proxy lane ve stress/capacity-curve denemeleri anahtar yönlendirme ve izolasyon
kontrollerinin çalıştığını doğruladı. Proxy/stress kapasite eğrisinde 10 kullanıcı
makul görünürken 25+ kullanıcı timeout saturasyonuna girdi; 50 ve 100 kullanıcı
badly saturated olarak gözlendi. Bu sonuçlar normal smoke başarısızlığı değil,
bilinçli stress/failure probe olarak yorumlanmalıdır.

Pozitif kontroller: `key_routing_correct=PASS`, `cross_session_key_isolation=PASS`,
`upload_validation_correct=PASS`, `secret_leak=0`, uygulanabilir koşularda
`no_server_crash=TRUE`.

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
- Fake LLM lane, 22 aktif eşzamanlı kullanıcıyı 5 dakika boyunca sıfır hata ve
sıfır timeout ile sürdürebilir; 23 aktif kullanıcı yalnızca 60 saniyelik kısa edge
kanıtıdır.
- Key routing, cross-session key isolation, upload validation, secret-redaction
kontrolleri ve encoding helper kontrolleri geçti.

Bu koşumlar **kanıtlamaz**:

- 1.000 gerçek aktif eşzamanlı kullanıcı.
- 50/100 kullanıcı production throughput.
- Browser/websocket Shiny session concurrency.
- Gerçek LLM provider throughput veya real-canary throughput.
- VM dışı production network latency.
- At-rest SQL Server encoding davranışı.
