# ==============================================================================
# Dosya Yolu: R/helpers_citations.R
# Açıklama:  YZ yanıtlarındaki "Kaynakça:" bölümünü ve satır içi alıntıları
#             tıklanabilir kaynak bağlantılarına dönüştüren yardımcı fonksiyonlar.
#             parse_kaynakca_section(), render_citation_section_html() ve
#             add_inline_citation_links() fonksiyonlarını içerir.
#             global.R tarafından helpers_messaging.R'den sonra source() ile yüklenir.
# ==============================================================================

# --- KAYNAKÇA BÖLÜMÜNÜ AYIRMA ---
# YZ yanıtının sonundaki "Kaynakça:" bölümünü algılar ve dosya listesini döndürür.
# Desteklenen formatlar:
#   Kaynakça:          (büyük/küçük harf, boşlukla)
#   1) dosya.pdf
#   2) başka_dosya.docx
# Döndürür: list(text_before = "...", files = c("dosya.pdf", "dosya.docx"))
parse_kaynakca_section <- function(content) {
  if (!is.character(content) || !nzchar(content)) {
    return(list(text_before = content, files = character(0)))
  }

  # "Kaynakça:" veya "Kaynakca:" ile başlayan son bölümü bul (büyük/küçük harf duyarsız)
  kaynakca_pattern <- "(?i)[\n\r]*(kaynakça|kaynakca|kaynaklar|sources?|references?)\\s*:?\\s*[\n\r]+"
  m <- regexpr(kaynakca_pattern, content, perl = TRUE)

  if (m == -1) {
    return(list(text_before = content, files = character(0)))
  }

  # Kaynakça başlığından önceki metin
  text_before <- trimws(substr(content, 1, m - 1))

  # Kaynakça bölümü metni (başlıktan sonra)
  match_end <- m + attr(m, "match.length")
  section_text <- substr(content, match_end, nchar(content))

  # Her satırdan dosya adını çıkar: "1) dosya.pdf", "- dosya.pdf", "* dosya.pdf", "dosya.pdf"
  lines <- strsplit(section_text, "[\n\r]+")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  # Boş veya başlık satırlarını filtrele
  files <- character(0)
  for (line in lines) {
    # "N)" veya "-" veya "*" ile başlayan satırları işle
    cleaned <- sub("^\\s*\\d+[.)\\)]\\s*", "", line)   # "1) " veya "1. " kaldır
    cleaned <- sub("^\\s*[-*]\\s*", "", cleaned)        # "- " veya "* " kaldır
    cleaned <- trimws(cleaned)

    # Geçerli dosya adı mı? (en az 3 karakter ve uzantı var veya dosya gibi görünüyor)
    if (nchar(cleaned) >= 2 && !grepl("^(kaynakça|kaynakca|sources?|references?)\\s*:?$", cleaned, ignore.case = TRUE)) {
      files <- c(files, cleaned)
    }
  }

  list(text_before = text_before, files = files)
}

# --- SATIR İÇİ ALINTILAR ---
# Metin içindeki [1], [2], [3] gibi referans numaralarını tıklanabilir
# üst simge bağlantılarına dönüştürür.
# "files" parametresi: parse_kaynakca_section()$files
add_inline_citation_links <- function(text, files) {
  if (length(files) == 0 || !nzchar(text)) return(text)

  # [1], [2] gibi referansları <sup class="inline-citation"> ile değiştir
  # Sadece geçerli indeks aralığında olanları değiştir
  n <- length(files)
  pattern <- paste0("\\[(", paste(1:n, collapse = "|"), ")\\]")

  gsub(
    pattern,
    '<sup class="inline-citation"><a class="citation-index-btn" data-citation-num="\\1">[\\1]</a></sup>',
    text,
    perl = TRUE
  )
}

# --- KAYNAKÇA HTML OLUŞTURMA ---
# Dosya listesini stilize edilmiş ve tıklanabilir HTML kaynakça bölümüne dönüştürür.
# Her dosya ".source-link" sınıfını kullanır; mevcut interaction_handlers.js
# bu sınıfa tıklanınca Shiny'e source_file_clicked gönderir.
render_citation_section_html <- function(files) {
  if (length(files) == 0) return("")

  # Her dosya için liste öğesi HTML'i oluştur
  items_html <- paste(
    mapply(function(fname, idx) {
      # Uzantıya göre ikon seç
      ext <- tolower(tools::file_ext(fname))
      icon_class <- switch(ext,
        pdf  = "fas fa-file-pdf",
        docx = "fas fa-file-word",
        doc  = "fas fa-file-word",
        xlsx = "fas fa-file-excel",
        xls  = "fas fa-file-excel",
        txt  = "fas fa-file-alt",
        csv  = "fas fa-table",
        "fas fa-file"
      )

      sprintf(
        '<li class="citation-source-item">
           <a class="source-link citation-file-link"
              data-filename="%s"
              data-source-id="citation_%d"
              title="%s"
              href="#">
             <i class="%s citation-file-icon"></i>
             <span class="citation-file-name">%s</span>
           </a>
         </li>',
        htmltools::htmlEscape(fname, attribute = TRUE),  # data-filename
        idx,                                              # data-source-id
        htmltools::htmlEscape(fname, attribute = TRUE),  # title
        icon_class,                                       # ikon CSS sınıfı
        htmltools::htmlEscape(fname)                      # görünen ad
      )
    },
    files, seq_along(files),
    SIMPLIFY = TRUE
    ),
    collapse = "\n"
  )

  # Tam kaynakça kutusu HTML
  sprintf(
    '<div class="citation-sources-box">
       <div class="citation-sources-header">
         <i class="fas fa-book-open citation-sources-icon"></i>
         <span>Kaynakça</span>
       </div>
       <ul class="citation-sources-list">
         %s
       </ul>
     </div>',
    items_html
  )
}

# --- ANA FONKSİYON: ALINTI İŞLEME ---
# YZ yanıt metnini alır; "Kaynakça:" bölümünü ayrıştırır, satır içi
# [N] referanslarını tıklanabilir yapar ve zengin HTML üretir.
# Döndürür: list(content = "değiştirilmiş_metin", citation_html = "kaynakça_html")
process_citations <- function(content) {
  if (!is.character(content) || !nzchar(content)) {
    return(list(content = content, citation_html = ""))
  }

  # Kaynakça bölümünü ayır
  parsed <- parse_kaynakca_section(content)

  if (length(parsed$files) == 0) {
    # Kaynakça yoksa içeriği olduğu gibi döndür
    return(list(content = content, citation_html = ""))
  }

  # Satır içi [1], [2] referanslarını tıklanabilir yap
  text_with_links <- add_inline_citation_links(parsed$text_before, parsed$files)

  # Kaynakça HTML bölümü oluştur
  citation_html <- render_citation_section_html(parsed$files)

  list(content = text_with_links, citation_html = citation_html)
}