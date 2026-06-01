# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-model-config-behavior.R
# Açıklama: R/helpers_claude_code_model_config.R saf/çevre-güdümlü yardımcılarının
#           DAVRANIŞSAL testleri. Mevcut test-claude-code-model-config-refactor-
#           contract.R yalnızca dosya ayrımını/varlığını doğrular; burada gerçek
#           davranış test edilir:
#             - parse_claude_code_env_list (ayraç/boşluk/tekille ayrıştırma)
#             - get_claude_code_model_capabilities (çevre varsayılanları)
#             - get_claude_code_runtime_model_capabilities / is_claude_code_thinking_model
#             - prompt_mentions_binary_document_type (ikili doküman türü tespiti)
#             - prompt_requests_document_operation (doküman işlem niyeti)
#             - workdir_has_binary_documents (yerel geçici dizin fixture'ı)
#           Bu dosyadaki desenler gerçek Türkçe karakter sınıfları (\b + [çğıöşü])
#           kullandığı için PCRE2 ile UYUMLUDUR. Shiny/DB/ağ/jsonlite GEREKMEZ.
# ==============================================================================

.ccmc_source_once <- function() {
  if (!exists("%||%", inherits = TRUE)) {
    assign("%||%", function(a, b) if (is.null(a)) b else a, envir = globalenv())
  }
  if (!exists("parse_claude_code_env_list",
              envir = globalenv(), mode = "function", inherits = TRUE)) {
    source(
      file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_model_config.R"),
      encoding = "UTF-8", local = globalenv()
    )
  }
  invisible(TRUE)
}

# Verilen çevre değişkenlerini geçici ayarlayıp sonunda eski hale getiren yardımcı.
.ccmc_with_env <- function(vars, code) {
  nms <- names(vars)
  old <- as.list(Sys.getenv(nms, names = TRUE, unset = NA_character_))
  on.exit({
    for (nm in nms) {
      v <- old[[nm]]
      if (is.na(v)) {
        Sys.unsetenv(nm)
      } else {
        a <- list(v); names(a) <- nm; do.call(Sys.setenv, a)
      }
    }
  }, add = TRUE)
  for (nm in nms) {
    v <- vars[[nm]]
    if (is.na(v)) {
      Sys.unsetenv(nm)
    } else {
      a <- list(v); names(a) <- nm; do.call(Sys.setenv, a)
    }
  }
  force(code)
}

# ------------------------------------------------------------------------------
# parse_claude_code_env_list
# ------------------------------------------------------------------------------
testthat::test_that("parse_claude_code_env_list ayraçlarla böler, trimler, boşları atar, tekille", {
  .ccmc_source_once()
  testthat::expect_identical(parse_claude_code_env_list(NULL), character(0))
  testthat::expect_identical(parse_claude_code_env_list(""), character(0))
  testthat::expect_identical(parse_claude_code_env_list("a,b,c"), c("a", "b", "c"))
  # Boşluklar trimlenir, noktalı virgül de ayraçtır.
  testthat::expect_identical(parse_claude_code_env_list("a, b ; c"), c("a", "b", "c"))
  # Ardışık ayraçlar ve boş parçalar atılır.
  testthat::expect_identical(parse_claude_code_env_list("a,,b"), c("a", "b"))
  # Satır sonu da ayraçtır.
  testthat::expect_identical(parse_claude_code_env_list("a\nb"), c("a", "b"))
  # Tekrarlar tekilleştirilir.
  testthat::expect_identical(parse_claude_code_env_list("a,a,b"), c("a", "b"))
  # Vektör girdide yalnızca ilk öğe kullanılır.
  testthat::expect_identical(parse_claude_code_env_list(c("x,y", "z")), c("x", "y"))
})

