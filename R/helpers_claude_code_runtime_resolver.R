# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_runtime_resolver.R
# Açıklama: Bilge Yolaç runtime çalışma dizini için relaxed kaynak dizin
#           çözümleme yardımcıları.
# ==============================================================================

# Runtime aynalama için mevcut dizini relaxed şekilde çözer
resolve_claude_runtime_source_dir <- function(workdir) {
  ham_yol <- as.character(workdir %||% "")[1]
  if (is.na(ham_yol) || !nzchar(ham_yol)) {
    return("")
  }

  if (exists("cc_resolve_existing_dir_relaxed", mode = "function", inherits = TRUE)) {
    relaxed <- tryCatch(
      cc_resolve_existing_dir_relaxed(ham_yol),
      error = function(e) ""
    )

    if (nzchar(relaxed)) {
      return(relaxed)
    }
  }

  yol_slash <- gsub("\\\\", "/", ham_yol, fixed = TRUE)

  adaylar <- unique(Filter(nzchar, c(
    ham_yol,
    yol_slash,
    enc2utf8(yol_slash),
    enc2native(yol_slash),
    if (grepl("^/[^/]", yol_slash) && !grepl("^//", yol_slash)) {
      paste0("/", yol_slash)
    } else {
      NULL
    },
    tryCatch(normalize_mcp_path(ham_yol, must_exist = FALSE), error = function(e) ""),
    tryCatch(normalize_mcp_path(yol_slash, must_exist = FALSE), error = function(e) "")
  )))

  for (aday in adaylar) {
    var_mi <- tryCatch(
      isTRUE(dir.exists(aday)) ||
        isTRUE(fs::dir_exists(aday)) ||
        isTRUE(path_exists_relaxed(aday)),
      error = function(e) FALSE
    )

    if (!isTRUE(var_mi)) next

    return(tryCatch(
      normalize_mcp_path(aday, must_exist = FALSE),
      error = function(e) aday
    ))
  }

  ""
}