# ==============================================================================
# Dosya Yolu: tests/testthat/test-admin-geri-bildirim-refactor-contract.R
# Açıklama: Geri Bildirim Analizi modülü UI extraction sözleşmesini doğrular.
# ==============================================================================

.read_repo_text_admin_gb <- function(path) {
  repo_root <- resolve_repo_root_for_tests()
  full_path <- file.path(repo_root, path)

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  txt <- gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

test_that("admin geri bildirim helper dosyası saf helper fonksiyonlarını taşır", {
  repo_root <- resolve_repo_root_for_tests()
  helper_path <- file.path(repo_root, "R/helpers_admin_geri_bildirim.R")

  expect_true(file.exists(helper_path))

  helper_text <- .read_repo_text_admin_gb("R/helpers_admin_geri_bildirim.R")

  expected_functions <- c(
    "admin_gb_count_tags",
    "admin_gb_tab_ui",
    "admin_gb_overview_ui",
    "admin_gb_memnuniyet_ui",
    "admin_gb_nps_ui",
    "admin_gb_icerik_ui"
  )

  for (fn in expected_functions) {
    expect_true(
      grepl(
        paste0(fn, "\\s*<-\\s*function\\s*\\("),
        helper_text,
        perl = TRUE
      ),
      info = paste("Eksik helper fonksiyonu:", fn)
    )
  }

  forbidden_runtime_calls <- c(
    "moduleServer\\s*\\(",
    "observeEvent\\s*\\(",
    "reactive\\s*\\(",
    "admin_safe_query\\s*\\("
  )

  for (pattern in forbidden_runtime_calls) {
    expect_false(
      grepl(pattern, helper_text, perl = TRUE),
      info = paste("Helper dosyası runtime/DB yan etkisi içermemelidir:", pattern)
    )
  }
})

test_that("admin geri bildirim modülü çıkarılan tab UI helper'ını kullanır", {
  module_text <- .read_repo_text_admin_gb("R/module_admin_geri_bildirim.R")

  expect_true(
    grepl("admin_gb_tab_ui\\s*\\(", module_text, perl = TRUE),
    info = "module_admin_geri_bildirim.R tab UI için admin_gb_tab_ui() kullanmalıdır."
  )

  removed_local_helpers <- c(
    "gb_overview_ui",
    "gb_memnuniyet_ui",
    "gb_nps_ui",
    "gb_icerik_ui"
  )

  for (fn in removed_local_helpers) {
    expect_false(
      grepl(
        paste0("\\n\\s*", fn, "\\s*<-\\s*function\\s*\\("),
        module_text,
        perl = TRUE
      ),
      info = paste("Çıkarılan nested UI helper modül içinde kalmamalıdır:", fn)
    )
  }
})

test_that("admin_gb_count_tags Türkçe etiket çevirisini ve sayımı korur", {
  repo_root <- resolve_repo_root_for_tests()
  helper_env <- new.env(parent = globalenv())

  source(
    file.path(repo_root, "R/helpers_admin_geri_bildirim.R"),
    encoding = "UTF-8",
    local = helper_env
  )

  ham <- data.frame(
    Etiketler = c(
      "tasarim, performans",
      "tasarim",
      "sikayet, diger",
      "",
      NA_character_
    ),
    stringsAsFactors = FALSE
  )

  sonuc <- helper_env$admin_gb_count_tags(ham)

  expect_s3_class(sonuc, "data.frame")
  expect_true(all(c("etiket", "cnt", "etiket_tr") %in% names(sonuc)))

  tasarim_row <- sonuc[sonuc$etiket == "tasarim", , drop = FALSE]
  expect_equal(nrow(tasarim_row), 1L)
  expect_equal(as.integer(tasarim_row$cnt[1]), 2L)
  expect_equal(tasarim_row$etiket_tr[1], "Tasarım Önerisi")

  sikayet_row <- sonuc[sonuc$etiket == "sikayet", , drop = FALSE]
  expect_equal(nrow(sikayet_row), 1L)
  expect_equal(sikayet_row$etiket_tr[1], "Şikâyet")
})