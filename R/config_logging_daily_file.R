# ==============================================================================
# R/config_logging_daily_file.R
# Günlük (tarih-duyarlı) log dosyası yardımcıları: tarih çözümleme, dosya yolu,
# dosya appender'ı ve açılışta günlük dosyayı garanti eden yardımcı.
#
# config_logging.R'den ÖNCE (foundation bölümü) yüklenir. Bu fonksiyonlar yalnızca
# TANIMLANIR; config_logging.R içindeki global `mergen_log_dir` değişkenini ÇAĞRI
# anında (lexical scope, call time) okurlar, bu yüzden burada hiçbir şey çağrılmaz.
#
# Maintainability: günlük log dosyası kümesi, config_logging.R'nin fonksiyon
# yoğunluğu tavanını aşmaması için bu odaklı dosyaya ayrılmıştır. Günlük devir
# anlamı korunur; dosya içeriği her zaman UTF-8'dir.
# ==============================================================================

# --- GÜNLÜK LOG DOSYASI ÇÖZÜMLEME (TARİH-DUYARLI) ---
# Tarih her log satırında yeniden çözülür. Bu, Haziran regresyonunun iki olası
# kök nedenini birden kapatır:
#   1) Her yeniden başlatma o günün mergen_YYYYMMDD.log dosyasını oluşturur.
#   2) Uzun süre açık kalan üretim süreci gece yarısını geçince otomatik olarak
#      yeni güne ait dosyaya yazmaya başlar; başlangıç tarihindeki eski dosyada
#      takılı kalmaz (son log 12.06 saat 23:51'de kalmıştı).
# Testler tarihi mergen.log.date_provider option'ı ile enjekte edebilir.
current_mergen_log_date <- function() {
  date_provider <- getOption("mergen.log.date_provider", NULL)
  current_date <- if (is.function(date_provider)) date_provider() else Sys.Date()
  if (inherits(current_date, "Date")) {
    return(current_date[1])
  }
  as.Date(current_date[1])
}

current_mergen_log_file_path <- function() {
  file.path(
    mergen_log_dir,
    sprintf("mergen_%s.log", format(current_mergen_log_date(), "%Y%m%d"))
  )
}

# Satırları günlük dosyaya İKİLİ kipte UTF-8 bayt olarak ekler. cat(file=)
# yazımı options(encoding) ve yerel kod sayfasına bağlıydı; Windows VM'de
# (CP1254) dosyaya CP1254 baytları düşüyor, UTF-8 okuyan canlı log
# görüntüleyicisinde Türkçe karakterler mojibake görünüyordu.
mergen_log_append_utf8 <- function(lines, target_file) {
  lines <- as.character(lines)
  lines[is.na(lines)] <- "NA"
  lines <- if (exists("normalize_text_utf8", mode = "function")) {
    normalize_text_utf8(lines)
  } else {
    enc2utf8(lines)
  }
  payload <- charToRaw(enc2utf8(paste0(paste(lines, collapse = "\n"), "\n")))
  con <- file(target_file, open = "ab")
  on.exit(close(con), add = TRUE)
  writeBin(payload, con)
  invisible(length(payload))
}

