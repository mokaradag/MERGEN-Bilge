# ==============================================================================
# Dosya Yolu: tools/pk/helpers_meta_generator_lock.R
# Açıklama: Faz 3b metadata üreticisi -- KOŞU KİLİDİ (sahiplik jetonlu).
#
# BU DOSYA ÇALIŞMA ZAMANI KODU DEĞİLDİR; kaynak manifestine EKLENMEZ.
#
# NEDEN AYRI DOSYA: kilit, birleştirme/katalog mantığından TAMAMEN bağımsız bir
# eşzamanlılık sınırıdır; kalp atışı, atomik devralma ve sahiplik doğrulaması
# eklendiğinde birleştirme dosyasını gereksiz yere kalabalıklaştırırdı.
#
# ÇÖZÜLEN ÜÇ AYRI YARIŞ:
#
#   1) CANLI KOŞU BAYAT SAYILMAZ. Kilit dizini bir kez oluşturulup `mtime`
#      hiç tazelenmezse, tam envanter (özellikle `sample` kipinde) varsayılan
#      3600 saniyeyi AŞTIĞINDA kendi kendine "bayat" olur ve ikinci bir koşu
#      canlı kilidi kırar. Bu yüzden koşu ilerledikçe KALP ATIŞI yazılır.
#
#   2) BAYAT KİLİDİ İKİ SÜREÇ AYNI ANDA DEVRALAMAZ. `unlink()` + `dir.create()`
#      çifti atomik DEĞİLDİR: A silip yeniden oluşturduktan sonra B aynı
#      `unlink()` ile A'NIN TAZE kilidini silebilir ve ikisi de `ok = TRUE`
#      döner. Devralma bu yüzden ATOMİK `file.rename()` ile yapılır: yalnızca
#      yeniden adlandırmayı KAZANAN süreç devralır.
#
#   3) SAHİBİ OLMAYAN KİLİT BIRAKILMAZ. Bırakma yalnızca diskteki sahiplik
#      jetonu bu koşunun jetonuyla EŞLEŞTİĞİNDE siler; aksi hâlde eski bir
#      sürecin `on.exit()` çağrısı, kendisinden sonra başlayan koşunun kilidini
#      silerdi.
#
# Kilit `dir.create()` üzerine kurulur: dizin oluşturma dosya sisteminde
# ATOMİKTİR ve aynı depoda index kilidi için de kullanılan kalıptır.
# ==============================================================================

PKG_META_LOCK_OWNER_FILE <- "owner.txt"
PKG_META_LOCK_HEARTBEAT_FILE <- "heartbeat.txt"

# Benzersiz sahiplik jetonu. Süreç kimliği TEK BAŞINA yetmez: işletim sistemi
# pid'leri geri dönüştürür ve iki farklı makine aynı paylaşımda aynı pid'i
# kullanabilir.
.pkgc_lock_token <- function() {
  rastgele <- paste(
    format(as.hexmode(sample.int(65535L, 4L, replace = TRUE)), width = 4L),
    collapse = ""
  )
  sprintf("%s-p%d-%s", format(Sys.time(), "%Y%m%d%H%M%S"), Sys.getpid(), rastgele)
}

.pkgc_lock_owner_text <- function(token) {
  paste0(
    "token=", token, "\n",
    "pid=", Sys.getpid(), "\n",
    "time=", format(Sys.time(), "%Y-%m-%dT%H:%M:%S"), "\n"
  )
}

# Diskteki sahiplik jetonunu oku. Okunamayan/eksik bir dosya `NA` döner; bu
# "sahip bilinmiyor" demektir ve bırakma yolunda TEMKİNLİ davranılır.
.pkgc_lock_read_token <- function(lock_path) {
  yol <- file.path(lock_path, PKG_META_LOCK_OWNER_FILE)
  if (!file.exists(yol)) return(NA_character_)

  satirlar <- tryCatch(readLines(yol, warn = FALSE), error = function(e) character(0))
  eslesen <- grep("^token=", satirlar, value = TRUE)
  if (!length(eslesen)) return(NA_character_)
  trimws(sub("^token=", "", eslesen[1]))
}

.pkgc_lock_touch <- function(lock_path) {
  yol <- file.path(lock_path, PKG_META_LOCK_HEARTBEAT_FILE)
  isTRUE(tryCatch({
    writeLines(format(Sys.time(), "%Y-%m-%dT%H:%M:%S"), yol)
    TRUE
  }, error = function(e) FALSE))
}

# Kilidin YAŞI, en TAZE canlılık kanıtından hesaplanır: kalp atışı dosyası,
# sahiplik dosyası ve dizinin kendisi. Yalnızca dizin `mtime` bakmak, kalp
# atışını yazan canlı bir koşuyu yine bayat sayardı.
.pkgc_lock_age_sec <- function(lock_path) {
  adaylar <- c(
    file.path(lock_path, PKG_META_LOCK_HEARTBEAT_FILE),
    file.path(lock_path, PKG_META_LOCK_OWNER_FILE),
    lock_path
  )
  zamanlar <- suppressWarnings(file.info(adaylar)$mtime)
  zamanlar <- zamanlar[!is.na(zamanlar)]
  if (!length(zamanlar)) return(NA_real_)

  yas <- suppressWarnings(as.numeric(difftime(Sys.time(), max(zamanlar), units = "secs")))
  if (length(yas) != 1L || is.na(yas)) return(NA_real_)
  yas
}

