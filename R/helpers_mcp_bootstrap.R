# ==============================================================================
# Dosya Yolu: R/helpers_mcp_bootstrap.R
# Açıklama: MCP araç ortamı için manifest tabanlı erken bootstrap yardımcıları.
#           Bu dosya yalnızca helpers_mcp_tools ortamını ve yol fallback
#           fonksiyonlarını hazırlar; downstream MCP helper dosyalarını source etmez.
# ==============================================================================

if (!exists("helpers_mcp_tools", envir = globalenv(), inherits = FALSE) ||
    !is.environment(get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE))) {
  stop(
    "MCP helper ortamı başlatılamadı. R/helpers_mcp_context.R önce manifestten yüklenmelidir.",
    call. = FALSE
  )
}

helpers_mcp_tools <- get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)

.mcp_bootstrap_has_tool_function <- function(name) {
  exists(name, envir = helpers_mcp_tools, inherits = FALSE) &&
    is.function(get(name, envir = helpers_mcp_tools, inherits = FALSE))
}

.mcp_bootstrap_assign_global_function <- function(name) {
  if (exists(name, envir = globalenv(), inherits = TRUE) &&
      is.function(get(name, envir = globalenv(), inherits = TRUE))) {
    assign(
      name,
      get(name, envir = globalenv(), inherits = TRUE),
      envir = helpers_mcp_tools
    )
  }

  invisible(TRUE)
}

.mcp_bootstrap_require_tool_functions <- function(required_functions, label) {
  missing_functions <- required_functions[!vapply(
    required_functions,
    .mcp_bootstrap_has_tool_function,
    logical(1)
  )]

  if (length(missing_functions) > 0L) {
    stop(
      sprintf(
        "%s sözleşmesi eksik. Manifest sırası bozuk olabilir. Eksik: %s",
        label,
        paste(missing_functions, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

# ------------------------------------------------------------------------------
# MCP context sözleşmesi
# ------------------------------------------------------------------------------
.mcp_bootstrap_require_tool_functions(
  c("mcp_debug_log", "get_session_user_id"),
  "MCP context helper"
)

# ------------------------------------------------------------------------------
# Yol yardımcıları
# ------------------------------------------------------------------------------
.mcp_bootstrap_assign_global_function("path_exists_relaxed")
.mcp_bootstrap_assign_global_function("normalize_excel_path")
.mcp_bootstrap_assign_global_function("resolve_readable_path")

if (!.mcp_bootstrap_has_tool_function("path_exists_relaxed")) {
  helpers_mcp_tools$path_exists_relaxed <- function(path) {
    if (is.null(path) || length(path) == 0L) {
      return(FALSE)
    }

    candidate <- as.character(path[1])
    if (is.na(candidate) || !nzchar(candidate)) {
      return(FALSE)
    }

    cand_slash <- gsub("\\\\", "/", candidate, fixed = TRUE)

    raw_variants <- c(
      candidate,
      cand_slash,
      sub("^//\\?/UNC", "//", cand_slash, perl = TRUE),
      sub("^//\\?/", "//", cand_slash, perl = TRUE),
      if (grepl("^/[^/]", cand_slash)) paste0("/", cand_slash) else NULL,
      gsub("/", "\\\\", cand_slash, fixed = TRUE)
    )

    raw_variants <- raw_variants[!is.na(raw_variants) & nzchar(raw_variants)]
    variants <- unique(trimws(raw_variants))
    fs_available <- requireNamespace("fs", quietly = TRUE)

    for (chk in variants) {
      if (tryCatch(isTRUE(file.exists(chk)), error = function(e) FALSE)) {
        return(TRUE)
      }

      if (isTRUE(fs_available) &&
          tryCatch(isTRUE(fs::file_exists(chk)), error = function(e) FALSE)) {
        return(TRUE)
      }

      chk_utf8 <- tryCatch(enc2utf8(chk), error = function(e) chk)

      if (tryCatch(isTRUE(file.exists(chk_utf8)), error = function(e) FALSE)) {
        return(TRUE)
      }

      if (isTRUE(fs_available) &&
          tryCatch(isTRUE(fs::file_exists(chk_utf8)), error = function(e) FALSE)) {
        return(TRUE)
      }
    }

    FALSE
  }
}

if (!.mcp_bootstrap_has_tool_function("resolve_readable_path")) {
  helpers_mcp_tools$resolve_readable_path <- function(path) {
    if (is.null(path) || length(path) == 0L) {
      return(path)
    }

    p <- as.character(path[1])
    if (is.na(p) || !nzchar(p)) {
      return(p)
    }

    if (tryCatch(isTRUE(file.exists(p)), error = function(e) FALSE)) {
      return(p)
    }

    p_bs <- gsub("/", "\\\\", p, fixed = TRUE)
    if (tryCatch(isTRUE(file.exists(p_bs)), error = function(e) FALSE)) {
      return(p_bs)
    }

    p_fwd <- gsub("\\\\", "/", p, fixed = TRUE)
    if (grepl("^/[^/]", p_fwd)) {
      p_unc <- paste0("/", p_fwd)
      if (tryCatch(isTRUE(file.exists(p_unc)), error = function(e) FALSE)) {
        return(p_unc)
      }

      p_unc_bs <- gsub("/", "\\\\", p_unc, fixed = TRUE)
      if (tryCatch(isTRUE(file.exists(p_unc_bs)), error = function(e) FALSE)) {
        return(p_unc_bs)
      }
    }

    p
  }
}

if (!.mcp_bootstrap_has_tool_function("normalize_excel_path")) {
  helpers_mcp_tools$normalize_excel_path <- function(path, must_exist = FALSE) {
    if (is.null(path) || length(path) == 0L) {
      return("")
    }

    p <- as.character(path[1])
    if (is.na(p) || !nzchar(p)) {
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

.mcp_bootstrap_require_tool_functions(
  c("path_exists_relaxed", "normalize_excel_path", "resolve_readable_path"),
  "MCP yol helper"
)

# ------------------------------------------------------------------------------
# Erken bootstrap hazır mı?
# ------------------------------------------------------------------------------
mcp_tools_bootstrap_core_ready <- function() {
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
    "resolve_readable_path"
  )

  all(vapply(required_functions, function(fn) {
    exists(fn, envir = tools_env, inherits = FALSE) &&
      is.function(get(fn, envir = tools_env, inherits = FALSE))
  }, logical(1)))
}

# ------------------------------------------------------------------------------
# Nihai MCP sözleşmesi.
# Bu fonksiyon bootstrap source edilirken TRUE olmak zorunda değildir.
# R/helpers_mcp_tools.R yüklendiğinde, manifest sırası gereği downstream helper'lar
# artık yüklenmiş olacağı için TRUE olmalıdır.
# ------------------------------------------------------------------------------
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

if (!isTRUE(mcp_tools_bootstrap_core_ready())) {
  stop("MCP bootstrap çekirdek sözleşmesi eksik.", call. = FALSE)
}

rm(
  .mcp_bootstrap_assign_global_function,
  .mcp_bootstrap_has_tool_function,
  .mcp_bootstrap_require_tool_functions
)