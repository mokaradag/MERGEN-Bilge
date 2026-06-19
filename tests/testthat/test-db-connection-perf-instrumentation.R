# ==============================================================================
# Dosya Yolu: tests/testthat/test-db-connection-perf-instrumentation.R
# Açıklama: get_connection() / release_connection() içindeki opt-in [PERF]
#           bağlantı ölçüm kancalarının davranışını doğrular.
#
#   - Ölçüm yalnızca MERGEN_PERF_LOG / options(mergen.perf_log) açıkken çalışır.
#   - Havuz (Pool) dalı gerçek ODBC/SQL Server gerektirmez; bu nedenle test
#     tamamen çevrimdışı ve deterministiktir.
#   - Amaç: havuzlama olmadan her çağrının yeni bağlantı açtığı/ kapattığı
#     ana-iş parçacığı maliyetinin ölçülebilir kaldığını güvence altına almak.
# ==============================================================================

local({
  # Performans yardımcısı normalde helper_bootstrap.R tarafından yüklenir;
  # izole koşumda da garanti altına alınır.
  if (!exists("mergen_perf_log", envir = globalenv(), inherits = FALSE)) {
    source(
      file.path(repo_root_for_tests, "R", "helpers_performance_instrumentation.R"),
      encoding = "UTF-8",
      local = globalenv()
    )
  }
})

# Sahte Pool nesnesi + log yakalama altyapısı ile get_connection("primary")
# çağrısını çalıştırır. Tüm global durum (pool, log_info, perf bayrağı) test
# sonunda eski haline döndürülür.
.with_db_perf_probe <- function(perf_enabled, code) {
  if (!exists("get_connection", envir = globalenv(), inherits = TRUE)) {
    testthat::skip("get_connection yüklenmedi (helper_bootstrap çalışmadı).")
  }

  captured <- character()

  pool_existed <- exists("pool", envir = globalenv(), inherits = FALSE)
  old_pool <- if (pool_existed) get("pool", envir = globalenv(), inherits = FALSE) else NULL
  old_log_info <- get("log_info", envir = globalenv(), inherits = TRUE)
  old_opt <- getOption("mergen.perf_log")
  old_env <- Sys.getenv("MERGEN_PERF_LOG", unset = NA_character_)

  on.exit({
    if (pool_existed) {
      assign("pool", old_pool, envir = globalenv())
    } else if (exists("pool", envir = globalenv(), inherits = FALSE)) {
      rm("pool", envir = globalenv())
    }
    assign("log_info", old_log_info, envir = globalenv())
    options(mergen.perf_log = old_opt)
    if (is.na(old_env)) Sys.unsetenv("MERGEN_PERF_LOG") else Sys.setenv(MERGEN_PERF_LOG = old_env)
  }, add = TRUE)

  # Sahte havuz: gerçek bağlantı açılmadan get_connection erken döner.
  assign("pool", structure(list(), class = "Pool"), envir = globalenv())
  assign(
    "log_info",
    function(msg, ...) captured[[length(captured) + 1L]] <<- as.character(msg)[1],
    envir = globalenv()
  )

  Sys.unsetenv("MERGEN_PERF_LOG")
  options(mergen.perf_log = isTRUE(perf_enabled))

  info <- get("get_connection", envir = globalenv(), inherits = TRUE)("primary")
  code(info, captured)
}

test_that("get_connection havuz dalında ölçüm açıkken [PERF] bağlantı kaydı üretir", {
  .with_db_perf_probe(TRUE, function(info, captured) {
    expect_true(isTRUE(info$pooled))

    perf_lines <- captured[grepl("[PERF]", captured, fixed = TRUE)]
    expect_true(any(grepl("event=db.connection_open", perf_lines, fixed = TRUE)))
    expect_true(any(grepl("pooled=TRUE", perf_lines, fixed = TRUE)))
  })
})

test_that("get_connection ölçüm kapalıyken hiç [PERF] kaydı üretmez", {
  .with_db_perf_probe(FALSE, function(info, captured) {
    expect_true(isTRUE(info$pooled))

    perf_lines <- captured[grepl("[PERF]", captured, fixed = TRUE)]
    expect_length(perf_lines, 0L)
  })
})
