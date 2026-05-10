# ==============================================================================
# Dosya Yolu: tests/testthat/helper_source_manifest_contract.R
# Açıklama: Manifest tabanlı source-order test yardımcıları.
#           global.R artık dev safe_source listesi taşımadığı için source-order
#           sözleşmeleri R/config_source_manifest.R üzerinden okunmalıdır.
# ==============================================================================

source_manifest_contract_repo_root <- function() {
  if (exists("resolve_repo_root_for_tests", mode = "function")) {
    return(resolve_repo_root_for_tests())
  }

  candidates <- unique(normalizePath(
    c(
      getwd(),
      file.path(getwd(), ".."),
      file.path(getwd(), "..", "..")
    ),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "R")) &&
        dir.exists(file.path(candidate, "tests", "testthat"))) {
      return(candidate)
    }
  }

  stop("Manifest test helper repo kökünü bulamadı.", call. = FALSE)
}

source_manifest_paths_for_tests <- function() {
  repo_root <- source_manifest_contract_repo_root()
  manifest_env <- new.env(parent = globalenv())

  source(
    file.path(repo_root, "R", "config_source_manifest.R"),
    encoding = "UTF-8",
    local = manifest_env
  )

  if (!exists("source_manifest_runtime_paths", envir = manifest_env, inherits = FALSE)) {
    stop(
      "Test manifesti source_manifest_runtime_paths nesnesini bulamadı.",
      call. = FALSE
    )
  }

  paths <- get("source_manifest_runtime_paths", envir = manifest_env, inherits = FALSE)

  if (!is.character(paths) || length(paths) == 0L) {
    stop("Test manifesti boş veya geçersiz.", call. = FALSE)
  }

  enc2utf8(paths)
}

expect_source_manifest_contains_for_tests <- function(required_paths,
                                                     paths = source_manifest_paths_for_tests(),
                                                     label = "Manifest içinde eksik kaynak kayıtları:") {
  positions <- match(required_paths, paths)

  testthat::expect_false(
    any(is.na(positions)),
    info = paste(
      label,
      paste(required_paths[is.na(positions)], collapse = ", ")
    )
  )

  invisible(positions)
}

expect_source_manifest_order_for_tests <- function(expected_order,
                                                   paths = source_manifest_paths_for_tests(),
                                                   label = "Manifest source sırası bozulmuş:") {
  positions <- match(expected_order, paths)

  testthat::expect_false(
    any(is.na(positions)),
    info = paste(
      "Manifest içinde eksik kaynak kayıtları:",
      paste(expected_order[is.na(positions)], collapse = ", ")
    )
  )

  testthat::expect_true(
    all(diff(positions) > 0L),
    info = paste(
      label,
      paste(expected_order, collapse = " -> ")
    )
  )

  invisible(positions)
}