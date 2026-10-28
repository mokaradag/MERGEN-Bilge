# ==============================================================================
# Dosya Yolu: R/helpers_files_docx_reader.R
# Açıklama: DOCX (ZIP) içindeki word/document.xml için kaynak sınırlı okuyucu.
#           Ortak dosya okuyucu (readFileContentToString) ve Bilge Yolaç belge
#           çıkarıcısı aynı sınırlı yoldan geçer; güvenilmeyen belge XML DOM
#           kurulmadan önce boyut/öğe/DTD bütçesiyle elenir.
# ==============================================================================

# DOCX içindeki word/document.xml'i SINIRLI okur. ZIP merkez dizinindeki beyan
# edilen boyut önce denetlenir; ardından açma, beyan yanlış olsa bile en fazla
# bütçe + 1 bayt üretir. Ayrıştırmadan ÖNCE '<' sayısı (kapanış etiketleri
# dahil) ve öznitelik ('=') sayısı sınırlanır; böylece küçük ama milyonlarca
# düğüm taşıyan belge DOM kurulmadan reddedilir. Varsayılan '<' bütçesi 25
# MB'ta ~13 bayt/'<' oranına denk gelir: daha yoğun (ör. kısa hücreli tablo)
# belge boyut sınırından önce öğe bütçesine takılabilir. Sınırlar:
# MERGEN_DOCX_MAX_XML_MB ve MERGEN_DOCX_MAX_XML_NODES (öğe ve öznitelik için
# ayrı ayrı); yalnız boyut sınırını yükseltmek düğüm bütçesini büyütmez.
mergen_docx_read_document_xml <- function(path, max_xml_bytes = NULL, max_elements = NULL,
                                          max_attributes_per_element = 1000L) {
  sinir <- function(ad, varsayilan) {
    deger <- suppressWarnings(as.numeric(Sys.getenv(ad, "")))
    if (length(deger) != 1L || !is.finite(deger) || deger <= 0) varsayilan else deger
  }
  max_xml_bytes <- max_xml_bytes %||% (sinir("MERGEN_DOCX_MAX_XML_MB", 25) * 1024 * 1024)
  max_elements <- max_elements %||% sinir("MERGEN_DOCX_MAX_XML_NODES", 2000000)

  liste <- tryCatch(utils::unzip(path, list = TRUE), error = function(e) NULL)
  if (!is.data.frame(liste)) stop("DOCX arşivi okunamadı.", call. = FALSE)
  giris <- liste[liste$Name == "word/document.xml", , drop = FALSE]
  if (nrow(giris) != 1L) stop("DOCX içindeki word/document.xml bulunamadı.", call. = FALSE)
  beyan <- suppressWarnings(as.numeric(giris$Length[1]))
  if (!is.finite(beyan) || beyan > max_xml_bytes) {
    stop("DOCX belge içeriği izin verilen boyutu aşıyor.", call. = FALSE)
  }

  baglanti <- unz(path, "word/document.xml", open = "rb")
  on.exit(close(baglanti), add = TRUE)
  baytlar <- readBin(baglanti, what = "raw", n = max_xml_bytes + 1)
  if (length(baytlar) > max_xml_bytes) {
    stop("DOCX belge içeriği izin verilen boyutu aşıyor.", call. = FALSE)
  }
  # UTF-16 belge (BOM ya da '<?' imzası) denetimlerden ÖNCE UTF-8'e çevrilir;
  # aksi hâlde DTD/öğe taraması UTF-16 baytlarını görmez. Çeviriden sonra kalan
  # NUL baytı UTF-8 XML'de geçersizdir (UCS-4 vb.): belge reddedilir.
  bas <- as.integer(baytlar[seq_len(min(4L, length(baytlar)))])
  utf16 <- if (identical(bas[1:2], c(255L, 254L)) || identical(bas, c(60L, 0L, 63L, 0L))) "UTF-16LE" else
    if (identical(bas[1:2], c(254L, 255L)) || identical(bas, c(0L, 60L, 0L, 63L))) "UTF-16BE" else NULL
  if (!is.null(utf16)) {
    if (bas[1] %in% c(254L, 255L)) baytlar <- baytlar[-(1:2)]
    baytlar <- iconv(list(baytlar), from = utf16, to = "UTF-8", toRaw = TRUE)[[1]]
    if (is.null(baytlar)) stop("DOCX belge kodlaması çözülemedi.", call. = FALSE)
    # UTF-8 karşılığı büyüyebilir (ör. 2 baytlık UTF-16 -> 3 baytlık UTF-8).
    if (length(baytlar) > max_xml_bytes) {
      stop("DOCX belge içeriği izin verilen boyutu aşıyor.", call. = FALSE)
    }
  }
  # Bayt taramaları yalnız eşleşme konumlarını üretir (tam boy mantıksal vektör yok).
  if (length(grepRaw(as.raw(0L), baytlar, fixed = TRUE))) {
    stop("DOCX belge kodlaması desteklenmiyor.", call. = FALSE)
  }
  acilar <- grepRaw(as.raw(0x3C), baytlar, fixed = TRUE, all = TRUE)
  if (length(acilar) > max_elements) {
    stop("DOCX belge yapısı izin verilen öğe sayısını aşıyor.", call. = FALSE)
  }
  # Öznitelik düğümleri '<' sayımına girmez. Öznitelik değeri '<' içeremez; bu
  # yüzden bir öğenin öznitelikleri kendi '<'i ile sonraki '<' arasındadır ve
  # oradaki '=' sayısı öznitelik sayısının üst sınırıdır. Toplam sınır DOM
  # büyümesini, öğe başı sınır libxml2'nin öğe başına karesel öznitelik
  # denetimini ayrıştırmadan önce keser.
  esitler <- grepRaw(as.raw(0x3D), baytlar, fixed = TRUE, all = TRUE)
  if (length(esitler) > max_elements ||
      (length(esitler) && max(tabulate(findInterval(esitler, acilar) + 1L)) > max_attributes_per_element)) {
    stop("DOCX belge yapısı izin verilen öznitelik sayısını aşıyor.", call. = FALSE)
  }
  # OOXML parçaları DTD taşımaz; DTD varlık zinciri metin çıkarımında büyüyebilir.
  if (isTRUE(mergen_docx_prolog_has_dtd(baytlar))) {
    stop("DOCX belge içeriği desteklenmeyen DTD bildirimi içeriyor.", call. = FALSE)
  }

  # NONET: dış varlık/DTD ağ erişimi yok; xml2 varsayılanı varlık genişletmez.
  # IGNORE_ENC: denetlenen UTF-8 baytları, bildirimdeki başka bir kodlamayla
  # (ör. EBCDIC) yeniden yorumlanmaz; tarama ile ayrıştırıcı aynı baytı görür.
  xml2::read_xml(baytlar, encoding = "UTF-8", options = c("NOBLANKS", "NONET", "IGNORE_ENC"))
}