# ATOMİK DEVRALMA. `file.rename()` tek bir dosya sistemi işlemidir: iki süreç
# aynı bayat kilidi devralmaya çalıştığında yalnızca BİRİ başarılı olur.
.pkgc_lock_take_over <- function(lock_path, token) {
  karantina <- paste0(lock_path, ".stale-", token)
  if (!isTRUE(tryCatch(file.rename(lock_path, karantina), error = function(e) FALSE))) {
    return(FALSE)
  }
  tryCatch(unlink(karantina, recursive = TRUE, force = TRUE), error = function(e) NULL)
  isTRUE(suppressWarnings(tryCatch(dir.create(lock_path, showWarnings = FALSE),
                                   error = function(e) FALSE)))
}

#' Üretici koşu kilidini al
#'
#' @param stale_sec Bu yaştan eski (KALP ATIŞI da bu kadar eskimiş) bir kilit
#'   ÇÖKMÜŞ bir koşudan kalmış sayılır ve ATOMİK olarak devralınır.
#' @return list(ok, path, token, reason, detail). `reason`:
#'   `acquired` | `takeover` | `contention` | `io_error`
pkgc_acquire_run_lock <- function(lock_path, stale_sec = 3600) {
  jeton <- .pkgc_lock_token()
  dizin <- dirname(lock_path)

  if (!dir.exists(dizin)) {
    dir.create(dizin, recursive = TRUE, showWarnings = FALSE)
  }
  if (!dir.exists(dizin)) {
    return(list(ok = FALSE, path = lock_path, token = NA_character_,
                reason = "io_error", detail = paste0(
      "Kilit dizininin ust klasoru OLUSTURULAMADI: ", dizin, ". ",
      "Bu bir EŞZAMANLILIK sorunu DEGIL, bir yazma/izin sorunudur; ",
      "silinecek bir kilit YOKTUR."
    )))
  }

  alindi <- isTRUE(suppressWarnings(dir.create(lock_path, showWarnings = FALSE)))
  gerekce <- "acquired"

  if (!alindi && dir.exists(lock_path)) {
    yas <- .pkgc_lock_age_sec(lock_path)
    if (!is.na(yas) && yas > stale_sec) {
      alindi <- .pkgc_lock_take_over(lock_path, jeton)
      if (alindi) gerekce <- "takeover"
    }
  }

  if (!alindi) {
    # KİLİT YOKKEN OLUŞTURULAMADI: bu ÇEKİŞME değil, G/Ç ya da izin hatasıdır.
    # Operatöre "var olmayan bir kilidi silin" demek yanlış yönlendirmedir.
    if (!dir.exists(lock_path)) {
      return(list(ok = FALSE, path = lock_path, token = NA_character_,
                  reason = "io_error", detail = paste0(
        "Kilit dizini OLUSTURULAMADI ve diskte de YOK: ", lock_path, ". ",
        "Bu bir EŞZAMANLILIK sorunu DEGIL; yazma izni / disk / yol sorunudur. ",
        "Silinecek bir kilit YOKTUR."
      )))
    }

    return(list(ok = FALSE, path = lock_path, token = NA_character_,
                reason = "contention", detail = paste0(
      "Baska bir uretici kosusu devam ediyor gorunuyor (kilit: ", lock_path, "). ",
      "Iki kosu ayni cikti dosyasini SON YAZAN KAZANIR bicimde ezebilecegi icin ",
      "bu kosu BASLATILMADI. Kosunun bittiginden eminseniz kilit dizinini silin."
    )))
  }

  tryCatch(
    writeLines(.pkgc_lock_owner_text(jeton),
               file.path(lock_path, PKG_META_LOCK_OWNER_FILE)),
    error = function(e) NULL
  )
  .pkgc_lock_touch(lock_path)

  list(ok = TRUE, path = lock_path, token = jeton, reason = gerekce,
       detail = NA_character_)
}

#' Kilidin KALP ATIŞINI tazele
#'
#' Uzun süren bir envanter koşusu boyunca ARA ARA çağrılır; aksi hâlde koşu
#' `stale_sec` süresini aştığında KENDİ kilidi bayat sayılır.
pkgc_refresh_run_lock <- function(lock) {
  if (is.null(lock) || !isTRUE(lock$ok)) return(invisible(FALSE))
  # SAHİPLİK DEĞİŞTİYSE TAZELEME YAPILMAZ: kilidi başka bir koşu devraldıysa
  # onun kalp atışını yazmak, o koşunun kilidini bizim canlı tutmamız olurdu.
  diskteki <- .pkgc_lock_read_token(lock$path)
  if (!is.na(diskteki) && !identical(diskteki, lock$token)) return(invisible(FALSE))
  invisible(.pkgc_lock_touch(lock$path))
}

#' Kilidi bırak -- YALNIZCA HÂLÂ SAHİBİYSEK
#'
#' Kilit bu koşu çalışırken kırılmış/devralınmışsa (bayat sayılma ya da operatör
#' temizliği), koşullar sonrası silme YENİ koşunun kilidini silerdi.
pkgc_release_run_lock <- function(lock) {
  if (is.null(lock) || !isTRUE(lock$ok)) return(invisible(FALSE))

  diskteki <- .pkgc_lock_read_token(lock$path)
  if (!is.na(diskteki) && !identical(diskteki, lock$token)) {
    return(invisible(FALSE))
  }

  tryCatch(unlink(lock$path, recursive = TRUE, force = TRUE), error = function(e) NULL)
  invisible(TRUE)
}
