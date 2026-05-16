# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_output_intent.R
# Açıklama: Bilge Yolaç çıktı dosyası niyet tespiti ve Dosya Yönetimi yenileme
#           yardımcıları. Küçük tutulur; UI veya streaming başlatmaz.
# ==============================================================================

cc_prompt_requests_bilge_yolac_output_file <- function(prompt) {
  metin <- tolower(enc2utf8(paste(as.character(prompt %||% ""), collapse = " ")))
  metin <- trimws(metin)
  if (!nzchar(metin)) return(FALSE)

  engelleme_deseni <- paste(
    c(
      "dosya\\s+oluşturmadan",
      "dosya\\s+olusturmadan",
      "belge\\s+oluşturmadan",
      "belge\\s+olusturmadan",
      "dok[üu]man\\s+oluşturmadan",
      "dokuman\\s+olusturmadan",
      "kaydetmeden",
      "çıktı\\s+oluşturmadan",
      "cikti\\s+olusturmadan",
      "do\\s+not\\s+create",
      "don't\\s+create",
      "without\\s+creating\\s+(a\\s+)?file",
      "no\\s+file\\s+creation"
    ),
    collapse = "|"
  )

  if (grepl(engelleme_deseni, metin, perl = TRUE)) {
    return(FALSE)
  }

  uretme_deseni <- paste(
    c(
      "\\boluştur[a-zçğıöşü]*\\b",
      "\\bolustur[a-zçğıöşü]*\\b",
      "\\byarat[a-zçğıöşü]*\\b",
      "\\büret[a-zçğıöşü]*\\b",
      "\\buret[a-zçğıöşü]*\\b",
      "\\bhazırla[a-zçğıöşü]*\\b",
      "\\bhazirla[a-zçğıöşü]*\\b",
      "\\byaz[a-zçğıöşü]*\\b",
      "\\bkaydet[a-zçğıöşü]*\\b",
      "\\bdönüştür[a-zçğıöşü]*\\b",
      "\\bdonustur[a-zçğıöşü]*\\b",
      "\\bexport\\b",
      "\\bgenerate\\b",
      "\\bcreate\\b",
      "\\bwrite\\b",
      "\\bproduce\\b",
      "\\bsave\\b",
      "\\bconvert\\b"
    ),
    collapse = "|"
  )

  hedef_deseni <- paste(
    c(
      "\\bdosya[a-zçğıöşü]*\\b",
      "\\bbelge[a-zçğıöşü]*\\b",
      "\\bdoküman[a-zçğıöşü]*\\b",
      "\\bdokuman[a-zçğıöşü]*\\b",
      "\\brapor[a-zçğıöşü]*\\b",
      "\\bçıktı[a-zçğıöşü]*\\b",
      "\\bcikti[a-zçğıöşü]*\\b",
      "\\.txt\\b",
      "\\.md\\b",
      "\\.docx\\b",
      "\\.doc\\b",
      "\\.pdf\\b",
      "\\.xlsx\\b",
      "\\.xls\\b",
      "\\.pptx\\b",
      "\\.ppt\\b",
      "\\btxt\\b",
      "\\bmarkdown\\b",
      "\\bword\\b",
      "\\bexcel\\b",
      "\\bpdf\\b",
      "\\bpowerpoint\\b",
      "\\btext\\s+file\\b",
      "\\bdocument\\b",
      "\\breport\\b",
      "\\bspreadsheet\\b",
      "\\bpresentation\\b",
      "\\bdownloadable\\b",
      "\\bindirilebilir\\b"
    ),
    collapse = "|"
  )

  grepl(uretme_deseni, metin, perl = TRUE) &&
    grepl(hedef_deseni, metin, perl = TRUE)
}

cc_generated_output_user_roots <- function(user_id) {
  uid <- as.character(user_id %||% "")
  if (!nzchar(uid) || uid %in% c("0", "unknown", "NA")) {
    return(character(0))
  }

  unique(Filter(nzchar, c(
    tryCatch(mergen_user_upload_dir(uid), error = function(e) ""),
    if (exists("MERGEN_UPLOADS_DIR", inherits = TRUE)) {
      file.path(MERGEN_UPLOADS_DIR, paste0("user_", uid))
    } else {
      ""
    },
    if (exists("MERGEN_MCP_BASE_DIR", inherits = TRUE)) {
      file.path(MERGEN_MCP_BASE_DIR, paste0("user_", uid))
    } else {
      ""
    }
  )))
}

cc_path_inside_user_roots <- function(path, roots) {
  roots <- unique(Filter(nzchar, as.character(roots %||% character(0))))
  if (!length(roots) || !nzchar(path %||% "")) return(FALSE)

  if (exists("cc_policy_path_inside_roots", mode = "function", inherits = TRUE)) {
    return(isTRUE(cc_policy_path_inside_roots(
      path,
      allowed_roots = roots,
      must_exist = FALSE
    )))
  }

  path_norm <- tolower(gsub(
    "\\\\", "/",
    normalizePath(path, winslash = "/", mustWork = FALSE)
  ))

  any(vapply(roots, function(root) {
    root_norm <- tolower(gsub(
      "\\\\", "/",
      normalizePath(root, winslash = "/", mustWork = FALSE)
    ))

    identical(path_norm, root_norm) || startsWith(path_norm, paste0(root_norm, "/"))
  }, logical(1)))
}

cc_refresh_file_manager_after_generated_outputs <- function(session,
                                                            user_id,
                                                            file_paths = character(0),
                                                            trigger = "bilge_yolac_generated_output") {
  paths <- unique(Filter(nzchar, as.character(file_paths %||% character(0))))
  paths <- paths[file.exists(paths) & !dir.exists(paths)]

  roots <- cc_generated_output_user_roots(user_id)

  for (path in paths) {
    if (!cc_path_inside_user_roots(path, roots)) {
      next
    }

    tryCatch(
      mergen_register_uploaded_file(
        src_path = path,
        as_name = basename(path),
        user_id = user_id,
        persist_under_mcp_base = TRUE
      ),
      error = function(e) {
        log_warn(paste(
          CLAUDE_CODE_LOG_PREFIX,
          "Üretilen dosya Dosya Yönetimi indeksine eklenemedi:",
          conditionMessage(e)
        ))
      }
    )
  }

  file_manager_data <- tryCatch(
    session$userData$file_manager_data,
    error = function(e) NULL
  )

  if (is.list(file_manager_data) &&
      is.function(file_manager_data$refresh_persisted_files)) {
    file_manager_data$refresh_persisted_files(trigger)
    return(invisible(TRUE))
  }

  invisible(FALSE)
}