# ------------------------------------------------------------------------------
# get_claude_code_model_capabilities (çevre güdümlü)
# ------------------------------------------------------------------------------
testthat::test_that("get_claude_code_model_capabilities çevre değişkenlerini ayrıştırır", {
  .ccmc_source_once()
  caps <- .ccmc_with_env(
    list(
      CLAUDE_CODE_THINKING_MODELS = "m1,m2",
      CLAUDE_CODE_BINARY_DOC_EXTENSIONS = "PDF,DOCX",
      CLAUDE_CODE_AUTO_FALLBACK_NON_THINKING_FOR_BINARY_DOCS = "FALSE"
    ),
    get_claude_code_model_capabilities()
  )
  testthat::expect_identical(caps$thinking_models, c("m1", "m2"))
  # Uzantılar küçük harfe çevrilir.
  testthat::expect_identical(caps$binary_doc_extensions, c("pdf", "docx"))
  testthat::expect_false(isTRUE(caps$auto_fallback_non_thinking_for_binary_docs))
})

testthat::test_that("get_claude_code_model_capabilities makul varsayılanlar üretir", {
  .ccmc_source_once()
  caps <- .ccmc_with_env(
    list(
      CLAUDE_CODE_THINKING_MODELS = NA_character_,
      CLAUDE_CODE_BINARY_DOC_EXTENSIONS = NA_character_,
      CLAUDE_CODE_AUTO_FALLBACK_NON_THINKING_FOR_BINARY_DOCS = NA_character_
    ),
    get_claude_code_model_capabilities()
  )
  testthat::expect_identical(caps$thinking_models, character(0))
  # Varsayılan uzantı listesi pdf/xlsx/... içerir (küçük harf).
  testthat::expect_true(all(c("pdf", "xlsx", "docx") %in% caps$binary_doc_extensions))
  # Varsayılan auto-fallback "TRUE".
  testthat::expect_true(isTRUE(caps$auto_fallback_non_thinking_for_binary_docs))
})

# ------------------------------------------------------------------------------
# get_claude_code_runtime_model_capabilities / is_claude_code_thinking_model
# ------------------------------------------------------------------------------
testthat::test_that("is_claude_code_thinking_model çevredeki thinking listesine göre karar verir", {
  .ccmc_source_once()
  # Sentetik, gerçek config'te bulunmayan model id'leri kullanılır.
  .ccmc_with_env(
    list(CLAUDE_CODE_THINKING_MODELS = "mergen-test-thinker-001"),
    {
      testthat::expect_true(is_claude_code_thinking_model("mergen-test-thinker-001"))
      testthat::expect_false(is_claude_code_thinking_model("mergen-test-normal-002"))
      caps <- get_claude_code_runtime_model_capabilities("mergen-test-thinker-001")
      testthat::expect_true(isTRUE(caps$thinking))
    }
  )
  # Boş/NULL model -> FALSE.
  testthat::expect_false(is_claude_code_thinking_model(""))
  testthat::expect_false(is_claude_code_thinking_model(NULL))
})

# ------------------------------------------------------------------------------
# prompt_mentions_binary_document_type
# ------------------------------------------------------------------------------
testthat::test_that("prompt_mentions_binary_document_type ikili doküman türlerini tanır", {
  .ccmc_source_once()
  testthat::expect_true(prompt_mentions_binary_document_type("bana bir pdf hazırla"))
  testthat::expect_true(prompt_mentions_binary_document_type("excel tablosu lazım"))
  testthat::expect_true(prompt_mentions_binary_document_type("powerpoint sunum yap"))
  # Gerçek Türkçe ifade (küçük harf girdi; tolower yerel-bağımsız kalsın diye).
  testthat::expect_true(prompt_mentions_binary_document_type("çalışma kitabı"))
})

testthat::test_that("prompt_mentions_binary_document_type doküman türü yoksa FALSE döner", {
  .ccmc_source_once()
  testthat::expect_false(prompt_mentions_binary_document_type("merhaba dünya"))
  testthat::expect_false(prompt_mentions_binary_document_type(""))
  testthat::expect_false(prompt_mentions_binary_document_type(NULL))
})

