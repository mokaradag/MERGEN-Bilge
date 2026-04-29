# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_upload_folder.R
# Açıklama: Bilge Yolaç kullanıcı yükleme klasörü çözümleme yardımcıları.
# ==============================================================================

cc_normalize_positive_user_id <- function(user_id) {
  if (is.null(user_id) || length(user_id) == 0L) {
    return("")
  }

  raw <- as.character(user_id[1])
  if (is.na(raw)) {
    return("")
  }

  raw <- trimws(raw)
  if (!nzchar(raw)) {
    return("")
  }

  uid <- suppressWarnings(as.integer(raw))
  if (is.na(uid) || uid <= 0L) {
    return("")
  }

  as.character(uid)
}

cc_resolve_existing_dir_relaxed <- function(dir_path) {
  dir_chr <- gsub("\\\\", "/", as.character(dir_path %||% "")[1], fixed = TRUE)
  if (is.na(dir_chr) || !nzchar(dir_chr)) return("")

  adaylar <- unique(Filter(nzchar, c(
    dir_chr,
    enc2utf8(dir_chr),
    enc2native(dir_chr),
    if (grepl("^/[^/]", dir_chr)) paste0("/", dir_chr) else NULL
  )))

  for (aday in adaylar) {
    var_mi <- tryCatch(
      isTRUE(dir.exists(aday)) || isTRUE(fs::dir_exists(aday)),
      error = function(e) FALSE
    )

    if (isTRUE(var_mi)) {
      return(
        tryCatch(
          {
            if (exists("normalize_mcp_path", mode = "function", inherits = TRUE)) {
              normalize_mcp_path(aday, must_exist = FALSE)
            } else {
              normalizePath(aday, winslash = "/", mustWork = FALSE)
            }
          },
          error = function(e) aday
        )
      )
    }
  }

  ""
}

cc_count_dir_items_relaxed <- function(dir_path) {
  cozulen <- cc_resolve_existing_dir_relaxed(dir_path)
  if (!nzchar(cozulen)) {
    return(list(path = "", count = -1L))
  }

  dosyalar_base <- tryCatch(
    list.files(
      cozulen,
      full.names = TRUE,
      recursive = FALSE,
      all.files = FALSE,
      include.dirs = TRUE
    ),
    error = function(e) character(0)
  )

  if (length(dosyalar_base) > 0) {
    return(list(path = cozulen, count = length(unique(dosyalar_base))))
  }

  klasorler_fs <- tryCatch(
    as.character(fs::dir_ls(cozulen, recurse = FALSE, type = "directory")),
    error = function(e) character(0)
  )

  dosyalar_fs <- tryCatch(
    as.character(fs::dir_ls(cozulen, recurse = FALSE, type = "file")),
    error = function(e) character(0)
  )

  tum_ogeler <- unique(c(klasorler_fs, dosyalar_fs))
  list(path = cozulen, count = length(tum_ogeler))
}

cc_resolve_real_upload_folder <- function(user_id, session_file_registry = NULL) {
  uid_chr <- cc_normalize_positive_user_id(user_id)
  if (!nzchar(uid_chr)) {
    return("")
  }

  uid_int <- suppressWarnings(as.integer(uid_chr))
  aday_klasorler <- character(0)

  # 1) İndeksten gelen gerçek dosya yolları
  indeks_df <- tryCatch(
    mergen_list_user_files(uid_int, prune_missing = FALSE),
    error = function(e) NULL
  )

  if (is.data.frame(indeks_df) && nrow(indeks_df) > 0 && "path" %in% names(indeks_df)) {
    gecerli_yollar <- indeks_df$path[
      vapply(indeks_df$path, path_exists_relaxed, logical(1))
    ]

    if (length(gecerli_yollar) > 0) {
      aday_klasorler <- c(aday_klasorler, dirname(gecerli_yollar))
    }
  }

  # 2) Oturumda tutulan mevcut dosya kayıtları
  if (is.list(session_file_registry) && length(session_file_registry) > 0) {
    registry_yollar <- vapply(session_file_registry, function(x) {
      as.character(x$persisted_path %||% x$path %||% x$datapath %||% "")
    }, character(1))

    registry_yollar <- registry_yollar[nzchar(registry_yollar)]
    registry_yollar <- registry_yollar[
      vapply(registry_yollar, path_exists_relaxed, logical(1))
    ]

    if (length(registry_yollar) > 0) {
      aday_klasorler <- c(aday_klasorler, dirname(registry_yollar))
    }
  }

  uploads_dir <- if (exists("MERGEN_UPLOADS_DIR", inherits = TRUE)) {
    get("MERGEN_UPLOADS_DIR", inherits = TRUE)
  } else {
    ""
  }

  uploads_dir <- as.character(uploads_dir %||% "")[1]
  if (is.na(uploads_dir)) {
    uploads_dir <- ""
  }

  # 3) Kanonik kullanıcı klasörü adayları
  aday_klasorler <- c(
    aday_klasorler,
    tryCatch(mergen_user_upload_dir(uid_int), error = function(e) ""),
    if (nzchar(uploads_dir)) file.path(uploads_dir, sprintf("user_%s", uid_chr)) else "",
    if (nzchar(uploads_dir)) {
      file.path(
        getOption("mergen.mcp_base_dir", uploads_dir),
        sprintf("user_%s", uid_chr)
      )
    } else {
      ""
    }
  )

  aday_klasorler <- unique(Filter(nzchar, aday_klasorler))

  en_iyi_klasor <- ""
  en_iyi_sayi <- -1L

  for (aday in aday_klasorler) {
    sonuc <- cc_count_dir_items_relaxed(aday)
    if (!nzchar(sonuc$path)) next

    if (isTRUE(sonuc$count > en_iyi_sayi)) {
      en_iyi_klasor <- sonuc$path
      en_iyi_sayi <- sonuc$count
    }
  }

  if (nzchar(en_iyi_klasor)) {
    return(en_iyi_klasor)
  }

  tryCatch(mergen_user_upload_dir(uid_int), error = function(e) "")
}