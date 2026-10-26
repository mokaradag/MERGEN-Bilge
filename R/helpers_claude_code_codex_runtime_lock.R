# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_codex_runtime_lock.R
# Açıklama: Bilge Yolaç runtime terfi kilidinin ve çıktı yayını hedef
#           kilidinin sahiplik primitifleri.
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
  # `Sys.setFileTime()` bazı UNC/ağ paylaşımlarında sessizce FALSE döner. Dönüş
  # yok sayıldığında marker mtime'ı tazelenmiyor, ama `kirayi_tazele()` BAŞARI
  # bildiriyordu; terfi 60 sn'yi aştığında ikinci bir worker CANLI sahibin
  # kilidini bayat sayıp siliyor ve aynı runtime ağacını eşzamanlı terfi
  # ettiriyordu. Yazma mtime'ı YAN ETKİ olarak günceller; o da başarısızsa
  # kira tazelenmemiştir ve FALSE dönülür.
  sonuc <- try(Sys.setFileTime(yol, Sys.time()), silent = TRUE)
  if (!inherits(sonuc, "try-error") && isTRUE(sonuc)) {
    # Sahiplik TAZELEMEDEN SONRA da doğrulanır: denetim ile zaman damgası
    # yazımı ayrı işlemlerdir ve bu aralıkta bir devralma kilidi değiştirmiş
    # olabilir. Doğrulamasız `TRUE`, ESKİ sahibin kritik bölümde kalmasına ve
    # aynı runtime ağacını eşzamanlı terfi etmesine izin veriyordu.
    return(invisible(identical(.cc_codex_lock_owner_token(dizin), jeton)))
  }

  # PAYLAŞILAN marker'ı yeniden yazan yedek yol: yazımdan HEMEN ÖNCE sahiplik
  # yeniden okunur (yeni sahibin jetonunu EZMEMEK için) ve yazımdan SONRA
  # yeniden doğrulanır.
  if (!identical(.cc_codex_lock_owner_token(dizin), jeton)) return(invisible(FALSE))
  yazildi <- try(writeLines(c(jeton, paste0("host=", Sys.info()[["nodename"]])), yol, useBytes = TRUE), silent = TRUE)
  if (inherits(yazildi, "try-error")) return(invisible(FALSE))
  invisible(identical(.cc_codex_lock_owner_token(dizin), jeton))
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
  # Kendi kilidini bırakan çağrı kısa çekişmede beklemeli; aksi hâlde canlı
  # sürecin kilidi kalıcı kalırdı. Muteks hatası "alınamadı" sayılır.
  reclaim <- mergen_reclaim_mutex(paste0(lock_dir, ".reclaim"),
                                  timeout = if (is.null(stale_sec)) 100 else 0)
  if (is.null(reclaim)) return(FALSE)
  on.exit(filelock::unlock(reclaim), add = TRUE)
  reaper <- paste0(lock_dir, ".reaper")

  reaper_jetonu <- paste0(Sys.getpid(), "-", basename(tempfile("ccrp")))

  alindi <- isTRUE(try(dir.create(reaper, showWarnings = FALSE), silent = TRUE))
  if (!alindi) {
    # Çöken bir süreçten kalan reaper dizini kalıcı kilitlenme üretmemelidir;
    # CANLI bir reaper ise kirasını tazeler ve yalnızca mtime'a bakarak
    # devralınmaz (yavaş UNC'de silme 60 sn'yi aşabilir).
    gozlenen_jeton <- .cc_codex_lock_owner_token(reaper)
    if (!mergen_lock_owner_reclaimable(file.path(reaper, "owner"), gozlenen_jeton,
                                       .CC_CODEX_REAPER_STALE_SEC, self_reclaim = TRUE)) return(FALSE)

    # DEVRALMA SAHİPLİK DOĞRULAMASI: yalnızca yaş denetimi yeterli değildi.
    # Yavaş bir UNC paylaşımında A süreci reaper'ı tutarken B onu bayat sayıp
    # siliyor; A çıkışta B'nin reaper'ını kaldırıyor ve üçüncü bir süreç aynı
    # kritik bölüme girebiliyordu. Bayat olarak GÖZLENEN jeton hâlâ yerinde
    # olmalı ve yaş yeniden doğrulanmalıdır.
    if (!identical(.cc_codex_lock_owner_token(reaper), gozlenen_jeton)) return(FALSE)

    # SİLME DOĞRULANIR: `unlink()` Windows/UNC'de açık tanıtıcı ya da izin
    # hatasında sessizce başarısız olabilir; doğrulanmadan yeniden oluşturmaya
    # geçmek, hâlâ var olan reaper'ı bizim sandığımız anlamına geliyordu.
    unlink(reaper, recursive = TRUE, force = TRUE)
    if (isTRUE(dir.exists(reaper))) return(FALSE)
    alindi <- isTRUE(try(dir.create(reaper, showWarnings = FALSE), silent = TRUE))
    if (!alindi) return(FALSE)
  }
  try(writeLines(c(reaper_jetonu, paste0("host=", Sys.info()[["nodename"]])), file.path(reaper, "owner"), useBytes = TRUE), silent = TRUE)
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
    if (!mergen_lock_owner_reclaimable(file.path(lock_dir, "owner"), beklenen_jeton, stale_sec,
                                       self_reclaim = TRUE)) return(FALSE)
  } else if (is.na(beklenen_jeton)) {
    return(FALSE)
  }

  # Silme DOĞRULANIR. `unlink()` Windows/UNC'de açık tanıtıcı ya da izin
  # hatasında sıfırdan farklı döner; koşulsuz `TRUE` bırakma çağıranlarının
  # yeniden denemeyi durdurmasına ve kalan kilidin sonraki runtime terfilerini
  # bayat kurtarmaya kadar engellemesine yol açıyordu.
  unlink(lock_dir, recursive = TRUE, force = TRUE)
  !isTRUE(dir.exists(lock_dir))
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
        writeLines(c(jeton, paste0("host=", Sys.info()[["nodename"]])), file.path(lock_dir, "owner"), useBytes = TRUE),
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
    if (mergen_lock_owner_reclaimable(file.path(lock_dir, "owner"),
                                      .cc_codex_lock_owner_token(lock_dir), stale_sec, self_reclaim = TRUE)) {
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

# YAYIN İŞLEMİ: hedef başına tek yazar (rezervasyon). Yedek ve staging adları
# yazarın rezervasyon jetonunu taşır; önek tek başına sahiplik kanıtı değildir.
# Sert ölümden kalan işlem yalnız bayat rezervasyonu devralan yazar tarafından,
# o rezervasyonun jetonuyla adlandırılmış yapıtlar üzerinden kurtarılır.
.cc_output_txn_paths <- function(dest, jeton = "", legacy = FALSE) {
  parent <- dirname(dest)
  base <- basename(dest)
  key_base <- if (.Platform$OS.type == "windows") tolower(base) else base
  key <- digest::digest(key_base, algo = "xxhash64", serialize = FALSE)
  lock <- file.path(parent, paste0(".cc-output-lock-", base))
  if (nchar(base, type = "bytes") > 200 && !dir.exists(lock))
    lock <- file.path(parent, paste0(".cc-output-lockhash-", key))
  suffix <- if (legacy) base else key
  list(lock = lock,
       backup = file.path(parent, paste0(".cc-output-backup-", jeton, "-", suffix)),
       staging = file.path(parent, paste0(".cc-output-stage-", jeton, "-", suffix)))
}

.cc_output_dest_lock <- function(dest, wait_sec = 10) {
  kilit <- .cc_output_txn_paths(dest)$lock
  jeton <- mergen_reservation_token("ccout")
  acquired <- function() {
    if (startsWith(basename(kilit), ".cc-output-lockhash-") &&
        inherits(try(writeBin(charToRaw(paste0(enc2utf8(basename(dest)), "\n")), file.path(kilit, "destination")),
                     silent = TRUE), "try-error")) {
      mergen_reservation_release(kilit, jeton)
      return(structure("", recovery_failed = TRUE))
    }
    jeton
  }
  bitis <- Sys.time() + wait_sec
  repeat {
    if (isTRUE(mergen_reservation_acquire(kilit, jeton))) return(acquired())
    kurtarma_hatasi <- FALSE
    if (isTRUE(mergen_reservation_takeover(kilit, jeton, stale_sec = 60,
      before_remove = function(onceki) {
        ok <- isTRUE(.cc_output_recover_dest(dest, onceki))
        kurtarma_hatasi <<- !ok
        ok
      }))) return(acquired())
    if (kurtarma_hatasi) return(structure("", recovery_failed = TRUE))
    if (Sys.time() >= bitis) return("")
    Sys.sleep(0.1)
  }
}

# Devralınan bayat rezervasyonun yarım işlemini çözer: hedef yoksa yedek geri
# konur; hedef varsa önceki sürüm silinmez, jetonlu benzersiz adla saklanır.
.cc_output_name_variants <- function(base) {
  names <- list(base)
  for (convert in list(enc2utf8, enc2native)) {
    candidate <- suppressWarnings(tryCatch(convert(base), error = function(e) NULL))
    same <- suppressWarnings(tryCatch(identical(enc2utf8(candidate), enc2utf8(base)),
                                      error = function(e) FALSE))
    if (isTRUE(same)) names[[length(names) + 1L]] <- candidate
  }
  names
}

.cc_output_recover_dest <- function(dest, jeton) {
  jeton <- as.character(jeton %||% "")[1]
  if (is.na(jeton) || !grepl("^[0-9]+-ccout[0-9a-f]+$", jeton)) return(TRUE)
  for (base in .cc_output_name_variants(basename(dest))) for (legacy in c(FALSE, TRUE)) {
    yollar <- suppressWarnings(tryCatch(.cc_output_txn_paths(file.path(dirname(dest), base), jeton,
      legacy = legacy), error = function(e) NULL))
    if (is.null(yollar)) return(FALSE)
    if (isTRUE(file.exists(yollar$backup))) {
      hedef <- if (isTRUE(file.exists(dest))) file.path(dirname(dest), paste0(
        ".cc-output-recovered-", jeton, "-", digest::digest(basename(dest), algo = "xxhash64", serialize = FALSE))) else dest
      if (!isTRUE(file.exists(hedef))) file.rename(yollar$backup, hedef)
    }
    unlink(yollar$staging, force = TRUE)
    if (isTRUE(file.exists(yollar$backup)) || isTRUE(file.exists(yollar$staging))) return(FALSE)
  }
  TRUE
}

# Yalnız taranan kilidin kimliğini yeniden üreten yorum kabul edilir.
.cc_output_recovery_dest <- function(parent, lock) {
  hashed <- startsWith(basename(lock), ".cc-output-lockhash-")
  if (hashed) {
    con <- suppressWarnings(tryCatch(file(file.path(lock, "destination"), "rb"), error = function(e) NULL))
    if (is.null(con)) return(NULL)
    on.exit(close(con), add = TRUE)
    bytes <- suppressWarnings(tryCatch(readBin(con, "raw", n = 4097L), error = function(e) raw()))
    if (!length(bytes) || length(bytes) > 4096L || tail(bytes, 1L) != as.raw(10)) return(NULL)
    # Yalnız son ayraç çıkarılır; dosya adındaki satır sonları korunur.
    native <- tryCatch(rawToChar(head(bytes, -1L)), error = function(e) "")
    utf8 <- native
    Encoding(utf8) <- "UTF-8"
    bases <- list(utf8, native)
    # Eski Windows metin bağlantısı CRLF yazmış olabilir; kimlik yine doğrulanır.
    if (length(bytes) > 1L && bytes[length(bytes) - 1L] == as.raw(13)) {
      native_crlf <- tryCatch(rawToChar(head(bytes, -2L)), error = function(e) "")
      utf8_crlf <- native_crlf
      Encoding(utf8_crlf) <- "UTF-8"
      bases <- c(bases, list(utf8_crlf, native_crlf))
    }
  } else bases <- list(sub("^\\.cc-output-lock-", "", basename(lock)))
  for (base in bases) {
    if (length(base) != 1L || is.na(base) || !nzchar(base)) next
    for (candidate in .cc_output_name_variants(base)) {
      dest <- suppressWarnings(tryCatch({
        if (!identical(basename(candidate), candidate) || candidate %in% c(".", "..")) NULL else {
          path <- file.path(parent, candidate)
          if (identical(.cc_output_txn_paths(path)$lock, lock)) path else NULL
        }
      }, error = function(e) NULL))
      if (!is.null(dest)) return(dest)
    }
  }
  NULL
}

# Plan dışında kalmış hedeflerin bayat rezervasyonları da aynı kuralla kurtarılır;
# canlı ya da sahipliği kanıtlanamayan rezervasyona dokunulmaz.
.cc_output_recover_parent <- function(parent) {
  kilitler <- suppressWarnings(list.files(parent, pattern = "^\\.cc-output-lock(hash)?-",
                                          all.files = TRUE, full.names = TRUE))
  kilitler <- kilitler[dir.exists(kilitler) & !grepl("\\.q-q[0-9a-f]+$", kilitler)]
  for (kilit in kilitler) {
    dest <- .cc_output_recovery_dest(parent, kilit)
    if (is.null(dest)) next
    jeton <- .cc_output_dest_lock(dest, wait_sec = 0)
    if (nzchar(jeton)) mergen_reservation_release(kilit, jeton)
  }
  invisible(NULL)
}
