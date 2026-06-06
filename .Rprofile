# ==============================================================================
# .Rprofile - MERGEN Bilge renv otomatik yükleyici (offline/üretim güvenli)
# ==============================================================================
# Bu dosya, standart renv `source("renv/activate.R")` satırının YERİNE bilinçli
# olarak KOŞULLU bir yükleyici kullanır. Nedeni:
#
#   - Standart (koşulsuz) renv aktivasyonu, renv.lock henüz üretilmemiş olsa
#     bile .libPaths()'i boş bir proje kütüphanesine çevirir ve renv'i internetten
#     indirmeyi dener. Bu davranış; bulut/CI önyüklemesini (paketler global
#     kütüphanede), çevrimdışı Windows VM'i ve repo'nun "kilit henüz yok"
#     durumunu BOZAR.
#
# Bu yüzden renv yalnızca GERÇEKTEN kilitliyse etkinleşir:
#   - renv/activate.R mevcut,
#   - renv.lock mevcut (kilit dosyası Windows VM'de üretilir),
#   - renv paketi zaten kurulu (asla internetten indirmeyi tetiklemeyiz).
#
# Aksi halde sessizce atlanır ve uygulama global/sistem kütüphanesiyle normal
# çalışır. Hata olursa bile R oturumu ASLA çökmez (tryCatch).
#
# NOT: Windows VM'de `renv::init()` çağırmayın; bu dosyayı koşulsuz sürümle EZER.
# Kilit üretmek/güncellemek için `Rscript tools/renv_snapshot.R` kullanın
# (ayrıntı: docs/dependency-locking.md).
# ==============================================================================

local({
  # Kaçış valfi: kendi bağımlılıklarını yöneten ortamlar (ör. bazı CI adımları)
  # renv otomatik yüklemeyi kapatabilir: MERGEN_DISABLE_RENV_AUTOLOAD=true
  disable_flag <- tolower(trimws(Sys.getenv("MERGEN_DISABLE_RENV_AUTOLOAD", unset = "")))
  if (disable_flag %in% c("true", "1", "yes", "evet")) {
    return(invisible(NULL))
  }

  activate_path <- file.path("renv", "activate.R")
  lock_path <- "renv.lock"

  renv_should_activate <-
    file.exists(activate_path) &&
    file.exists(lock_path) &&
    requireNamespace("renv", quietly = TRUE)

  if (isTRUE(renv_should_activate)) {
    tryCatch(
      source(activate_path),
      error = function(e) {
        message(
          "renv etkinleştirilemedi; global kütüphaneyle devam ediliyor: ",
          conditionMessage(e)
        )
      }
    )
  }
})
