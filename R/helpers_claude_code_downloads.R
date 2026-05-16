# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_downloads.R
# Açıklama: Bilge Yolaç tarafından üretilen dosyaları yerel Shiny bağlantıları ile
#           indirilebilir hale getirir. İnternet gerektirmez; dosyalar uygulama
#           altındaki bilge_yolac_downloads/ klasörüne kopyalanır.
# ==============================================================================

#' Bilge Yolaç indirme kök klasörünü döndürür
#'
#' @return İndirme kök klasörü
get_claude_code_download_root <- function() {
  kok <- getOption("mergen.claude_code_download_root", "")

  if (!nzchar(kok)) {
    kok <- file.path(getwd(), "bilge_yolac_downloads")
    options(mergen.claude_code_download_root = kok)
  }

  if (!dir.exists(kok)) {
    dir.create(kok, recursive = TRUE, showWarnings = FALSE)
  }

  normalizePath(kok, winslash = "/", mustWork = FALSE)
}

#' URL/dizin segmentini güvenli hale getirir
#'
#' @param x Ham metin
#' @param fallback Boş kalırsa kullanılacak yedek değer
#' @return Güvenli segment
sanitize_claude_code_download_segment <- function(x, fallback = "oge") {
  x <- as.character(x %||% "")[1]
  x <- enc2utf8(x)
  x <- gsub("[^A-Za-z0-9._-]+", "_", x, perl = TRUE)
  x <- gsub("_+", "_", x, perl = TRUE)
  x <- sub("^_+", "", x, perl = TRUE)
  x <- sub("_+$", "", x, perl = TRUE)

  if (!nzchar(x)) {
    x <- fallback
  }

  x
}

#' Dosya boyutunu okunabilir metne çevirir
#'
#' @param bytes Bayt cinsinden boyut
#' @return Okunabilir boyut etiketi
format_claude_code_download_size <- function(bytes) {
  bytes <- suppressWarnings(as.numeric(bytes)[1])

  if (is.na(bytes)) return("Boyut bilinmiyor")
  if (bytes < 1024) return(paste0(bytes, " B"))
  if (bytes < 1024^2) return(paste0(round(bytes / 1024, 1), " KB"))
  if (bytes < 1024^3) return(paste0(round(bytes / 1024^2, 1), " MB"))

  paste0(round(bytes / 1024^3, 2), " GB")
}

#' Claude Code'un yazdığı hedef yolu gerçek dosyaya çözümler
#'
#' @param path_value Araç girdisinden gelen yol
#' @param runtime_workdir Claude Code'un gerçekten çalıştığı dizin
#' @param source_workdir Kullanıcının seçtiği/asıl kaynak dizin
#' @return Var olan dosya yolu veya boş metin
resolve_claude_code_generated_path <- function(path_value,
                                               runtime_workdir = "",
                                               source_workdir = "",
                                               allowed_roots = character(0)) {
  yol <- as.character(path_value %||% "")[1]
  if (!nzchar(yol)) return("")

  mutlak_mi <- grepl("^(?:[A-Za-z]:|/|\\\\\\\\)", yol)

  adaylar <- unique(Filter(nzchar, c(
    yol,
    if (!isTRUE(mutlak_mi) && nzchar(runtime_workdir)) file.path(runtime_workdir, yol) else NULL,
    if (!isTRUE(mutlak_mi) && nzchar(source_workdir)) file.path(source_workdir, yol) else NULL
  )))

  for (aday in adaylar) {
    aday_norm <- tryCatch(
      normalize_mcp_path(aday, must_exist = FALSE),
      error = function(e) normalizePath(aday, winslash = "/", mustWork = FALSE)
    )

    if (isTRUE(file.exists(aday_norm)) && !isTRUE(dir.exists(aday_norm))) {
      if (length(allowed_roots) &&
          !cc_policy_path_inside_roots(aday_norm, allowed_roots, must_exist = FALSE)) {
        log_warn(paste(
          CLAUDE_CODE_LOG_PREFIX,
          "Üretilen dosya izin verilen köklerin dışında bırakıldı:",
          gsub("[{}]", "", aday_norm)
        ))
        next
      }

      return(aday_norm)
    }
  }

  ""
}

