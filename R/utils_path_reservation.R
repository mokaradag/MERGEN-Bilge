# ==============================================================================
# Dosya Yolu: R/utils_path_reservation.R
# Açıklama: Bir dosya yolunu EŞZAMANLI süreçlere karşı atomik biçimde
#           rezerve etmenin ortak primitifleri. `tempfile()` adı süreçler
#           arasında REZERVE ETMEZ ve `!file.exists(hedef)` + `file.rename()`
#           ikilisi ayrı işlemlerdir; iki çağrı aynı yolu seçtiğinde POSIX
#           `file.rename()` diğerinin dosyasını sessizce değiştirir.
#
# SÖZLEŞME (R/helpers_claude_code_codex_runtime_lock.R ile aynı model):
#   * Rezervasyon YALNIZCA `dir.create()` ile alınır (atomik, üzerine-yazmaz).
#   * DAYANIKLI sahiplik jetonu rezervasyonu TUTMANIN ön koşuludur; geri
#     okunamazsa rezervasyon hemen bırakılır ve çağıran FALSE görür.
#   * Devralma önce sahiplik kanıtına dayanır: canlı yerel sahip asla
#     devralınmaz; yaş yalnız doğrulanamayan (eski biçim/uzak host) sahip için
#     sınırlı kurtarmadır. Bayat olarak GÖZLENEN jeton hâlâ yerinde olmalıdır.
#   * Bırakma da sahiplik kanıtı ister: jeton artık bizim değilse rezervasyon
#     KALDIRILMAZ (aksi hâlde yeni sahibin rezervasyonu silinir).
#   * Kaldırma YOL ADINA GÖRE yapılmaz. Rezervasyon önce ATOMİK
#     `file.rename()` ile benzersiz bir karantinaya taşınır, jeton TAŞINAN
#     örnekte yeniden doğrulanır ve yalnızca doğrulanan örnek silinir; başkasına
#     ait örnek yerine GERİ KONUR. Yol adına göre doğrudan `unlink()`,
#     denetimden sonra beliren YENİ sahibin rezervasyonunu siliyordu.
#   * Bırakma sonucu KALDIRMANIN GERÇEKLEŞTİĞİNİ bildirir; `unlink()` başarısız
#     olduğunda `TRUE` dönmek çağıranı yanıltıyordu.
#
# BİLİNEN ARTIK RİSK (izleniyor, kapatılmadı): base R dosya sistemi için atomik
# karşılaştır-ve-değiştir sunmaz. Karantina taşıması, yanlış örneğin SİLİNMESİNİ
# önler (yakalanan örnek doğrulanır, gerekirse geri konur) ancak yakalama ile
# yeniden edinme arasındaki pencereyi tümüyle kapatmaz; bu,
# `atomic_write_text()` dayanıklılık sınırıyla aynı sınıftadır ve derlenmiş bir
# bağımlılık olmadan kapatılamaz. Yaşa dayalı devralma da kendi başına terk
# kanıtı DEĞİLDİR: uzun bloklayan terfi adımları için tüketici
# `mergen_reservation_touch()` ile CANLI kira tazeler.
# Bu dosya Shiny, reactive state, DB veya ağ bağımlılığı İÇERMEZ.
# ==============================================================================

# İzole `source()` edildiğinde (worker, odaklı test, hata ayıklama) `%||%`
# `utils_common.R` ile gelmeyebilir; üç rezervasyon fonksiyonu çağrı anında
# "bulunamadı" hatası veriyor ve hata kopyalama akışına yayılıyordu.
if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(a, b) if (is.null(a)) b else a
}

# Mantıksal yol/kimlik değişmez; yalnız Windows I/O çağrısı uzun yol biçimini alır.
# Açık Win32 öneki kayıt defteri ayarı istemez; ayraçları ters eğik olmalıdır.
mergen_logical_path <- function(path) {
  if (.Platform$OS.type != "windows" || !length(path)) return(path)
  path <- chartr("\\", "/", as.character(path))
  path <- sub("^//[?]/UNC/", "//", path, ignore.case = TRUE)
  sub("^//[?]/(?=[A-Za-z]:/)", "", path, perl = TRUE)
}

