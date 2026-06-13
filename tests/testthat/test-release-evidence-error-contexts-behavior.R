# ==============================================================================
# Dosya Yolu: tests/testthat/test-release-evidence-error-contexts-behavior.R
# Açıklama: Release kanıt okuyucusunun YENİ secret-safe hata-kategorisi özetini
#           doğrular: release_evidence_summarize_error_contexts (saf, ERROR
#           satırlarındaki "Error in <bağlam>:" etiketini sayar, mesaj içeriği
#           taşımaz), release_evidence_log_health entegrasyonu (error_contexts
#           alanı) ve module_health_release.R UI yüzeyi
#           (.health_release_error_contexts + health_release_ui). Çevrimdışı,
#           deterministik; gerçek artifact/DB/ağ yoktur.
# ==============================================================================

suppressMessages(library(shiny))

# Türkçe yorum: Saf okuyucu + sağlık biçimlendiriciler + release UI tek ortamda.
.errCtxEnv <- function() {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  source(file.path(kok, "R", "helpers_health_formatters.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "helpers_release_evidence.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "module_health_release.R"), encoding = "UTF-8", local = env)
  env
}

test_that("release_evidence_summarize_error_contexts boş/NULL girdide boş liste döner", {
  env <- .errCtxEnv()
  expect_identical(env$release_evidence_summarize_error_contexts(NULL), list())
  expect_identical(env$release_evidence_summarize_error_contexts(character(0)), list())
})

test_that("release_evidence_summarize_error_contexts bağlamı sayar ve azalan sırada döner", {
  env <- .errCtxEnv()
  satirlar <- c(
    "ERROR [2026-06-13 10:00:00] Error in TRUE_STREAM_SAVE_USER_MSG: bağlantı koptu",
    "ERROR [2026-06-13 10:01:00] Error in FILE PIPELINE: kopyalama hatası",
    "ERROR [2026-06-13 10:02:00] Error in TRUE_STREAM_SAVE_USER_MSG: yine koptu",
    "ERROR [2026-06-13 10:03:00] Error in TRUE_STREAM_SAVE_USER_MSG: tekrar"
  )
  res <- env$release_evidence_summarize_error_contexts(satirlar)
  expect_length(res, 2L)
  # Türkçe yorum: en sık bağlam (3 kez) başa gelmeli
  expect_identical(res[[1]]$context, "TRUE_STREAM_SAVE_USER_MSG")
  expect_identical(res[[1]]$count, 3L)
  expect_identical(res[[2]]$context, "FILE PIPELINE")
  expect_identical(res[[2]]$count, 1L)
})

test_that("release_evidence_summarize_error_contexts mesaj İÇERİĞİNİ taşımaz (secret-safe)", {
  env <- .errCtxEnv()
  satirlar <- c(
    "ERROR [2026-06-13 10:00:00] Error in DB_WRITE: gizli_token_ABC123 sızmamali"
  )
  res <- env$release_evidence_summarize_error_contexts(satirlar)
  duz <- paste(utils::capture.output(utils::str(res)), collapse = "\n")
  # Türkçe yorum: iki noktadan sonraki mesaj içeriği asla taşınmaz
  expect_false(grepl("gizli_token_ABC123", duz, fixed = TRUE))
  expect_false(grepl("sızmamali", duz, fixed = TRUE))
  expect_identical(res[[1]]$context, "DB_WRITE")
})

test_that("release_evidence_summarize_error_contexts 'Error in' kalıbına uymayanı 'diğer'e koyar", {
  env <- .errCtxEnv()
  satirlar <- c(
    "ERROR [2026-06-13 10:00:00] doğrudan log_error mesajı, bağlam yok",
    "ERROR [2026-06-13 10:01:00] başka bir serbest hata"
  )
  res <- env$release_evidence_summarize_error_contexts(satirlar)
  expect_length(res, 1L)
  expect_identical(res[[1]]$context, "diğer")
  expect_identical(res[[1]]$count, 2L)
})

test_that("release_evidence_summarize_error_contexts top_n sınırını uygular", {
  env <- .errCtxEnv()
  satirlar <- c(
    "ERROR x Error in A: m", "ERROR x Error in A: m", "ERROR x Error in A: m",
    "ERROR x Error in B: m", "ERROR x Error in B: m",
    "ERROR x Error in C: m"
  )
  res <- env$release_evidence_summarize_error_contexts(satirlar, top_n = 2L)
  expect_length(res, 2L)
  expect_identical(res[[1]]$context, "A")
  expect_identical(res[[2]]$context, "B")
})