# Dosya sınırlı parçalarla (satır sınırında bölünerek) UTF-8 doğrulanır; büyük
# dosya belleğe tümüyle alınmaz. `from` bayt ofsetinden itibaren (yalnız yeni
# eklenen kısım) doğrulanabilir; `nabiz` her parçada çalışır (kilit tazeleme).
# NUL baytı bu yazıcının biçimi değildir (ör. UTF-16); dosya UTF-8 sayılmaz.
mergen_log_file_is_utf8 <- function(target_file, chunk = 4 * 1024^2, from = 0, nabiz = NULL) {
  con <- file(target_file, open = "rb")
  on.exit(close(con), add = TRUE)
  if (from > 0) {
    seek(con, where = from, origin = "start")
    if (!isTRUE(seek(con) == from)) return(FALSE)
  }
  gecerli <- function(b) !any(b == as.raw(0L)) && validUTF8(rawToChar(b))
  artik <- raw(0)
  repeat {
    .mergen_log_heartbeat(nabiz)
    parca <- readBin(con, what = "raw", n = chunk)
    if (!length(parca)) break
    artik <- c(artik, parca)
    sonlar <- which(artik == as.raw(10L))
    kesim <- if (length(sonlar)) sonlar[length(sonlar)] else if (length(artik) >= 4 * chunk) {
      # Zorunlu kesim çok baytlı harfi bölmez: son (yarım olabilecek) harf
      # sonraki parçaya bırakılır.
      n <- length(artik)
      ilk <- max(1L, n - 3L)
      bas <- which(bitwAnd(as.integer(artik[ilk:n]), 0xC0L) != 0x80L)
      if (length(bas)) ilk + bas[length(bas)] - 2L else n
    } else 0L
    if (kesim > 0L) {
      if (!gecerli(artik[seq_len(kesim)])) return(FALSE)
      artik <- artik[-seq_len(kesim)]
    }
  }
  gecerli(artik)
}

# Dosya kimliği: boyut + mtime (+ istenirse ilk 256 bayt). Aynı boyutta
# değiştirilen/geri yüklenen dosya önbellekteki kararı devralmaz.
.mergen_log_file_kimlik <- function(target_file, bas = FALSE) {
  bilgi <- suppressWarnings(file.info(target_file))
  kimlik <- list(boyut = bilgi$size, zaman = as.numeric(bilgi$mtime))
  if (isTRUE(bas)) {
    bas <- if (is.na(bilgi$size)) raw(0) else try(readBin(target_file, what = "raw", n = 256L), silent = TRUE)
    kimlik$bas <- if (inherits(bas, "try-error")) raw(0) else bas
  }
  kimlik
}

# Eski cat(file=) yazıcısının yerel kod sayfasıyla (CP1254) satır bıraktığı
# günlük dosya yerinde DÖNÜŞTÜRÜLMEZ: kod sayfası tahmini, tam içerik geçici
# kopyası ve süreçler arası değiştirme yarışı olmaz. Süreçler arası kilit altında
# yeniden denetlenir ve olduğu gibi (bayt bayt, izinleriyle)
# `<ad>.legacy-SSDDss-PID.log` adına taşınır; yeni satırlar temiz UTF-8 dosyada
# başlar. Taşınamazsa FALSE döner (60 sn sonra yeniden denenir).
# Doğrulanan dosya kimliği (boyut, mtime, baş baytlar) saklanır: başka bir
# yazıcı (ör. yükseltme sırasında hâlâ çalışan eski süreç) ekleme yaparsa
# yalnız yeni baytlar denetlenir; dosya küçülür/değişirse tamamı yeniden taranır.
.MERGEN_LOG_UTF8_CHECKED <- new.env(parent = emptyenv())

