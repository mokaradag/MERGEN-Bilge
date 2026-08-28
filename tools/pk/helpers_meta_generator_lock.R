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

# Kaynaklanan app.R/global.R kalıcı RStudio sürecinin seçeneklerini, yerelini,
# MERGEN_LOG_DIR değerini ve Shiny resource path kayıtlarını değiştirir. Koşu
# kilidi bootstrap'ten hemen önce alındığı ve her çıkışta bırakıldığı için aynı
# nesne, SOURCE-GÜVENLİ süreç anlık görüntüsünü de taşır. Böylece hata yolu da
# başarı yolu da operatörün süreç durumunu başlangıçtaki hâline döndürür.
.pkgc_capture_process_state <- function() {
  # Snapshot almak için Shiny'yi YÜKLEME: requireNamespace() bile kalıcı süreç
  # yan etkisi yaratabilir. Namespace zaten yüklüyse mevcut kaynak eşlemeleri
  # okunur; değilse başlangıç eşlemesi boş kabul edilir.
  onceki_options <- options()
  shiny_yuklu <- "shiny" %in% loadedNamespaces()
  kaynaklar <- if (shiny_yuklu) {
    tryCatch(shiny::resourcePaths(), error = function(e) character(0))
  } else {
    character(0)
  }

  yerel_kategoriler <- c(
    "LC_COLLATE", "LC_CTYPE", "LC_TIME", "LC_NUMERIC", "LC_MONETARY", "LC_MESSAGES"
  )
  yerel <- vapply(yerel_kategoriler, function(kategori) {
    tryCatch(Sys.getlocale(kategori), error = function(e) "")
  }, character(1))

  list(
    options = onceki_options,
    locale = yerel,
    mergen_log_dir = Sys.getenv("MERGEN_LOG_DIR", unset = NA_character_),
    resource_paths = kaynaklar
  )
}

.pkgc_restore_process_state <- function(state) {
  if (is.null(state) || !is.list(state)) return(invisible(FALSE))

  # Bootstrap'ın normalize ettiği log dizini ortam değişkenini geri al.
  onceki_log <- state$mergen_log_dir
  if (is.null(onceki_log) || !length(onceki_log)) onceki_log <- NA_character_
  onceki_log <- as.character(onceki_log)[1]
  if (is.na(onceki_log)) {
    Sys.unsetenv("MERGEN_LOG_DIR")
  } else {
    Sys.setenv(MERGEN_LOG_DIR = onceki_log)
  }

  # global.R'nin eklediği/yeniden bağladığı Shiny kaynak öneklerini eski
  # eşlemeye döndür. Başlangıçta olmayan önekler kaldırılır.
  if ("shiny" %in% loadedNamespaces()) {
    onceki <- state$resource_paths
    if (is.null(onceki)) onceki <- character(0)
    simdiki <- tryCatch(shiny::resourcePaths(), error = function(e) character(0))

    tum <- union(names(simdiki), names(onceki))
    for (onek in tum) {
      eski <- if (onek %in% names(onceki)) unname(onceki[[onek]]) else NA_character_
      yeni <- if (onek %in% names(simdiki)) unname(simdiki[[onek]]) else NA_character_
      if (identical(eski, yeni)) next

      if (!is.na(yeni)) {
        tryCatch(shiny::removeResourcePath(onek), error = function(e) NULL)
      }
      if (!is.na(eski)) {
        tryCatch(shiny::addResourcePath(onek, eski), error = function(e) NULL)
      }
    }
  }

  # Yalnızca seçilmiş birkaç option değil, bootstrap'ten önceki TÜM option
  # kümesi geri yüklenir; global.R'nin eklediği seçenekler de silinir.
  onceki_options <- state$options
  if (is.list(onceki_options)) {
    eklenen <- setdiff(names(options()), names(onceki_options))
    for (ad in eklenen) {
      tryCatch(options(stats::setNames(list(NULL), ad)), error = function(e) NULL)
    }
    tryCatch(options(onceki_options), error = function(e) NULL)
  }

  # Yerel en sonda geri alınır; option/resource işlemlerinin hata mesajı veya
  # biçimlendirmesi operatörün eski yereline sızmaz.
  onceki_yerel <- state$locale
  if (is.character(onceki_yerel) && length(onceki_yerel)) {
    for (kategori in names(onceki_yerel)) {
      deger <- onceki_yerel[[kategori]]
      if (!is.na(deger) && nzchar(deger)) {
        try(suppressWarnings(Sys.setlocale(kategori, deger)), silent = TRUE)
      }
    }
  }

  invisible(TRUE)
}

