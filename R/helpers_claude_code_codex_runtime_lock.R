# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_codex_runtime_lock.R
# Açıklama: Bilge Yolaç runtime terfi kilidinin sahiplik primitifleri.
#           R/helpers_claude_code_codex_runtime_fixes.R dosyasından ÖNCE
#           yüklenmelidir; o dosya bu yardımcıları kullanır ve kendi bakım
#           bütçesini aşmamak için primitifleri burada tutar.
#
# SÖZLEŞME:
#   - Kilit YALNIZCA `dir.create()` (atomik, üzerine-yazmayan) ile alınır.
#   - Dayanıklı sahiplik marker'ı kilidi TUTMANIN ön koşuludur.
#   - Yıkıcı işlemler (bayat devralma / bırakma) reaper dizini altında
#     serileştirilir ve kilit dizini asla yerinden oynatılmaz.
# ==============================================================================

# Reaper dizininin bayatlık eşiği (canlı reaper kirasını tazeler).
.CC_CODEX_REAPER_STALE_SEC <- 60

# Kilit dizinindeki sahiplik jetonu (okunamazsa NA_character_). Kilidi bırakma
# kararının tek kanıtı budur; edinme ve bırakma yolları aynı okuyucuyu paylaşır.
.cc_codex_lock_owner_token <- function(dizin) {
  yol <- file.path(dizin, "owner")
  # `try(..., silent = TRUE)` yalnızca HATAYI bastırır; eksik dosyada bağlantı
  # açma UYARISI sızar ve katı test koşucusunu düşürür.
  if (!isTRUE(file.exists(yol))) return(NA_character_)
  satir <- suppressWarnings(try(readLines(yol, warn = FALSE), silent = TRUE))
  if (inherits(satir, "try-error") || !length(satir)) return(NA_character_)
  as.character(satir[1])
}

# CANLI SAHİPLİK KİRASI: uzun süren terfi adımları (UNC üzerinde `file.rename`,
# temizlik, `normalizePath`) 60 sn'yi meşru olarak aşabilir. Yalnızca mtime'a
# bakan devralma, HÂLÂ ÇALIŞAN sahibin kilidini kırıp iki worker'ın aynı runtime
# ağacını eşzamanlı terfi ettirmesine izin veriyordu. Sahip marker'ı tazeler;
# bayatlık ölçümü de MARKER mtime'ı üzerinden yapılır.
.cc_codex_touch_dir_lock <- function(dizin, jeton) {
  if (!nzchar(as.character(jeton %||% "")[1])) return(invisible(FALSE))
  if (!identical(.cc_codex_lock_owner_token(dizin), jeton)) return(invisible(FALSE))
  yol <- file.path(dizin, "owner")
  try(Sys.setFileTime(yol, Sys.time()), silent = TRUE)
  invisible(TRUE)
}

# Kilit yaşı: SAHİP marker'ı tazelendiği için önce onun mtime'ı kullanılır;
# marker okunamazsa dizin mtime'ına düşülür.
.cc_codex_dir_lock_age <- function(dizin) {
  for (yol in c(file.path(dizin, "owner"), dizin)) {
    bilgi <- try(file.info(yol), silent = TRUE)
    if (!inherits(bilgi, "try-error") && NROW(bilgi) && !is.na(bilgi$mtime[1])) {
      return(as.numeric(difftime(Sys.time(), bilgi$mtime[1], units = "secs")))
    }
  }
  NA_real_
}

