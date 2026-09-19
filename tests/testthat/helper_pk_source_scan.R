# ==============================================================================
# Dosya Yolu: tests/testthat/helper_pk_source_scan.R
# Açıklama: PK kaynak taramaları için SATIR İÇİ YORUMA DUYARSIZ okuyucu.
#
#           Olumsuz kaynak iddiaları ("şu çağrı ARTIK yok") yorum satırlarını da
#           içeren ham metinde çalıştığında, yasaklı ifadeyi ALINTILAYAN
#           açıklayıcı bir yorum üretimde hiçbir gerileme olmadan testi
#           KIRARDI. Eski kod-yalnız yardımcıları yalnızca TAM SATIR yorumlarını
#           atıyordu; PK kaynakları ise `kod  # açıklama` biçimini yoğun
#           kullanır, dolayısıyla satır içi yorumlar taranan metinde KALIYORDU
#           (PR #719 inceleme, P3).
#
#           Ayrıştırıcı tabanlı yaklaşım seçildi: `getParseData()` yorumları
#           TAM konumlarıyla bildirir, dize içindeki `#` karakterini yorum
#           SAYMAZ ve çok baytlı Türkçe metinde karakter konumları doğrudur.
#           Ayrıştırma başarısız olursa eski tam-satır davranışına düşülür;
#           böylece tarama hiçbir durumda SESSİZCE boşalmaz.
# ==============================================================================

#' R kaynağındaki TÜM yorumları (satır içi dâhil) at, dizeleri KORU
pk_test_strip_r_comments <- function(metin) {
  duz <- gsub("\r\n?", "\n", as.character(metin %||% "")[1])
  if (!nzchar(duz)) return("")

  satirlar <- strsplit(duz, "\n", fixed = TRUE)[[1]]

  ifade <- tryCatch(parse(text = duz, keep.source = TRUE), error = function(e) NULL)
  pd <- if (is.null(ifade)) NULL else {
    tryCatch(utils::getParseData(ifade), error = function(e) NULL)
  }

  if (!is.data.frame(pd) || !nrow(pd)) {
    # AYRIŞTIRILAMAYAN metinde eski (tam satır) davranış korunur.
    return(paste(satirlar[!grepl("^\\s*#", satirlar, perl = TRUE)], collapse = "\n"))
  }

  yorumlar <- pd[pd$token == "COMMENT", , drop = FALSE]
  for (i in seq_len(nrow(yorumlar))) {
    satir <- yorumlar$line1[i]
    if (is.na(satir) || satir < 1L || satir > length(satirlar)) next

    ham <- satirlar[satir]
    metin <- as.character(yorumlar$text[i])[1]
    kes <- NA_integer_

    # SÜTUN İNDEKSİ DOĞRULANIR, KÖRÜ KÖRÜNE KULLANILMAZ.
    #
    # `getParseData()` sütunlarının KARAKTER mi BAYT mı sayıldığı platform ve
    # R sürümüne göre değişebilir. Çok baytlı Türkçe metin yorumdan ÖNCE
    # geldiğinde bayt tabanlı bir indeks `substr()` ile birlikte satırı ERKEN
    # keser ve KOD KAYBOLUR; olumlu kaynak iddiaları Windows'ta sessizce
    # düşerdi. Bu yüzden aday indeks önce DOĞRULANIR.
    sutun <- yorumlar$col1[i]
    if (!is.na(sutun) && sutun >= 1L && sutun <= nchar(ham) &&
        startsWith(substring(ham, sutun), metin)) {
      kes <- sutun
    } else if (nzchar(metin)) {
      # Yedek: yorum metninin SON geçtiği yer (yorum satır sonuna kadar sürer,
      # dolayısıyla daha erken bir eşleşme bir dizenin içindedir).
      konumlar <- gregexpr(metin, ham, fixed = TRUE)[[1]]
      if (!identical(konumlar[1], -1L)) kes <- konumlar[length(konumlar)]
    }

    # Konum DOĞRULANAMADIYSA satıra DOKUNULMAZ: eksik kırpmak, kodu yanlışlıkla
    # silmekten her zaman daha güvenlidir.
    if (is.na(kes)) next
    satirlar[satir] <- if (kes <= 1L) "" else substr(ham, 1L, kes - 1L)
  }
  paste(satirlar, collapse = "\n")
}

#' Bir repo dosyasını bayt güvenli oku ve yorumlarından arındır
#'
#' Windows VM'de bazı kaynaklar geçersiz UTF-8 dizisi taşıyabildiği için okuma
#' `readBin()` + `iconv(sub = "byte")` kalıbını korur (depo sözleşmesi).
pk_test_code_only_file <- function(rel_path) {
  kok <- resolve_repo_root_for_tests()
  yol <- file.path(kok, rel_path)
  ham <- readBin(yol, "raw", file.info(yol)$size)
  pk_test_strip_r_comments(iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8",
                                 sub = "byte"))
}