# Benzersiz sahiplik jetonu. Süreç kimliği TEK BAŞINA yetmez: işletim sistemi
# pid'leri geri dönüştürür ve iki farklı makine aynı paylaşımda aynı pid'i
# kullanabilir.
# Surec-yerel monotonik sayac. Jeton benzersizligi SAATE ya da RNG'ye
# BIRAKILMAZ: kaba cozunurluklu bir saatte ayni saniyede uretilen iki jeton
# aksi halde ayni olabilir ve atomik devralma iki kosuyu ayirt edemezdi.
.PKGC_LOCK_COUNTER <- new.env(parent = emptyenv())
.PKGC_LOCK_COUNTER$n <- 0L

.pkgc_lock_token <- function() {
  # GLOBAL RNG DURUMU BOZULMAZ. Uretici, operatorun ACIK RStudio oturumuna
  # `source(...)` ile yuklenir; `sample.int()` `.Random.seed` degerini
  # ilerletir, yani jeton uretmek operatorun `set.seed()` ile sabitledigi
  # yeniden uretilebilirligi SESSIZCE bozardi. Bu yuzden durum alinip geri
  # konur; ancak yalnizca geri koymak jetonlari AYNI yapardi (ayni tohum ->
  # ayni ornek). Bu nedenle her cagri once yuksek cozunurluklu saatten
  # OZEL bir tohum kurar, jetona surec-yerel bir sayac da eklenir.
  vardi <- exists(".Random.seed", envir = globalenv(), inherits = FALSE)
  eski <- if (vardi) get(".Random.seed", envir = globalenv(), inherits = FALSE) else NULL
  on.exit({
    if (vardi) {
      assign(".Random.seed", eski, envir = globalenv())
    } else if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) {
      rm(".Random.seed", envir = globalenv())
    }
  }, add = TRUE)

  .PKGC_LOCK_COUNTER$n <- .PKGC_LOCK_COUNTER$n + 1L
  sayac <- .PKGC_LOCK_COUNTER$n
  tohum <- as.integer(bitwXor(
    as.integer((as.numeric(Sys.time()) * 1e6) %% 2147483647),
    bitwXor(as.integer(Sys.getpid()), sayac)
  ))
  set.seed(tohum)

  rastgele <- paste(
    format(as.hexmode(sample.int(65535L, 4L, replace = TRUE)), width = 4L),
    collapse = ""
  )
  sprintf("%s-p%d-c%d-%s", format(Sys.time(), "%Y%m%d%H%M%S"),
          Sys.getpid(), sayac, rastgele)
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
    # DEVRALMA YARIŞI G/Ç HATASI SAYILMAZ.
    #
    # `.pkgc_lock_take_over()` bayat kilidi ONCE `file.rename()` ile karantinaya
    # tasir, SONRA yeniden olusturur. Bu iki adim arasindaki pencerede yaris
    # halindeki ikinci sureci hem `dir.create()` basarisiz olur hem de
    # `dir.exists()` FALSE doner; eski kod bunu "diskte kilit YOK, yazma/izin
    # sorunu" diye raporluyordu. Gercek neden esZAMANLILIK'tir. Bu yuzden
    # G/C hatasi ILAN EDILMEDEN once SINIRLI bir yeniden deneme yapilir.
    if (!dir.exists(lock_path)) {
      for (deneme in seq_len(3L)) {
        Sys.sleep(0.05)
        if (isTRUE(suppressWarnings(dir.create(lock_path, showWarnings = FALSE)))) {
          alindi <- TRUE
          break
        }
        if (dir.exists(lock_path)) break
      }
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

  # Anlık görüntü kilit BAŞARILI alındıktan sonra, fakat app.R bootstrap'inden
  # ÖNCE alınır. Başarısız kilit edinimi operatör sürecine dokunmaz.
  surec_durumu <- .pkgc_capture_process_state()

  # SAHİPLİK JETONU KALICI YAZILAMAZSA EDİNİM BAŞARISIZDIR.
  #
  # Yazım hatası sessizce yutuluyordu; jetonsuz bir kilit sonra "sahip
  # bilinmiyor" durumuna düşer ve devralma/bırakma yolları KİMİN sahip olduğunu
  # kanıtlayamaz. Bu, jeton şemasının önlemek için var olduğu eşzamanlı-yazar
  # yarışını geri getirirdi.
  yazildi <- isTRUE(tryCatch({
    writeLines(.pkgc_lock_owner_text(jeton),
               file.path(lock_path, PKG_META_LOCK_OWNER_FILE))
    identical(.pkgc_lock_read_token(lock_path), jeton)
  }, error = function(e) FALSE))

  if (!yazildi) {
    .pkgc_restore_process_state(surec_durumu)
    tryCatch(unlink(lock_path, recursive = TRUE, force = TRUE), error = function(e) NULL)
    return(list(ok = FALSE, path = lock_path, token = NA_character_,
                reason = "owner_write_failed", detail = paste0(
      "Kilit sahiplik jetonu yazilamadi; es zamanli yazar korumasi ",
      "dogrulanamadigi icin kosu BASLATILMADI."
    )))
  }

  .pkgc_lock_touch(lock_path)

  list(ok = TRUE, path = lock_path, token = jeton, reason = gerekce,
       detail = NA_character_, process_state = surec_durumu)
}

