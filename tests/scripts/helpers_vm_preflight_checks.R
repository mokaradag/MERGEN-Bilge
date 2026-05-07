# ==============================================================================
# Dosya Yolu: tests/scripts/helpers_vm_preflight_checks.R
# Açıklama: Windows VM gerçek preflight koşumu için yeniden kullanılabilir
#           üretim kontrolleri. Uygulamayı başlatmaz; run_vm_preflight_real.R
#           app.R'yi source ettikten sonra bu yardımcılar gerçek runtime
#           sabitlerini ve fonksiyonlarını doğrular.
# ==============================================================================

vm_preflight_stop <- function(message) {
  stop(message, call. = FALSE)
}

vm_preflight_first_string <- function(value, default = "") {
  if (is.null(value) || length(value) == 0L || is.na(value[1])) {
    return(default)
  }

  out <- trimws(as.character(value[1]))
  if (!nzchar(out)) {
    return(default)
  }

  out
}

vm_preflight_get_global <- function(name, default = NULL) {
  if (exists(name, envir = globalenv(), inherits = TRUE)) {
    return(get(name, envir = globalenv(), inherits = TRUE))
  }

  default
}

vm_preflight_required_functions <- function(function_names, label = "VM preflight") {
  function_names <- unique(as.character(function_names))

  missing <- function_names[!vapply(
    function_names,
    function(nm) {
      exists(nm, envir = globalenv(), mode = "function", inherits = TRUE)
    },
    logical(1)
  )]

  if (length(missing) > 0L) {
    vm_preflight_stop(sprintf(
      "%s başarısız: eksik fonksiyon(lar): %s",
      label,
      paste(missing, collapse = ", ")
    ))
  }

  invisible(TRUE)
}

vm_preflight_path_exists <- function(path) {
  path <- vm_preflight_first_string(path, default = "")
  if (!nzchar(path)) {
    return(FALSE)
  }

  if (exists("path_exists_relaxed", envir = globalenv(), mode = "function", inherits = TRUE)) {
    relaxed <- get("path_exists_relaxed", envir = globalenv(), inherits = TRUE)
    return(isTRUE(tryCatch(relaxed(path), error = function(e) FALSE)))
  }

  isTRUE(file.exists(path)) || isTRUE(dir.exists(path))
}

vm_preflight_normalize_for_compare <- function(path) {
  path <- vm_preflight_first_string(path, default = "")

  if (!nzchar(path)) {
    return("")
  }

  if (exists("normalize_for_path_compare", envir = globalenv(), mode = "function", inherits = TRUE)) {
    normalize_fn <- get("normalize_for_path_compare", envir = globalenv(), inherits = TRUE)
    return(tryCatch(
      normalize_fn(path),
      error = function(e) tolower(gsub("\\", "/", path, fixed = TRUE))
    ))
  }

  normalized <- tryCatch(
    normalizePath(path, winslash = "/", mustWork = FALSE),
    error = function(e) gsub("\\", "/", path, fixed = TRUE)
  )

  tolower(trimws(normalized))
}

vm_preflight_resolve_configured_path <- function(global_name,
                                                 env_name = global_name,
                                                 default = "") {
  global_value <- vm_preflight_get_global(global_name, default = NULL)
  global_path <- vm_preflight_first_string(global_value, default = "")

  if (nzchar(global_path)) {
    return(global_path)
  }

  env_path <- vm_preflight_first_string(Sys.getenv(env_name, ""), default = "")
  if (nzchar(env_path)) {
    return(env_path)
  }

  vm_preflight_first_string(default, default = "")
}

vm_preflight_writable_dir_candidates <- function(dir_path) {
  dir_path <- vm_preflight_first_string(dir_path, default = "")

  if (!nzchar(dir_path)) {
    return(character(0))
  }

  slash_path <- gsub("\\", "/", dir_path, fixed = TRUE)

  candidates <- unique(Filter(nzchar, c(
    dir_path,
    slash_path,
    enc2utf8(dir_path),
    enc2native(dir_path),
    gsub("/", "\\", slash_path, fixed = TRUE),
    if (grepl("^/[^/]", slash_path)) paste0("/", slash_path) else NULL,
    if (grepl("^/[^/]", slash_path)) gsub("/", "\\", paste0("/", slash_path), fixed = TRUE) else NULL
  )))

  if (exists("normalize_mcp_path", envir = globalenv(), mode = "function", inherits = TRUE)) {
    normalize_fn <- get("normalize_mcp_path", envir = globalenv(), inherits = TRUE)

    normalized <- unique(vapply(
      candidates,
      function(candidate) {
        tryCatch(
          normalize_fn(candidate, must_exist = FALSE),
          error = function(e) candidate
        )
      },
      character(1)
    ))

    candidates <- unique(c(candidates, normalized))
  }

  candidates
}