# Kilit üzerindeki YIKICI işlemler (bayat devralma ve bırakma) tek bir "reaper"
# dizini altında serileştirilir ve yalnızca GÖZLENEN jeton hâlâ yerindeyse
# uygulanır. Kilit dizini hiçbir zaman yerinden oynatılmaz; eski karantina/geri
# koyma protokolü, canlı bir kilidi geçici olarak kaldırıp üçüncü bir worker'ın
# aynı kritik bölüme girmesine izin veriyordu.
.cc_codex_reap_dir_lock <- function(lock_dir, beklenen_jeton, stale_sec = NULL) {
  reaper <- paste0(lock_dir, ".reaper")

  reaper_jetonu <- paste0(Sys.getpid(), "-", basename(tempfile("ccrp")))

  alindi <- isTRUE(try(dir.create(reaper, showWarnings = FALSE), silent = TRUE))
  if (!alindi) {
    # Çöken bir süreçten kalan reaper dizini kalıcı kilitlenme üretmemelidir;
    # CANLI bir reaper ise kirasını tazeler ve yalnızca mtime'a bakarak
    # devralınmaz (yavaş UNC'de silme 60 sn'yi aşabilir).
    gozlenen_jeton <- .cc_codex_lock_owner_token(reaper)
    yas <- .cc_codex_dir_lock_age(reaper)
    if (!is.finite(yas) || yas <= .CC_CODEX_REAPER_STALE_SEC) return(FALSE)

    # DEVRALMA SAHİPLİK DOĞRULAMASI: yalnızca yaş denetimi yeterli değildi.
    # Yavaş bir UNC paylaşımında A süreci reaper'ı tutarken B onu bayat sayıp
    # siliyor; A çıkışta B'nin reaper'ını kaldırıyor ve üçüncü bir süreç aynı
    # kritik bölüme girebiliyordu. Bayat olarak GÖZLENEN jeton hâlâ yerinde
    # olmalı ve yaş yeniden doğrulanmalıdır.
    if (!identical(.cc_codex_lock_owner_token(reaper), gozlenen_jeton)) return(FALSE)
    yas <- .cc_codex_dir_lock_age(reaper)
    if (!is.finite(yas) || yas <= .CC_CODEX_REAPER_STALE_SEC) return(FALSE)

    unlink(reaper, recursive = TRUE, force = TRUE)
    alindi <- isTRUE(try(dir.create(reaper, showWarnings = FALSE), silent = TRUE))
    if (!alindi) return(FALSE)
  }
  try(writeLines(reaper_jetonu, file.path(reaper, "owner"), useBytes = TRUE), silent = TRUE)
  # Dayanıklı marker reaper'ı TUTMANIN ön koşuludur: doğrulanamazsa yıkıcı işlem
  # hiç yapılmaz ve dizin hemen bırakılır.
  if (!identical(.cc_codex_lock_owner_token(reaper), reaper_jetonu)) {
    unlink(reaper, recursive = TRUE, force = TRUE)
    return(FALSE)
  }
  # ÇIKIŞTA reaper YALNIZCA hâlâ bizim jetonumuzu taşıyorsa kaldırılır.
  on.exit({
    if (identical(.cc_codex_lock_owner_token(reaper), reaper_jetonu)) {
      unlink(reaper, recursive = TRUE, force = TRUE)
    }
  }, add = TRUE)

  if (!dir.exists(lock_dir)) return(TRUE)

  mevcut <- .cc_codex_lock_owner_token(lock_dir)
  if (!identical(mevcut, beklenen_jeton)) return(FALSE)

  if (!is.null(stale_sec)) {
    # İşaretsiz (NA jetonlu) kilit yalnızca YAŞ yeniden doğrulanırsa kaldırılır;
    # yeni oluşturulmuş ya da kirasını TAZELEYEN bir kilit korunur.
    .cc_codex_touch_dir_lock(reaper, reaper_jetonu)
    yas <- .cc_codex_dir_lock_age(lock_dir)
    if (!is.finite(yas) || yas <= stale_sec) return(FALSE)
  } else if (is.na(beklenen_jeton)) {
    return(FALSE)
  }

  unlink(lock_dir, recursive = TRUE, force = TRUE)
  TRUE
}

.cc_codex_acquire_dir_lock <- function(lock_dir, guard = NULL, attempts = 200L,
                                       stale_sec = 60) {
  attempts <- max(1L, suppressWarnings(as.integer(attempts[1])))
  stale_sec <- suppressWarnings(as.numeric(stale_sec[1]))
  if (!length(stale_sec) || !is.finite(stale_sec) || stale_sec <= 0) stale_sec <- Inf

  # Sahiplik jetonu: yavaş bir dosya sisteminde eskiyen kilit kırılıp başka bir
  # worker tarafından yeniden alınırsa, gecikmiş eski sahip yeni sahibin
  # kilidini silmemelidir (kritik bölüme üçüncü worker girerdi).
  jeton <- paste0(Sys.getpid(), "-", basename(tempfile("cclk")))

  # attempts + 1: son tur, beklemeler sırasında eskiyen kilidin kırılmasından
  # sonra bir kez daha denemeyi sağlar.
  for (i in seq_len(attempts + 1L)) {
    .cc_codex_guard_check(guard)

    olustu <- try(dir.create(lock_dir, showWarnings = FALSE), silent = TRUE)
    if (!inherits(olustu, "try-error") && isTRUE(olustu)) {
      try(
        writeLines(jeton, file.path(lock_dir, "owner"), useBytes = TRUE),
        silent = TRUE
      )
      # Dayanıklı marker kilidi tutmanın ÖN KOŞULUDUR: yazma sessizce
      # başarısız olursa işaretsiz kilit 60 sn sonra devralınabilir ve iki
      # worker aynı runtime ağacını eşzamanlı terfi ettirebilirdi.
      if (identical(.cc_codex_lock_owner_token(lock_dir), jeton)) return(jeton)
      # Marker doğrulanamadıysa kilidi TUTMA hakkımız yok. Dizini biz
      # oluşturduk; her durumda kaldırılır, aksi hâlde kimsenin bırakmadığı bu
      # kilit stale_sec dolana kadar sonraki tüm çalıştırmaları engellerdi.
      unlink(lock_dir, recursive = TRUE, force = TRUE)
      return("")
    }

    # Çöken bir süreçten kalan kilit dizini yaşına göre kırılır; aksi hâlde her
    # sonraki çalıştırma kalıcı olarak fail-closed duruma düşerdi. Yaş, sahibin
    # TAZELEDİĞİ marker üzerinden ölçülür: canlı bir sahip devralınmaz.
    yas <- .cc_codex_dir_lock_age(lock_dir)

    if (is.finite(yas) && yas > stale_sec) {
      # BAYAT KİLİDİ DEVRALMA reaper üzerinden serileştirilir ve kilit dizini
      # YERİNDEN OYNATILMAZ. Silme yalnızca bayat olarak gözlenen jeton hâlâ
      # yerindeyse ve yaş yeniden doğrulanırsa yapılır; bu sırada kilidi almış
      # taze bir sahip farklı jeton taşıdığı için korunur.
      eski_jeton <- .cc_codex_lock_owner_token(lock_dir)
      if (isTRUE(.cc_codex_reap_dir_lock(lock_dir, eski_jeton, stale_sec)) &&
          !dir.exists(lock_dir)) {
        next
      }
    }

    if (i > attempts) break
    Sys.sleep(0.05)
  }

  ""
}
