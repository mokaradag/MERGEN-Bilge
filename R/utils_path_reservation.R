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
#   * Devralma YAŞA DEĞİL sahiplik kanıtına dayanır: bayat olarak GÖZLENEN
#     jeton hâlâ yerinde olmalıdır. Yalnızca yaşa bakan devralma, yavaş bir UNC
#     paylaşımında CANLI sahibin rezervasyonunu kırıp iki çağrının aynı hedefi
#     terfi ettirmesine izin veriyordu.
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

# Bayat rezervasyon eşiği (saniye). Uzun süren terfi adımları (UNC üzerinde
# `file.rename`/`file.copy`) bu süreyi meşru olarak aşabilir; bu yüzden canlı
# sahip `mergen_reservation_touch()` ile kirasını tazeleyebilir.
.MERGEN_RESERVATION_STALE_SEC <- 60

# Süreç kimliği + benzersiz geçici ad: aynı makinede iki çağrı aynı jetonu
# üretemez.
mergen_reservation_token <- function(onek = "mrsv") {
  paste0(Sys.getpid(), "-", basename(tempfile(onek)))
}

.mergen_reservation_marker <- function(rezerv) {
  file.path(rezerv, "owner")
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
    bilgi <- try(file.info(yol), silent = TRUE)
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

  alindi <- isTRUE(try(dir.create(rezerv, showWarnings = FALSE), silent = TRUE))
  if (!alindi) return(FALSE)

  yazildi <- try(
    writeLines(jeton, .mergen_reservation_marker(rezerv), useBytes = TRUE),
    silent = TRUE
  )
  if (inherits(yazildi, "try-error") ||
      !identical(mergen_reservation_owner(rezerv), jeton)) {
    unlink(rezerv, recursive = TRUE, force = TRUE)
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
  yazildi <- try(writeLines(jeton, yol, useBytes = TRUE), silent = TRUE)
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
  karantina <- paste0(rezerv, ".q-", basename(tempfile("q")))
  tasindi <- isTRUE(tryCatch(file.rename(rezerv, karantina), error = function(e) FALSE))
  if (!tasindi) return(FALSE)

  if (!identical(mergen_reservation_owner(karantina), jeton)) {
    # Yakalanan örnek BAŞKASINA ait: silinmez, yerine geri konur. Geri koyma
    # başarısız olursa karantina DİSKTE BIRAKILIR (silmek yeni sahibin canlı
    # rezervasyonunu yok ederdi); özgün yol serbesttir ve bayat temizlik
    # karantinayı sonradan toplar.
    geri <- isTRUE(tryCatch(file.rename(karantina, rezerv), error = function(e) FALSE))
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

  sonuc <- tryCatch(unlink(karantina, recursive = TRUE, force = TRUE),
                    error = function(e) 1L)
  identical(as.integer(sonuc)[1], 0L) && !isTRUE(dir.exists(karantina))
}

# Bayat rezervasyonu devralır. Çökmüş bir çalıştırmadan kalan rezervasyon kalıcı
# kilitlenme üretmemelidir; ancak CANLI sahip kirasını tazelediyse veya jeton
# devralma penceresinde değiştiyse devralma YAPILMAZ.
mergen_reservation_takeover <- function(rezerv, jeton,
                                        stale_sec = .MERGEN_RESERVATION_STALE_SEC) {
  gozlenen <- mergen_reservation_owner(rezerv)
  # OKUNAMAYAN marker sahiplik KANITI DEĞİLDİR: iki başarısız okuma da
  # `NA_character_` döner ve `identical(NA, NA)` TRUE olur. Geçici bir UNC
  # okuma hatası, CANLI bir rezervasyonun devralınmasına izin veriyordu.
  if (length(gozlenen) != 1L || is.na(gozlenen) || !nzchar(gozlenen)) return(FALSE)

  yas <- mergen_reservation_age_sec(rezerv)
  if (!is.finite(yas) || yas <= stale_sec) return(FALSE)

  # GÖZLENEN jeton hâlâ yerinde olmalı ve yaş YENİDEN doğrulanmalıdır.
  if (!identical(mergen_reservation_owner(rezerv), gozlenen)) return(FALSE)
  yas <- mergen_reservation_age_sec(rezerv)
  if (!is.finite(yas) || yas <= stale_sec) return(FALSE)

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