vm_preflight_check_writable_dir <- function(dir_path, label) {
  dir_path <- vm_preflight_first_string(dir_path, default = "")

  if (!nzchar(dir_path)) {
    vm_preflight_stop(sprintf(
      "VM preflight başarısız: %s yolu boş.",
      label
    ))
  }

  candidates <- vm_preflight_writable_dir_candidates(dir_path)
  errors <- character(0)

  for (candidate in candidates) {
    dir.create(candidate, recursive = TRUE, showWarnings = FALSE)

    probe_file <- file.path(
      candidate,
      sprintf(".preflight_write_probe_%s.tmp", as.integer(Sys.time()))
    )

    ok <- tryCatch({
      writeBin(charToRaw("ok"), probe_file)
      file.exists(probe_file) || vm_preflight_path_exists(probe_file)
    }, error = function(e) {
      errors <<- c(errors, sprintf("%s -> %s", candidate, conditionMessage(e)))
      FALSE
    })

    try(unlink(probe_file, force = TRUE), silent = TRUE)

    if (isTRUE(ok)) {
      cat(sprintf("OK: %s yazılabilir: %s\n", label, candidate))
      return(invisible(normalizePath(candidate, winslash = "/", mustWork = FALSE)))
    }
  }

  vm_preflight_stop(sprintf(
    paste(
      "VM preflight başarısız: %s yazılabilir değil.",
      "İstenen yol: %s",
      "Denenen varyantlar: %s",
      "Hatalar: %s"
    ),
    label,
    dir_path,
    paste(candidates, collapse = " | "),
    paste(errors, collapse = " | ")
  ))
}

vm_preflight_check_core_writable_paths <- function() {
  active_log_dir <- vm_preflight_first_string(
    Sys.getenv("MERGEN_LOG_DIR", "logs"),
    default = "logs"
  )

  uploads_dir <- vm_preflight_resolve_configured_path(
    "MERGEN_UPLOADS_DIR",
    "MERGEN_UPLOADS_DIR",
    "mergen_uploads"
  )

  files_root <- vm_preflight_resolve_configured_path(
    "MERGEN_FILES_ROOT",
    "MERGEN_FILES_ROOT",
    ""
  )

  mcp_base_dir <- vm_preflight_resolve_configured_path(
    "MERGEN_MCP_BASE_DIR",
    "MERGEN_MCP_BASE_DIR",
    ""
  )

  index_path <- vm_preflight_resolve_configured_path(
    "MERGEN_INDEX_PATH",
    "MERGEN_INDEX_PATH",
    ""
  )

  checked <- list(
    active_log_dir = vm_preflight_check_writable_dir(active_log_dir, "aktif log dizini"),
    destek_uploads_dir = vm_preflight_check_writable_dir("destek_uploads", "destek yükleme dizini"),
    bilge_yolac_downloads_dir = vm_preflight_check_writable_dir(
      "bilge_yolac_downloads",
      "Bilge Yolaç indirme dizini"
    )
  )

  if (nzchar(files_root)) {
    checked$files_root <- vm_preflight_check_writable_dir(files_root, "MERGEN files root")
  }

  mcp_base_ok <- FALSE
  if (nzchar(mcp_base_dir)) {
    checked$mcp_base_dir <- vm_preflight_check_writable_dir(mcp_base_dir, "MERGEN MCP base dir")
    mcp_base_ok <- TRUE
  }

  uploads_check <- tryCatch(
    vm_preflight_check_writable_dir(uploads_dir, "MERGEN yükleme dizini"),
    error = function(e) e
  )

  if (inherits(uploads_check, "error")) {
    if (isTRUE(mcp_base_ok)) {
      warning(sprintf(
        paste(
          "MERGEN_UPLOADS_DIR yazılabilir değil ancak MERGEN_MCP_BASE_DIR yazılabilir.",
          "Üretim dosya roundtrip kontrolü MCP tabanı üzerinden devam edecek.",
          "Atlanan fallback dizin: %s",
          "Hata: %s"
        ),
        uploads_dir,
        conditionMessage(uploads_check)
      ), call. = FALSE)
    } else {
      stop(conditionMessage(uploads_check), call. = FALSE)
    }
  } else {
    checked$uploads_dir <- uploads_check
  }

  if (nzchar(index_path)) {
    checked$index_parent_dir <- vm_preflight_check_writable_dir(
      dirname(index_path),
      "MERGEN index parent dizini"
    )
  }

  invisible(checked)
}

