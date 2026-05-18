# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_downloads_html.R
# Açıklama: Bilge Yolaç indirme kartlarının HTML sunum katmanı. Görünen yol
#           hesaplama, indirme kartı HTML üretme ve mevcut dosyaya doğrudan
#           link üretme bu dosyada toplanır. Asıl dosya staging/kopyalama
#           mantığı R/helpers_claude_code_downloads.R dosyasındadır.
#
#           Dosya bölünmesinin nedeni: tıklanabilir indirme kartı ve mevcut
#           dosya doğrudan link helper'ları downloads.R'yi 25 fonksiyona
#           çıkarmıştı; HTML sunum katmanını ayırarak maintainability ratchet
#           taban çizgisini koruyacak şekilde her iki dosyayı da 25+ eşiğinin
#           altına indiriyoruz.
# ==============================================================================

#' Üretilen dosyanın kullanıcı dostu görünen yolunu hesaplar
#'
#' @param file_path Dosya yolu
#' @param runtime_workdir Claude Code runtime dizini
#' @param source_workdir Kullanıcının seçtiği/asıl kaynak dizin
#' @return Gösterim yolu
build_claude_code_display_path <- function(file_path,
                                           runtime_workdir = "",
                                           source_workdir = "") {
  hedef <- tryCatch(
    normalize_mcp_path(file_path, must_exist = FALSE),
    error = function(e) normalizePath(file_path, winslash = "/", mustWork = FALSE)
  )

  bazlar <- unique(Filter(nzchar, c(source_workdir, runtime_workdir)))

  for (baz in bazlar) {
    baz_norm <- tryCatch(
      normalize_mcp_path(baz, must_exist = FALSE),
      error = function(e) normalizePath(baz, winslash = "/", mustWork = FALSE)
    )

    rel <- tryCatch(
      gsub("\\\\", "/", fs::path_rel(hedef, start = baz_norm), fixed = TRUE),
      error = function(e) ""
    )

    if (nzchar(rel) && !startsWith(rel, "../")) {
      return(rel)
    }
  }

  basename(hedef)
}

#' İndirilebilir dosyaları AI cevabının sonuna eklenecek HTML'e dönüştürür
#'
#' @param downloads İndirme kayıtları listesi
#' @return HTML metni
format_claude_code_generated_downloads_html <- function(downloads) {
  if (!length(downloads)) return("")

  kartlar <- vapply(downloads, function(dosya) {
    alt_metin <- paste(
      c(dosya$display_path %||% "", dosya$size_label %||% ""),
      collapse = " • "
    )
    alt_metin <- gsub("^ • | • $", "", alt_metin)

    paste0(
      '<a class="cc-generated-file-card" href="',
      htmltools::htmlEscape(dosya$url %||% ""),
      '" download="',
      htmltools::htmlEscape(dosya$download_name %||% dosya$display_name %||% "dosya"),
      '" target="_blank" rel="noopener noreferrer" title="',
      htmltools::htmlEscape(dosya$original_path %||% ""),
      '">',
      '<span class="cc-generated-file-main">',
      '<span class="cc-generated-file-icon"><i class="fas fa-download"></i></span>',
      '<span class="cc-generated-file-texts">',
      '<span class="cc-generated-file-name">',
      htmltools::htmlEscape(dosya$display_name %||% "Dosya"),
      '</span>',
      '<span class="cc-generated-file-subtitle">',
      htmltools::htmlEscape(alt_metin),
      '</span>',
      '</span>',
      '</span>',
      '<span class="cc-generated-file-action">İndir</span>',
      '</a>'
    )
  }, character(1), USE.NAMES = FALSE)

  paste0(
    '<div class="cc-generated-files">',
    '<div class="cc-generated-files-title">',
    '<i class="fas fa-folder-open"></i> Oluşturulan Dosyalar',
    '</div>',
    '<div class="cc-generated-files-list">',
    paste(kartlar, collapse = ""),
    '</div>',
    '</div>'
  )
}

# NOT: format_claude_code_existing_file_link_html
# R/helpers_claude_code_existing_file_link.R dosyasında zaten tanımlıdır;
# bu dosyaya tekrar koyulması duplicate fonksiyon tanımı oluşturur.
