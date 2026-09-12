# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-document-orchestration-behavior.R
# Açıklama: helpers_claude_code_documents.R içindeki üç orkestratörü doğrular:
#           - prepare_claude_code_document_context: prompt niyetini + çalışma
#             dizinindeki binary dokümanları algılar, metin çıkarımı hazırlar,
#             manifest/inline payload/zenginleştirilmiş prompt üretir.
#           - write_claude_code_document_summary_file: özet metnini UTF-8 BOM ile
#             .txt dosyasına yazar (boş/eksik dizin -> "").
#           - summarize_claude_code_documents_with_local_llm: hazır metinleri
#             yerel LLM ile özetler, özet dosyasını üretir, file_write tool_use
#             ekler.
#
#           Tüm çıkarım/LLM/indirme bağımlılıkları stub'lanır; gerçek PDF/Excel/
#           DOCX fixture'ı YOKTUR (çıkarıcı stub'lanır). Modülün kaynak-zamanı
#           extractor-guard'ı, gerekli iki fonksiyon env'e önceden stub'lanarak
#           atlanır. Çevrimdışı ve deterministik.
# ==============================================================================

# Türkçe yorum: helpers_claude_code_documents.R'yi yalıtılmış ortama yükler.
# Kaynak-zamanı guard'ı extract_supported_document_text_for_claude ve
# get_office_document_reader_template_path varlığını arar; bunları önceden stub
# koyarak extractor dosyasının globalenv'e kaynaklanmasını önleriz.
.ccDocEnv <- function() {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  env$extract_supported_document_text_for_claude <- function(path) "ÖRNEK METİN"
  env$get_office_document_reader_template_path <- function() "/sahte/reader_template.R"
  # Doküman seçimi sınırları ve prompt dosya-adı çıkarımı hazırlık
  # yardımcılarında yaşar; izole test bunları da yüklemelidir.
  source(file.path(kok, "R", "config_claude_code.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "helpers_claude_code_bounded_scan.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "helpers_claude_code_input_matching.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "helpers_claude_code_runtime_prepare.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "helpers_claude_code_runtime_lease.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "helpers_claude_code_output_sync.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "helpers_claude_code_documents.R"), encoding = "UTF-8", local = env)
  # Özetleme orkestrasyonu (summarize/write_summary_file/build_summary_messages)
  # document_summary.R'ye ayrıldı; aynı izole ortama yüklenir.
  source(file.path(kok, "R", "helpers_claude_code_document_summary.R"), encoding = "UTF-8", local = env)
  env$cat <- function(...) invisible(NULL)
  env$CLAUDE_CODE_LOG_PREFIX <- "[CC]"
  env$log_error <- function(...) invisible(NULL)
  env$log_info <- function(...) invisible(NULL)
  env$log_warn <- function(...) invisible(NULL)
  env
}

# Türkçe yorum: prepare_claude_code_document_context için ortak stub'lar
.ccDocPrepareStubs <- function(env, support_dir, reading = TRUE, creation = FALSE,
                               docs = "/dokumanlar/rapor.pdf", has_docs = TRUE,
                               extract_text = "PDF metni") {
  env$get_claude_code_binary_doc_extensions <- function() c("pdf", "docx", "xls", "xlsx", "doc")
  env$workdir_has_binary_documents <- function(dir, exts, limits = NULL) isTRUE(has_docs)
  env$prompt_requests_existing_document_reading <- function(prompt) isTRUE(reading)
  env$prompt_requests_binary_document_creation <- function(prompt) isTRUE(creation)
  env$list_claude_code_binary_documents <- function(dir, extensions = NULL, max_files = 200L, limits = NULL) as.character(docs)
  env$get_claude_code_document_support_dir <- function(user_id = NULL,
                                                      request_id = NULL,
                                                      base_dir = NULL) support_dir
  env$get_claude_code_text_extractable_extensions <- function() c("pdf", "docx", "txt")
  env$sanitize_claude_doc_cache_name <- function(name) gsub("[^A-Za-z0-9_.-]", "_", name)
  env$extract_supported_document_text_for_claude <- function(path) extract_text
  invisible(env)
}

# ---------------------------------------------------------------------------
# prepare_claude_code_document_context
# ---------------------------------------------------------------------------

