# ==============================================================================
# Dosya Yolu: R/helpers_mcp_bootstrap.R
# Açıklama: MCP araç ortamı için destek dosyası yükleme, yol fallback ve
#           sözleşme doğrulama yardımcılarını toplar.
# ==============================================================================

mcp_tools_find_support_file <- function(relative_path) {
  relative_path <- gsub("\\\\", "/", relative_path, fixed = TRUE)

  candidate_roots <- c(
    getwd(),
    dirname(getwd()),
    dirname(dirname(getwd())),
    Sys.getenv("MERGEN_REPO_ROOT", unset = ""),
    if (exists("repo_root_for_tests", envir = globalenv(), inherits = TRUE)) {
      get("repo_root_for_tests", envir = globalenv(), inherits = TRUE)
    } else {
      ""
    }
  )

  candidate_roots <- unique(candidate_roots[nzchar(candidate_roots)])

  candidates <- unique(c(
    relative_path,
    file.path(candidate_roots, relative_path)
  ))

  for (candidate in candidates) {
    candidate <- tryCatch(
      normalizePath(candidate, winslash = "/", mustWork = FALSE),
      error = function(e) candidate
    )

    if (file.exists(candidate)) {
      return(candidate)
    }
  }

  ""
}

.mcp_context_ready <- FALSE
if (exists("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)) {
  helpers_mcp_tools <- get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)
  .mcp_context_ready <- is.environment(helpers_mcp_tools) &&
    exists("mcp_debug_log", envir = helpers_mcp_tools, inherits = FALSE) &&
    exists("get_session_user_id", envir = helpers_mcp_tools, inherits = FALSE)
}

if (!isTRUE(.mcp_context_ready)) {
  .mcp_context_path <- mcp_tools_find_support_file("R/helpers_mcp_context.R")

  if (!nzchar(.mcp_context_path)) {
    stop(
      sprintf(
        "R/helpers_mcp_context.R bulunamadı; helpers_mcp_bootstrap.R yüklenemiyor. Çalışma dizini: %s",
        getwd()
      ),
      call. = FALSE
    )
  }

  source(.mcp_context_path, encoding = "UTF-8", local = globalenv())
}

if (!exists("helpers_mcp_tools", envir = globalenv(), inherits = FALSE) ||
    !is.environment(get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE))) {
  stop("MCP helper ortamı başlatılamadı.", call. = FALSE)
}

helpers_mcp_tools <- get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)

if (!exists("mcp_debug_log", envir = helpers_mcp_tools, inherits = FALSE) ||
    !exists("get_session_user_id", envir = helpers_mcp_tools, inherits = FALSE)) {
  stop("MCP context helper sözleşmesi eksik.", call. = FALSE)
}

rm(.mcp_context_ready)

if (exists("path_exists_relaxed", envir = globalenv(), inherits = TRUE)) {
  assign(
    "path_exists_relaxed",
    get("path_exists_relaxed", envir = globalenv(), inherits = TRUE),
    envir = helpers_mcp_tools
  )
}

if (!exists("path_exists_relaxed", envir = helpers_mcp_tools, inherits = FALSE)) {
  if (exists("path_exists_relaxed", envir = globalenv(), inherits = TRUE)) {
    assign(
      "path_exists_relaxed",
      get("path_exists_relaxed", envir = globalenv(), inherits = TRUE),
      envir = helpers_mcp_tools
    )
  }
}

if (!exists("path_exists_relaxed", envir = helpers_mcp_tools, inherits = FALSE)) {
  helpers_mcp_tools$path_exists_relaxed <- function(path) {
    if (is.null(path) || length(path) == 0) return(FALSE)

    candidate <- as.character(path[1])
    if (!nzchar(candidate)) return(FALSE)

    cand_slash <- gsub("\\\\", "/", candidate, fixed = TRUE)

    variants <- unique(trimws(Filter(nzchar, c(
      candidate,
      cand_slash,
      sub("^//\\?/UNC", "//", cand_slash, perl = TRUE),
      sub("^//\\?/", "//", cand_slash, perl = TRUE),
      if (grepl("^/[^/]", cand_slash)) paste0("/", cand_slash) else NULL,
      gsub("/", "\\\\", cand_slash, fixed = TRUE)
    ))))

    for (chk in variants) {
      if (tryCatch(isTRUE(file.exists(chk)), error = function(e) FALSE)) return(TRUE)
      if (tryCatch(isTRUE(fs::file_exists(chk)), error = function(e) FALSE)) return(TRUE)

      chk_utf8 <- tryCatch(enc2utf8(chk), error = function(e) chk)
      if (tryCatch(isTRUE(file.exists(chk_utf8)), error = function(e) FALSE)) return(TRUE)
      if (tryCatch(isTRUE(fs::file_exists(chk_utf8)), error = function(e) FALSE)) return(TRUE)
    }

    FALSE
  }
}

