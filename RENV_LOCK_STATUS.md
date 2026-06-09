# renv.lock Durumu (On-Prem / Windows VM)

> Bu dosya bir **durum işaretçisidir** (marker). Gerçek `renv.lock` DEĞİLDİR
> ve onun yerine geçmez. `renv.lock`, Windows VM production repository içinde
> commit edilmiştir. Bu dosya yalnızca kilidin ne zaman/nerede üretildiğini,
> nasıl restore edileceğini ve hangi dosyaların commit edilmemesi gerektiğini
> belgeleyen operasyonel bir provenance/status notudur.

## Özet

- **Durum:** ✅ Gerçek `renv.lock`, çalışan Windows VM production repository içinde commit edilmiştir.
- **Üreten ortam:** Windows VM, **R 4.6.0**, uygulamanın çalıştığı güncel paket kütüphanesi.
- **Üretim tarihi:** 2026-06-09.
- **Üretim komutu:** `source("tools/renv_snapshot.R")` (repo kökünde).
- **On-prem yol:** `//rehisds/uygulamalar/Primavera/PYB/04 - Geliştirme/MERGEN Bilge/renv.lock`
- **Kilitlenen paket sayısı (recursive bağımlılıklar dahil):** 117.
- **Satır sayısı:** ~4354.

## Operasyonel kapsam ve commit sınırı

`renv.lock` is committed in the Windows VM production repository. This file remains
only as an operational note documenting when and where the lock was produced, how
it should be restored, and which files must not be committed.

`renv/library/` ASLA commit edilmez (kök `.gitignore` zaten yok sayar); yalnızca
`renv.lock` dependency kilidi olarak izlenir.

## Davranış notu (önemli)

- `tools/renv_snapshot.R` yalnızca `renv.lock`'u **kaydeder**; `renv/library`'yi
  **doldurmaz**. Bu yüzden VM'de kilit üretildikten sonra bile, `renv::restore()`
  çalıştırılmadıysa proje kütüphanesi boştur.
- Kök `.Rprofile` bunu bilir: renv yalnızca `renv.lock` + renv + **DOLU** bir
  `renv/library` birlikte mevcutsa etkinleşir. VM'de kütüphane boş olduğundan
  uygulama **global/sistem kütüphanesiyle** normal çalışmaya devam eder; üretim
  bozulmaz.
- Temiz bir ortamda kilitten kurulum için: `Rscript -e "renv::restore(prompt = FALSE)"`.

## Doğrulanan paket sürümleri (VM çıktısından özet)

R 4.6.0 ile kilitlenen başlıca runtime paketleri (tam liste gerçek `renv.lock`'ta):

```
arrow 24.0.0, av 0.9.6, base64enc 0.1-6, callr 3.7.6, cellranger 1.1.0,
cli 3.6.6, commonmark 2.0.0, curl 7.1.0, data.table 1.18.4, DBI 1.3.0,
dplyr 1.2.1, DT 0.34.0, duckdb 1.5.2, fastmatch 1.1-8, future 1.70.0,
glue 1.8.1, htmltools 0.5.9, httr 1.4.8, jsonlite 2.0.0, later 1.4.8,
logger 0.4.2, lubridate 1.9.5, markdown 2.0, odbc 1.7.0, openssl 2.4.1,
pdftools 3.9.0, pool 1.0.5, processx 3.9.0, promises 1.5.0, purrr 1.2.2,
readr 2.2.0, readxl 1.5.0, renv 1.2.3, rlang 1.2.0, shiny 1.13.0,
shinyBS 0.65.0, shinycssloaders 1.1.0, shinydashboard 0.7.3, shinyjs 2.1.1,
shinyWidgets 0.9.1, stringdist 0.9.17, stringi 1.8.7, stringr 1.6.0,
testthat 3.3.2, tibble 3.3.1, tidyr 1.3.2, urltools 1.7.3.1, withr 3.0.2,
writexl 1.5.4, xml2 1.5.2
```

Ayrıntılı rehber: `docs/dependency-locking.md`.
