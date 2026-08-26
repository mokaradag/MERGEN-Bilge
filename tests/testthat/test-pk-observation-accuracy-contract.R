# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-observation-accuracy-contract.R
# Açıklama: Gözlem doğruluğu sözleşmeleri: toplulaştırma öncesi satır sayısı,
#           yalnızca uygulanan filtreler ve düşürülen filtrelerin bildirimi.
# ==============================================================================

.pk_observation_test_env <- function() {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  root <- resolve_repo_root_for_tests()

  for (rel in c(
    "R/helpers_pk_config.R",
    "R/helpers_pk_provenance.R",
    "R/helpers_pk_telemetry_record.R",
    # İZOLE YÜKLEME: taban dosya manifest sırasına göre AÇIKÇA önce gelir
    # (üretimdeki dinamik `source()` keşfi KALDIRILDI).
    "R/helpers_pk_analysis_filters_base.R",
    "R/helpers_pk_analysis_filters.R",
    # Manifest sirasi: taban dosya `helpers_pk_telemetry.R` ONCESINDE yuklenir.
    # (Uretim dosyasindaki dinamik `source()` kesfi KALDIRILDI.)
    "R/helpers_pk_telemetry_base.R",
    "R/helpers_pk_telemetry.R"
  )) {
    source(file.path(root, rel), encoding = "UTF-8", local = env)
  }

  env
}

test_that("toplulaştırma kökeninde eşleşen kayıt sayısı korunur", {
  env <- .pk_observation_test_env()
  env$pk_provenance_current_request_id <- function(session) "req-count"

  result <- local({
    session <- list()
    selected_query <- list(id = "q-count", name = "Sayım", engine = "v1")
    env$apply_smart_filters(
      data.frame(tur = rep(c("A", "B"), each = 125L), stringsAsFactors = FALSE),
      list(
        filters = list(list(column = "tur", value = "A", operation = "exact_match")),
        aggregation = "count",
        group_column = NULL
      ),
      "A türünü say"
    )
  })

  expect_identical(nrow(result), 1L)

  observation <- env$pk_filter_observation_take(list(
    request_id = "req-count",
    query_id = "q-count",
    query_name = "Sayım",
    question = "A türünü say"
  ))

  expect_identical(observation$matched_rows, 125L)
  expect_length(observation$applied_filters, 1L)
  expect_length(observation$dropped_filters, 0L)
})

test_that("gözlem yalnız uygulanan filtreleri ve yapılandırılmış motoru kaydeder", {
  env <- .pk_observation_test_env()
  env$pk_provenance_current_request_id <- function(session) "req-observe"
  env$query_library <- list(list(id = "q-engine", name = "Motor Sorgusu", engine = "v2"))

  captured <- new.env(parent = emptyenv())
  env$pk_telemetry_log_analysis <- function(info, conn, db_target = NULL) {
    captured$info <- info
    invisible(TRUE)
  }
  env$pk_provenance_stash <- function(session, footer, request_id = NULL, ...) {
    captured$footer <- footer
    captured$request_id <- request_id
    invisible(TRUE)
  }

  result <- local({
    session <- list()
    selected_query <- env$query_library[[1]]
    env$apply_smart_filters(
      data.frame(amount = 1:5),
      list(
        filters = list(
          list(column = "amount", value = "2", operation = "greater_than"),
          list(column = "missing", value = "x", operation = "exact_match"),
          list(column = "amount", value = "not-a-number", operation = "exact_match")
        ),
        aggregation = "count",
        group_column = NULL
      ),
      "iki üstünü say"
    )
  })

  expect_identical(nrow(result), 1L)

  env$pk_analysis_observe(list(), NULL, list(
    request_id = "req-observe",
    question = "iki üstünü say",
    username = "kullanici",
    engine = "v1",
    query_id = "q-engine",
    query_name = "Motor Sorgusu",
    filter_status = "ok_filtered",
    filters = list(
      list(column = "amount", value = "2", operation = "greater_than"),
      list(column = "missing", value = "x", operation = "exact_match"),
      list(column = "amount", value = "not-a-number", operation = "exact_match")
    ),
    pre_rls_rows = 5L,
    authorized_rows = 5L,
    filtered_rows = 1L,
    outcome = "Basarili"
  ))

  expect_identical(captured$info$engine, "v2")
  expect_identical(captured$info$filtered_rows, 3L)
  expect_identical(captured$info$filter_count, 1L)
  expect_identical(captured$info$filters[[1]]$column, "amount")
  expect_true("filter_dropped" %in% captured$info$degradation_codes)
  expect_true(grepl("missing", captured$footer, fixed = TRUE))
  expect_true(grepl("not-a-number", captured$footer, fixed = TRUE))
  expect_identical(captured$request_id, "req-observe")
})

