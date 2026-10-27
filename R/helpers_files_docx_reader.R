# ==============================================================================
# Dosya Yolu: R/helpers_files_docx_reader.R
# Açıklama: DOCX (ZIP) içindeki word/document.xml için kaynak sınırlı okuyucu.
#           Ortak dosya okuyucu (readFileContentToString) ve Bilge Yolaç belge
#           çıkarıcısı aynı sınırlı yoldan geçer; güvenilmeyen belge XML DOM
#           kurulmadan önce boyut/öğe/DTD bütçesiyle elenir.
# ==============================================================================

# DOCX içindeki word/document.xml'i SINIRLI okur. ZIP merkez dizinindeki beyan
# edilen boyut önce denetlenir; ardından açma, beyan yanlış olsa bile en fazla
# bütçe + 1 bayt üretir. Ayrıştırmadan ÖNCE öğe sayısı (yaklaşık '<' sayısı)
# sınırlanır; böylece küçük ama milyonlarca düğüm taşıyan belge DOM kurulmadan
# reddedilir. Sınırlar: MERGEN_DOCX_MAX_XML_MB ve MERGEN_DOCX_MAX_XML_NODES.
mergen_docx_read_document_xml <- function(path, max_xml_bytes = NULL, max_elements = NULL) {
  sinir <- function(ad, varsayilan) {
    deger <- suppressWarnings(as.numeric(Sys.getenv(ad, "")))
    if (length(deger) != 1L || !is.finite(deger) || deger <= 0) varsayilan else deger
  }
  max_xml_bytes <- max_xml_bytes %||% (sinir("MERGEN_DOCX_MAX_XML_MB", 25) * 1024 * 1024)
  max_elements <- max_elements %||% sinir("MERGEN_DOCX_MAX_XML_NODES", 750000)

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
  if (sum(baytlar == as.raw(0x3C)) > max_elements) {
    stop("DOCX belge yapısı izin verilen öğe sayısını aşıyor.", call. = FALSE)
  }
  # OOXML parçaları DTD taşımaz; DTD varlık zinciri metin çıkarımında büyüyebilir.
  if (length(grepRaw("<!DOCTYPE", baytlar, fixed = TRUE)) > 0L) {
    stop("DOCX belge içeriği desteklenmeyen DTD bildirimi içeriyor.", call. = FALSE)
  }

  # NONET: dış varlık/DTD ağ erişimi yok; xml2 varsayılanı varlık genişletmez.
  xml2::read_xml(baytlar, options = c("NOBLANKS", "NONET"))
}
