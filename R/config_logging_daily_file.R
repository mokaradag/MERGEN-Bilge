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
# yoğunluğu tavanını aşmaması için bu odaklı dosyaya ayrılmıştır. Davranış,
# dosya içeriği, kodlaması ve günlük devir anlamı eskisiyle BİREBİR aynıdır.
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
    mergen_log_append_utf8(lines, target_file),
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
    mergen_log_append_utf8(banner, target_file),
    error = function(e) {
      message(sprintf(
        "[MERGEN LOGGING ERROR] Acilis gunluk log dosyasi olusturulamadi (%s): %s",
        target_file, conditionMessage(e)
      ))
    }
  )
  invisible(target_file)
}
