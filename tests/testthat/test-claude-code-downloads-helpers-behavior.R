# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-downloads-helpers-behavior.R
# Açıklama: R/helpers_claude_code_downloads.R saf yardımcılarının DAVRANIŞSAL
#           testleri. Bu fonksiyonlar mevcut testlerde HİÇ çağrılmıyordu:
#             - sanitize_claude_code_download_segment (güvenli dosya/segment adı)
#             - format_claude_code_download_size (bayt -> okunabilir boyut)
#             - get_claude_code_download_root (indirme kök dizini çözümleme)
#           Güvenlik açısından önemli: segment temizleyici yol ayraçlarını ('/','\')
#           ve güvensiz karakterleri '_' yapar. Saf base R; ağ/DB/Shiny GEREKMEZ.
# ==============================================================================

.ccdl_source_once <- function() {
  if (!exists("%||%", inherits = TRUE)) {
    assign("%||%", function(a, b) if (is.null(a)) b else a, envir = globalenv())
  }
  if (!exists("sanitize_claude_code_download_segment",
              envir = globalenv(), mode = "function", inherits = TRUE)) {
    source(
      file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_downloads.R"),
      encoding = "UTF-8", local = globalenv()
    )
  }
  invisible(TRUE)
}

.ccdl_with_option <- function(value, code) {
  old <- getOption("mergen.claude_code_download_root")
  on.exit(options(mergen.claude_code_download_root = old), add = TRUE)
  options(mergen.claude_code_download_root = value)
  force(code)
}

# ------------------------------------------------------------------------------
# sanitize_claude_code_download_segment
# ------------------------------------------------------------------------------
testthat::test_that("sanitize_claude_code_download_segment güvenli adı korur, güvensizi '_' yapar", {
  .ccdl_source_once()
  testthat::expect_identical(sanitize_claude_code_download_segment("rapor.pdf"), "rapor.pdf")
  # Boşluk ve yol ayracı '_' olur.
  testthat::expect_identical(sanitize_claude_code_download_segment("a b/c"), "a_b_c")
  # Ardışık güvensizler tek '_'e iner, baş/son '_' kırpılır.
  testthat::expect_identical(sanitize_claude_code_download_segment("__a..b__"), "a..b")
})

testthat::test_that("sanitize_claude_code_download_segment yol ayraçlarını nötrler (güvenlik)", {
  .ccdl_source_once()
  donen <- sanitize_claude_code_download_segment("../secret/key.txt")
  # Sonuçta '/' veya '\\' KALMAMALI.
  testthat::expect_false(grepl("/", donen, fixed = TRUE))
  testthat::expect_false(grepl("\\", donen, fixed = TRUE))
  # Yalnızca güvenli karakter sınıfı.
  testthat::expect_match(donen, "^[A-Za-z0-9._-]+$", perl = TRUE)
})

testthat::test_that("sanitize_claude_code_download_segment Türkçe/güvensiz girdiyi güvenli kümeye indirger", {
  .ccdl_source_once()
  donen <- sanitize_claude_code_download_segment("Çalışma Özeti.pdf")
  testthat::expect_match(donen, "^[A-Za-z0-9._-]+$", perl = TRUE)
  testthat::expect_true(grepl("pdf", donen, fixed = TRUE))
})

testthat::test_that("sanitize_claude_code_download_segment boş/NULL/yalnızca-güvensiz girdide fallback döner", {
  .ccdl_source_once()
  testthat::expect_identical(sanitize_claude_code_download_segment(""), "oge")
  testthat::expect_identical(sanitize_claude_code_download_segment(NULL), "oge")
  testthat::expect_identical(sanitize_claude_code_download_segment("@@@"), "oge")
  # Özel fallback onurlanır.
  testthat::expect_identical(sanitize_claude_code_download_segment("", fallback = "yedek"), "yedek")
  testthat::expect_identical(sanitize_claude_code_download_segment("###", fallback = "Z"), "Z")
})

# ------------------------------------------------------------------------------
# format_claude_code_download_size
# ------------------------------------------------------------------------------
testthat::test_that("format_claude_code_download_size baytı uygun birime ölçekler", {
  .ccdl_source_once()
  testthat::expect_identical(format_claude_code_download_size(0), "0 B")
  testthat::expect_identical(format_claude_code_download_size(512), "512 B")
  testthat::expect_identical(format_claude_code_download_size(1024), "1 KB")
  testthat::expect_identical(format_claude_code_download_size(1536), "1.5 KB")
  testthat::expect_identical(format_claude_code_download_size(1048576), "1 MB")
  testthat::expect_identical(format_claude_code_download_size(1073741824), "1 GB")
  testthat::expect_identical(format_claude_code_download_size(5 * 1024^3), "5 GB")
})

testthat::test_that("format_claude_code_download_size geçersiz boyutta açıklayıcı metin döner", {
  .ccdl_source_once()
  testthat::expect_identical(format_claude_code_download_size(NA), "Boyut bilinmiyor")
  testthat::expect_identical(format_claude_code_download_size("abc"), "Boyut bilinmiyor")
})

# ------------------------------------------------------------------------------
# get_claude_code_download_root
# ------------------------------------------------------------------------------
testthat::test_that("get_claude_code_download_root option'daki kökü çözer ve gerekirse oluşturur", {
  .ccdl_source_once()
  hedef <- file.path(tempdir(), "ccdl_root_behavior_test")
  unlink(hedef, recursive = TRUE)
  on.exit(unlink(hedef, recursive = TRUE), add = TRUE)

  donen <- .ccdl_with_option(hedef, get_claude_code_download_root())

  # Dizin oluşturulmuş ve ileri eğik çizgili mutlak yol dönmüş olmalı.
  testthat::expect_true(dir.exists(donen))
  testthat::expect_identical(basename(donen), "ccdl_root_behavior_test")
  testthat::expect_false(grepl("\\\\", donen))
})
