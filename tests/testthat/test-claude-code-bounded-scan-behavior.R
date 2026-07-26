# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-bounded-scan-behavior.R
# Açıklama: Bilge Yolaç sınırlı (bounded) dizin tarayıcısının davranışını
#           doğrular: sınıra ulaşıldığında ERKEN durma, dizin/derinlik/bayt/
#           süre sınırları, varsayılan hariç tutmalar, erişilemeyen alt dizinin
#           ölümcül olmaması ve bağlantı (symlink) döngü koruması.
#           Çevrimdışı ve deterministiktir; DB/LLM/tarayıcı gerektirmez.
# ==============================================================================

.cc_bounded_scan_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())

  env$`%||%` <- function(x, y) if (is.null(x)) y else x

  source(
    file.path(repo_root, "R", "helpers_claude_code_bounded_scan.R"),
    encoding = "UTF-8",
    local = env
  )

  env
}

.cc_bounded_scan_fixture <- function(dosya_sayisi = 12L) {
  kok <- withr::local_tempdir(.local_envir = parent.frame())

  for (i in seq_len(dosya_sayisi)) {
    writeLines("veri", file.path(kok, sprintf("dosya%02d.txt", i)), useBytes = TRUE)
  }

  dir.create(file.path(kok, "alt", "derin"), recursive = TRUE)
  writeLines("alt", file.path(kok, "alt", "alt.txt"), useBytes = TRUE)
  writeLines("derin", file.path(kok, "alt", "derin", "derin.txt"), useBytes = TRUE)

  for (haric in c(".git", "node_modules", "document_support")) {
    dir.create(file.path(kok, haric))
    writeLines("x", file.path(kok, haric, "gizli.txt"), useBytes = TRUE)
  }

  dir.create(file.path(kok, "renv", "library"), recursive = TRUE)
  writeLines("x", file.path(kok, "renv", "library", "paket.R"), useBytes = TRUE)

  kok
}

test_that("sınırlı tarayıcı max_files sınırında erken durur", {
  env <- .cc_bounded_scan_env()
  kok <- .cc_bounded_scan_fixture(40L)

  sonuc <- env$cc_scan_directory_bounded(kok, max_files = 5L)

  expect_true(isTRUE(sonuc$ok))
  expect_equal(sonuc$file_count, 5L)
  expect_true(isTRUE(sonuc$truncated))
  expect_equal(sonuc$truncated_reason, "max_files")

  # Erken durma gerçek olmalı: kalan ağaç numaralandırılmamalıdır.
  expect_lt(sonuc$file_count, 40L)
})

test_that("sınırlı tarayıcı max_directories sınırını uygular", {
  env <- .cc_bounded_scan_env()
  kok <- .cc_bounded_scan_fixture()

  sonuc <- env$cc_scan_directory_bounded(kok, max_dirs = 0L)

  expect_equal(sonuc$dir_count, 0L)
  expect_true(isTRUE(sonuc$truncated))
  expect_equal(sonuc$truncated_reason, "max_directories")
})

test_that("sınırlı tarayıcı max_depth sınırını uygular", {
  env <- .cc_bounded_scan_env()
  kok <- .cc_bounded_scan_fixture()

  sonuc <- env$cc_scan_directory_bounded(kok, max_depth = 0L)

  expect_equal(sonuc$dir_count, 0L)
  expect_false(any(grepl("/alt/", sonuc$files, fixed = TRUE)))
  expect_true(isTRUE(sonuc$truncated))
  expect_equal(sonuc$truncated_reason, "max_depth")
})

test_that("sınırlı tarayıcı max_total_bytes sınırını uygular", {
  env <- .cc_bounded_scan_env()
  kok <- .cc_bounded_scan_fixture()

  sonuc <- env$cc_scan_directory_bounded(kok, max_total_bytes = 6)

  expect_true(sonuc$total_bytes <= 6)
  expect_true(isTRUE(sonuc$truncated))
  expect_equal(sonuc$truncated_reason, "max_total_bytes")
})

test_that("sınırlı tarayıcı zaman aşımını raporlar", {
  env <- .cc_bounded_scan_env()
  kok <- .cc_bounded_scan_fixture()

  sonuc <- env$cc_scan_directory_bounded(kok, max_elapsed_ms = 0)

  expect_true(isTRUE(sonuc$truncated))
  expect_equal(sonuc$truncated_reason, "timeout")
})

test_that("tek dosya boyut sınırını aşan dosya atlanır", {
  env <- .cc_bounded_scan_env()
  kok <- withr::local_tempdir()

  writeLines("kucuk", file.path(kok, "kucuk.txt"), useBytes = TRUE)
  writeLines(strrep("x", 5000), file.path(kok, "buyuk.txt"), useBytes = TRUE)

  sonuc <- env$cc_scan_directory_bounded(kok, max_file_bytes = 100)

  expect_true("kucuk.txt" %in% basename(sonuc$files))
  expect_false("buyuk.txt" %in% basename(sonuc$files))
  expect_true(any(grepl("buyuk.txt", sonuc$skipped, fixed = TRUE)))
})