#' Kilidin KALP ATIŞINI tazele
#'
#' Uzun süren bir envanter koşusu boyunca ARA ARA çağrılır; aksi hâlde koşu
#' `stale_sec` süresini aştığında KENDİ kilidi bayat sayılır.
pkgc_refresh_run_lock <- function(lock) {
  if (is.null(lock) || !isTRUE(lock$ok)) return(invisible(FALSE))
  # SAHİPLİK DEĞİŞTİYSE TAZELEME YAPILMAZ: kilidi başka bir koşu devraldıysa
  # onun kalp atışını yazmak, o koşunun kilidini bizim canlı tutmamız olurdu.
  # `NA` = SAHİP BİLİNMİYOR -> SAHİBİ DEĞİLİZ. Eski koşul yalnızca FARKLI ve
  # NA olmayan bir jetonu reddediyordu; okunamayan/eksik `owner.txt`, kilidi
  # HÂLÂ bizim sanmamıza yol açıyordu. Dizin devralınmışsa ve jetonu geçici
  # olarak okunamıyorsa eski koşu YENİ koşunun kilidini canlı tutar ve daha
  # sonra siler.
  diskteki <- .pkgc_lock_read_token(lock$path)
  if (is.na(diskteki) || !identical(diskteki, lock$token)) return(invisible(FALSE))
  invisible(.pkgc_lock_touch(lock$path))
}

#' Kilidi bırak -- YALNIZCA HÂLÂ SAHİBİYSEK
#'
#' Kilit bu koşu çalışırken kırılmış/devralınmışsa (bayat sayılma ya da operatör
#' temizliği), koşullar sonrası silme YENİ koşunun kilidini silerdi.
pkgc_release_run_lock <- function(lock) {
  if (is.null(lock) || !isTRUE(lock$ok)) return(invisible(FALSE))

  # Sahiplik değişmiş olsa bile BU koşunun bootstrap yan etkileri geri alınır.
  # on.exit kullanmak, aşağıdaki sahiplik erken dönüşlerinde de restorasyonu
  # garanti eder.
  surec_durumu <- if (!is.null(lock$process_state)) lock$process_state else NULL
  on.exit(.pkgc_restore_process_state(surec_durumu), add = TRUE)

  # `NA` = SAHİP BİLİNMİYOR -> SİLİNMEZ (bkz. tazeleme açıklaması).
  diskteki <- .pkgc_lock_read_token(lock$path)
  if (is.na(diskteki) || !identical(diskteki, lock$token)) {
    return(invisible(FALSE))
  }

  tryCatch(unlink(lock$path, recursive = TRUE, force = TRUE), error = function(e) NULL)
  invisible(TRUE)
}