test_that("tüm filtreler düşürüldüyse ok_no_filter bozuk olarak raporlanır", {
  env <- .pk_observation_test_env()
  env$pk_provenance_current_request_id <- function(session) "req-expr"

  captured <- new.env(parent = emptyenv())
  env$pk_telemetry_log_analysis <- function(info, conn, db_target = NULL) {
    captured$info <- info
    invisible(TRUE)
  }
  env$pk_provenance_stash <- function(session, footer, request_id = NULL, ...) {
    captured$footer <- footer
    invisible(TRUE)
  }

  # LLM yalnızca filter_expression döndürdü ve ifade değerlendirilemedi:
  # uygulanan filtre yok, düşürülen tek bir ifade var.
  result <- local({
    session <- list()
    selected_query <- list(id = "q-expr", name = "Ifade Sorgusu")
    env$apply_smart_filters(
      data.frame(amount = 1:5),
      list(
        filters = list(),
        filter_expression = "bilinmeyen_sutun > 2",
        aggregation = NULL,
        group_column = NULL
      ),
      "ifade sorusu"
    )
  })

  expect_identical(nrow(result), 5L)

  env$pk_analysis_observe(list(), NULL, list(
    request_id = "req-expr",
    question = "ifade sorusu",
    username = "kullanici",
    query_id = "q-expr",
    query_name = "Ifade Sorgusu",
    filter_status = "ok_no_filter",
    filters = list(),
    pre_rls_rows = 5L,
    authorized_rows = 5L,
    filtered_rows = 5L,
    outcome = "Basarili"
  ))

  # Alt bilgi "soru genel olarak yorumlandı" DEMEMELİ; durum bozuktur.
  expect_identical(captured$info$filter_status, "malformed")
  expect_true("filter_malformed" %in% captured$info$degradation_codes)
  expect_true("filter_dropped" %in% captured$info$degradation_codes)
  expect_false(grepl("genel olarak yorumland", captured$footer, fixed = TRUE))
})

test_that("düşürülen filtre stopped gibi özgül durumları ezmez", {
  env <- .pk_observation_test_env()
  env$pk_provenance_current_request_id <- function(session) "req-stopped"

  captured <- new.env(parent = emptyenv())
  env$pk_telemetry_log_analysis <- function(info, conn, db_target = NULL) {
    captured$info <- info
    invisible(TRUE)
  }
  env$pk_provenance_stash <- function(session, footer, request_id = NULL, ...) {
    invisible(TRUE)
  }

  local({
    session <- list()
    selected_query <- list(id = "q-stop", name = "Durdurulan")
    env$apply_smart_filters(
      data.frame(amount = 1:5),
      list(
        filters = list(),
        filter_expression = "bilinmeyen_sutun > 2",
        aggregation = NULL,
        group_column = NULL
      ),
      "durdurulan soru"
    )
  })

  env$pk_analysis_observe(list(), NULL, list(
    request_id = "req-stopped",
    question = "durdurulan soru",
    username = "kullanici",
    query_id = "q-stop",
    query_name = "Durdurulan",
    filter_status = "stopped",
    filters = list(),
    pre_rls_rows = 5L,
    authorized_rows = 5L,
    filtered_rows = 5L,
    outcome = "Durduruldu"
  ))

  expect_identical(captured$info$filter_status, "stopped")
})
