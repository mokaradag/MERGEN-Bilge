# ==============================================================================
# Dosya Yolu: tests/testthat/test-llm-worker-payload-helpers-behavior.R
# Açıklama: R/helpers_llm_worker_payload.R içindeki saf payload yardımcılarının
#           DAVRANIŞSAL testleri. Mevcut
#           test-llm-worker-payload-refactor-contract.R yalnızca kaynak-düzenini
#           doğrular; bu yardımcılar doğrudan çağrılarak test edilmiyordu:
#             - llm_worker_scalar_nzchar (boş/NA/skaler-olmayan ayrımı)
#             - llm_worker_last_user_text (son kullanıcı mesajı; type/role,
#               content/message alanları)
#             - llm_worker_add_fallback_chart (NULL -> "")
#             - llm_worker_build_chart_summary (Türkçe grafik özeti; sayısal/
#               kategorik gözlem dalları)
#           Shiny/DB/LLM/ağ GEREKMEZ; yalnızca base R (stats taban paketi).
# ==============================================================================

.llmpayload_source_once <- function() {
  if (exists("llm_worker_scalar_nzchar", envir = globalenv(),
             mode = "function", inherits = TRUE) &&
      exists("llm_worker_build_chart_summary", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_llm_worker_payload.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

# ------------------------------------------------------------------------------
# llm_worker_scalar_nzchar
# ------------------------------------------------------------------------------
testthat::test_that("llm_worker_scalar_nzchar yalnızca boş-olmayan karakter skaleri için TRUE döner", {
  .llmpayload_source_once()
  testthat::expect_true(llm_worker_scalar_nzchar("x"))
  # İlk öğe boş değilse TRUE
  testthat::expect_true(llm_worker_scalar_nzchar(c("a", "b")))

  testthat::expect_false(llm_worker_scalar_nzchar(""))
  testthat::expect_false(llm_worker_scalar_nzchar(NA_character_))
  testthat::expect_false(llm_worker_scalar_nzchar(NULL))
  testthat::expect_false(llm_worker_scalar_nzchar(character(0)))
  # Karakter olmayan tipler FALSE
  testthat::expect_false(llm_worker_scalar_nzchar(5))
  testthat::expect_false(llm_worker_scalar_nzchar(TRUE))
  # İlk öğe boşsa FALSE
  testthat::expect_false(llm_worker_scalar_nzchar(c("", "b")))
})

# ------------------------------------------------------------------------------
# llm_worker_last_user_text
# ------------------------------------------------------------------------------
testthat::test_that("llm_worker_last_user_text son kullanıcı mesajını döndürür", {
  .llmpayload_source_once()
  ch <- list(
    list(type = "user", content = "ilk"),
    list(type = "ai", content = "cevap"),
    list(type = "user", content = "son soru")
  )
  testthat::expect_identical(llm_worker_last_user_text(ch), "son soru")

  # role + message alanlarını da destekler
  ch_role <- list(list(role = "user", message = "mesaj alani"))
  testthat::expect_identical(llm_worker_last_user_text(ch_role), "mesaj alani")
})

testthat::test_that("llm_worker_last_user_text kullanıcı mesajı yoksa/boş geçmişte NULL döner", {
  .llmpayload_source_once()
  testthat::expect_null(llm_worker_last_user_text(list()))
  testthat::expect_null(llm_worker_last_user_text(NULL))
  ch_ai <- list(list(type = "ai", content = "sadece ai"))
  testthat::expect_null(llm_worker_last_user_text(ch_ai))
})

# ------------------------------------------------------------------------------
# llm_worker_add_fallback_chart
# ------------------------------------------------------------------------------
testthat::test_that("llm_worker_add_fallback_chart metni korur, NULL'u boş dizeye çevirir", {
  .llmpayload_source_once()
  testthat::expect_identical(llm_worker_add_fallback_chart("metin"), "metin")
  testthat::expect_identical(llm_worker_add_fallback_chart(NULL), "")
})

# ------------------------------------------------------------------------------
# llm_worker_build_chart_summary
# ------------------------------------------------------------------------------
testthat::test_that("llm_worker_build_chart_summary geçersiz grafik için sabit özet döner", {
  .llmpayload_source_once()
  sabit <- "Grafik hazırlandı; veri kısa süreli özetlendi."
  testthat::expect_identical(llm_worker_build_chart_summary(NULL), sabit)
  testthat::expect_identical(llm_worker_build_chart_summary(list(chart = "liste-degil")), sabit)
})

testthat::test_that("llm_worker_build_chart_summary tip/eksen/satır bilgisini özetler", {
  .llmpayload_source_once()
  spec <- list(type = "bar", mapping = list(x = "Kategori", y = "Tutar"), n = 120)
  out <- llm_worker_build_chart_summary(spec)
  testthat::expect_match(out, "Grafik hazırlandı: Tür: bar", fixed = TRUE)
  testthat::expect_match(out, "X=Kategori, Y=Tutar", fixed = TRUE)
  testthat::expect_match(out, "Örnek satır sayısı: 120", fixed = TRUE)

  # raw_chart$chart sarmalayıcısı ve yalnızca X ekseni
  spec_wrap <- list(chart = list(type = "line", mapping = list(x = "Ay")))
  out_wrap <- llm_worker_build_chart_summary(spec_wrap)
  testthat::expect_match(out_wrap, "Tür: line", fixed = TRUE)
  testthat::expect_match(out_wrap, "X=Ay", fixed = TRUE)

  # Hiç betimleyici alan yoksa "Dosyadaki verilerden üretildi"
  out_empty <- llm_worker_build_chart_summary(list(chart = list()))
  testthat::expect_match(out_empty, "Dosyadaki verilerden üretildi", fixed = TRUE)
})

testthat::test_that("llm_worker_build_chart_summary sayısal Y için istatistik gözlemi ekler", {
  .llmpayload_source_once()
  df <- data.frame(
    Kategori = c("a", "b", "c", "d"),
    Tutar = c(10, 20, 30, 100),
    stringsAsFactors = FALSE
  )
  spec <- list(type = "bar", mapping = list(x = "Kategori", y = "Tutar"), data = df)
  out <- llm_worker_build_chart_summary(spec)
  testthat::expect_match(out, "Ortanca", fixed = TRUE)
  testthat::expect_match(out, "IQR", fixed = TRUE)
  # Veri-temelli gözlem dalı kapanış cümlesini değiştirir
  testthat::expect_match(out, "Eksenlerdeki deseni", fixed = TRUE)
})

testthat::test_that("llm_worker_build_chart_summary kategorik X için en sık kategorileri özetler", {
  .llmpayload_source_once()
  df <- data.frame(
    Kategori = c("a", "a", "b", "c"),
    stringsAsFactors = FALSE
  )
  spec <- list(type = "bar", mapping = list(x = "Kategori"), data = df)
  out <- llm_worker_build_chart_summary(spec)
  testthat::expect_match(out, "En sık kategoriler", fixed = TRUE)
})
