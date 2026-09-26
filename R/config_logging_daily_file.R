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
  payload <- enc2utf8(paste0(paste(lines, collapse = "\n"), "\n"))
  con <- file(target_file, open = "ab")
  on.exit(close(con), add = TRUE)
  writeBin(charToRaw(payload), con)
  invisible(TRUE)
}

# Dosya sınırlı parçalarla (satır sınırında bölünerek) UTF-8 doğrulanır; büyük
# dosya belleğe tümüyle alınmaz.
mergen_log_file_is_utf8 <- function(target_file, chunk = 4 * 1024^2) {
  con <- file(target_file, open = "rb")
  on.exit(close(con), add = TRUE)
  gecerli <- function(b) validUTF8(rawToChar(b[b != as.raw(0L)]))
  artik <- raw(0)
  repeat {
    parca <- readBin(con, what = "raw", n = chunk)
    if (!length(parca)) break
    artik <- c(artik, parca)
    sonlar <- which(artik == as.raw(10L))
    kesim <- if (length(sonlar)) sonlar[length(sonlar)] else if (length(artik) >= 4 * chunk) length(artik) else 0L
    if (kesim > 0L) {
      if (!gecerli(artik[seq_len(kesim)])) return(FALSE)
      artik <- artik[-seq_len(kesim)]
    }
  }
  gecerli(artik)
}

# Eski cat(file=) yazıcısının yerel kod sayfasıyla (CP1254) satır bıraktığı
# günlük dosya yerinde DÖNÜŞTÜRÜLMEZ: kod sayfası tahmini, tam içerik geçici
# kopyası ve süreçler arası değiştirme yarışı olmaz. Süreçler arası kilit altında
# yeniden denetlenir ve olduğu gibi (bayt bayt, izinleriyle)
# `<ad>.legacy-SSDDss-PID.log` adına taşınır; yeni satırlar temiz UTF-8 dosyada
# başlar. Taşınamazsa FALSE döner (60 sn sonra yeniden denenir).
.MERGEN_LOG_UTF8_CHECKED <- new.env(parent = emptyenv())

mergen_log_upgrade_legacy_file <- function(target_file, lock_wait = 2, stale_after = 60) {
  anahtar <- normalizePath(target_file, winslash = "/", mustWork = FALSE)
  durum <- .MERGEN_LOG_UTF8_CHECKED[[anahtar]]
  if (isTRUE(durum)) return(TRUE)
  if (is.numeric(durum) && as.numeric(Sys.time()) < durum) return(FALSE)
  temiz <- function() !file.exists(target_file) || isTRUE(mergen_log_file_is_utf8(target_file))
  sonuc <- tryCatch(
    temiz() || .mergen_log_move_legacy(target_file, temiz, lock_wait, stale_after),
    error = function(e) FALSE
  )
  .MERGEN_LOG_UTF8_CHECKED[[anahtar]] <- if (isTRUE(sonuc)) TRUE else as.numeric(Sys.time()) + 60
  isTRUE(sonuc)
}

.mergen_log_move_legacy <- function(target_file, temiz, lock_wait, stale_after) {
  kilit <- paste0(target_file, ".lock")
  bitis <- Sys.time() + lock_wait
  while (!dir.create(kilit, showWarnings = FALSE)) {
    # Çöken sürecin bıraktığı bayat kilit kaldırılır.
    yas <- as.numeric(difftime(Sys.time(), file.info(kilit)$mtime, units = "secs"))
    if (isTRUE(yas > stale_after)) unlink(kilit, recursive = TRUE)
    if (Sys.time() > bitis) return(FALSE)
    Sys.sleep(0.05)
  }
  on.exit(unlink(kilit, recursive = TRUE), add = TRUE)
  if (temiz()) return(TRUE)
  kenar <- sub("(\\.log)?$", sprintf(".legacy-%s-%d.log", format(Sys.time(), "%H%M%S"), Sys.getpid()),
               target_file)
  isTRUE(file.rename(target_file, kenar)) && temiz()
}

# Karışık kodlama üretmeden UTF-8 ekler: eski satırlı dosya taşınamadıysa satırlar
# `<ad>.utf8.log` yedeğine yazılır.
mergen_log_write_utf8 <- function(lines, target_file) {
  hedef <- if (isTRUE(mergen_log_upgrade_legacy_file(target_file))) {
    target_file
  } else {
    sub("(\\.log)?$", ".utf8.log", target_file)
  }
  mergen_log_append_utf8(lines, hedef)
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
