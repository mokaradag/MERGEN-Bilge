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
  # Byte-safe okuma: POSIX/C locale altinda readLines + grepl UTF-8 markaja
  # ragmen "input string 1 is invalid UTF-8" uretebiliyor. readBin + iconv
  # ile bytleri korur, grepl(..., useBytes = TRUE) ile arariz.
  repo_root <- .repo_root_version_single()
  full_path <- file.path(repo_root, rel_path)
  if (!file.exists(full_path)) return("")

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    # BOŞ DOSYA DA VACUOUS GEÇİRİR: bu dosyalardaki taramaların çoğu
    # `expect_false(grepl(...))` biçimindedir ve boş dize hepsini karşılar.
    stop(sprintf("Kaynak dosya BOŞ ya da okunamıyor: %s", full_path), call. = FALSE)
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_data <- readBin(con, what = "raw", n = size)

  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8")[[1]]
  )
  # GEÇERSİZ UTF-8 SESSİZCE KABUL EDİLMEZ.
  #
  # `sub = "byte"` her geçersiz baytı kaçırır ve HER ZAMAN bir dize döndürür,
  # dolayısıyla aşağıdaki `NA` kapısı ULAŞILAMAZ kalıyordu: UTF-8 dışı bir
  # kodlamayla kaydedilmiş kaynak dosya kaçırılmış mojibake olarak taranıyor,
  # ASCII sözleşme belirteçleri yine eşleşiyor ve NEGATİF iddialar bozuk bir
  # dosya için de geçiyordu. `test-true-streaming-reset-ui-contract.R` ile
  # `test-ux-regression-guardrails.R` zaten bu kuralı uygular.
  if (is.na(txt)) {
    stop(sprintf("Kaynak dosya geçerli UTF-8 değil: %s", rel_path), call. = FALSE)
  }
  txt <- gsub("\r\n?|\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

test_that("Sistem Durumu Sürüm karti get_app_version_label kullanir", {
  txt <- .read_version_file("R/helpers_health_runtime_checks.R")
  expect_true(nzchar(txt), info = "R/helpers_health_runtime_checks.R okunamadi.")

  expect_true(
    grepl("get_app_version_label()", txt, fixed = TRUE, useBytes = TRUE),
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
      fixed = TRUE,
      useBytes = TRUE
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
  # UTF-8 byte dizisi: Sürüm -> S(0x53) ü(0xC3 0xBC) r(0x72) ü(0xC3 0xBC) m(0x6D)
  utf8_surum <- rawToChar(as.raw(
    c(0x22, 0x53, 0xC3, 0xBC, 0x72, 0xC3, 0xBC, 0x6D, 0x22)
  ))
  Encoding(utf8_surum) <- "UTF-8"
  utf8_surum_git <- rawToChar(as.raw(
    c(0x22, 0x53, 0xC3, 0xBC, 0x72, 0xC3, 0xBC, 0x6D, 0x20, 0x2F, 0x20,
      0x47, 0x69, 0x74, 0x20, 0x43, 0x6F, 0x6D, 0x6D, 0x69, 0x74, 0x22)
  ))
  Encoding(utf8_surum_git) <- "UTF-8"

  expect_true(
    grepl(utf8_surum, txt, fixed = TRUE, useBytes = TRUE) ||
      grepl(utf8_surum_git, txt, fixed = TRUE, useBytes = TRUE),
    info = "Genel Bakış kartinda 'Sürüm' etiketi korunmalidir."
  )
})

test_that("Sidebar UI get_app_version_label / get_current_version kullanir", {
  txt <- .read_version_file("R/module_sidebar_user_panel.R")
  expect_true(nzchar(txt), info = "R/module_sidebar_user_panel.R okunamadi.")

  expect_true(
    grepl("get_app_version_label()", txt, fixed = TRUE, useBytes = TRUE) ||
      grepl("get_current_version()", txt, fixed = TRUE, useBytes = TRUE),
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
    grepl("get_current_version <- function()", txt, fixed = TRUE, useBytes = TRUE),
    info = "get_current_version() tanimi bulunmalidir."
  )

  expect_true(
    grepl("get_app_version_label <- function()", txt, fixed = TRUE, useBytes = TRUE),
    info = "get_app_version_label() tanimi bulunmalidir."
  )
})