mergen_io_path <- function(path) {
  if (.Platform$OS.type != "windows" || !length(path)) return(path)
  result <- as.character(path)
  for (i in seq_along(result)) {
    p <- result[i]
    if (is.na(p) || !nzchar(p)) next
    slash <- chartr("\\", "/", p)
    if (startsWith(slash, "//?/")) {
      result[i] <- chartr("/", "\\", slash)
      next
    }
    if (startsWith(slash, "//./")) next
    absolute <- as.character(fs::path_abs(fs::path_expand(p)))
    if (!grepl("^[A-Za-z]:/|^//[^/]+/[^/]+", absolute)) next
    units <- length(iconv(enc2utf8(absolute), "UTF-8", "UTF-16LE", toRaw = TRUE)[[1]]) / 2
    # Dizin oluşturma, dosya açmadan daha dar bir olağan yol bütçesine sahiptir.
    if (units <= 247L) next
    extended <- if (startsWith(absolute, "//")) paste0("//?/UNC/", substring(absolute, 3L)) else
      paste0("//?/", absolute)
    result[i] <- chartr("/", "\\", extended)
  }
  result
}

# Bayat rezervasyon eşiği (saniye). Uzun süren terfi adımları (UNC üzerinde
# `file.rename`/`file.copy`) bu süreyi meşru olarak aşabilir; bu yüzden canlı
# sahip `mergen_reservation_touch()` ile kirasını tazeleyebilir.
.MERGEN_RESERVATION_STALE_SEC <- 60

# Bütçe ve gerçek karantina aynı sabit genişlikli biçimi kullanır.
mergen_reservation_quarantine_path <- function(rezerv, unique = TRUE) {
  key <- if (unique) digest::digest(tempfile("q"), algo = "xxhash64", serialize = FALSE) else strrep("0", 16L)
  units <- function(x) {
    if (.Platform$OS.type == "windows") length(iconv(enc2utf8(x), "UTF-8", "UTF-16LE", toRaw = TRUE)[[1]]) / 2 else
      nchar(x, type = "bytes")
  }
  original <- paste0(rezerv, ".q-q", key)
  compact <- file.path(dirname(rezerv), paste0(".mergen-rsv.q-q", key))
  overflow <- units(basename(original)) > 255L ||
    (.Platform$OS.type == "windows" && units(file.path(original, "owner")) > 259L)
  if (overflow && units(compact) < units(original)) compact else original
}

# Süreç kimliği + benzersiz geçici ad: aynı makinede iki çağrı aynı jetonu
# üretemez.
mergen_reservation_token <- function(onek = "mrsv") {
  paste0(Sys.getpid(), "-", basename(tempfile(onek)))
}

.mergen_reservation_marker <- function(rezerv) {
  mergen_io_path(file.path(rezerv, "owner"))
}

# Rezervasyon dizinindeki sahiplik jetonu (okunamazsa NA_character_). Bırakma ve
# devralma kararlarının tek kanıtı budur.
mergen_reservation_owner <- function(rezerv) {
  yol <- .mergen_reservation_marker(rezerv)
  # `try(..., silent = TRUE)` yalnızca HATAYI bastırır; eksik dosyada bağlantı
  # açma UYARISI sızar ve katı test koşucusunu düşürür.
  if (!isTRUE(file.exists(yol))) return(NA_character_)
  satir <- suppressWarnings(try(readLines(yol, warn = FALSE), silent = TRUE))
  if (inherits(satir, "try-error") || !length(satir)) return(NA_character_)
  as.character(satir[1])
}

# Rezervasyon yaşı: SAHİP marker'ı tazelendiği için önce onun mtime'ı kullanılır;
# marker okunamazsa dizin mtime'ına düşülür.
mergen_reservation_age_sec <- function(rezerv) {
  for (yol in c(.mergen_reservation_marker(rezerv), rezerv)) {
    bilgi <- try(file.info(mergen_io_path(yol)), silent = TRUE)
    if (!inherits(bilgi, "try-error") && NROW(bilgi) && !is.na(bilgi$mtime[1])) {
      return(as.numeric(difftime(Sys.time(), bilgi$mtime[1], units = "secs")))
    }
  }
  NA_real_
}