#' Araç kullanımlarından üretilen dosya yollarını toplar
#'
#' @param tool_uses Claude Code araç kullanımları
#' @param runtime_workdir Claude Code runtime dizini
#' @param source_workdir Kullanıcının seçtiği/asıl kaynak dizin
#' @return Dosya yolları
list_claude_code_generated_file_paths <- function(tool_uses,
                                                  runtime_workdir = "",
                                                  source_workdir = "",
                                                  allowed_roots = character(0),
                                                  user_id = 0L) {
  if (!length(tool_uses)) return(character(0))

  if (!length(allowed_roots)) {
    allowed_roots <- cc_policy_allowed_output_roots(
      user_id = user_id,
      workdir = runtime_workdir %||% source_workdir
    )
  }

  dosyalar <- character(0)

  for (arac in tool_uses) {
    arac_adi <- tolower(as.character(arac$name %||% "")[1])
    if (!nzchar(arac_adi)) next

    # Yalnızca dosya üretme/değiştirme araçlarını hedefle
    if (!grepl("write|edit|file_write", arac_adi, ignore.case = TRUE)) {
      next
    }

    girdi <- arac$input %||% list()
    hedef_yol <- girdi$path %||% girdi$file_path %||% ""

    cozulen_yol <- resolve_claude_code_generated_path(
      path_value = hedef_yol,
      runtime_workdir = runtime_workdir,
      source_workdir = source_workdir,
      allowed_roots = allowed_roots
    )

    if (nzchar(cozulen_yol)) {
      dosyalar <- c(dosyalar, cozulen_yol)
    }
  }

  unique(dosyalar[nzchar(dosyalar)])
}

#' Dosya için kullanıcıya gösterilecek göreli yol üretir
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

#' Dosyaları indirilebilir klasöre kopyalar
#'
#' @param file_paths Kaynak dosya yolları
#' @param user_id Kullanıcı kimliği
#' @param session_token Shiny oturum anahtarı
#' @return İndirme kayıtları listesi
stage_claude_code_downloads <- function(file_paths,
                                        user_id = 0L,
                                        session_token = "",
                                        allowed_roots = character(0)) {
  file_paths <- unique(Filter(nzchar, as.character(file_paths %||% character(0))))

  if (!length(file_paths)) return(list())

  if (!length(allowed_roots)) {
    allowed_roots <- cc_policy_allowed_output_roots(user_id = user_id)
  }

  file_paths <- cc_policy_filter_generated_file_paths(
    file_paths,
    allowed_roots = allowed_roots,
    context = "indirilecek dosya"
  )

  if (!length(file_paths)) return(list())

  kok <- get_claude_code_download_root()

  kullanici_etiketi <- sanitize_claude_code_download_segment(
    paste0("user_", as.character(user_id %||% 0L)),
    fallback = "user_0"
  )

  oturum_etiketi <- sanitize_claude_code_download_segment(
    paste0("session_", as.character(session_token %||% "anonim")),
    fallback = "session_anonim"
  )

  hedef_dizin <- file.path(kok, kullanici_etiketi, oturum_etiketi)
  if (!dir.exists(hedef_dizin)) {
    dir.create(hedef_dizin, recursive = TRUE, showWarnings = FALSE)
  }

  sonuc <- list()

  for (i in seq_along(file_paths)) {
    kaynak <- file_paths[i]

    if (!isTRUE(file.exists(kaynak)) || isTRUE(dir.exists(kaynak))) next

    orijinal_ad <- basename(kaynak)

    guvenli_ad <- sanitize_claude_code_download_segment(
      orijinal_ad,
      fallback = paste0("dosya_", i)
    )

    hedef_ad <- paste0(
      format(Sys.time(), "%Y%m%d-%H%M%S"),
      "_",
      sprintf("%02d", i),
      "_",
      guvenli_ad
    )

    hedef_yol <- file.path(hedef_dizin, hedef_ad)

    kopyalandi <- tryCatch(
      file.copy(
        from = kaynak,
        to = hedef_yol,
        overwrite = TRUE,
        copy.mode = TRUE,
        copy.date = TRUE
      ),
      error = function(e) FALSE
    )

    if (!isTRUE(kopyalandi)) next

    boyut <- suppressWarnings(as.numeric(file.info(hedef_yol)$size[1]))

    url <- paste(
      "bilge_yolac_downloads",
      utils::URLencode(kullanici_etiketi, reserved = TRUE),
      utils::URLencode(oturum_etiketi, reserved = TRUE),
      utils::URLencode(hedef_ad, reserved = TRUE),
      sep = "/"
    )

    sonuc[[length(sonuc) + 1]] <- list(
      original_path = tryCatch(
        normalize_mcp_path(kaynak, must_exist = FALSE),
        error = function(e) normalizePath(kaynak, winslash = "/", mustWork = FALSE)
      ),
      download_path = tryCatch(
        normalizePath(hedef_yol, winslash = "/", mustWork = FALSE),
        error = function(e) hedef_yol
      ),
      display_name = orijinal_ad,
      download_name = orijinal_ad,
      url = url,
      size = boyut,
      size_label = format_claude_code_download_size(boyut)
    )
  }

  sonuc
}