mergen_log_upgrade_legacy_file <- function(target_file, lock_wait = 2, stale_after = 60, nabiz = NULL) {
  anahtar <- normalizePath(target_file, winslash = "/", mustWork = FALSE)
  durum <- .MERGEN_LOG_UTF8_CHECKED[[anahtar]]
  if (is.numeric(durum) && as.numeric(Sys.time()) < durum) return(FALSE)
  kimlik <- .mergen_log_file_kimlik(target_file)
  boyut <- kimlik$boyut
  onceki <- if (is.list(durum)) durum$boyut else NA_real_
  if (is.list(durum) && (is.na(boyut) ||
                         (identical(boyut, onceki) && identical(kimlik$zaman, durum$zaman) &&
                          identical(.mergen_log_file_kimlik(target_file, bas = TRUE)$bas, durum$bas)))) {
    return(TRUE)
  }
  temiz <- function(nabiz2 = NULL) {
    !file.exists(target_file) || isTRUE(mergen_log_file_is_utf8(target_file, nabiz = c(nabiz, nabiz2)))
  }
  sonuc <- tryCatch({
    ek_temiz <- !is.na(onceki) && !is.na(boyut) && boyut > onceki &&
      identical(.mergen_log_file_kimlik(target_file, bas = TRUE)$bas, durum$bas) &&
      isTRUE(mergen_log_file_is_utf8(target_file, from = onceki, nabiz = nabiz))
    ek_temiz || temiz() || .mergen_log_move_legacy(target_file, temiz, lock_wait, stale_after)
  }, error = function(e) FALSE)
  .MERGEN_LOG_UTF8_CHECKED[[anahtar]] <- if (isTRUE(sonuc)) {
    .mergen_log_file_kimlik(target_file, bas = TRUE)
  } else {
    as.numeric(Sys.time()) + 60
  }
  isTRUE(sonuc)
}

.mergen_log_move_legacy <- function(target_file, temiz, lock_wait, stale_after) {
  kilit <- paste0(target_file, ".lock")
  jeton <- .mergen_log_lock_acquire(kilit, lock_wait, stale_after)
  if (is.null(jeton)) return(FALSE)
  on.exit(.mergen_log_lock_release(kilit, jeton), add = TRUE)
  # Uzun tarama sırasında kilit tazelenir; başka süreç onu bayat saymaz.
  if (temiz(kilit)) {
    return(TRUE)
  }
  if (!.mergen_log_lock_owned(kilit, jeton)) return(FALSE)
  taban <- sub("(\\.log)?$", sprintf(".legacy-%s-%d", format(Sys.time(), "%H%M%S"), Sys.getpid()),
               target_file)
  kenar <- paste0(taban, ".log")
  sira <- 1L
  while (file.exists(kenar)) {
    sira <- sira + 1L
    kenar <- sprintf("%s-%d.log", taban, sira)
  }
  isTRUE(file.rename(target_file, kenar)) && temiz()
}

# Çok-süreçli dağıtımda (tools/run_mergen_workers.R) ya da log dizini UNC/ağ
# paylaşımıyken (başka hostlar da yazabilir) eklemeler kısa bir süreçler arası
# kilitle sıralanır; MERGEN_LOG_SHARED_WRITERS=true bunu zorlar (ör. eşlenmiş
# ağ sürücüsü). Kilit alınamazsa paylaşılan dosyaya kilitsiz YAZILMAZ: satır
# sürece özel `<ad>.p<HOST>-<PID>.log` yedeğine düşer ve sonra birleştirilir.
.mergen_log_shared_writers <- function(target_file = "") {
  tolower(trimws(Sys.getenv("MERGEN_LOG_SHARED_WRITERS", ""))) %in% c("1", "true", "t", "yes", "y", "on") ||
    isTRUE(suppressWarnings(as.integer(Sys.getenv("MERGEN_APP_WORKER_COUNT", "1"))) > 1L) ||
    grepl("^(\\\\\\\\|//)[^\\\\/]+[\\\\/]", as.character(target_file)[1])
}

.MERGEN_LOG_LOCK_BACKOFF <- new.env(parent = emptyenv())

# Yedeğin ana dosyaya zaten eklenmiş bayt sayısı: silinemeyen ya da geri
# alınamayan yedek kaldığı yerden sürer, satırlar iki kez eklenmez. Değer
# süreç belleğinde ve `<yedek>.birlesen` yan dosyasında tutulur.
.MERGEN_LOG_MERGE_OFFSET <- new.env(parent = emptyenv())