# Rezervasyonu alır. Dayanıklı marker yazılıp GERİ OKUNAMAZSA rezervasyon
# bırakılır: sahiplik kanıtlanamadan kritik bölüme girilmemelidir.
mergen_reservation_acquire <- function(rezerv, jeton) {
  jeton <- as.character(jeton %||% "")[1]
  if (is.na(jeton) || !nzchar(jeton)) return(FALSE)

  alindi <- isTRUE(try(dir.create(mergen_io_path(rezerv), showWarnings = FALSE), silent = TRUE))
  if (!alindi) return(FALSE)

  yazildi <- try(
    writeLines(c(jeton, paste0("host=", Sys.info()[["nodename"]])), .mergen_reservation_marker(rezerv), useBytes = TRUE),
    silent = TRUE
  )
  if (inherits(yazildi, "try-error") ||
      !identical(mergen_reservation_owner(rezerv), jeton)) {
    unlink(mergen_io_path(rezerv), recursive = TRUE, force = TRUE, expand = FALSE)
    return(FALSE)
  }
  TRUE
}

# CANLI SAHİPLİK KİRASI: uzun terfi adımlarında marker tazelenir.
# `Sys.setFileTime()` bazı UNC paylaşımlarında sessizce FALSE döner; bu durumda
# marker aynı jetonla YENİDEN YAZILIR (yazma mtime'ı yan etki olarak günceller)
# ve jeton geri okunarak doğrulanır.
mergen_reservation_touch <- function(rezerv, jeton) {
  jeton <- as.character(jeton %||% "")[1]
  if (is.na(jeton) || !nzchar(jeton)) return(invisible(FALSE))
  if (!identical(mergen_reservation_owner(rezerv), jeton)) return(invisible(FALSE))

  yol <- .mergen_reservation_marker(rezerv)
  sonuc <- try(Sys.setFileTime(yol, Sys.time()), silent = TRUE)
  if (!inherits(sonuc, "try-error") && isTRUE(sonuc)) {
    # Sahiplik TAZELEMEDEN SONRA da doğrulanır: denetim ile `Sys.setFileTime()`
    # ayrı işlemlerdir ve bu aralıkta bir devralma rezervasyonu değiştirmiş
    # olabilir. Doğrulamasız `TRUE`, ESKİ sahibin YENİ sahibin marker'ını
    # tazeleyip kritik bölümde kalmasına izin veriyordu.
    return(invisible(identical(mergen_reservation_owner(rezerv), jeton)))
  }

  # Yedek yol PAYLAŞILAN marker'ı yeniden yazar; bu yüzden yazımdan HEMEN ÖNCE
  # sahiplik yeniden okunur ve yalnızca hâlâ bizse yazılır (başka sahibin
  # jetonunu ezmemek için), yazımdan SONRA da yeniden doğrulanır.
  if (!identical(mergen_reservation_owner(rezerv), jeton)) return(invisible(FALSE))
  yazildi <- try(writeLines(c(jeton, paste0("host=", Sys.info()[["nodename"]])), yol, useBytes = TRUE), silent = TRUE)
  if (inherits(yazildi, "try-error")) return(invisible(FALSE))
  invisible(identical(mergen_reservation_owner(rezerv), jeton))
}

# SAHİPLİK BAĞLI KALDIRMA. Yol adına göre doğrudan `unlink()` etmek DENETLE-SİL
# yarışıdır: denetimden sonra başka bir süreç rezervasyonu değiştirebilir ve
# onun CANLI rezervasyonu siliniyordu. Dizin önce ATOMİK `file.rename()` ile
# benzersiz bir karantina adına taşınır; jeton TAŞINAN örnekte yeniden
# doğrulanır ve yalnızca doğrulanan örnek silinir. Yakalanan örnek bizim
# değilse yerine GERİ KONUR.
.mergen_reservation_remove_owned <- function(rezerv, jeton) {
  if (!is.character(jeton) || length(jeton) != 1L || is.na(jeton) || !nzchar(jeton)) return(FALSE)
  karantina <- mergen_reservation_quarantine_path(rezerv)
  tasindi <- isTRUE(tryCatch(file.rename(mergen_io_path(rezerv), mergen_io_path(karantina)), error = function(e) FALSE))
  if (!tasindi) return(FALSE)

  if (!identical(mergen_reservation_owner(karantina), jeton)) {
    # Yakalanan örnek BAŞKASINA ait: silinmez, yerine geri konur. Geri koyma
    # başarısız olursa karantina DİSKTE BIRAKILIR (silmek yeni sahibin canlı
    # rezervasyonunu yok ederdi); özgün yol serbesttir, belirsiz örnek
    # otomatik silinmez.
    geri <- isTRUE(tryCatch(file.rename(mergen_io_path(karantina), mergen_io_path(rezerv)), error = function(e) FALSE))
    if (!geri) {
      try(
        warning(sprintf(
          "mergen_reservation: yabancı rezervasyon geri konulamadı: %s", karantina
        ), call. = FALSE),
        silent = TRUE
      )
    }
    return(FALSE)
  }

  sonuc <- tryCatch(unlink(mergen_io_path(karantina), recursive = TRUE, force = TRUE, expand = FALSE),
                    error = function(e) 1L)
  identical(as.integer(sonuc)[1], 0L) && !isTRUE(dir.exists(mergen_io_path(karantina)))
}

