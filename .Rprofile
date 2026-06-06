# ==============================================================================
# .Rprofile - MERGEN Bilge renv otomatik yukleyici (offline / uretim guvenli)
# ==============================================================================
# ASCII-only yorumlar: bu dosya HER R baslangicinda source edilir ve testler
# tarafindan okunur; Windows VM (Turkce/Windows-1254 locale) uzerinde Turkce
# ozel karakterler "invalid UTF-8" sorunlari uretebildigi icin bilincli olarak
# ASCII tutulmustur.
#
# Bu dosya, standart renv `source("renv/activate.R")` satirinin YERINE bilincli
# olarak KOSULLU bir yukleyici kullanir. Standart (kosulsuz) renv aktivasyonu,
# kilit/kutuphane hazir olmasa bile .libPaths()'i bos bir proje kutuphanesine
# cevirir ve renv'i internetten indirmeye calisir; bu da bulut/CI onyuklemesini,
# cevrimdisi VM'i ve "kilit/kutuphane henuz hazir degil" durumunu BOZAR.
#
# renv yalnizca GERCEKTEN kullanima hazir oldugunda etkinlesir:
#   1. renv/activate.R mevcut,
#   2. renv.lock mevcut (kilit Windows VM'de uretilir),
#   3. renv paketi zaten kurulu (asla internetten indirme tetiklenmez),
#   4. renv/library GERCEKTEN dolu (en az bir kurulu paket var).
#
# (4) kritik: `tools/renv_snapshot.R` yalnizca renv.lock'u KAYDEDER; renv/library'yi
# DOLDURMAZ. Bu yuzden uretim VM'inde kilit olusturulduktan sonra bile, restore
# yapilmadiysa proje kutuphanesi bostur. (4) sayesinde bu durumda renv etkinlesmez
# ve uygulama mevcut global/sistem kutuphanesiyle calismaya devam eder (uretim
# bozulmaz). Temiz bir ortamda `renv::restore()` calistirilip renv/library
# doldurulunca aktivasyon kendiliginden devreye girer.
#
# Hata olursa bile R oturumu ASLA cokmez (tryCatch). Kacis valfi:
# MERGEN_DISABLE_RENV_AUTOLOAD=true.
#
# NOT: Windows VM'de `renv::init()` cagirmayin; bu dosyayi kosulsuz surumle EZER.
# Kilit uretmek/guncellemek icin `Rscript tools/renv_snapshot.R` kullanin
# (ayrinti: docs/dependency-locking.md).
# ==============================================================================

local({
  # Kacis valfi: kendi bagimliliklarini yoneten ortamlar renv otomatik yuklemeyi
  # kapatabilir: MERGEN_DISABLE_RENV_AUTOLOAD=true
  disable_flag <- tolower(trimws(Sys.getenv("MERGEN_DISABLE_RENV_AUTOLOAD", unset = "")))
  if (disable_flag %in% c("true", "1", "yes", "evet")) {
    return(invisible(NULL))
  }

  activate_path <- file.path("renv", "activate.R")
  lock_path <- "renv.lock"

  # renv/library gercekten dolu mu? (restore yapildi mi?) Standart renv kutuphane
  # yapisi: renv/library/<platform>/<R-x.y>/<arch>/<paket>/DESCRIPTION. Sabit
  # derinlikte Sys.glob ile sinirli/hizli kontrol; bulunamazsa GUVENLI varsayilan
  # olarak global kutuphane kullanilir.
  renv_library_ready <- function() {
    lib_root <- file.path("renv", "library")
    if (!dir.exists(lib_root)) {
      return(FALSE)
    }
    descs <- Sys.glob(file.path(lib_root, "*", "*", "*", "*", "DESCRIPTION"))
    length(descs) > 0L
  }

  renv_should_activate <-
    file.exists(activate_path) &&
    file.exists(lock_path) &&
    requireNamespace("renv", quietly = TRUE) &&
    isTRUE(renv_library_ready())

  if (isTRUE(renv_should_activate)) {
    tryCatch(
      source(activate_path),
      error = function(e) {
        message(
          "renv etkinlestirilemedi; global kutuphaneyle devam ediliyor: ",
          conditionMessage(e)
        )
      }
    )
  }
})