vm_preflight_check_atomic_write_probe <- function(active_log_dir) {
  if (!exists("atomic_write_text", envir = globalenv(), mode = "function", inherits = TRUE)) {
    warning("atomic_write_text() bulunamadı; atomic write probe atlandı.")
    return(invisible(FALSE))
  }

  atomic_write_text_fn <- get("atomic_write_text", envir = globalenv(), inherits = TRUE)
  atomic_probe <- file.path(active_log_dir, "preflight_atomic_write_probe.json")

  tryCatch({
    atomic_write_text_fn('{"ok":true}', atomic_probe)
    if (!file.exists(atomic_probe)) {
      stop("atomic write probe dosyasi olusmadi.")
    }
    cat("OK: atomic_write_text probe başarılı.\n")
  }, error = function(e) {
    vm_preflight_stop(sprintf(
      "VM preflight başarısız: atomic_write_text probe başarısız: %s",
      conditionMessage(e)
    ))
  }, finally = {
    try(unlink(atomic_probe, force = TRUE), silent = TRUE)
  })

  invisible(TRUE)
}

vm_preflight_check_utf8_roundtrip <- function(active_log_dir) {
  probe_text <- enc2utf8("Türkçe UTF-8 probe: ğüşİÖÇ — Şablon_İzleç.xlsx")
  probe_file <- file.path(
    active_log_dir,
    sprintf(".preflight_utf8_probe_%s.txt", as.integer(Sys.time()))
  )

  tryCatch({
    writeBin(charToRaw(probe_text), probe_file)
    size <- file.info(probe_file)$size[1]

    if (is.na(size) || size <= 0) {
      stop("UTF-8 probe dosyası boş oluştu.")
    }

    raw_data <- readBin(probe_file, what = "raw", n = size)
    read_back <- rawToChar(raw_data, multiple = FALSE)
    Encoding(read_back) <- "UTF-8"
    read_back <- enc2utf8(read_back)

    if (!identical(read_back, probe_text)) {
      stop(sprintf(
        "UTF-8 roundtrip uyuşmadı. Beklenen='%s', Okunan='%s'",
        probe_text,
        read_back
      ))
    }

    cat("OK: UTF-8 dosya yaz/oku roundtrip başarılı.\n")
  }, error = function(e) {
    vm_preflight_stop(sprintf(
      "VM preflight başarısız: UTF-8 roundtrip başarısız: %s",
      conditionMessage(e)
    ))
  }, finally = {
    try(unlink(probe_file, force = TRUE), silent = TRUE)
  })

  invisible(TRUE)
}

