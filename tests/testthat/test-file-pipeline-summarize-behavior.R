# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-pipeline-summarize-behavior.R
# Açıklama: helpers_file_summary_task.R içindeki summarize_file_with_llm davranışını
#           doğrular. Bu fonksiyon yüklenen dosya metnini LLM ile ayrıntılı
#           içerik dökümüne çevirir; LLM list($content)/karakter dönüşünü
#           işler, boş/NA dönüşü ve LLM hatasını başarısızlık olarak iletir.
#           call_llm_with_retry stub'lanır; gerçek LLM/ağ/DB yoktur.
#           Çevrimdışı ve deterministik.
# ==============================================================================

# Türkçe yorum: özet görev dosyasını yalıtılmış ortama yükler. Bağımlılık
# call_llm_with_retry env içine stub edilir; as_llm_settings_list aynı dosyada
# tanımlıdır.
.filePipelineSummEnv <- function() {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  source(file.path(kok, "R", "helpers_file_summary_task.R"), encoding = "UTF-8", local = env)
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
  veri <- jsonlite::fromJSON(chat[[2]]$content)$untrusted_document
  expect_identical(veri$filename, "Türkçe_dosya.pdf")
  expect_identical(veri$truncated_content, "ELEKTRONİK İÇERİK")
  expect_match(chat[[1]]$content, "güvenilmeyen veridir", fixed = TRUE)
  expect_match(chat[[1]]$content, "uygulama", fixed = TRUE)
})

test_that("summarize_file_with_llm boş/NA dönüşü başarısızlık sayar; içerik parçası özet diye dönmez", {
  env <- .filePipelineSummEnv()
  for (donus in list("", NA_character_, list(content = NULL), "   ")) {
    env$call_llm_with_retry <- function(chat, settings, max_retries = 2) donus
    expect_error(env$summarize_file_with_llm("Bu bir test içeriğidir.", "x.txt", list()),
                 "Özet çıkarılamadı")
  }
})

test_that("summarize_file_with_llm LLM hatasını yutmaz; hat uyarı yoluna iletilir", {
  env <- .filePipelineSummEnv()
  env$call_llm_with_retry <- function(chat, settings, max_retries = 2) {
    stop("ağ hatası")
  }
  expect_error(env$summarize_file_with_llm("Önemli içerik buradadır.", "h.txt", list()), "ağ hatası")
})

test_that("summarize_file_with_llm uzun içeriği 60000 karaktere kısaltarak işler", {
  env <- .filePipelineSummEnv()
  yakalanan <- new.env(parent = emptyenv())
  env$call_llm_with_retry <- function(chat, settings, max_retries = 2) {
    yakalanan$chat <- chat
    "özet"
  }
  uzun <- paste(rep("A", 70000), collapse = "")
  res <- env$summarize_file_with_llm(uzun, "buyuk.txt", list())
  # Türkçe yorum: kullanıcı mesajındaki içerik 60000 karaktere kısaltılmalı
  user_msg <- yakalanan$chat[[2]]$content
  a_count <- nchar(gsub("[^A]", "", user_msg))
  expect_equal(a_count, 60000)
  expect_identical(res, "özet")
})

test_that("summarize_file_with_llm NULL dosya metni için güvenli çalışır", {
  env <- .filePipelineSummEnv()
  env$call_llm_with_retry <- function(chat, settings, max_retries = 2) "tamam"
  res <- env$summarize_file_with_llm(NULL, "bos.txt", NULL)
  expect_identical(res, "tamam")
})

test_that("özet görevi okuma hatasını özetlemez; durdurma dosyası LLM kapısına bağlanır", {
  env <- .filePipelineSummEnv()
  env$readFileContentToString <- function(...) stop("dosya yok")
  llm <- 0L
  env$summarize_file_with_llm <- function(...) { llm <<- llm + 1L; "özet" }
  gorev <- env$file_summary_task_fn("a.txt", "/yok/a.txt", list())
  expect_error(gorev(), "Dosya içeriği okunamadı")
  expect_identical(llm, 0L)

  dur <- tempfile("dur_")
  env$readFileContentToString <- function(...) "metin"
  kapi <- NULL
  env$summarize_file_with_llm <- function(...) {
    kapi <<- getOption("mergen.llm.stop_check")
    file.create(dur)
    "özet"
  }
  gorev <- env$file_summary_task_fn("a.txt", "/k/a.txt", list(), dur)
  # LLM sürerken durdurma dosyası oluşursa sonuç döndürülmez.
  expect_error(gorev(), "iptal edildi")
  expect_true(is.function(kapi))
  expect_true(kapi())
  expect_null(getOption("mergen.llm.stop_check"))
  unlink(dur)
})