if (exists("normalize_excel_path", envir = globalenv(), inherits = TRUE)) {
  assign(
    "normalize_excel_path",
    get("normalize_excel_path", envir = globalenv(), inherits = TRUE),
    envir = helpers_mcp_tools
  )
}

if (exists("resolve_readable_path", envir = globalenv(), inherits = TRUE)) {
  assign(
    "resolve_readable_path",
    get("resolve_readable_path", envir = globalenv(), inherits = TRUE),
    envir = helpers_mcp_tools
  )
}

if (!exists("resolve_readable_path", envir = helpers_mcp_tools, inherits = FALSE)) {
  helpers_mcp_tools$resolve_readable_path <- function(path) {
    if (is.null(path) || !nzchar(path)) return(path)

    p <- as.character(path[1])

    if (tryCatch(isTRUE(file.exists(p)), error = function(e) FALSE)) return(p)

    p_bs <- gsub("/", "\\\\", p, fixed = TRUE)
    if (tryCatch(isTRUE(file.exists(p_bs)), error = function(e) FALSE)) return(p_bs)

    p_fwd <- gsub("\\\\", "/", p, fixed = TRUE)
    if (grepl("^/[^/]", p_fwd)) {
      p_unc <- paste0("/", p_fwd)
      if (tryCatch(isTRUE(file.exists(p_unc)), error = function(e) FALSE)) return(p_unc)

      p_unc_bs <- gsub("/", "\\\\", p_unc, fixed = TRUE)
      if (tryCatch(isTRUE(file.exists(p_unc_bs)), error = function(e) FALSE)) return(p_unc_bs)
    }

    p
  }
}

if (!exists("normalize_excel_path", envir = helpers_mcp_tools, inherits = FALSE)) {
  helpers_mcp_tools$normalize_excel_path <- function(path, must_exist = FALSE) {
    if (is.null(path) || length(path) == 0L) {
      return("")
    }

    p <- as.character(path[1])
    if (!nzchar(p)) {
      return("")
    }

    p <- enc2utf8(gsub("\\\\", "/", p, fixed = TRUE))

    if (isTRUE(must_exist)) {
      resolved <- tryCatch(
        helpers_mcp_tools$resolve_readable_path(p),
        error = function(e) p
      )

      if (!isTRUE(helpers_mcp_tools$path_exists_relaxed(resolved))) {
        stop(sprintf("Dosya bulunamadı: %s", p), call. = FALSE)
      }

      p <- resolved
    }

    p
  }
}

if (!exists("safe_read_excel_table", envir = helpers_mcp_tools, inherits = FALSE) ||
    !exists("safe_read_table_generic", envir = helpers_mcp_tools, inherits = FALSE) ||
    !exists("create_md_table", envir = helpers_mcp_tools, inherits = FALSE)) {

  .mcp_table_readers_path <- mcp_tools_find_support_file("R/helpers_mcp_table_readers.R")

  if (!nzchar(.mcp_table_readers_path)) {
    stop(
      sprintf(
        "R/helpers_mcp_table_readers.R bulunamadı; helpers_mcp_bootstrap.R yüklenemiyor. Çalışma dizini: %s",
        getwd()
      ),
      call. = FALSE
    )
  }

  source(.mcp_table_readers_path, encoding = "UTF-8", local = globalenv())
}

if (!exists("safe_read_excel_table", envir = helpers_mcp_tools, inherits = FALSE) ||
    !is.function(helpers_mcp_tools$safe_read_excel_table) ||
    !exists("safe_read_table_generic", envir = helpers_mcp_tools, inherits = FALSE) ||
    !is.function(helpers_mcp_tools$safe_read_table_generic) ||
    !exists("create_md_table", envir = helpers_mcp_tools, inherits = FALSE) ||
    !is.function(helpers_mcp_tools$create_md_table)) {
  stop("MCP tablo okuyucu sözleşmesi eksik.", call. = FALSE)
}

