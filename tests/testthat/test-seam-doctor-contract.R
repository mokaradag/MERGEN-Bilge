# ==============================================================================
# Dosya Yolu: tests/testthat/test-seam-doctor-contract.R
# Açıklama: tests/scripts/seam_doctor.R betiğinin hafif, secret-güvenli ve
#           source(...)-güvenli kalmasını korur. Doctor artifact'i kanıt
#           kapısı DEĞİLDİR; kanıt kapıları seam/bölge sözleşme testleridir.
# ==============================================================================

.seam_doctor_repo_root <- function() {
  candidates <- unique(normalizePath(
    c(getwd(), file.path(getwd(), ".."), file.path(getwd(), "..", "..")),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "tests", "scripts"))) {
      return(candidate)
    }
  }

  stop("Seam doctor contract repo kökü bulunamadı.", call. = FALSE)
}

.seam_doctor_read_text <- function(...) {
  path <- file.path(.seam_doctor_repo_root(), ...)

  if (!file.exists(path)) {
    stop(sprintf("Beklenen dosya bulunamadı: %s", path), call. = FALSE)
  }

  size <- suppressWarnings(file.info(path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  enc2utf8(gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE))
}

testthat::test_that("seam doctor hafif, secret-güvenli ve source-güvenli kalır", {
  doctor <- .seam_doctor_read_text("tests", "scripts", "seam_doctor.R")

  required_tokens <- c(
    "Dosya Yolu: tests/scripts/seam_doctor.R",
    "R/config_source_manifest.R",
    "R/config_ui_assets.R",
    "R/config_ui_asset_zones.R",
    "R/config_ui_asset_zone_validators.R",
    "R/config_seam_guard_tests.R",
    "R/config_seam_registry.R",
    "mergen_seam_registry_validate",
    "ui_asset_zones_validate",
    "ui_asset_frontend_ownership_gaps",
    "artifacts", # artifact kök klasörü
    "seam-doctor",
    "doctor_runs_heavy_checks",
    "doctor_runs_runtime",
    "doctor_runs_browser",
    "doctor_runs_database",
    "not_run_by_seam_doctor",
    "SEAM_DOCTOR_RESULT"
  )

  missing_tokens <- required_tokens[!vapply(
    required_tokens,
    function(token) grepl(token, doctor, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  testthat::expect_equal(
    missing_tokens,
    character(0),
    info = paste("Seam doctor sözleşme tokenları eksik:", paste(missing_tokens, collapse = ", "))
  )

  # Yorum satırları çıkarılır; yasak desenler yalnızca çalıştırılabilir kodda
  # aranır ki açıklayıcı yorumlar yanlış pozitif üretmesin.
  doctor_code <- gsub("(?m)^\\s*#.*$", "", doctor, perl = TRUE)

  forbidden_tokens <- c(
    "quit(",
    "install.packages(",
    "download.file(",
    "shiny::runApp",
    "processx::",
    "dbConnect",
    "Sys.setenv("
  )

  found_forbidden <- forbidden_tokens[vapply(
    forbidden_tokens,
    function(token) grepl(token, doctor_code, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  testthat::expect_equal(
    found_forbidden,
    character(0),
    info = paste(
      "Seam doctor hafif kalmalıdır; yasak desen bulundu:",
      paste(found_forbidden, collapse = ", ")
    )
  )
})

testthat::test_that("seam doctor gerçek repoda sorunsuz çalışır ve artifact üretir", {
  repo_root <- .seam_doctor_repo_root()

  artifact_dir <- file.path(tempdir(), sprintf("seam-doctor-test-%d", as.integer(Sys.time()) %% 100000L))
  on.exit(unlink(artifact_dir, recursive = TRUE, force = TRUE), add = TRUE)

  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  # Betik options(warn = 1) ayarlar; strict suite (stop_on_warning) için
  # global uyarı seviyesi test sonunda geri yüklenir.
  old_warn <- getOption("warn")
  on.exit(options(warn = old_warn), add = TRUE)

  # Betik argümanları commandArgs ile okur; testte doğrudan ortamda çalıştırıp
  # varsayılan artifact yerine geçici dizine yazdırmak için args taklit edilir.
  doctor_env <- new.env(parent = globalenv())
  assign(
    "commandArgs",
    function(trailingOnly = TRUE) c("--artifact-dir", artifact_dir),
    envir = doctor_env
  )

  doctor_ok <- tryCatch(
    {
      source(
        file.path(repo_root, "tests", "scripts", "seam_doctor.R"),
        encoding = "UTF-8",
        local = doctor_env
      )
      TRUE
    },
    error = function(e) {
      testthat::fail(sprintf("Seam doctor hata verdi: %s", conditionMessage(e)))
      FALSE
    }
  )

  testthat::expect_true(doctor_ok)

  artifacts <- list.files(artifact_dir, pattern = "^seam-doctor-.*\\.json$", full.names = TRUE)

  testthat::expect_true(
    length(artifacts) >= 1L,
    info = "Seam doctor JSON artifact üretmelidir."
  )

  artifact_text <- paste(readLines(artifacts[[1]], warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  testthat::expect_true(
    grepl("\"problem_count\": 0", artifact_text, fixed = TRUE),
    info = "Gerçek repoda seam doctor yapısal sorun bildirmemelidir."
  )

  testthat::expect_true(
    grepl("\"doctor_runs_heavy_checks\": false", artifact_text, fixed = TRUE),
    info = "Seam doctor artifact'i ağır kontrol çalıştırmadığını açıkça belirtmelidir."
  )
})
