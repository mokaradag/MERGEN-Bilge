# ==============================================================================
# Dosya Yolu: tests/testthat/test-utils-common-behavior.R
# Açıklama: utils_common.R temel saf yardımcılarının davranışsal testleri.
#           safe_trimws, safe_nzchar, resolve_runtime_value ve strip_planner_text
#           giriş -> çıkış davranışı doğrulanır. Bu yardımcılar uygulama genelinde
#           kullanıldığından düşük seviyeli davranış kontrolü değerlidir.
#           DB/LLM/tarayıcı gerekmez; ASCII girdiler tercih edilir.
# ==============================================================================

.utils_common_source_once <- function() {
  if (exists("safe_trimws", envir = globalenv(), mode = "function", inherits = TRUE) &&
      exists("resolve_runtime_value", envir = globalenv(), mode = "function", inherits = TRUE) &&
      exists("strip_planner_text", envir = globalenv(), mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }

  source(
    file.path(resolve_repo_root_for_tests(), "R", "utils_common.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  invisible(TRUE)
}

testthat::test_that("safe_trimws baş/son boşlukları temizler", {
  .utils_common_source_once()

  testthat::expect_identical(safe_trimws("  abc  "), "abc")
  testthat::expect_identical(safe_trimws("abc"), "abc")
  testthat::expect_identical(safe_trimws("   "), "")
})

testthat::test_that("safe_nzchar anlamlı metni TRUE, boş/NA/geçersizi FALSE döner", {
  .utils_common_source_once()

  testthat::expect_true(safe_nzchar("abc"))
  testthat::expect_true(safe_nzchar("  abc  "))

  testthat::expect_false(safe_nzchar(""))
  testthat::expect_false(safe_nzchar("   "))
  testthat::expect_false(safe_nzchar(NA_character_))
  testthat::expect_false(safe_nzchar(character(0)))
  testthat::expect_false(safe_nzchar(123))
  testthat::expect_false(safe_nzchar(NULL))
})

testthat::test_that("resolve_runtime_value fonksiyonu çağırır, değeri olduğu gibi döner", {
  .utils_common_source_once()

  # Düz değerler olduğu gibi döner.
  testthat::expect_identical(resolve_runtime_value(42), 42)
  testthat::expect_identical(resolve_runtime_value("metin"), "metin")
  testthat::expect_null(resolve_runtime_value(NULL))

  # Fonksiyon ise çağrılır.
  testthat::expect_identical(resolve_runtime_value(function() 99), 99)

  # Fonksiyon hata verirse NULL'a düşer.
  testthat::expect_null(resolve_runtime_value(function() stop("boom")))
})

testthat::test_that("strip_planner_text araç çağrısı ve planlayıcı kalıntısını temizler", {
  .utils_common_source_once()

  # Güvenli sınır durumları.
  testthat::expect_null(strip_planner_text(NULL))
  testthat::expect_identical(strip_planner_text(character(0)), "")
  testthat::expect_identical(strip_planner_text(123), "")

  # Normal metin korunur.
  testthat::expect_identical(strip_planner_text("normal cevap"), "normal cevap")

  # <tool_call> bloğu kaldırılır.
  out_tool <- strip_planner_text("Cevap <tool_call>{\"x\":1}</tool_call>")
  testthat::expect_false(grepl("tool_call", out_tool, fixed = TRUE))
  testthat::expect_true(grepl("Cevap", out_tool, fixed = TRUE))

  # İngilizce planlayıcı meta-cümlesi kaldırılır, asıl cevap kalır.
  out_planner <- strip_planner_text("We need to call the tool.\nAsil cevap.")
  testthat::expect_false(grepl("We need to", out_planner, ignore.case = TRUE))
  testthat::expect_true(grepl("Asil cevap", out_planner, fixed = TRUE))

  # Üç+ ardışık boş satır iki satıra indirilir.
  testthat::expect_identical(strip_planner_text("A\n\n\n\nB"), "A\n\nB")
})
