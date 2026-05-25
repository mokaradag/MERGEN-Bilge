# ==============================================================================
# Dosya Yolu: tests/testthat/test-version-single-source-contract.R
# Açıklama: Sistem Durumu > Genel Bakış > Sürüm karti ile sidebar, Hakkında
#           ve karşılama ekranlarinin AYNI tek dogru sürüm kaynagindan
#           gelmesi sözleşmesini korur (config_version_history.R).
#
# Karsi koruma: helpers_health_runtime_checks.R icinde
#   version <- getOption("mergen.version", Sys.getenv("MERGEN_APP_VERSION", "N/A"))
# kullanmamali; bunun yerine get_app_version_label() / get_current_version()
# kullanmalidir. Aksi halde Sistem Durumu farkli versiyon gosterir.
# ==============================================================================

.repo_root_version_single <- function() {
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

  stop("Repo kökü bulunamadı.", call. = FALSE)
}

.read_version_file <- function(rel_path) {
  repo_root <- .repo_root_version_single()
  full_path <- file.path(repo_root, rel_path)
  if (!file.exists(full_path)) return("")
  txt <- paste(readLines(full_path, warn = FALSE, encoding = "UTF-8"),
               collapse = "\n")
  enc2utf8(txt)
}

test_that("Sistem Durumu Sürüm karti get_app_version_label kullanir", {
  txt <- .read_version_file("R/helpers_health_runtime_checks.R")
  expect_true(nzchar(txt), info = "R/helpers_health_runtime_checks.R okunamadi.")

  expect_true(
    grepl("get_app_version_label()", txt, fixed = TRUE),
    info = paste(
      "helpers_health_runtime_checks.R Sürüm degerini get_app_version_label()",
      "uzerinden okumalidir; bu, sidebar/Hakkında ile ayni tek dogru kaynaktir."
    )
  )
})

test_that("Sistem Durumu Sürüm karti getOption('mergen.version', ...) BIRINCIL kaynak olarak kullanmaz", {
  txt <- .read_version_file("R/helpers_health_runtime_checks.R")
  expect_true(nzchar(txt), info = "R/helpers_health_runtime_checks.R okunamadi.")

  # Eski regresyon: birincil kaynak olarak getOption('mergen.version', ...)
  # kullaniliyordu; bu degisken yoksa "N/A" gosteriliyordu ve sidebar'dan
  # farkli bir versiyon ciktigi gözlemleniyordu.
  expect_false(
    grepl(
      'getOption("mergen.version", Sys.getenv("MERGEN_APP_VERSION", "N/A"))',
      txt,
      fixed = TRUE
    ),
    info = paste(
      "Sürüm karti birincil kaynak olarak getOption('mergen.version', ...)",
      "kullanmamalidir. get_app_version_label() / get_current_version() tek",
      "dogru kaynaktir."
    )
  )
})

test_that("Sürüm health_result etiketi 'Sürüm' veya 'Sürüm / Git Commit'", {
  txt <- .read_version_file("R/helpers_health_runtime_checks.R")
  expect_true(nzchar(txt), info = "R/helpers_health_runtime_checks.R okunamadi.")

  # Etiket "Sürüm" olarak sade veya geriye uyumluluk icin
  # "Sürüm / Git Commit" olarak kabul edilir.
  expect_true(
    grepl('"Sürüm"', txt, fixed = TRUE) ||
      grepl('"Sürüm / Git Commit"', txt, fixed = TRUE),
    info = "Genel Bakış kartinda 'Sürüm' etiketi korunmalidir."
  )
})

test_that("Sidebar UI get_app_version_label / get_current_version kullanir", {
  txt <- .read_version_file("R/module_sidebar_user_panel.R")
  expect_true(nzchar(txt), info = "R/module_sidebar_user_panel.R okunamadi.")

  expect_true(
    grepl("get_app_version_label()", txt, fixed = TRUE) ||
      grepl("get_current_version()", txt, fixed = TRUE),
    info = paste(
      "Sidebar versiyon etiketi tek dogru kaynaktan (config_version_history.R)",
      "alinmalidir."
    )
  )
})

test_that("config_version_history.R get_current_version + get_app_version_label tanimlar", {
  txt <- .read_version_file("R/config_version_history.R")
  expect_true(nzchar(txt), info = "R/config_version_history.R okunamadi.")

  expect_true(
    grepl("get_current_version <- function()", txt, fixed = TRUE),
    info = "get_current_version() tanimi bulunmalidir."
  )

  expect_true(
    grepl("get_app_version_label <- function()", txt, fixed = TRUE),
    info = "get_app_version_label() tanimi bulunmalidir."
  )
})
