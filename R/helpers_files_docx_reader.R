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
# dahil) sınırlanır; böylece küçük ama milyonlarca düğüm taşıyan belge DOM
# kurulmadan reddedilir. Varsayılan '<' bütçesi, Word'ün yoğun tablo XML'inde
# (~15 bayt/'<') boyut sınırından önce devreye girmez; yalnızca anormal
# yoğunluktaki belgeyi eler. Sınırlar: MERGEN_DOCX_MAX_XML_MB ve
# MERGEN_DOCX_MAX_XML_NODES.
mergen_docx_read_document_xml <- function(path, max_xml_bytes = NULL, max_elements = NULL) {
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
  }
  if (any(baytlar == as.raw(0L))) {
    stop("DOCX belge kodlaması desteklenmiyor.", call. = FALSE)
  }
  if (sum(baytlar == as.raw(0x3C)) > max_elements) {
    stop("DOCX belge yapısı izin verilen öğe sayısını aşıyor.", call. = FALSE)
  }
  # OOXML parçaları DTD taşımaz; DTD varlık zinciri metin çıkarımında büyüyebilir.
  if (length(grepRaw("<!DOCTYPE", baytlar, fixed = TRUE)) > 0L) {
    stop("DOCX belge içeriği desteklenmeyen DTD bildirimi içeriyor.", call. = FALSE)
  }

  # NONET: dış varlık/DTD ağ erişimi yok; xml2 varsayılanı varlık genişletmez.
  xml2::read_xml(baytlar, encoding = "UTF-8", options = c("NOBLANKS", "NONET"))
}
