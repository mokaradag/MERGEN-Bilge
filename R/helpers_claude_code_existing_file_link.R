# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_existing_file_link.R
# Açıklama: Bilge Yolaç tarafından kullanıcı klasöründe zaten oluşturulmuş
#           dosyalar için kopyalama/staging yapmadan doğrudan indirilebilir
#           Shiny bağlantısı üretir.
# ==============================================================================

#' Var olan yerel dosyayı kopyalamadan tıklanabilir Bilge Yolaç kartına çevirir
#'
#' Doküman özeti gibi dosya zaten kullanıcı klasöründe fiziksel olarak oluşmuşsa
#' bilge_yolac_downloads alanına kopyalamaya çalışmaz. Dosyanın bulunduğu klasörü
#' oturuma özel güvenli Shiny resource path olarak sunar ve doğrudan link üretir.
#'
#' @param file_path Var olan dosya yolu
#' @param user_id Kullanıcı kimliği
#' @param session_token Shiny oturum token'ı
#' @param allowed_roots Güvenlik için izinli kökler
#' @param display_path Kartta gösterilecek göreli yol
#' @return HTML kartı veya boş metin
format_claude_code_existing_file_link_html <- function(file_path,
                                                       user_id = 0L,
                                                       session_token = "",
                                                       allowed_roots = character(0),
                                                       display_path = "") {
  dosya_yolu <- as.character(file_path %||% "")[1]
  if (is.na(dosya_yolu) || !nzchar(dosya_yolu)) return("")

  dosya_norm <- tryCatch(
    normalizePath(dosya_yolu, winslash = "/", mustWork = TRUE),
    error = function(e) ""
  )

  if (!nzchar(dosya_norm) ||
      !isTRUE(file.exists(dosya_norm)) ||
      isTRUE(dir.exists(dosya_norm))) {
    return("")
  }

  if (!length(allowed_roots)) {
    log_warn(paste(
      CLAUDE_CODE_LOG_PREFIX,
      "Doğrudan link üretimi izinli kök verilmediği için engellendi:",
      basename(dosya_norm)
    ))
    return("")
  }

  if (exists("cc_policy_path_inside_roots", mode = "function", inherits = TRUE) &&
      !cc_policy_path_inside_roots(dosya_norm, allowed_roots)) {
    log_warn(paste(
      CLAUDE_CODE_LOG_PREFIX,
      "Doğrudan link üretimi izinli kök dışında engellendi:",
      dosya_norm
    ))
    return("")
  }

  klasor_norm <- tryCatch(
    normalizePath(dirname(dosya_norm), winslash = "/", mustWork = TRUE),
    error = function(e) ""
  )

  if (!nzchar(klasor_norm) || !isTRUE(dir.exists(klasor_norm))) {
    return("")
  }

  kullanici_etiketi <- sanitize_claude_code_download_segment(
    paste0("user_", as.character(user_id %||% 0L)),
    fallback = "user_0"
  )

  oturum_etiketi <- sanitize_claude_code_download_segment(
    paste0("session_", as.character(session_token %||% "anonim")),
    fallback = "session_anonim"
  )

  resource_prefix <- sanitize_claude_code_download_segment(
    paste("bilge_yolac_existing", kullanici_etiketi, oturum_etiketi, sep = "_"),
    fallback = "bilge_yolac_existing"
  )

  withCallingHandlers(
    shiny::addResourcePath(resource_prefix, klasor_norm),
    warning = function(w) {
      if (grepl("already", conditionMessage(w), ignore.case = TRUE)) {
        invokeRestart("muffleWarning")
      }
    }
  )

  dosya_adi <- basename(dosya_norm)
  boyut <- suppressWarnings(as.numeric(file.info(dosya_norm)$size[1]))
  boyut_etiketi <- format_claude_code_download_size(boyut)

  url <- paste(
    resource_prefix,
    utils::URLencode(dosya_adi, reserved = TRUE),
    sep = "/"
  )

  alt_metin <- paste(
    c(display_path %||% dosya_adi, boyut_etiketi %||% ""),
    collapse = " • "
  )
  alt_metin <- gsub("^ • | • $", "", alt_metin)

  paste0(
    '<div class="cc-generated-files">',
    '<div class="cc-generated-files-title">',
    '<i class="fas fa-folder-open"></i> Oluşturulan Dosyalar',
    '</div>',
    '<div class="cc-generated-files-list">',
    # HTML öznitelik bağlamındaki değerler attribute = TRUE ile escape edilir;
    # böylece dosya adı/yolundaki çift tırnak veya tek tırnak öznitelikten
    # dışarı kaçamaz (öznitelik enjeksiyonu savunması). Eleman metni (span)
    # bağlamı varsayılan escape ile kalır.
    '<a class="cc-generated-file-card" href="',
    htmltools::htmlEscape(url, attribute = TRUE),
    '" download="',
    htmltools::htmlEscape(dosya_adi, attribute = TRUE),
    '" target="_blank" rel="noopener noreferrer" title="',
    htmltools::htmlEscape(dosya_norm, attribute = TRUE),
    '">',
    '<span class="cc-generated-file-main">',
    '<span class="cc-generated-file-icon"><i class="fas fa-download"></i></span>',
    '<span class="cc-generated-file-texts">',
    '<span class="cc-generated-file-name">',
    htmltools::htmlEscape(dosya_adi),
    '</span>',
    '<span class="cc-generated-file-subtitle">',
    htmltools::htmlEscape(alt_metin),
    '</span>',
    '</span>',
    '</span>',
    '<span class="cc-generated-file-action">İndir</span>',
    '</a>',
    '</div>',
    '</div>'
  )
}