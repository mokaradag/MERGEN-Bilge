# ==============================================================================
# Dosya Yolu: tests/testthat/test-followup-text-helpers-behavior.R
# Açıklama: R/helpers_followup_questions.R saf metin/flag yardımcılarının
#           DAVRANIŞSAL testleri. Toleranslı enable_followups flag okuması,
#           kullanıcı bakış açısı düzeltmesi, takip sorusu normalizasyonu, kod
#           çiti temizleme, JSON payload ayrıştırma ve bağlam kısaltma gerçek
#           fonksiyonlar çağrılarak doğrulanır. Shiny/DB/LLM gerekmez.
# ==============================================================================

.followup_src_once <- function() {
  if (exists("coerce_followup_flag", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_followup_questions.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

testthat::test_that("coerce_followup_flag mantıksal/sayısal/dize truthy değerleri toleranslı okur", {
  .followup_src_once()
  # Mantıksal
  testthat::expect_true(coerce_followup_flag(TRUE))
  testthat::expect_false(coerce_followup_flag(FALSE))
  # Sayısal
  testthat::expect_true(coerce_followup_flag(1))
  testthat::expect_true(coerce_followup_flag(1L))
  testthat::expect_false(coerce_followup_flag(0))
  testthat::expect_false(coerce_followup_flag(NA_real_))
  # Dize (TR/EN truthy sözcükleri, büyük/küçük harf ve boşluk toleranslı)
  testthat::expect_true(coerce_followup_flag("true"))
  testthat::expect_true(coerce_followup_flag("  EVET "))
  testthat::expect_true(coerce_followup_flag("Aktif"))
  testthat::expect_true(coerce_followup_flag("on"))
  testthat::expect_true(coerce_followup_flag("1"))
  testthat::expect_false(coerce_followup_flag("false"))
  testthat::expect_false(coerce_followup_flag("hayir"))
  # Geçersiz/boş
  testthat::expect_false(coerce_followup_flag(NULL))
  testthat::expect_false(coerce_followup_flag(list()))
})

testthat::test_that("ensure_user_perspective kullanıcıya hitabı birinci tekil şahısa çevirir", {
  .followup_src_once()
  testthat::expect_identical(
    ensure_user_perspective("Bunu yapmak istiyor musunuz?"),
    "Bunu yapmak istiyorum, nasıl yapabilirim?"
  )
  testthat::expect_identical(
    ensure_user_perspective("Detayları görmek ister misiniz?"),
    "Detayları görmek istiyorum, nasıl yapabilirim?"
  )
  # Zaten birinci şahıs olan soru değişmez.
  testthat::expect_identical(
    ensure_user_perspective("Bunu nasıl yapabilirim?"),
    "Bunu nasıl yapabilirim?"
  )
})

testthat::test_that("normalize_followup_texts kırpar, tekrarı kaldırır, soru işareti ekler ve sınırlar", {
  .followup_src_once()
  out <- normalize_followup_texts(c("  Soru bir  ", "Soru bir", "Soru iki"), limit = 3L)
  testthat::expect_identical(out, c("Soru bir?", "Soru iki?"))

  # Çok kısa (<=3 karakter) öğeler elenir.
  out2 <- normalize_followup_texts(c("ab", "Geçerli bir soru"))
  testthat::expect_identical(out2, "Geçerli bir soru?")

  # limit uygulanır.
  out3 <- normalize_followup_texts(c("Birinci soru", "İkinci soru", "Üçüncü soru"), limit = 1L)
  testthat::expect_identical(length(out3), 1L)

  # Boş/NULL girdi NULL döndürür.
  testthat::expect_null(normalize_followup_texts(NULL))
  testthat::expect_null(normalize_followup_texts(c("", "  ")))
})

testthat::test_that("normalize_followup_texts 220 karakter sınırını uygular", {
  .followup_src_once()
  long <- strrep("a", 300)
  out <- normalize_followup_texts(long)
  # 220 karaktere kırpılır, ardından '?' eklenir => 221.
  testthat::expect_identical(nchar(out), 221L)
  testthat::expect_identical(substr(out, 1, 220), strrep("a", 220))
})

testthat::test_that("strip_code_fences ```json ... ``` çitlerini temizler", {
  .followup_src_once()
  testthat::expect_identical(strip_code_fences("```json\n{\"a\":1}\n```"), "{\"a\":1}")
  testthat::expect_identical(strip_code_fences("```\nmetin\n```"), "metin")
  testthat::expect_identical(strip_code_fences("çitsiz metin"), "çitsiz metin")
})

testthat::test_that("parse_followup_payload followups/questions/sorular anahtarlarını çözer", {
  .followup_src_once()
  testthat::skip_if_not_installed("jsonlite")
  testthat::expect_identical(
    parse_followup_payload('{"followups":["S1","S2"]}'),
    c("S1", "S2")
  )
  testthat::expect_identical(parse_followup_payload('{"questions":["Q1"]}'), "Q1")
  testthat::expect_identical(parse_followup_payload('{"sorular":["X"]}'), "X")
  # Kod çiti içindeki JSON da çözülür.
  testthat::expect_identical(
    parse_followup_payload('```json\n{"followups":["A"]}\n```'),
    "A"
  )
  # Düz JSON dizisi karakter vektörüne çözülür.
  testthat::expect_identical(parse_followup_payload('["a","b"]'), c("a", "b"))
  # Geçersiz JSON ve boş girdi NULL.
  testthat::expect_null(parse_followup_payload("bu json değil {"))
  testthat::expect_null(parse_followup_payload(""))
})

testthat::test_that("truncate_followup_context limit aşımında üç nokta ile kısaltır", {
  .followup_src_once()
  testthat::expect_identical(truncate_followup_context("kısa", 2000L), "kısa")
  testthat::expect_identical(truncate_followup_context("abcdefgh", 5L), "abcde \U2026")
  testthat::expect_identical(truncate_followup_context("", 10L), "")
  testthat::expect_identical(truncate_followup_context(NULL), "")
})