if (!exists("ensure_session_file_registry", envir = helpers_mcp_tools, inherits = FALSE) ||
    !exists("register_uploaded_file", envir = helpers_mcp_tools, inherits = FALSE) ||
    !exists("resolve_file_argument", envir = helpers_mcp_tools, inherits = FALSE)) {

  .mcp_file_resolver_path <- mcp_tools_find_support_file("R/helpers_mcp_file_resolver.R")

  if (!nzchar(.mcp_file_resolver_path)) {
    stop(
      sprintf(
        "R/helpers_mcp_file_resolver.R bulunamadı; helpers_mcp_bootstrap.R yüklenemiyor. Çalışma dizini: %s",
        getwd()
      ),
      call. = FALSE
    )
  }

  source(.mcp_file_resolver_path, encoding = "UTF-8", local = globalenv())
}

if (!exists("ensure_session_file_registry", envir = helpers_mcp_tools, inherits = FALSE) ||
    !is.function(helpers_mcp_tools$ensure_session_file_registry) ||
    !exists("register_uploaded_file", envir = helpers_mcp_tools, inherits = FALSE) ||
    !is.function(helpers_mcp_tools$register_uploaded_file) ||
    !exists("resolve_file_argument", envir = helpers_mcp_tools, inherits = FALSE) ||
    !is.function(helpers_mcp_tools$resolve_file_argument)) {
  stop("MCP dosya çözümleyici sözleşmesi eksik.", call. = FALSE)
}

if (!exists("extract_mcp_file_schema", envir = helpers_mcp_tools, inherits = FALSE) ||
    !exists("find_matching_column", envir = helpers_mcp_tools, inherits = FALSE) ||
    !exists("normalize_args", envir = helpers_mcp_tools, inherits = FALSE) ||
    !exists("normalize_chart_type", envir = helpers_mcp_tools, inherits = FALSE) ||
    !exists("prettify_column_name", envir = helpers_mcp_tools, inherits = FALSE)) {

  .mcp_schema_helpers_path <- mcp_tools_find_support_file("R/helpers_mcp_schema_helpers.R")

  if (!nzchar(.mcp_schema_helpers_path)) {
    stop(
      sprintf(
        "R/helpers_mcp_schema_helpers.R bulunamadı; helpers_mcp_bootstrap.R yüklenemiyor. Çalışma dizini: %s",
        getwd()
      ),
      call. = FALSE
    )
  }

  source(.mcp_schema_helpers_path, encoding = "UTF-8", local = globalenv())
}

if (!exists("extract_mcp_file_schema", envir = helpers_mcp_tools, inherits = FALSE) ||
    !is.function(helpers_mcp_tools$extract_mcp_file_schema) ||
    !exists("find_matching_column", envir = helpers_mcp_tools, inherits = FALSE) ||
    !is.function(helpers_mcp_tools$find_matching_column) ||
    !exists("normalize_args", envir = helpers_mcp_tools, inherits = FALSE) ||
    !is.function(helpers_mcp_tools$normalize_args) ||
    !exists("normalize_chart_type", envir = helpers_mcp_tools, inherits = FALSE) ||
    !is.function(helpers_mcp_tools$normalize_chart_type) ||
    !exists("prettify_column_name", envir = helpers_mcp_tools, inherits = FALSE) ||
    !is.function(helpers_mcp_tools$prettify_column_name)) {
  stop("MCP şema/kolon helper sözleşmesi eksik.", call. = FALSE)
}

if (exists(".mcp_table_readers_path", inherits = FALSE)) {
  rm(.mcp_table_readers_path)
}

if (exists(".mcp_file_resolver_path", inherits = FALSE)) {
  rm(.mcp_file_resolver_path)
}

if (exists(".mcp_schema_helpers_path", inherits = FALSE)) {
  rm(.mcp_schema_helpers_path)
}

if (!exists("analyze_uploaded_file", envir = helpers_mcp_tools, inherits = FALSE) ||
    !exists("get_column_statistics", envir = helpers_mcp_tools, inherits = FALSE) ||
    !exists("sql_query_uploaded_file", envir = helpers_mcp_tools, inherits = FALSE) ||
    !exists("safe_has_duckdb", envir = helpers_mcp_tools, inherits = FALSE)) {

  .mcp_basic_tools_path <- mcp_tools_find_support_file("R/helpers_mcp_basic_tools.R")

  if (!nzchar(.mcp_basic_tools_path)) {
    stop(
      sprintf(
        "R/helpers_mcp_basic_tools.R bulunamadı; helpers_mcp_bootstrap.R yüklenemiyor. Çalışma dizini: %s",
        getwd()
      ),
      call. = FALSE
    )
  }

  source(.mcp_basic_tools_path, encoding = "UTF-8", local = globalenv())
}