test_that("prepare_claude_code_document_context okuma niyeti yoksa doküman görevi algılamaz", {
  env <- .ccDocEnv()
  sd <- tempfile("destek"); dir.create(sd)
  .ccDocPrepareStubs(env, sd, reading = FALSE)
  res <- env$prepare_claude_code_document_context("Word dökümanı oluştur", runtime_workdir = tempdir())
  expect_false(res$document_task_detected)
  expect_false(res$text_sidecars_ready)
})

test_that("prepare_claude_code_document_context oluşturma niyeti varken okuma yolunu devreye almaz", {
  env <- .ccDocEnv()
  sd <- tempfile("destek"); dir.create(sd)
  .ccDocPrepareStubs(env, sd, reading = TRUE, creation = TRUE)
  res <- env$prepare_claude_code_document_context("dosyayı oku ve yeni docx oluştur", runtime_workdir = tempdir())
  expect_false(res$document_task_detected)
})

test_that("prepare_claude_code_document_context doküman yoksa görev algılamaz", {
  env <- .ccDocEnv()
  sd <- tempfile("destek"); dir.create(sd)
  .ccDocPrepareStubs(env, sd, reading = TRUE, has_docs = FALSE)
  res <- env$prepare_claude_code_document_context("bu dosyayı özetle", runtime_workdir = tempdir())
  expect_false(res$document_task_detected)
})

test_that("prepare_claude_code_document_context görev var ama liste boşsa has_binary_docs FALSE döner", {
  env <- .ccDocEnv()
  sd <- tempfile("destek"); dir.create(sd)
  .ccDocPrepareStubs(env, sd, reading = TRUE, has_docs = TRUE, docs = character(0))
  res <- env$prepare_claude_code_document_context("bu dosyayı özetle", runtime_workdir = tempdir())
  expect_true(res$document_task_detected)
  expect_false(res$has_binary_docs)
})

test_that("prepare_claude_code_document_context geçerli dokümandan metin çıkarıp manifest/prompt üretir", {
  env <- .ccDocEnv()
  sd <- tempfile("destek"); dir.create(sd)
  .ccDocPrepareStubs(env, sd, reading = TRUE, docs = "/dokumanlar/rapor.pdf",
                     extract_text = "Bu raporun ayrıntılı içeriğidir.")
  res <- env$prepare_claude_code_document_context("rapor.pdf dosyasını özetle", runtime_workdir = tempdir())
  expect_true(res$document_task_detected)
  expect_true(res$has_binary_docs)
  expect_true(res$text_sidecars_ready)
  expect_length(res$prepared_files, 1L)
  expect_true(nzchar(res$manifest_path))
  expect_true(file.exists(res$manifest_path))
  # Türkçe yorum: zenginleştirilmiş prompt orijinalden farklı olmalı (manifest eklenir)
  expect_false(identical(res$prompt, "rapor.pdf dosyasını özetle"))
  # Türkçe yorum: metin sidecar dosyası destek dizinine yazılmış olmalı
  expect_true(length(list.files(sd, pattern = "\\.txt$")) >= 1L)
})

test_that("prepare_claude_code_document_context desteklenmeyen uzantıyı çıkaramaz ve sidecar üretmez", {
  env <- .ccDocEnv()
  sd <- tempfile("destek"); dir.create(sd)
  # Türkçe yorum: .doc çıkarılabilir uzantı listesinde değil -> unsupported
  .ccDocPrepareStubs(env, sd, reading = TRUE, docs = "/dokumanlar/eski.doc")
  res <- env$prepare_claude_code_document_context("eski.doc özetle", runtime_workdir = tempdir())
  expect_true(res$has_binary_docs)
  expect_false(res$text_sidecars_ready)
  expect_true("eski.doc" %in% res$unsupported_files)
})

test_that("prepare_claude_code_document_context boş metin çıkarımında sidecar üretmez", {
  env <- .ccDocEnv()
  sd <- tempfile("destek"); dir.create(sd)
  .ccDocPrepareStubs(env, sd, reading = TRUE, docs = "/dokumanlar/bos.pdf", extract_text = "")
  res <- env$prepare_claude_code_document_context("bos.pdf özetle", runtime_workdir = tempdir())
  expect_true(res$has_binary_docs)
  expect_false(res$text_sidecars_ready)
})

# ---------------------------------------------------------------------------
# write_claude_code_document_summary_file
# ---------------------------------------------------------------------------