# DTD yalnızca prologda (kök öğeden önce) bulunabilir. Prolog sırayla taranır:
# BOM, boşluk, <?...?> ve <!--...--> atlanır; başka her <! bildirimi DTD sayılıp
# reddedilir. Kök öğeden sonraki yorum/CDATA içindeki "<!DOCTYPE" metni DTD
# değildir. Yorum içindeki "<a" gibi metin taramayı erken bitiremez.
mergen_docx_prolog_has_dtd <- function(baytlar) {
  n <- length(baytlar)
  bul <- function(desen, bas) {
    if (bas > n) return(NA_integer_)
    k <- grepRaw(desen, baytlar, offset = bas, fixed = TRUE)
    if (length(k)) k[1] else NA_integer_
  }
  bosluk <- as.raw(c(0x20, 0x09, 0x0D, 0x0A))
  i <- if (n >= 3L && identical(as.integer(baytlar[1:3]), c(239L, 187L, 191L))) 4L else 1L
  repeat {
    while (i <= n && baytlar[i] %in% bosluk) i <- i + 1L
    if (i + 1L > n || baytlar[i] != as.raw(0x3C)) return(FALSE)
    if (baytlar[i + 1L] == as.raw(0x3F)) {
      k <- bul(charToRaw("?>"), i + 2L)
      if (is.na(k)) return(FALSE)
      i <- k + 2L
    } else if (baytlar[i + 1L] == as.raw(0x21)) {
      if (i + 3L > n || !identical(baytlar[(i + 2L):(i + 3L)], charToRaw("--"))) return(TRUE)
      k <- bul(charToRaw("-->"), i + 4L)
      if (is.na(k)) return(FALSE)
      i <- k + 3L
    } else {
      return(FALSE)
    }
  }
}
