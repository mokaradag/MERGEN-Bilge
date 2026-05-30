# ==============================================================================
# Dosya Yolu: tests/testthat/test-summarization-user-prompt-behavior.R
# Açıklama: R/helpers_summarization_prompts.R build_summarization_user_prompt
#           DAVRANIŞSAL testleri. Tek/çoklu dosya, detay seviyesi (brief/standard/
#           detailed) ve odak modu (numerical/decisions/comparison/general)
#           dallarının ürettiği prompt metnini doğrular. Saf base R (paste/switch/
#           vapply/nchar/format); ağ/LLM/DB GEREKMEZ.
# ==============================================================================

.summuser_source_once <- function() {
  if (exists("build_summarization_user_prompt", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_summarization_prompts.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

.summuser_file <- function(name, content) list(name = name, content = content)

# ------------------------------------------------------------------------------
# TEK DOSYA
# ------------------------------------------------------------------------------
testthat::test_that("tek dosya: belge içeriği ve dosya adı prompt'a gömülür", {
  .summuser_source_once()
  files <- list(.summuser_file("rapor.pdf", "Bu bir test belgesidir."))
  out <- build_summarization_user_prompt(files, detail_level = "standard")

  testthat::expect_true(grepl("BELGE İÇERİĞİ:", out, fixed = TRUE))
  testthat::expect_true(grepl("Bu bir test belgesidir.", out, fixed = TRUE))
  testthat::expect_true(grepl("### rapor.pdf", out, fixed = TRUE))
  # Tek dosyada içerik ayracı "---" bulunur.
  testthat::expect_true(grepl("\n\n---\n\n", out, fixed = TRUE))
})

testthat::test_that("tek dosya brief: kısa-öz yönergesi, detaylı döküm YOK", {
  .summuser_source_once()
  files <- list(.summuser_file("not.txt", "icerik"))
  out <- build_summarization_user_prompt(files, detail_level = "brief")

  testthat::expect_true(grepl("KISA VE ÖZ", out, fixed = TRUE))
  testthat::expect_true(grepl("Detaylara girme", out, fixed = TRUE))
  # brief modunda detaylı şablon başlıkları olmamalı.
  testthat::expect_false(grepl("DETAYLI İÇERİK DÖKÜMÜ", out, fixed = TRUE))
  testthat::expect_false(grepl("Ana Konular", out, fixed = TRUE))
})

testthat::test_that("tek dosya detailed: kapsamlı şablon ve formatlı karakter sayısı", {
  .summuser_source_once()
  # nchar = 1234 -> format big.mark '.' -> '1.234'
  files <- list(.summuser_file("buyuk.docx", strrep("a", 1234L)))
  out <- build_summarization_user_prompt(files, detail_level = "detailed")

  testthat::expect_true(grepl("KAPSAMLI ve DETAYLI", out, fixed = TRUE))
  testthat::expect_true(grepl("DETAYLI İÇERİK DÖKÜMÜ", out, fixed = TRUE))
  testthat::expect_true(grepl("KRİTİK SAYISAL VERİLER", out, fixed = TRUE))
  testthat::expect_true(grepl("**Toplam Uzunluk:** 1.234 karakter", out, fixed = TRUE))
})

testthat::test_that("tek dosya standard (varsayılan dal): dengeli şablon başlıkları", {
  .summuser_source_once()
  files <- list(.summuser_file("a.txt", "x"))
  # Bilinmeyen detail_level switch() varsayılan dala (standard) düşer.
  out_default <- build_summarization_user_prompt(files, detail_level = "boyle-bir-seviye-yok")
  out_std <- build_summarization_user_prompt(files, detail_level = "standard")

  testthat::expect_true(grepl("dengeli detayda özetle", out_std, fixed = TRUE))
  testthat::expect_true(grepl("**Ana Konular:**", out_std, fixed = TRUE))
  testthat::expect_true(grepl("**Önemli Noktalar:**", out_std, fixed = TRUE))
  # Bilinmeyen seviye standard ile aynı çıktıyı verir.
  testthat::expect_identical(out_default, out_std)
})

# ------------------------------------------------------------------------------
# ODAK MODU
# ------------------------------------------------------------------------------
testthat::test_that("odak modu: numerical/decisions/comparison ek yönerge ekler, general eklemez", {
  .summuser_source_once()
  files <- list(.summuser_file("a.txt", "x"))

  out_num <- build_summarization_user_prompt(files, "standard", "numerical")
  out_dec <- build_summarization_user_prompt(files, "standard", "decisions")
  out_cmp <- build_summarization_user_prompt(files, "standard", "comparison")
  out_gen <- build_summarization_user_prompt(files, "standard", "general")

  testthat::expect_true(grepl("ÖZELLİKLE sayısal verilere", out_num, fixed = TRUE))
  testthat::expect_true(grepl("karar noktalarına", out_dec, fixed = TRUE))
  testthat::expect_true(grepl("karşılaştır", out_cmp, fixed = TRUE))
  # general modu hiçbir odak yönergesi eklemez: numerical/decisions metni yok.
  testthat::expect_false(grepl("ÖZELLİKLE sayısal verilere", out_gen, fixed = TRUE))
  testthat::expect_false(grepl("karar noktalarına", out_gen, fixed = TRUE))
  # general çıktısı, odak yönergesi olmayan standard çıktısına eşit olmalı.
  testthat::expect_identical(out_gen, build_summarization_user_prompt(files, "standard"))
})

# ------------------------------------------------------------------------------
# ÇOKLU DOSYA
# ------------------------------------------------------------------------------
testthat::test_that("çoklu dosya: her dosya numaralı blok + birleşik ayraçlar", {
  .summuser_source_once()
  files <- list(
    .summuser_file("ilk.pdf", "alfa"),
    .summuser_file("ikinci.docx", "beta")
  )
  out <- build_summarization_user_prompt(files, detail_level = "standard")

  testthat::expect_true(grepl("### DOSYA 1: ilk.pdf", out, fixed = TRUE))
  testthat::expect_true(grepl("### DOSYA 2: ikinci.docx", out, fixed = TRUE))
  testthat::expect_true(grepl("alfa", out, fixed = TRUE))
  testthat::expect_true(grepl("beta", out, fixed = TRUE))
  testthat::expect_true(grepl("--- DOSYA SONU ---", out, fixed = TRUE))
  testthat::expect_true(grepl("--- TÜM DOSYALAR BİTTİ ---", out, fixed = TRUE))
  testthat::expect_true(grepl("**Toplam Dosya Sayısı:** 2", out, fixed = TRUE))
})

testthat::test_that("çoklu dosya detailed: toplam karakter formatlı ve karşılaştırma bölümü", {
  .summuser_source_once()
  # 1000 + 234 = 1234 karakter -> '1.234'
  files <- list(
    .summuser_file("a.txt", strrep("a", 1000L)),
    .summuser_file("b.txt", strrep("b", 234L))
  )
  out <- build_summarization_user_prompt(files, detail_level = "detailed")

  testthat::expect_true(grepl("KAPSAMLI ve DETAYLI", out, fixed = TRUE))
  testthat::expect_true(grepl("**Toplam Karakter:** 1.234", out, fixed = TRUE))
  testthat::expect_true(grepl("DOSYALAR ARASI KARŞILAŞTIRMA", out, fixed = TRUE))
})

testthat::test_that("çoklu dosya brief: kısa-öz, detaylı döküm YOK", {
  .summuser_source_once()
  files <- list(.summuser_file("a", "x"), .summuser_file("b", "y"))
  out <- build_summarization_user_prompt(files, detail_level = "brief")

  testthat::expect_true(grepl("KISA VE ÖZ", out, fixed = TRUE))
  testthat::expect_false(grepl("DOSYALAR ARASI KARŞILAŞTIRMA", out, fixed = TRUE))
})

testthat::test_that("çıktı her zaman tek uzunlukta karakter dizesidir", {
  .summuser_source_once()
  out <- build_summarization_user_prompt(
    list(.summuser_file("a.txt", "icerik")), "detailed", "numerical"
  )
  testthat::expect_type(out, "character")
  testthat::expect_length(out, 1L)
})
