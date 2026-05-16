# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_artifact_links.R
# Açıklama: Bilge Yolaç tarafından üretilen kullanıcı çıktısı dosyalarını
#           daha güvenilir biçimde bulur, indirilebilir karta dönüştürür ve
#           bağlantıları ayrı bir UI mesajı olarak garanti eder.
#
# Not: Bu dosya büyük modülleri şişirmemek için ayrı tutulmuştur.
# ==============================================================================

cc_downloadable_artifact_extensions <- function() {
  c(
    "txt", "md", "csv", "log", "json", "html", "htm", "rtf",
    "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pdf",
    "png", "jpg", "jpeg", "gif", "webp", "svg",
    "zip"
  )
}

cc_prompt_requests_downloadable_artifact <- function(prompt) {
  metin <- tolower(enc2utf8(paste(as.character(prompt %||% ""), collapse = " ")))
  if (!nzchar(metin)) return(FALSE)

  uretim_deseni <- paste(
    c(
      "oluştur", "olustur", "yarat", "hazırla", "hazirla",
      "üret", "uret", "kaydet", "yaz", "export", "ekspor",
      "create", "generate", "write", "save", "produce"
    ),
    collapse = "|"
  )

  dosya_deseni <- paste(
    c(
      "\\.txt\\b", "\\.md\\b", "\\.docx\\b", "\\.doc\\b",
      "\\.xlsx\\b", "\\.xls\\b", "\\.pdf\\b",
      "\\.pptx\\b", "\\.ppt\\b", "\\.csv\\b", "\\.html\\b",
      "\\btxt\\b", "\\bword\\b", "\\bdocx\\b", "\\bexcel\\b",
      "\\bxlsx\\b", "\\bpdf\\b", "\\bpptx\\b",
      "\\bdocument\\b", "\\bdosya\\b", "\\bbelge\\b"
    ),
    collapse = "|"
  )

  grepl(uretim_deseni, metin, perl = TRUE) &&
    grepl(dosya_deseni, metin, perl = TRUE)
}

augment_claude_code_downloadable_artifact_prompt <- function(prompt, workdir = "") {
  prompt <- enc2utf8(as.character(prompt %||% "")[1])
  if (!cc_prompt_requests_downloadable_artifact(prompt)) return(prompt)

  workdir <- enc2utf8(as.character(workdir %||% "")[1])

  ek_not <- c(
    "",
    "",
    "BİLGE YOLAÇ ÇIKTI DOSYASI TALİMATI:",
    "- Kullanıcı bir dosya/belge oluşturmanı istedi.",
    "- Yalnızca metinde açıklama yapma; fiziksel dosyayı gerçekten oluştur.",
    "- Dosyayı mevcut çalışma dizini içinde oluştur. Mutlak sistem dışı yol kullanma.",
    "- Uygun uzantıyı koru: .txt, .docx, .xlsx, .pdf vb.",
    "- Dosya oluşturulduktan sonra yanıtında kısa biçimde dosya adını belirt.",
    "- Uygulama dosyayı ayrıca indirilebilir bağlantıya dönüştürecektir; manuel kopyala/yapıştır önermene gerek yok."
  )

  if (nzchar(workdir)) {
    ek_not <- c(
      ek_not,
      paste0("- Geçerli çalışma dizini: ", workdir)
    )
  }

  paste(c(prompt, ek_not), collapse = "\n")
}

cc_is_internal_artifact_path <- function(path) {
  yol <- gsub("\\\\", "/", as.character(path %||% "")[1])
  if (!nzchar(yol)) return(TRUE)

  grepl("/BILGE_YOLAC_DOKUMAN_REHBERI\\.md$", yol, perl = TRUE) ||
    grepl("/document_support/", yol, perl = TRUE) ||
    grepl("/\\.document_support/", yol, perl = TRUE) ||
    grepl("/bilge_yolac_downloads/", yol, perl = TRUE)
}

cc_normalize_artifact_paths <- function(paths) {
  paths <- unique(Filter(nzchar, as.character(paths %||% character(0))))
  if (!length(paths)) return(character(0))

  paths <- vapply(
    paths,
    function(p) {
      tryCatch(
        canonicalize_claude_code_file_path(p),
        error = function(e) normalizePath(p, winslash = "/", mustWork = FALSE)
      )
    },
    character(1),
    USE.NAMES = FALSE
  )

  paths <- paths[nzchar(paths)]
  paths <- paths[file.exists(paths) & !dir.exists(paths)]

  if (exists("deduplicate_claude_code_file_paths", mode = "function")) {
    return(deduplicate_claude_code_file_paths(paths))
  }

  paths[!duplicated(tolower(paths))]
}