test_that("write_claude_code_document_summary_file boş dizin/metin için boş string döner", {
  env <- .ccDocEnv()
  expect_identical(env$write_claude_code_document_summary_file("özet", ""), "")
  expect_identical(env$write_claude_code_document_summary_file("", tempdir()), "")
  expect_identical(env$write_claude_code_document_summary_file("özet", "/var/olmayan/dizin"), "")
})

test_that("write_claude_code_document_summary_file geçerli girdide dosya yazar ve yolu döner", {
  env <- .ccDocEnv()
  od <- tempfile("ozet"); dir.create(od)
  yol <- env$write_claude_code_document_summary_file("Türkçe özet: çğışöü", od)
  expect_true(nzchar(yol))
  expect_true(file.exists(yol))
  expect_true(grepl("dosya_aciklamalari\\.txt$", yol))
})

test_that("write_claude_code_document_summary_file BOM yazıcı başarısızsa boş string döner", {
  env <- .ccDocEnv()
  od <- tempfile("ozet"); dir.create(od)
  env$write_claude_code_utf8_bom_text_file <- function(text, file_path) FALSE
  expect_identical(env$write_claude_code_document_summary_file("özet", od), "")
})

# ---------------------------------------------------------------------------
# summarize_claude_code_documents_with_local_llm
# ---------------------------------------------------------------------------

test_that("summarize_claude_code_documents_with_local_llm hazır metin yoksa hata döner", {
  env <- .ccDocEnv()
  res <- env$summarize_claude_code_documents_with_local_llm(
    document_context = list(text_sidecars_ready = FALSE),
    model_id = "m1"
  )
  expect_false(res$success)
  expect_true(grepl("Hazır doküman metin çıkarımı bulunamadı", res$error, fixed = TRUE))
})

test_that("summarize_claude_code_documents_with_local_llm başarıyla özetler ve dosya/araç üretir", {
  env <- .ccDocEnv()
  od <- tempfile("ozet"); dir.create(od)
  env$call_local_llm <- function(chat_history, current_settings) {
    list(content = "Ayrıntılı doküman özeti.", duration = 1.2)
  }
  res <- env$summarize_claude_code_documents_with_local_llm(
    document_context = list(text_sidecars_ready = TRUE, prompt = "özetle"),
    model_id = "m1", output_dir = od
  )
  expect_true(res$success)
  expect_identical(res$output, "Ayrıntılı doküman özeti.")
  expect_length(res$tool_uses, 1L)
  expect_identical(res$tool_uses[[1]]$name, "file_write")
  expect_true(nzchar(res$generated_summary_path))
  expect_true(file.exists(res$generated_summary_path))
})

test_that("summarize_claude_code_documents_with_local_llm çıktı dizini yoksa dosya üretmeden başarı döner", {
  env <- .ccDocEnv()
  env$call_local_llm <- function(chat_history, current_settings) list(content = "özet metni")
  res <- env$summarize_claude_code_documents_with_local_llm(
    document_context = list(text_sidecars_ready = TRUE, prompt = "özetle"),
    model_id = "m1", output_dir = ""
  )
  expect_true(res$success)
  expect_identical(res$output, "özet metni")
  expect_identical(res$tool_uses, list())
  expect_identical(res$generated_summary_path, "")
})

test_that("summarize_claude_code_documents_with_local_llm boş LLM çıktısında hata döner", {
  env <- .ccDocEnv()
  od <- tempfile("ozet"); dir.create(od)
  env$call_local_llm <- function(chat_history, current_settings) list(content = "")
  res <- env$summarize_claude_code_documents_with_local_llm(
    document_context = list(text_sidecars_ready = TRUE, prompt = "özetle"),
    model_id = "m1", output_dir = od
  )
  expect_false(res$success)
  expect_true(grepl("Doküman özeti oluşturulamadı", res$error, fixed = TRUE))
})

test_that("summarize_claude_code_documents_with_local_llm LLM hata fırlatınca güvenli hata döner", {
  env <- .ccDocEnv()
  env$call_local_llm <- function(chat_history, current_settings) stop("ağ hatası")
  res <- env$summarize_claude_code_documents_with_local_llm(
    document_context = list(text_sidecars_ready = TRUE, prompt = "özetle"),
    model_id = "m1", output_dir = ""
  )
  expect_false(res$success)
  expect_true(grepl("Doküman özeti oluşturulamadı", res$error, fixed = TRUE))
  expect_true(grepl("ağ hatası", res$error, fixed = TRUE))
})