vm_preflight_check_file_store_roundtrip <- function(user_id = 999999001L,
                                                    original_name = "Türkçe_İsim_Şablon.xlsx") {
  vm_preflight_required_functions(
    c(
      "mergen_register_uploaded_file",
      "mergen_list_user_files",
      "resolve_uploaded_file",
      "mergen_remove_from_index"
    ),
    label = "File Store roundtrip preflight"
  )

  source_dir <- file.path(
    tempdir(),
    sprintf("mergen_preflight_upload_%s", format(Sys.time(), "%Y%m%d%H%M%S"))
  )

  dir.create(source_dir, recursive = TRUE, showWarnings = FALSE)

  source_path <- file.path(source_dir, original_name)
  registered_path <- NULL

  cleanup <- function() {
    try(mergen_remove_from_index(user_id, original_name), silent = TRUE)

    if (!is.null(registered_path) && nzchar(as.character(registered_path))) {
      try(unlink(registered_path, force = TRUE), silent = TRUE)
    }

    try(unlink(source_dir, recursive = TRUE, force = TRUE), silent = TRUE)
  }

  on.exit(cleanup(), add = TRUE)

  tryCatch({
    writeBin(
      charToRaw(enc2utf8("MERGEN VM preflight file store probe\nTürkçe: ğüşİÖÇ\n")),
      source_path
    )

    if (!file.exists(source_path)) {
      stop(sprintf("Probe kaynak dosyası oluşturulamadı: %s", source_path))
    }

    registered_path <- mergen_register_uploaded_file(
      src_path = source_path,
      as_name = original_name,
      user_id = user_id,
      persist_under_mcp_base = TRUE
    )

    if (!vm_preflight_path_exists(registered_path)) {
      stop(sprintf("Kayıtlı dosya fiziksel olarak bulunamadı: %s", registered_path))
    }

    listed <- mergen_list_user_files(user_id, prune_missing = FALSE)

    if (!is.data.frame(listed) || !all(c("path", "name") %in% names(listed))) {
      stop("mergen_list_user_files() path/name kolonlarını içeren data.frame döndürmedi.")
    }

    listed_names <- enc2utf8(as.character(listed$name))
    if (!original_name %in% listed_names) {
      stop(sprintf(
        "Kullanıcı dosya listesinde özgün görünen ad bulunamadı. Beklenen=%s, Gelen=%s",
        original_name,
        paste(listed_names, collapse = ", ")
      ))
    }

    matched <- listed[listed_names == original_name, , drop = FALSE]
    matched_path <- as.character(matched$path[1])

    if (!vm_preflight_path_exists(matched_path)) {
      stop(sprintf("Listelenen dosya yolu bulunamadı: %s", matched_path))
    }

    resolved_path <- resolve_uploaded_file(original_name, user_id = user_id)

    if (is.null(resolved_path) || !vm_preflight_path_exists(resolved_path)) {
      stop(sprintf("resolve_uploaded_file() özgün adla dosyayı çözemedi: %s", original_name))
    }

    registered_cmp <- vm_preflight_normalize_for_compare(registered_path)
    resolved_cmp <- vm_preflight_normalize_for_compare(resolved_path)

    if (!identical(registered_cmp, resolved_cmp)) {
      stop(sprintf(
        "resolve_uploaded_file() farklı path döndürdü. registered=%s, resolved=%s",
        registered_path,
        resolved_path
      ))
    }

    cat(sprintf(
      "OK: File Store roundtrip başarılı. user_id=%s, display=%s\n",
      as.character(user_id),
      original_name
    ))
  }, error = function(e) {
    vm_preflight_stop(sprintf(
      "VM preflight başarısız: File Store roundtrip başarısız: %s",
      conditionMessage(e)
    ))
  })

  invisible(TRUE)
}

vm_preflight_check_live_user_id_provider_contract <- function() {
  vm_preflight_required_functions(
    c(
      "make_current_user_id_provider",
      "resolve_effective_user_id"
    ),
    label = "Live user id provider preflight"
  )

  fake_session <- new.env(parent = emptyenv())
  fake_session$userData <- new.env(parent = emptyenv())

  current_user_id <- 0L

  provider_bundle <- make_current_user_id_provider(
    session = fake_session,
    current_user_id_ref = function() current_user_id
  )

  if (!is.list(provider_bundle) ||
      !is.function(provider_bundle$current_user_id_provider)) {
    vm_preflight_stop(
      "VM preflight başarısız: make_current_user_id_provider geçerli provider döndürmedi."
    )
  }

  assert_provider_value <- function(expected, label) {
    actual <- provider_bundle$current_user_id_provider()

    if (!identical(as.integer(actual), as.integer(expected))) {
      vm_preflight_stop(sprintf(
        "VM preflight başarısız: live user id provider kontratı bozuldu [%s]. Beklenen=%s, Gelen=%s",
        label,
        as.character(expected),
        as.character(actual)
      ))
    }
  }

  assert_provider_value(0L, "başlangıç placeholder")

  current_user_id <- 123L
  assert_provider_value(123L, "canlı fallback güncellemesi")

  fake_session$userData$user_id <- 456L
  assert_provider_value(456L, "session$userData önceliği")

  fake_session$userData$user_id <- 0L
  current_user_id <- 789L
  assert_provider_value(789L, "session placeholder sonrası canlı fallback")

  cat("OK: Live current_user_id provider kontratı başarılı.\n")
  invisible(TRUE)
}