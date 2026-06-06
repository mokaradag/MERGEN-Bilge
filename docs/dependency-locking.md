# Bağımlılık Kilitleme (renv) — MERGEN Bilge

Bu belge, MERGEN Bilge için `renv` tabanlı bağımlılık kilit mekanizmasını
açıklar. Amaç: üretim/geliştirme Windows VM'indeki **çalışan R 4.6.0 paket
kütüphanesinin** kesin sürümlerini `renv.lock` içinde sabitlemek ve temiz bir
ortamda bu sürümleri geri yükleyebilmek.

> **En önemli kural:** `renv.lock` **ÇALIŞAN Windows VM'inizden** üretilmelidir
> (R 4.6.0 + güncel kütüphane). Linux/bulut/Codex ortamında `renv.lock`
> ÜRETMEYİN; aksi halde kilit, üretim temel hattınız olmayan sürümleri/sistem
> varsayımlarını kodlar.

---

## 1. Tasarım Özeti

- **Tek insan-okunur manifest:** `R/config_packages.R` (`required_packages`).
  Uygulama açılışındaki eksik-paket doğrulaması (`requireNamespace`) KORUNUR.
- **Kesin sürüm kaynağı:** `renv.lock` (Windows VM'de üretilir).
- **Otomatik yükleyici:** kök `.Rprofile`, `renv/activate.R`'yi YALNIZCA kilit
  gerçekten varsa ve renv kuruluysa çağırır (offline/üretim güvenli; ayrıntı §4).
- **CI/önyükleme:** `tests/scripts/ci_install_packages.R`, `renv.lock` varsa
  `renv::restore()` tercih eder; yoksa mevcut RSPM/CRAN akışına geri düşer.

### Commit EDİLEN / EDİLMEYEN dosyalar

| Dosya | Commit? | Not |
|------|---------|-----|
| `renv.lock` | ✅ Evet | Kesin sürümler (VM'de üretilir) |
| `.Rprofile` | ✅ Evet | Koşullu/offline-güvenli yükleyici |
| `renv/activate.R` | ✅ Evet | renv önyükleyici (renv tarafından üretilir) |
| `renv/settings.json` | ✅ Evet (varsa) | renv proje ayarları |
| `renv/.gitignore` | ✅ Evet | Alt klasör yok sayma kuralları |
| `renv/library/` | ❌ Hayır | Yerel paket kütüphanesi |
| `renv/cellar/`, `renv/staging/`, `renv/sandbox/`, `renv/python/`, `renv/local/`, `renv/lock/` | ❌ Hayır | Yerel/önbellek/ara dizinler |

Kök `.gitignore` ve `renv/.gitignore` bu politikayı zaten uygular.

---

## 2. Windows VM'de İlk Kilit Üretimi (R 4.6.0)

Repo kökünde (örn. `...\MERGEN Bilge`), çalışan R 4.6.0 oturumunda:

```r
# 1) renv'i kur (yalnızca bir kez yeterli)
install.packages("renv")

# 2) Kilidi MEVCUT (global) çalışan kütüphaneden üret.
#    Bu betik required_packages + test/CI ekstralarını kapsar, .Rprofile'a DOKUNMAZ.
#    PowerShell/CMD'den:
#       Rscript tools/renv_snapshot.R
#    veya R oturumundan:
source("tools/renv_snapshot.R")
```

> **`renv::init()` ÇAĞIRMAYIN.** `init()`, kök `.Rprofile`'ı koşulsuz sürümle
> EZER ve repo'nun offline/bulut güvenli davranışını bozar. Kilidi yalnızca
> `tools/renv_snapshot.R` (veya doğrudan `renv::snapshot(...)`) ile üretin.

`tools/renv_snapshot.R` özetle şunu yapar:

```r
renv::snapshot(
  packages = <required_packages + testthat/withr/processx/callr + renv>,
  prompt   = FALSE,
  lockfile = "renv.lock"
)
```

---

## 3. Temiz Ortamda Doğrulama ve Test

```r
# (İsteğe bağlı, önerilir) Temiz bir proje kütüphanesinde geri yüklemeyi dene:
Rscript -e "renv::restore(prompt = FALSE)"

# MERGEN testlerini çalıştır:
Rscript tests/testthat.R

# Uygulamayı başlat (üretim launcher'ı):
run_mergen_prod.bat
```

Önerilen tam VM iş akışı:

1. Çalışan R 4.6.0 kütüphanesinden başla.
2. `Rscript tools/renv_snapshot.R` → `renv.lock` üret/güncelle.
3. **R oturumunu yeniden başlat** (`.Rprofile` artık kilidi görür ve renv'i etkinleştirir).
4. Mümkünse temiz bir kütüphanede `renv::restore()` ile doğrula.
5. `Rscript tests/testthat.R`.
6. Shiny uygulamasını başlat.
7. `renv.lock` (ve gerekiyorsa `renv/settings.json`) commit et — `renv/library` ASLA.

---

## 4. `.Rprofile` Neden Koşullu?

Standart renv `.Rprofile` (`source("renv/activate.R")`) **koşulsuzdur**:
`renv.lock` henüz yokken bile `.libPaths()`'i boş bir proje kütüphanesine çevirir
ve renv'i internetten indirmeyi dener. Bu davranış:

- bulut/CI önyüklemesini (paketler global kütüphanede) BOZAR,
- çevrimdışı VM'de gereksiz indirme denemesi yapar,
- "kilit henüz üretilmedi" durumunda uygulamayı kullanılamaz hale getirir.

Bu yüzden kök `.Rprofile` renv'i **yalnızca** şu üç koşul birlikte sağlandığında
etkinleştirir:

1. `renv/activate.R` mevcut,
2. `renv.lock` mevcut,
3. `renv` paketi zaten kurulu (asla indirme tetiklenmez).

Aksi halde sessizce atlanır; uygulama global/sistem kütüphanesiyle normal çalışır
ve oturum hiçbir koşulda çökmez.

---

## 5. Paketleri Yükselttikten Sonra Kilidi Güncelleme

1. Windows VM'de paketleri normal şekilde güncelle
   (`update.packages()` veya `install.packages(...)`).
2. `Rscript tools/renv_snapshot.R` ile `renv.lock`'u yeniden üret.
3. `Rscript -e "renv::restore(prompt = FALSE)"` ve `Rscript tests/testthat.R` ile doğrula.
4. `renv.lock` farkını gözden geçir ve commit et.

`R/config_packages.R`'ye **yeni bir paket** eklediğinizde: önce paketi VM'de kurun,
sonra kilidi yeniden üretin. `tests/testthat/test-renv-lock-contract.R` testi,
`required_packages` ile `renv.lock` arasında tutarlılığı doğrular (kilit varsa).

---

## 6. CI / AI / Bulut Önyükleme Davranışı

`tests/scripts/ci_install_packages.R`:

- `renv.lock` **varsa** ve renv kullanılabilirse → `renv::restore(prompt = FALSE)`
  (eksik kalırsa klasik akış tamamlar),
- `renv.lock` **yoksa** → mevcut RSPM/CRAN kurulum akışı (değişmeden).

Bu sayede:

- Linux/Codex/AI bootstrap çalışmaya devam eder,
- RSPM→CRAN geri düşüş mantığı korunur,
- çevrimdışı/on-prem varsayımları bozulmaz.

GitHub Actions paket önbelleği `renv.lock`'u da hash anahtarına dahil eder
(`.github/workflows/mergen-ai-validation.yml`), böylece kilit değiştiğinde önbellek
yenilenir.

**Kaçış valfi:** kendi bağımlılıklarını yöneten herhangi bir ortam, renv otomatik
yüklemeyi kapatabilir:

```sh
MERGEN_DISABLE_RENV_AUTOLOAD=true
```

Bu ayar set edildiğinde kök `.Rprofile` renv'i etkinleştirmez (global kütüphane
kullanılır).

**`tests.yml` notu:** `tests.yml` bağımlılıkları `r-lib/actions/setup-r-dependencies@v2`
ile açık bir `packages:` listesinden kurar. `renv.lock` COMMIT EDİLDİKTEN SONRA bu
iş akışını bir kez doğrulayın: `setup-r-dependencies` çoğunlukla `renv.lock`'u
otomatik algılar; sorun çıkarsa ya bu adımdan önce
`MERGEN_DISABLE_RENV_AUTOLOAD=true` set edin ya da adımı `renv::restore()` kullanacak
şekilde güncelleyin. `renv.lock` henüz yokken (mevcut durum) `.Rprofile` no-op
olduğundan `tests.yml` bugünkü davranışıyla çalışmaya devam eder.

---

## 7. Kabul Kontrol Listesi

- [ ] `renv.lock` Windows VM R 4.6.0 ortamında üretildi.
- [ ] `.Rprofile`, `renv/activate.R`, `renv/.gitignore` repoda mevcut.
- [ ] `renv/library` commit EDİLMEDİ.
- [ ] Temiz ortamda `renv::restore(prompt = FALSE)` çalışıyor.
- [ ] `R/config_packages.R` açılış doğrulaması hâlâ çalışıyor.
- [ ] `Rscript tests/testthat.R` geçiyor.
- [ ] `tests/testthat/test-renv-lock-contract.R` geçiyor.
- [ ] CI/AI bootstrap (`tools/ai_validate.sh`) hâlâ kullanılabilir.