# `ofs` verilmezse okunur (yedekten büyükse 0); verilirse yazılır, 0 kaydı siler.
# Yazımda yan dosya kaydedilebildiyse TRUE döner.
.mergen_log_merged_offset <- function(yedek, ofs = NULL) {
  anahtar <- normalizePath(yedek, winslash = "/", mustWork = FALSE)
  yan <- paste0(yedek, ".birlesen")
  if (is.null(ofs)) {
    kayit <- suppressWarnings(try(as.numeric(readLines(yan, n = 1L, warn = FALSE)), silent = TRUE))
    if (inherits(kayit, "try-error")) kayit <- NA_real_
    ofs <- max(c(0, kayit, .MERGEN_LOG_MERGE_OFFSET[[anahtar]]), na.rm = TRUE)
    boyut <- suppressWarnings(file.info(yedek)$size)
    return(if (is.na(boyut) || ofs > boyut) 0 else ofs)
  }
  if (ofs <= 0) {
    if (exists(anahtar, envir = .MERGEN_LOG_MERGE_OFFSET, inherits = FALSE)) {
      rm(list = anahtar, envir = .MERGEN_LOG_MERGE_OFFSET)
    }
    unlink(yan)
    return(invisible(TRUE))
  }
  .MERGEN_LOG_MERGE_OFFSET[[anahtar]] <- ofs
  yazim <- suppressWarnings(try(writeLines(format(ofs, scientific = FALSE), yan), silent = TRUE))
  invisible(!inherits(yazim, "try-error") && file.exists(yan))
}

.mergen_log_append_fallback <- function(lines, target_file) {
  kilit <- filelock::lock(paste0(target_file, ".writer"), timeout = 250)
  if (is.null(kilit)) {
    target_file <- sub("\\.log$", paste0("-", basename(tempfile("")), ".log"), target_file)
    kilit <- filelock::lock(paste0(target_file, ".writer"), timeout = 0)
    if (is.null(kilit)) stop("Yedek günlük kilidi alınamadı.")
  }
  on.exit(filelock::unlock(kilit), add = TRUE)
  mergen_log_append_utf8(lines, target_file)
}

# Yedek dosyadaki satırlar kilit altında ana dosyaya eklenir ve yedek silinir.
# Yarıda kalan kopya geri alınır (hedef eski boyutuna kesilir); yeniden
# denemede aynı satırlar iki kez eklenmez.
.mergen_log_merge_fallback <- function(target_file, yedek, nabiz = NULL) {
  kilit <- paste0(target_file, ".lock")
  jeton <- .mergen_log_lock_acquire(kilit, 0.5, 60)
  if (is.null(jeton)) return(invisible(FALSE))
  on.exit(.mergen_log_lock_release(kilit, jeton), add = TRUE)
  yazici_kilidi <- filelock::lock(paste0(yedek, ".writer"), timeout = 0)
  if (is.null(yazici_kilidi)) return(invisible(FALSE))
  on.exit(filelock::unlock(yazici_kilidi), add = TRUE)
  if (!file.exists(yedek)) {
    .mergen_log_merged_offset(yedek, 0)
    return(invisible(TRUE))
  }
  baslangic <- file.info(target_file)$size
  if (is.na(baslangic)) baslangic <- 0
  ofs <- .mergen_log_merged_offset(yedek)
  kopyalanan <- 0
  giris <- file(yedek, open = "rb")
  cikis <- file(target_file, open = "ab")
  kopya <- try({
    if (ofs > 0) seek(giris, where = ofs, origin = "start")
    repeat {
      .mergen_log_heartbeat(c(nabiz, kilit))
      parca <- readBin(giris, what = "raw", n = 1024^2)
      if (!length(parca)) break
      writeBin(parca, cikis)
      kopyalanan <- kopyalanan + length(parca)
    }
    close(cikis)
    cikis <- NULL
  }, silent = TRUE)
  tamam <- !inherits(kopya, "try-error")
  close(giris)
  if (!is.null(cikis)) try(close(cikis), silent = TRUE)
  if (isTRUE(tamam)) {
    unlink(yedek)
    if (!file.exists(yedek)) {
      .mergen_log_merged_offset(yedek, 0)
      return(invisible(TRUE))
    }
    # Silinemeyen yedek: eklenen bayt sayısı kaydedilir; kaydedilemezse
    # yedek aşağıda karantinaya alınır.
    if (isTRUE(.mergen_log_merged_offset(yedek, ofs + kopyalanan))) return(invisible(TRUE))
    simdi <- NA_real_
  } else {
    con <- try(file(target_file, open = "r+b"), silent = TRUE)
    if (!inherits(con, "try-error")) {
      try({
        seek(con, where = baslangic, rw = "write")
        truncate(con)
      }, silent = TRUE)
      close(con)
    }
    simdi <- suppressWarnings(file.info(target_file)$size)
    if (isTRUE(simdi == baslangic)) return(invisible(FALSE))
  }
  # Geri alma doğrulanamazsa yedek yeniden denenmez (satırlar iki kez
  # eklenmez); inceleme için çakışmasız ayrı adla saklanır ve taşıma
  # doğrulanır. Taşınamazsa ana dosyadaki kısmi bayt sayısı kaydedilir ve
  # sonraki birleştirme oradan sürer.
  taban <- sub("(\\.log)?$", sprintf(".birlesmedi-%s-%d", format(Sys.time(), "%Y%m%d%H%M%S"), Sys.getpid()), yedek)
  karantina <- paste0(taban, ".log")
  sira <- 1L
  while (file.exists(karantina)) {
    sira <- sira + 1L
    karantina <- sprintf("%s-%d.log", taban, sira)
  }
  if (isTRUE(suppressWarnings(file.rename(yedek, karantina))) && !file.exists(yedek)) {
    .mergen_log_merged_offset(yedek, 0)
    return(invisible(isTRUE(tamam)))
  }
  if (!isTRUE(tamam) && !is.na(simdi) && simdi > baslangic) {
    .mergen_log_merged_offset(yedek, ofs + (simdi - baslangic))
  }
  invisible(FALSE)
}