if (!exists("analyze_uploaded_file", envir = helpers_mcp_tools, inherits = FALSE) ||
    !is.function(helpers_mcp_tools$analyze_uploaded_file) ||
    !exists("get_column_statistics", envir = helpers_mcp_tools, inherits = FALSE) ||
    !is.function(helpers_mcp_tools$get_column_statistics) ||
    !exists("sql_query_uploaded_file", envir = helpers_mcp_tools, inherits = FALSE) ||
    !is.function(helpers_mcp_tools$sql_query_uploaded_file) ||
    !exists("safe_has_duckdb", envir = helpers_mcp_tools, inherits = FALSE) ||
    !is.function(helpers_mcp_tools$safe_has_duckdb)) {
  stop("MCP temel araç sözleşmesi eksik.", call. = FALSE)
}

if (exists(".mcp_basic_tools_path", inherits = FALSE)) {
  rm(.mcp_basic_tools_path)
}

if (!exists("prepare_chart_data", envir = helpers_mcp_tools, inherits = FALSE)) {
  .mcp_chart_tools_path <- mcp_tools_find_support_file("R/helpers_mcp_chart_tools.R")

  if (!nzchar(.mcp_chart_tools_path)) {
    stop(
      sprintf(
        "R/helpers_mcp_chart_tools.R bulunamadı; helpers_mcp_bootstrap.R yüklenemiyor. Çalışma dizini: %s",
        getwd()
      ),
      call. = FALSE
    )
  }

  source(.mcp_chart_tools_path, encoding = "UTF-8", local = globalenv())
}

if (!exists("prepare_chart_data", envir = helpers_mcp_tools, inherits = FALSE) ||
    !is.function(helpers_mcp_tools$prepare_chart_data)) {
  stop("MCP grafik aracı sözleşmesi eksik.", call. = FALSE)
}

if (exists(".mcp_chart_tools_path", inherits = FALSE)) {
  rm(.mcp_chart_tools_path)
}

if (!exists("analyze_and_visualize", envir = helpers_mcp_tools, inherits = FALSE)) {
  .mcp_analyze_visualize_path <- mcp_tools_find_support_file("R/helpers_mcp_analyze_visualize.R")

  if (!nzchar(.mcp_analyze_visualize_path)) {
    stop(
      sprintf(
        "R/helpers_mcp_analyze_visualize.R bulunamadı; helpers_mcp_bootstrap.R yüklenemiyor. Çalışma dizini: %s",
        getwd()
      ),
      call. = FALSE
    )
  }

  source(.mcp_analyze_visualize_path, encoding = "UTF-8", local = globalenv())
}

if (!exists("analyze_and_visualize", envir = helpers_mcp_tools, inherits = FALSE) ||
    !is.function(helpers_mcp_tools$analyze_and_visualize)) {
  stop("MCP analyze/visualize aracı sözleşmesi eksik.", call. = FALSE)
}

if (exists(".mcp_analyze_visualize_path", inherits = FALSE)) {
  rm(.mcp_analyze_visualize_path)
}

mcp_tools_bootstrap_ready <- function() {
  if (!exists("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)) {
    return(FALSE)
  }

  tools_env <- get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)
  if (!is.environment(tools_env)) {
    return(FALSE)
  }

  required_functions <- c(
    "mcp_debug_log",
    "get_session_user_id",
    "path_exists_relaxed",
    "normalize_excel_path",
    "resolve_readable_path",
    "safe_read_excel_table",
    "safe_read_table_generic",
    "create_md_table",
    "ensure_session_file_registry",
    "register_uploaded_file",
    "resolve_file_argument",
    "extract_mcp_file_schema",
    "find_matching_column",
    "normalize_args",
    "normalize_chart_type",
    "prettify_column_name",
    "analyze_uploaded_file",
    "get_column_statistics",
    "sql_query_uploaded_file",
    "safe_has_duckdb",
    "prepare_chart_data",
    "analyze_and_visualize"
  )

  all(vapply(required_functions, function(fn) {
    exists(fn, envir = tools_env, inherits = FALSE) &&
      is.function(get(fn, envir = tools_env, inherits = FALSE))
  }, logical(1)))
}

if (!isTRUE(mcp_tools_bootstrap_ready())) {
  stop("MCP bootstrap sözleşmesi eksik.", call. = FALSE)
}