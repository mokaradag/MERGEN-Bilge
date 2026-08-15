# ==============================================================================
# Dosya Yolu: tests/testthat/test-deep-analysis-v2-provenance-stash-behavior.R
# Açıklama: Derin Düşünme v2 kanonik fact kayıtlarının uzlaştırma SONRASINDA
#           istek-kapsamlı provenance yuvasına taşındığını ve nihai `block`
#           doğrulamasında gerçekten kullanıldığını kanıtlar.
# ==============================================================================

.deep_v2_stash_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

  for (dosya in c(
    "helpers_pk_config.R",
    "helpers_pk_text_turkish.R",
    "helpers_pk_numeric_provenance.R",
    "helpers_pk_provenance.R",
    "helpers_deep_analysis_reconcile.R"
  )) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = env)
  }
  env
}

.deep_v2_fact <- function(id, value = 60) {
  list(
    fact_id = id,
    kind = "measure",
    column = "Progress",
    aggregation = "weighted_mean",
    value = value,
    status = "ok",
    unit = "%",
    percent_scale = "fraction",
    decimals = 1L,
    display = sprintf("%%%0.1f", value),
    label = "İlerleme"
  )
}

test_that("uzlaştırılmış v2 facts provenance stash'e taşınır ve başarısız paket dışlanır", {
  env <- .deep_v2_stash_env()
  iyi_id <- "progress.weighted.weighted_mean.overall.abc123"
  kotu_id <- "progress.failed.weighted_mean.overall.def456"

  query_results <- list(
    list(
      success = TRUE,
      query_name = "İyi v2",
      query_id = "q_good",
      pk_engine_mode = "v2",
      pk_facts = list(.deep_v2_fact(iyi_id)),
      pk_fallback_text = "**Hesaplanan değerler**\n- İlerleme: %60,0",
      pk_observation = list(query_id = "q_good")
    ),
    list(
      success = FALSE,
      query_name = "Başarısız v2",
      query_id = "q_bad",
      pk_engine_mode = "v2",
      pk_facts = list(.deep_v2_fact(kotu_id, 77)),
      pk_fallback_text = "KULLANILMAMALI",
      pk_observation = list(query_id = "q_bad")
    )
  )

  collected <- env$pk_deep_collect_v2_provenance(query_results)
  expect_length(collected$facts, 1L)
  expect_identical(collected$facts[[1]]$fact_id, iyi_id)
  expect_false(any(vapply(collected$facts,
                          function(f) identical(f$fact_id, kotu_id), logical(1))))
  expect_identical(collected$query_id, "q_good")
  expect_false(grepl("KULLANILMAMALI", collected$fallback_text, fixed = TRUE))

  session <- list(userData = new.env(parent = emptyenv()))
  env$pk_provenance_clear(session, request_id = "req-deep-v2")
  observers <- env$pk_deep_observation_helpers(
    session = session,
    conn = NULL,
    username = "sentetik",
    user_prompt = "ilerleme",
    request_id = "req-deep-v2",
    started_at = Sys.time()
  )

  ok <- observers$stash(
    footers = "\n\n---\n**Analiz Kaynağı**\n- **Sorgu:** q_good · İyi v2\n",
    facts = collected$facts,
    fallback_text = collected$fallback_text,
    query_id = collected$query_id,
    mode = "block"
  )
  expect_true(isTRUE(ok))

  pending <- env$pk_provenance_take(session, request_id = "req-deep-v2", full = TRUE)
  expect_length(pending$facts, 1L)
  expect_identical(pending$facts[[1]]$fact_id, iyi_id)
  expect_identical(pending$mode, "block")
  expect_true(grepl("Hesaplanan değerler", pending$fallback_text, fixed = TRUE))
})

test_that("stash'teki Deep v2 fact registry halüsinasyon sayıyı nihai block modunda engeller", {
  env <- .deep_v2_stash_env()
  fact_id <- "progress.weighted.weighted_mean.overall.abc123"
  fact <- .deep_v2_fact(fact_id)

  session <- list(userData = new.env(parent = emptyenv()))
  env$pk_provenance_clear(session, request_id = "req-block")
  observers <- env$pk_deep_observation_helpers(
    session = session,
    conn = NULL,
    username = "sentetik",
    user_prompt = "ilerleme",
    request_id = "req-block",
    started_at = Sys.time()
  )

  expect_true(isTRUE(observers$stash(
    footers = "\n\n---\n**Analiz Kaynağı**\n- **Sorgu:** q_good · İyi v2\n",
    facts = list(fact),
    fallback_text = "**Hesaplanan değerler**\n- İlerleme: %60,0",
    query_id = "q_good",
    mode = "block"
  )))

  model_text <- sprintf("Ağırlıklı ilerleme %%99,0 [fact:%s].", fact_id)
  decorated <- env$pk_provenance_decorate(
    model_text, session, request_id = "req-block"
  )

  expect_true(grepl("Yanıt doğrulanamadı", decorated, fixed = TRUE))
  expect_true(grepl("%60,0", decorated, fixed = TRUE))
  expect_false(grepl("%99,0", decorated, fixed = TRUE))
  expect_true(grepl("Analiz Kaynağı (Derin Analiz)", decorated, fixed = TRUE))
})