# Başka süreçlerin (ör. kapanmış işçi) 60 sn'dir dokunulmamış yedekleri kilit
# altında sahiplenilir (yeniden adlandırma) ve mtime sırasıyla birleştirilir.
.mergen_log_orphan_fallbacks <- function(target_file, surec_yedek, kilitli) {
  if (!isTRUE(kilitli)) return(character(0))
  kok <- gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", sub("\\.log$", "", basename(target_file)))
  adaylar <- list.files(dirname(target_file), pattern = paste0("^", kok, "\\.p[A-Za-z0-9_-]+\\.log$"),
                        full.names = TRUE)
  adaylar <- adaylar[basename(adaylar) != basename(surec_yedek)]
  # Bu sürecin önceden sahiplenip birleştiremediği yedekler yaşa bakılmadan
  # yeniden denenir; yeniden adlandırılmaz.
  bizim <- grepl(sprintf("-m%d\\.log$", Sys.getpid()), basename(adaylar))
  zaman <- file.info(adaylar)$mtime
  eski <- !bizim & !is.na(zaman) & as.numeric(difftime(Sys.time(), zaman, units = "secs")) > 60
  sahiplenilen <- sub("\\.log$", sprintf("-m%d.log", Sys.getpid()), adaylar[eski])
  tasinan <- logical(length(sahiplenilen))
  for (i in seq_along(sahiplenilen)) {
    kaynak <- adaylar[eski][i]
    hedef <- sahiplenilen[i]
    yazici_kilidi <- filelock::lock(paste0(kaynak, ".writer"), timeout = 0)
    if (is.null(yazici_kilidi)) next
    (function() tryCatch({
      if (file.exists(hedef)) return(NULL)
      yan <- paste0(kaynak, ".birlesen")
      hedef_yan <- paste0(hedef, ".birlesen")
      if (!file.exists(yan) && file.exists(hedef_yan)) {
        unlink(hedef_yan)
        if (file.exists(hedef_yan)) return(NULL)
      }
      # Bayt kaydı doğrulanmadan günlük sahiplenilmez.
      if (file.exists(yan) && !isTRUE(suppressWarnings(try({
        file.copy(yan, hedef_yan, overwrite = TRUE) &&
          identical(readBin(yan, "raw", file.info(yan)$size),
                    readBin(hedef_yan, "raw", file.info(hedef_yan)$size))
      }, silent = TRUE)))) return(NULL)
      tasinan[i] <<- isTRUE(file.rename(kaynak, hedef))
      if (tasinan[i]) unlink(yan) else unlink(hedef_yan)
    }, finally = filelock::unlock(yazici_kilidi)))()
  }
  secilen <- c(adaylar[bizim], sahiplenilen[tasinan])
  secilen[order(file.info(secilen)$mtime, basename(secilen))]
}