test_that("release_evidence_summarize_error_contexts güvenli olmayan karakterleri ayıklar", {
  env <- .errCtxEnv()
  satirlar <- c("ERROR x Error in <script>alert(1)</script>: zararlı")
  res <- env$release_evidence_summarize_error_contexts(satirlar)
  expect_length(res, 1L)
  # Türkçe yorum: < > ( ) gibi karakterler ayıklanır; etiket güvenli kalır
  expect_false(grepl("<", res[[1]]$context, fixed = TRUE))
  expect_false(grepl(">", res[[1]]$context, fixed = TRUE))
  expect_false(grepl("(", res[[1]]$context, fixed = TRUE))
})

test_that("release_evidence_log_health çıktısı error_contexts alanını içerir", {
  env <- .errCtxEnv()
  log_dir <- withr::local_tempdir()
  log_yolu <- file.path(log_dir, sprintf("mergen_%s.log", format(Sys.Date(), "%Y%m%d")))
  writeLines(c(
    "INFO [2026-06-13 09:00:00] normal",
    "ERROR [2026-06-13 09:01:00] Error in SSO_VALIDATE: imza hatası",
    "ERROR [2026-06-13 09:02:00] Error in SSO_VALIDATE: tekrar",
    "WARN [2026-06-13 09:03:00] uyarı"
  ), log_yolu, useBytes = TRUE)

  ozet <- env$release_evidence_log_health(log_dir = log_dir)
  expect_true(ozet$found)
  expect_identical(ozet$error_count, 2L)
  expect_true(is.list(ozet$error_contexts))
  expect_length(ozet$error_contexts, 1L)
  expect_identical(ozet$error_contexts[[1]]$context, "SSO_VALIDATE")
  expect_identical(ozet$error_contexts[[1]]$count, 2L)
})

test_that(".health_release_error_contexts boş kategoride NULL, doluda özet listesi üretir", {
  env <- .errCtxEnv()
  expect_null(env$.health_release_error_contexts(NULL))
  expect_null(env$.health_release_error_contexts(list()))

  ui <- env$.health_release_error_contexts(list(
    list(context = "FILE PIPELINE", count = 4L),
    list(context = "DB_WRITE", count = 1L)
  ))
  html <- paste(as.character(ui), collapse = "\n")
  expect_true(grepl("Hata kategorileri", html, fixed = TRUE))
  expect_true(grepl("FILE PIPELINE", html, fixed = TRUE))
  expect_true(grepl("DB_WRITE", html, fixed = TRUE))
  expect_true(grepl("health-release-error-contexts", html, fixed = TRUE))
})

test_that("health_release_ui log kartında hata kategorilerini gösterir (mevcut alan varsa)", {
  env <- .errCtxEnv()
  overview <- list(
    generated_at = "2026-06-13 09:00:00",
    vm_evidence = list(found = FALSE, status = "not_found", steps = list(),
                       passed = 0L, failed = 0L, skipped = 0L),
    ai_validation = list(found = FALSE),
    log_health = list(
      found = TRUE, window_lines = 100L, error_count = 5L, warn_count = 1L,
      last_error_at = "2026-06-13 08:00:00",
      error_contexts = list(
        list(context = "MCP_TOOL", count = 3L),
        list(context = "IMAGE_GEN", count = 2L)
      )
    ),
    proof_note = "SKIP kanıt değildir."
  )
  ui <- env$health_release_ui(overview)
  html <- paste(as.character(ui), collapse = "\n")
  expect_true(grepl("MCP_TOOL", html, fixed = TRUE))
  expect_true(grepl("IMAGE_GEN", html, fixed = TRUE))
  expect_true(grepl("Hata kategorileri", html, fixed = TRUE))
})

test_that("health_release_ui error_contexts yoksa eski davranışı korur (regresyon yok)", {
  env <- .errCtxEnv()
  overview <- list(
    generated_at = "2026-06-13 09:00:00",
    vm_evidence = list(found = FALSE, status = "not_found", steps = list(),
                       passed = 0L, failed = 0L, skipped = 0L),
    ai_validation = list(found = FALSE),
    log_health = list(found = TRUE, window_lines = 10L, error_count = 0L,
                      warn_count = 0L, last_error_at = ""),
    proof_note = "not"
  )
  ui <- env$health_release_ui(overview)
  html <- paste(as.character(ui), collapse = "\n")
  # Türkçe yorum: error_contexts alanı yok -> kategori bloğu render edilmez
  expect_false(grepl("Hata kategorileri", html, fixed = TRUE))
  # Ama temel log kartı yine görünür
  expect_true(grepl("ERROR sayısı", html, fixed = TRUE))
})