cc_list_recent_artifact_paths <- function(workdir,
                                          started_at = NULL,
                                          extensions = cc_downloadable_artifact_extensions(),
                                          recursive = TRUE,
                                          max_files = 5000L,
                                          grace_seconds = 10L) {
  workdir <- as.character(workdir %||% "")[1]
  if (!nzchar(workdir) || !dir.exists(workdir)) return(character(0))

  ogeler <- tryCatch(
    list.files(
      workdir,
      full.names = TRUE,
      recursive = recursive,
      all.files = FALSE,
      include.dirs = FALSE,
      no.. = TRUE
    ),
    error = function(e) character(0)
  )

  if (!length(ogeler)) return(character(0))

  ogeler <- ogeler[!dir.exists(ogeler)]
  if (!length(ogeler)) return(character(0))

  if (length(ogeler) > max_files) {
    ogeler <- ogeler[seq_len(max_files)]
  }

  uzantilar <- tolower(tools::file_ext(ogeler))
  ogeler <- ogeler[uzantilar %in% tolower(extensions)]

  if (!length(ogeler)) return(character(0))

  ogeler <- ogeler[!vapply(ogeler, cc_is_internal_artifact_path, logical(1))]
  if (!length(ogeler)) return(character(0))

  if (!is.null(started_at)) {
    baslangic <- suppressWarnings(as.numeric(as.POSIXct(started_at)))
    if (is.finite(baslangic)) {
      bilgi <- tryCatch(file.info(ogeler), error = function(e) NULL)
      if (!is.null(bilgi) && nrow(bilgi) > 0L) {
        mtime <- suppressWarnings(as.numeric(bilgi$mtime))
        ogeler <- ogeler[is.finite(mtime) & mtime >= (baslangic - grace_seconds)]
      }
    }
  }

  cc_normalize_artifact_paths(ogeler)
}

collect_claude_code_downloads_from_paths <- function(file_paths,
                                                     runtime_workdir = "",
                                                     source_workdir = "",
                                                     user_id = 0L,
                                                     session_token = "",
                                                     allowed_roots = character(0)) {
  file_paths <- cc_normalize_artifact_paths(file_paths)
  if (!length(file_paths)) return(list())

  if (!length(allowed_roots)) {
    allowed_roots <- cc_policy_allowed_output_roots(
      user_id = user_id,
      workdir = runtime_workdir %||% source_workdir
    )
  }

  file_paths <- cc_policy_filter_generated_file_paths(
    file_paths,
    allowed_roots = allowed_roots,
    context = "indirilebilir çıktı dosyası"
  )

  if (!length(file_paths)) return(list())

  tryCatch(
    normalize_claude_code_text_files(
      file_paths = file_paths,
      extensions = c("txt", "log", "csv", "md")
    ),
    error = function(e) NULL
  )

  indirmeler <- tryCatch(
    stage_claude_code_downloads(
      file_paths = file_paths,
      user_id = user_id,
      session_token = session_token,
      allowed_roots = allowed_roots
    ),
    error = function(e) list()
  )

  if (!length(indirmeler)) return(list())

  for (i in seq_along(indirmeler)) {
    indirmeler[[i]]$display_path <- tryCatch(
      build_claude_code_display_path(
        file_path = indirmeler[[i]]$original_path,
        runtime_workdir = runtime_workdir,
        source_workdir = source_workdir
      ),
      error = function(e) basename(indirmeler[[i]]$original_path %||% "")
    )
  }

  indirmeler
}

collect_claude_code_artifact_downloads <- function(before_snapshot,
                                                   source_before_snapshot = list(),
                                                   tool_uses = list(),
                                                   runtime_workdir = "",
                                                   source_workdir = "",
                                                   run_started_at = NULL,
                                                   user_id = 0L,
                                                   session_token = "") {
  adaylar <- character(0)

  if (nzchar(runtime_workdir) && dir.exists(runtime_workdir)) {
    adaylar <- c(
      adaylar,
      tryCatch(
        diff_claude_code_workdir_snapshot(
          before_snapshot = before_snapshot,
          workdir = runtime_workdir
        ),
        error = function(e) character(0)
      )
    )
  }

  if (nzchar(source_workdir) && dir.exists(source_workdir)) {
    adaylar <- c(
      adaylar,
      tryCatch(
        diff_claude_code_workdir_snapshot(
          before_snapshot = source_before_snapshot,
          workdir = source_workdir
        ),
        error = function(e) character(0)
      )
    )
  }

  adaylar <- c(
    adaylar,
    tryCatch(
      list_claude_code_generated_file_paths(
        tool_uses = tool_uses,
        runtime_workdir = runtime_workdir,
        source_workdir = source_workdir,
        user_id = user_id
      ),
      error = function(e) character(0)
    ),
    cc_list_recent_artifact_paths(
      workdir = runtime_workdir,
      started_at = run_started_at
    ),
    cc_list_recent_artifact_paths(
      workdir = source_workdir,
      started_at = run_started_at
    )
  )

  adaylar <- adaylar[!vapply(adaylar, cc_is_internal_artifact_path, logical(1))]

  adaylar <- tryCatch(
    wait_for_stable_claude_code_file_paths(adaylar),
    error = function(e) cc_normalize_artifact_paths(adaylar)
  )

  collect_claude_code_downloads_from_paths(
    file_paths = adaylar,
    runtime_workdir = runtime_workdir,
    source_workdir = source_workdir,
    user_id = user_id,
    session_token = session_token
  )
}

cc_send_generated_downloads_message <- function(session,
                                                ns,
                                                downloads,
                                                accent_color = "#7C4DFF",
                                                character_name = "Bilge Yolaç",
                                                welcome_id = NULL) {
  if (!length(downloads)) return(invisible(FALSE))

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
      welcomeId = welcome_id %||% ns("welcome_screen")
    )
  )

  invisible(TRUE)
}