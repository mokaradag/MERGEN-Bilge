# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-pipeline-summarize-behavior.R
# Açıklama: helpers_file_pipeline.R içindeki summarize_file_with_llm davranışını
#           doğrular. Bu fonksiyon yüklenen dosya metnini LLM ile ayrıntılı
#           içerik dökümüne çevirir; LLM list($content)/karakter dönüşü,
#           boş/NA dönüş ve hata durumunda kısaltılmış içerik fallback'i
#           üretir. call_llm_with_retry stub'lanır; gerçek LLM/ağ/DB yoktur.
#           Çevrimdışı ve deterministik.
# ==============================================================================

# Türkçe yorum: helpers_file_pipeline.R'yi yalıtılmış ortama yükler. Bağımlılık
# call_llm_with_retry env içine stub edilir; as_llm_settings_list aynı dosyada
# tanımlıdır.
.filePipelineSummEnv <- function() {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  source(file.path(kok, "R", "helpers_file_pipeline.R"), encoding = "UTF-8", local = env)
  env
}

test_that("summarize_file_with_llm list($content) dönüşünden içeriği çıkarır", {
  env <- .filePipelineSummEnv()
  yakalanan <- new.env(parent = emptyenv())
  env$call_llm_with_retry <- function(chat, settings, max_retries = 2) {
    yakalanan$chat <- chat
    yakalanan$settings <- settings
    yakalanan$max_retries <- max_retries
    list(content = "Ayrıntılı içerik dökümü: başlık 1, başlık 2")
  }

  res <- env$summarize_file_with_llm("Rapor metni", "rapor.txt", list(model_selection = "m1"))
  expect_identical(res, "Ayrıntılı içerik dökümü: başlık 1, başlık 2")
  # Türkçe yorum: max_retries=2 ile çağrıldığı doğrulanır
  expect_identical(yakalanan$max_retries, 2)
})

test_that("summarize_file_with_llm düz karakter dönüşünü olduğu gibi döndürür", {
  env <- .filePipelineSummEnv()
  env$call_llm_with_retry <- function(chat, settings, max_retries = 2) {
    "Düz metin yanıtı"
  }
  res <- env$summarize_file_with_llm("içerik", "dosya.md", list())
  expect_identical(res, "Düz metin yanıtı")
})

test_that("summarize_file_with_llm kullanıcı mesajına dosya adı ve içerik parçasını koyar", {
  env <- .filePipelineSummEnv()
  yakalanan <- new.env(parent = emptyenv())
  env$call_llm_with_retry <- function(chat, settings, max_retries = 2) {
    yakalanan$chat <- chat
    "ok"
  }
  env$summarize_file_with_llm("ELEKTRONİK İÇERİK", "Türkçe_dosya.pdf", list())

  chat <- yakalanan$chat
  expect_length(chat, 2L)
  # Türkçe yorum: ilk mesaj sistem talimatı (özet DEĞİL, çıkarım) olmalı
  expect_identical(chat[[1]]$type, "system")
  expect_true(grepl("ÇIKARTMAK", chat[[1]]$content, fixed = TRUE))
  # Türkçe yorum: ikinci mesaj kullanıcı; dosya adı ve içerik parçası içermeli
  expect_identical(chat[[2]]$type, "user")
  expect_true(grepl("Türkçe_dosya.pdf", chat[[2]]$content, fixed = TRUE))
  expect_true(grepl("ELEKTRONİK İÇERİK", chat[[2]]$content, fixed = TRUE))
})

test_that("summarize_file_with_llm boş/NA dönüşte kısaltılmış içerik fallback'i üretir", {
  env <- .filePipelineSummEnv()
  # Türkçe yorum: boş karakter dönüşü -> fallback
  env$call_llm_with_retry <- function(chat, settings, max_retries = 2) ""
  res <- env$summarize_file_with_llm("Bu bir test içeriğidir.", "x.txt", list())
  expect_true(grepl("Özet çıkarılamadı", res, fixed = TRUE))
  expect_true(grepl("Bu bir test içeriğidir.", res, fixed = TRUE))

  # Türkçe yorum: NA dönüşü -> fallback
  env$call_llm_with_retry <- function(chat, settings, max_retries = 2) NA_character_
  res2 <- env$summarize_file_with_llm("içerik", "y.txt", list())
  expect_true(grepl("Özet çıkarılamadı", res2, fixed = TRUE))

  # Türkçe yorum: NULL içerikli list -> fallback
  env$call_llm_with_retry <- function(chat, settings, max_retries = 2) list(content = NULL)
  res3 <- env$summarize_file_with_llm("içerik", "z.txt", list())
  expect_true(grepl("Özet çıkarılamadı", res3, fixed = TRUE))
})

test_that("summarize_file_with_llm LLM hata fırlatınca güvenli fallback döner", {
  env <- .filePipelineSummEnv()
  env$call_llm_with_retry <- function(chat, settings, max_retries = 2) {
    stop("ağ hatası")
  }
  res <- env$summarize_file_with_llm("Önemli içerik buradadır.", "h.txt", list())
  expect_true(grepl("Özet çıkarılamadı", res, fixed = TRUE))
  expect_true(grepl("Önemli içerik buradadır.", res, fixed = TRUE))
})

test_that("summarize_file_with_llm uzun içeriği 60000 karaktere kısaltarak işler", {
  env <- .filePipelineSummEnv()
  yakalanan <- new.env(parent = emptyenv())
  env$call_llm_with_retry <- function(chat, settings, max_retries = 2) {
    yakalanan$chat <- chat
    ""  # fallback'i tetikle ki snippet kullanılsın
  }
  uzun <- paste(rep("A", 70000), collapse = "")
  res <- env$summarize_file_with_llm(uzun, "buyuk.txt", list())
  # Türkçe yorum: kullanıcı mesajındaki içerik 60000 karaktere kısaltılmalı
  user_msg <- yakalanan$chat[[2]]$content
  # "İçerik (kısaltılmış olabilir):\n" öneki + en fazla 60000 'A'
  a_count <- nchar(gsub("[^A]", "", user_msg))
  expect_equal(a_count, 60000)
  # Türkçe yorum: fallback parçası ilk 1000 karakterle sınırlı
  expect_true(grepl("Özet çıkarılamadı", res, fixed = TRUE))
})

test_that("summarize_file_with_llm NULL dosya metni için güvenli çalışır", {
  env <- .filePipelineSummEnv()
  env$call_llm_with_retry <- function(chat, settings, max_retries = 2) "tamam"
  res <- env$summarize_file_with_llm(NULL, "bos.txt", NULL)
  expect_identical(res, "tamam")
})