# Karışık kodlama üretmeden UTF-8 ekler: eski satırlı dosya taşınamadıysa satırlar
# `<ad>.utf8.log` yedeğine yazılır. Birleştirilemeyen yedek varken yeni satırlar
# da yedeğe eklenir; günlükteki kronolojik sıra bozulmaz.
mergen_log_write_utf8 <- function(lines, target_file) {
  host <- gsub("[^A-Za-z0-9_-]", "_", c(Sys.info()["nodename"], "h")[1])
  surec_yedek <- sub("(\\.log)?$", sprintf(".p%s-%d.log", host, Sys.getpid()), target_file)
  jeton <- NULL
  if (.mergen_log_shared_writers(target_file)) {
    ekle_kilit <- paste0(target_file, ".append.lock")
    ertele <- .MERGEN_LOG_LOCK_BACKOFF[[ekle_kilit]]
    if (is.numeric(ertele) && as.numeric(Sys.time()) < ertele) {
      return(invisible(.mergen_log_append_fallback(lines, surec_yedek) > 0))
    }
    # Kısa bekleme: yetim kilit her log satırını saniyelerce bloklamaz; zaman
    # aşımı birkaç saniye önbelleklenir.
    jeton <- .mergen_log_lock_acquire(ekle_kilit, 0.25, 120)
    if (is.null(jeton)) {
      .MERGEN_LOG_LOCK_BACKOFF[[ekle_kilit]] <- as.numeric(Sys.time()) + 5
      return(invisible(.mergen_log_append_fallback(lines, surec_yedek) > 0))
    }
    on.exit(.mergen_log_lock_release(ekle_kilit, jeton), add = TRUE)
    nabiz <- ekle_kilit
  } else {
    nabiz <- NULL
  }
  yedek <- sub("(\\.log)?$", ".utf8.log", target_file)
  if (!isTRUE(mergen_log_upgrade_legacy_file(target_file, nabiz = nabiz))) {
    return(invisible(.mergen_log_append_fallback(lines, yedek) > 0))
  }
  for (y in c(yedek, .mergen_log_orphan_fallbacks(target_file, surec_yedek, !is.null(jeton)), surec_yedek)) {
    if (file.exists(y) && !isTRUE(.mergen_log_merge_fallback(target_file, y, nabiz))) {
      return(invisible(.mergen_log_append_fallback(lines, y) > 0))
    }
  }
  # Son ekleme öncesi kilit tazelenir; sahipliği kaybeden yazıcı ana dosyaya dokunmaz.
  if (!is.null(jeton)) {
    .mergen_log_heartbeat(ekle_kilit)
    if (!.mergen_log_lock_owned(ekle_kilit, jeton)) {
      return(invisible(.mergen_log_append_fallback(lines, surec_yedek) > 0))
    }
  }
  once <- file.info(target_file)$size
  eklenen <- mergen_log_append_utf8(lines, target_file)
  # Son boyut tam olarak önceki + bu yazımın baytıysa doğrulanan kimlik
  # ilerletilir; araya giren (denetlenmemiş) baytlar sonraki yazımda taranır.
  anahtar <- normalizePath(target_file, winslash = "/", mustWork = FALSE)
  durum <- .MERGEN_LOG_UTF8_CHECKED[[anahtar]]
  if (is.list(durum) && (identical(durum$boyut, once) || (is.na(durum$boyut) && is.na(once)))) {
    kimlik <- .mergen_log_file_kimlik(target_file, bas = length(durum$bas) < 256L)
    if (isTRUE(kimlik$boyut == (if (is.na(once)) 0 else once) + eklenen)) {
      if (is.null(kimlik$bas)) kimlik$bas <- durum$bas
      .MERGEN_LOG_UTF8_CHECKED[[anahtar]] <- kimlik
    }
  }
  invisible(TRUE)
}