# ------------------------------------------------------------------------------
# prompt_requests_document_operation
# ------------------------------------------------------------------------------
testthat::test_that("prompt_requests_document_operation ASCII-baş-harfli işlem fiil/anahtarlarını tanır", {
  .ccmc_source_once()
  testthat::expect_true(prompt_requests_document_operation("dosyayı oku"))
  testthat::expect_true(prompt_requests_document_operation("veriyi analiz et"))
  testthat::expect_true(prompt_requests_document_operation("bunu incele"))
  testthat::expect_true(prompt_requests_document_operation("listele"))
  testthat::expect_true(prompt_requests_document_operation("read the file"))
  testthat::expect_true(prompt_requests_document_operation("summarize this"))
})

testthat::test_that("prompt_requests_document_operation işlem niyeti yoksa FALSE döner", {
  .ccmc_source_once()
  testthat::expect_false(prompt_requests_document_operation("merhaba"))
  testthat::expect_false(prompt_requests_document_operation(""))
  testthat::expect_false(prompt_requests_document_operation(NULL))
})

testthat::test_that("prompt_requests_document_operation: Türkçe-baş-harfli fiil sınırlaması (karakterizasyon)", {
  .ccmc_source_once()
  # MEVCUT DAVRANIŞ: Desenler ASCII-yalnız \b sınırı kullandığından, Türkçe'ye özgü
  # bir harfle BAŞLAYAN fiiller (ö/ç/ş/ğ/ı/ü) yakalanmaz. Örn. "\bözet" başındaki
  # \b, boşluk ile 'ö' arasında sınır göremez (ikisi de ASCII-\w değildir).
  # ASCII varyantı "ozetle" yakalanırken Türkçe "özetle" yakalanmaz.
  testthat::expect_true(prompt_requests_document_operation("ozetle"))   # ASCII -> TRUE
  testthat::expect_false(prompt_requests_document_operation("özetle"))  # Türkçe ö -> FALSE (sınırlama)
})

# ------------------------------------------------------------------------------
# workdir_has_binary_documents (geçici dizin fixture'ı)
# ------------------------------------------------------------------------------
testthat::test_that("workdir_has_binary_documents geçersiz/boş dizinde FALSE döner", {
  .ccmc_source_once()
  testthat::expect_false(workdir_has_binary_documents(NULL))
  testthat::expect_false(workdir_has_binary_documents("/var/bos/olmayan/dizin/xyz"))

  bos_dir <- file.path(tempdir(), "ccmc_empty_dir")
  dir.create(bos_dir, showWarnings = FALSE)
  on.exit(unlink(bos_dir, recursive = TRUE), add = TRUE)
  testthat::expect_false(workdir_has_binary_documents(bos_dir, extensions = c("pdf")))
})

testthat::test_that("workdir_has_binary_documents açık uzantı listesiyle ikili dokümanı bulur", {
  .ccmc_source_once()
  d <- file.path(tempdir(), "ccmc_docs_dir")
  dir.create(d, showWarnings = FALSE)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)

  writeLines("x", file.path(d, "rapor.pdf"))
  writeLines("x", file.path(d, "notlar.txt"))

  testthat::expect_true(workdir_has_binary_documents(d, extensions = c("pdf")))
  # Yalnızca .docx aranınca .pdf/.txt eşleşmez.
  testthat::expect_false(workdir_has_binary_documents(d, extensions = c("docx")))
})

testthat::test_that("workdir_has_binary_documents extensions=NULL iken çevre varsayılanını kullanır", {
  .ccmc_source_once()
  d <- file.path(tempdir(), "ccmc_default_ext_dir")
  dir.create(d, showWarnings = FALSE)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  writeLines("x", file.path(d, "sunum.pptx"))

  .ccmc_with_env(
    list(CLAUDE_CODE_BINARY_DOC_EXTENSIONS = "pdf,pptx,docx"),
    testthat::expect_true(workdir_has_binary_documents(d, extensions = NULL))
  )
})