#' Araç kullanımından indirilebilir dosya listesi üretir
#'
#' @param tool_uses Claude Code araç kullanımları
#' @param runtime_workdir Claude Code runtime dizini
#' @param source_workdir Kullanıcının seçtiği/asıl kaynak dizin
#' @param user_id Kullanıcı kimliği
#' @param session_token Shiny oturum anahtarı
#' @return İndirme kayıtları listesi
collect_claude_code_generated_downloads <- function(tool_uses,
                                                    runtime_workdir = "",
                                                    source_workdir = "",
                                                    user_id = 0L,
                                                    session_token = "") {
  allowed_roots <- cc_policy_allowed_output_roots(
    user_id = user_id,
    workdir = runtime_workdir %||% source_workdir
  )

  dosya_yollari <- list_claude_code_generated_file_paths(
    tool_uses = tool_uses,
    runtime_workdir = runtime_workdir,
    source_workdir = source_workdir,
    allowed_roots = allowed_roots,
    user_id = user_id
  )

  if (!length(dosya_yollari)) return(list())

  indirmeler <- stage_claude_code_downloads(
    file_paths = dosya_yollari,
    user_id = user_id,
    session_token = session_token,
    allowed_roots = allowed_roots
  )

  if (!length(indirmeler)) return(list())

  for (i in seq_along(indirmeler)) {
    indirmeler[[i]]$display_path <- build_claude_code_display_path(
      file_path = indirmeler[[i]]$original_path,
      runtime_workdir = runtime_workdir,
      source_workdir = source_workdir
    )
  }

  indirmeler
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

#' Verilen dosya yollarından doğrudan indirme kayıtları üretir
#'
#' @param file_paths Dosya yolları
#' @param runtime_workdir Runtime çalışma dizini
#' @param source_workdir Kaynak çalışma dizini
#' @param user_id Kullanıcı kimliği
#' @param session_token Shiny oturum anahtarı
#' @return İndirme kayıtları listesi
collect_claude_code_downloads_from_paths <- function(file_paths,
                                                     runtime_workdir = "",
                                                     source_workdir = "",
                                                     user_id = 0L,
                                                     session_token = "") {
  file_paths <- unique(Filter(nzchar, as.character(file_paths %||% character(0))))
  if (!length(file_paths)) return(list())

  allowed_roots <- unique(c(
    cc_policy_allowed_output_roots(
      user_id = user_id,
      workdir = runtime_workdir %||% source_workdir
    ),
    if (nzchar(source_workdir)) {
      cc_policy_allowed_output_roots(user_id = user_id, workdir = source_workdir)
    } else {
      character(0)
    },
    if (nzchar(runtime_workdir)) {
      cc_policy_allowed_output_roots(user_id = user_id, workdir = runtime_workdir)
    } else {
      character(0)
    }
  ))

  indirmeler <- stage_claude_code_downloads(
    file_paths = file_paths,
    user_id = user_id,
    session_token = session_token,
    allowed_roots = allowed_roots
  )

  if (!length(indirmeler)) return(list())

  for (i in seq_along(indirmeler)) {
    indirmeler[[i]]$display_path <- build_claude_code_display_path(
      file_path = indirmeler[[i]]$original_path,
      runtime_workdir = runtime_workdir,
      source_workdir = source_workdir
    )
  }

  indirmeler
}

#' Oluşturulan dosya indirme kartlarını ayrı mesaj olarak gönderir
#'
#' @param session Shiny session
#' @param ns Namespace fonksiyonu
#' @param downloads İndirme kayıtları
#' @param accent_color Karakter rengi
#' @param character_name Karakter adı
#' @param welcome_id Karşılama ekranı ID
#' @return TRUE/FALSE
cc_send_generated_downloads_message <- function(session,
                                                ns,
                                                downloads,
                                                accent_color = "#7C4DFF",
                                                character_name = "Bilge Yolaç",
                                                welcome_id = NULL) {
  html <- format_claude_code_generated_downloads_html(downloads)
  if (!nzchar(html)) return(invisible(FALSE))

  session$sendCustomMessage(
    type = "cc-add-message",
    message = list(
      target = ns("output_area"),
      type = "assistant",
      content = html,
      timestamp = format(Sys.time(), "%H:%M:%S"),
      accentColor = accent_color,
      characterName = character_name,
      welcomeId = welcome_id
    )
  )

  invisible(TRUE)
}