# Hem konsola hem dosyaya log yaz.
# Satır ayrımı logger::appender_file ile aynıdır (her satır "\n" ile biter);
# dosya kodlaması ise yerel ayardan bağımsız olarak her zaman UTF-8'dir.
# Üç üretim güvenilirliği iyileştirmesi:
#   1) Hedef dosya her satırda güncel tarihe göre yeniden çözülür (günlük devir).
#   2) Log dizini her yazımdan önce garanti edilir (UNC/ağ paylaşımı dayanıklılığı).
#   3) Yazma hatası SESSİZCE yutulmaz; konsola bildirilir; böylece bir paylaşım
#      hatası günlerce fark edilmeden log üretimini durduramaz.
# Konsol native-dönüşümü ayrı appender'da yapılır.
mergen_daily_file_appender <- function(lines) {
  if (!dir.exists(mergen_log_dir)) {
    dir.create(mergen_log_dir, recursive = TRUE, showWarnings = FALSE)
  }

  target_file <- current_mergen_log_file_path()
  tryCatch(
    mergen_log_write_utf8(lines, target_file),
    error = function(e) {
      message(sprintf(
        "[MERGEN LOGGING ERROR] Gunluk log dosyasina yazilamadi (%s): %s",
        target_file, conditionMessage(e)
      ))
    }
  )
}

# --- AÇILIŞTA GÜNLÜK DOSYAYI GARANTİLE (THRESHOLD-BAĞIMSIZ) ---
# Haziran regresyonunun çekirdek belirtisi: uygulama açılışında
# mergen_YYYYMMDD.log dosyası HİÇ oluşmuyordu (konsol logları çalışsa bile).
# Kök neden ne olursa olsun (yüksek MERGEN_LOG_THRESHOLD ilk INFO satırını
# filtreliyor; logger appender dağıtımı ilk çağrıda dosyaya ulaşmıyor; vb.),
# logger appender'ı dosyayı YALNIZCA eşiği geçen bir satır yazıldığında
# oluşturur. Bu yardımcı, her açılışta günün dosyasını DOĞRUDAN (logger ve
# threshold'dan tamamen bağımsız) oluşturup açılış başlığını yazar; böylece
# dosyanın her gün, her yeniden başlatmada var olması garanti edilir.
# Yazım yolu dosya appender'ı ile aynıdır (UTF-8 ikili ekleme).
mergen_ensure_daily_log_file <- function() {
  if (!dir.exists(mergen_log_dir)) {
    dir.create(mergen_log_dir, recursive = TRUE, showWarnings = FALSE)
  }
  target_file <- current_mergen_log_file_path()
  banner <- sprintf(
    "INFO [%s] === MERGEN Bilge gunluk log dosyasi hazir: %s ===",
    format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    target_file
  )
  tryCatch(
    mergen_log_write_utf8(banner, target_file),
    error = function(e) {
      message(sprintf(
        "[MERGEN LOGGING ERROR] Acilis gunluk log dosyasi olusturulamadi (%s): %s",
        target_file, conditionMessage(e)
      ))
    }
  )
  invisible(target_file)
}