# Bayat rezervasyonu devralır. Çökmüş bir çalıştırmadan kalan rezervasyon kalıcı
# kilitlenme üretmemelidir; ancak CANLI sahip korunur ve jeton devralma
# penceresinde değiştiyse devralma YAPILMAZ. Karar ortak sahip kuralıdır:
# kanıtlı ölü sahip hemen, eski biçim (host satırsız) ya da uzak host yalnız
# `stale_sec` aşılınca. Muteks dosyası kalıcıdır (indeks/Yolaç kilitleriyle aynı):
# kilit bırakılıp yol silinirse bekleyen ve yeni gelen süreç farklı dosyaları
# kilitleyip kritik bölüme birlikte girebilirdi.
mergen_reservation_takeover <- function(rezerv, jeton,
                                        stale_sec = .MERGEN_RESERVATION_STALE_SEC,
                                        before_remove = NULL) {
  jeton <- as.character(jeton %||% "")[1]
  if (is.na(jeton) || !nzchar(jeton)) return(FALSE)
  gozlenen <- mergen_reservation_owner(rezerv)
  # OKUNAMAYAN marker sahiplik KANITI DEĞİLDİR: iki başarısız okuma da
  # `NA_character_` döner ve `identical(NA, NA)` TRUE olur. Geçici bir UNC
  # okuma hatası, CANLI bir rezervasyonun devralınmasına izin veriyordu.
  if (length(gozlenen) != 1L || is.na(gozlenen) || !nzchar(gozlenen)) return(FALSE)
  if (!exists("mergen_reclaim_mutex", mode = "function") ||
      !exists("mergen_lock_owner_reclaimable", mode = "function")) return(FALSE)
  # Canlı sahip için dizin muteksi beklenmez; karar kilit altında yinelenir.
  if (!mergen_lock_owner_reclaimable(.mergen_reservation_marker(rezerv), gozlenen,
      stale_sec = stale_sec, age_paths = c(.mergen_reservation_marker(rezerv), rezerv))) return(FALSE)

  guard_yolu <- file.path(dirname(rezerv), ".mergen-rsv.reclaim")
  guard <- mergen_reclaim_mutex(guard_yolu, timeout = 2000)
  if (is.null(guard)) return(FALSE)
  on.exit(filelock::unlock(guard), add = TRUE)
  if (!identical(mergen_reservation_owner(rezerv), gozlenen) ||
      !mergen_lock_owner_reclaimable(.mergen_reservation_marker(rezerv), gozlenen,
                                     stale_sec = stale_sec,
                                     age_paths = c(.mergen_reservation_marker(rezerv), rezerv))) return(FALSE)
  if (is.function(before_remove) && !isTRUE(before_remove(gozlenen))) return(FALSE)

  # Silme, GÖZLENEN örneğe bağlıdır: karantina taşımasından sonra jeton hâlâ
  # `gozlenen` değilse rezervasyon bu aralıkta değişmiştir ve devralınmaz.
  if (!.mergen_reservation_remove_owned(rezerv, gozlenen)) return(FALSE)
  mergen_reservation_acquire(rezerv, jeton)
}

# Rezervasyon YALNIZCA hâlâ bizim jetonumuzu taşıyorsa kaldırılır. Sonuç
# KALDIRMANIN GERÇEKLEŞTİĞİNİ bildirir: `unlink()` Windows kilidi/izin
# hatasında sıfırdan farklı döner ve çağıran rezervasyonu bırakılmış sanıp
# sonraki yazımların engellendiğini fark etmiyordu.
mergen_reservation_release <- function(rezerv, jeton) {
  jeton <- as.character(jeton %||% "")[1]
  if (is.na(jeton) || !nzchar(jeton)) return(invisible(FALSE))
  if (!identical(mergen_reservation_owner(rezerv), jeton)) return(invisible(FALSE))
  invisible(.mergen_reservation_remove_owned(rezerv, jeton))
}