test_that("varsayılan hariç tutulan dizinler taranmaz", {
  env <- .cc_bounded_scan_env()
  kok <- .cc_bounded_scan_fixture()

  sonuc <- env$cc_scan_directory_bounded(kok)

  expect_false(any(grepl("/\\.git/", sonuc$files, perl = TRUE)))
  expect_false(any(grepl("/node_modules/", sonuc$files, fixed = TRUE)))
  expect_false(any(grepl("/document_support/", sonuc$files, fixed = TRUE)))
  expect_false(any(grepl("/renv/library/", sonuc$files, fixed = TRUE)))

  # Normal alt klasörler taranmaya devam eder.
  expect_true("alt.txt" %in% basename(sonuc$files))
  expect_true("derin.txt" %in% basename(sonuc$files))
})

test_that("hariç tutulan dizin listesi yapılandırılabilir", {
  env <- .cc_bounded_scan_env()
  kok <- .cc_bounded_scan_fixture()

  sonuc <- env$cc_scan_directory_bounded(kok, exclude_dirs = c("alt"))

  expect_false("alt.txt" %in% basename(sonuc$files))
  expect_true(any(grepl("gizli.txt", basename(sonuc$files), fixed = TRUE)))
})

test_that("erişilemeyen alt dizin taramayı düşürmez", {
  skip_on_os("windows")
  skip_if(identical(Sys.info()[["user"]], "root"), "root her dizini okuyabilir.")

  env <- .cc_bounded_scan_env()
  kok <- withr::local_tempdir()

  writeLines("veri", file.path(kok, "gorunur.txt"), useBytes = TRUE)

  kapali <- file.path(kok, "kapali")
  dir.create(kapali)
  writeLines("gizli", file.path(kapali, "gizli.txt"), useBytes = TRUE)
  Sys.chmod(kapali, "000")
  on.exit(Sys.chmod(kapali, "700"), add = TRUE)

  sonuc <- env$cc_scan_directory_bounded(kok)

  expect_true(isTRUE(sonuc$ok))
  expect_true("gorunur.txt" %in% basename(sonuc$files))
})

test_that("dizin bağlantısı döngüsü sonsuz gezinmeye yol açmaz", {
  skip_on_os("windows")

  env <- .cc_bounded_scan_env()
  kok <- withr::local_tempdir()

  dir.create(file.path(kok, "alt"))
  writeLines("veri", file.path(kok, "alt", "veri.txt"), useBytes = TRUE)

  baglanti_ok <- suppressWarnings(
    file.symlink(kok, file.path(kok, "alt", "dongu"))
  )
  skip_if_not(isTRUE(baglanti_ok), "Sembolik bağlantı oluşturulamadı.")

  sonuc <- env$cc_scan_directory_bounded(kok, max_elapsed_ms = 3000)

  expect_true(isTRUE(sonuc$ok))
  expect_false(identical(sonuc$truncated_reason, "timeout"))
  expect_true("veri.txt" %in% basename(sonuc$files))
})

test_that("izinli kök dışına kaçan bağlantı atlanır", {
  skip_on_os("windows")

  env <- .cc_bounded_scan_env()
  kok <- withr::local_tempdir()
  disari <- withr::local_tempdir()

  writeLines("disarida", file.path(disari, "sizinti.txt"), useBytes = TRUE)
  writeLines("icerde", file.path(kok, "icerde.txt"), useBytes = TRUE)

  baglanti_ok <- suppressWarnings(
    file.symlink(disari, file.path(kok, "kacak"))
  )
  skip_if_not(isTRUE(baglanti_ok), "Sembolik bağlantı oluşturulamadı.")

  sonuc <- env$cc_scan_directory_bounded(kok)

  expect_false("sizinti.txt" %in% basename(sonuc$files))
  expect_true("icerde.txt" %in% basename(sonuc$files))
})

test_that("göreli yol dönüşümü kök altındaki yapıyı korur", {
  env <- .cc_bounded_scan_env()
  kok <- .cc_bounded_scan_fixture(2L)

  sonuc <- env$cc_scan_directory_bounded(kok)
  rel <- env$cc_scan_relative_paths(sonuc$files, kok)

  expect_true("alt/alt.txt" %in% rel)
  expect_false(any(startsWith(rel, "/")))
})

test_that("list.files boş dönerse fs yedeği ile listeleme sürer", {
  # Windows VM / UNC paylaşımlarında base R list.files bazen boş döner; bu
  # yedek olmadan tarama sessizce boş sonuç üretir.
  env <- .cc_bounded_scan_env()
  kok <- .cc_bounded_scan_fixture(3L)

  env$list.files <- function(...) character(0)

  sonuc <- env$cc_scan_directory_bounded(kok)

  expect_true(isTRUE(sonuc$ok))
  expect_true(sonuc$file_count > 0L)
  expect_true("dosya01.txt" %in% basename(sonuc$files))
})

test_that("geçersiz kök güvenli sonuç döndürür", {
  env <- .cc_bounded_scan_env()

  bos <- env$cc_scan_directory_bounded("")
  expect_false(isTRUE(bos$ok))
  expect_equal(bos$truncated_reason, "invalid_root")

  yok <- env$cc_scan_directory_bounded(file.path(tempdir(), "kesinlikle_yok_12345"))
  expect_false(isTRUE(yok$ok))
  expect_equal(yok$truncated_reason, "missing_root")
})
