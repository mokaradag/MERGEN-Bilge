# ==============================================================================
# Dosya Yolu: tests/testthat/test-e2e-health-dashboard-regression.R
# Açıklama: Sistem Durumu paneli için offline, gizli değer maskeleme ve refresh
#           yarış durumlarını kapsayan deterministik E2E benzeri regresyon testi.
# ==============================================================================

.find_e2e_health_repo_root <- function() {
  candidates <- unique(normalizePath(
    c(
      getwd(),
      file.path(getwd(), ".."),
      file.path(getwd(), "..", "..")
    ),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "tests", "testthat"))) {
      return(candidate)
    }
  }

  stop("Health E2E test repo kökünü bulamadı. Testi repo kökünden çalıştırın.", call. = FALSE)
}

repo_root_e2e_health <- .find_e2e_health_repo_root()

if (!exists("resolve_repo_root_for_tests", envir = globalenv(), inherits = FALSE)) {
  source(
    file.path(repo_root_e2e_health, "tests", "testthat", "helper_bootstrap.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
}

repo_root_e2e_health <- resolve_repo_root_for_tests()

if (!exists("e2e_health_config", envir = globalenv(), inherits = FALSE)) {
  source(
    file.path(
      repo_root_e2e_health,
      "tests",
      "testthat",
      "helper_e2e_health_dashboard_harness.R"
    ),
    encoding = "UTF-8",
    local = globalenv()
  )
}

source(file.path(repo_root_e2e_health, "R", "utils_common.R"), encoding = "UTF-8", local = globalenv())
source(file.path(repo_root_e2e_health, "R", "helpers_health_formatters.R"), encoding = "UTF-8", local = globalenv())
source(file.path(repo_root_e2e_health, "R", "helpers_health_checks.R"), encoding = "UTF-8", local = globalenv())

test_that("health snapshot redacts secrets and skips public endpoint probes", {
  config <- e2e_health_config()
  recorder <- e2e_health_probe_recorder()

  checks <- e2e_health_collect_snapshot(
    config = config,
    probe = recorder$probe
  )

  rendered_text <- paste(capture.output(print(checks)), collapse = "\n")

  for (secret in e2e_health_secret_texts(config)) {
    expect_false(
      grepl(secret, rendered_text, fixed = TRUE),
      info = paste("Gizli değer sağlık çıktısına sızmamalı:", secret)
    )
  }

  secret_row <- checks[checks$id == "env.AI_KEYS_MASTER", , drop = FALSE]
  expect_identical(nrow(secret_row), 1L)
  expect_identical(secret_row$status[[1]], "ok")
  expect_true(grepl("configured", secret_row$value[[1]], fixed = TRUE))
  expect_false(grepl("super-secret-master-key", secret_row$value[[1]], fixed = TRUE))

  probe_calls <- recorder$calls()
  expect_true(any(grepl("127.0.0.1", probe_calls, fixed = TRUE)))
  expect_false(any(grepl("example.com", probe_calls, fixed = TRUE)))

  public_row <- checks[checks$id == "endpoint.image", , drop = FALSE]
  expect_identical(public_row$status[[1]], "warning")
  expect_identical(public_row$value[[1]], "Atlandı")
  expect_match(public_row$detail[[1]], "Genel internet|public endpoint", ignore.case = TRUE)
})

test_that("production health endpoint guard skips public URLs before network probe", {
  res <- health_check_http_endpoint(
    id = "endpoint.public_contract",
    label = "Public Endpoint Contract",
    endpoint = "https://example.com/v1/models",
    configured_required = FALSE,
    timeout_sec = 1
  )

  expect_identical(res$status[[1]], "warning")
  expect_identical(res$value[[1]], "Atlandı")
  expect_match(res$detail[[1]], "Genel internet|public endpoint", ignore.case = TRUE)
})

test_that("health refresh result is idempotent and stale-safe", {
  config <- e2e_health_config()
  recorder <- e2e_health_probe_recorder()

  checks_first <- e2e_health_collect_snapshot(
    config = config,
    probe = recorder$probe
  )

  state <- e2e_health_new_state()
  state <- e2e_health_begin_refresh(state, "health_001")
  state <- e2e_health_apply_refresh_result(state, "health_001", checks_first)
  state <- e2e_health_apply_refresh_result(state, "health_001", checks_first)

  expect_identical(state$update_count, 1L)
  expect_identical(state$last_skip_reason, "duplicate_refresh")
  expect_identical(length(state$applied_refresh_ids), 1L)

  checks_second <- checks_first
  checks_second$value[checks_second$id == "app.boot"] <- "Yenilendi"

  state <- e2e_health_begin_refresh(state, "health_002")
  state <- e2e_health_apply_refresh_result(state, "health_001", checks_first)

  expect_identical(state$update_count, 1L)
  expect_identical(state$last_skip_reason, "stale_refresh")
  expect_false(any(state$checks$value == "Yenilendi"))

  state <- e2e_health_apply_refresh_result(state, "health_002", checks_second)

  expect_identical(state$update_count, 2L)
  expect_identical(state$last_skip_reason, "applied")
  expect_true(any(state$checks$value == "Yenilendi"))

  message_types <- vapply(state$messages, `[[`, character(1), "type")
  expect_true("removeHealthTooltips" %in% message_types)
  expect_true("updateHealthTimestamp" %in% message_types)
  expect_true("initHealthTooltips" %in% message_types)
})

test_that("rendered health tabs are stable and never expose raw secrets", {
  config <- e2e_health_config()
  checks <- e2e_health_collect_snapshot(config)

  state <- e2e_health_new_state()
  state <- e2e_health_begin_refresh(state, "health_render")
  state <- e2e_health_apply_refresh_result(state, "health_render", checks)

  rendered_tabs <- e2e_health_render_all_tabs(state)

  expect_setequal(names(rendered_tabs), e2e_health_tab_names())
  expect_true(all(nzchar(unlist(rendered_tabs, use.names = FALSE))))

  expect_true(grepl("Genel Bakış", rendered_tabs$overview, fixed = TRUE))
  expect_true(grepl("Bağlantılar", rendered_tabs$connectivity, fixed = TRUE))
  expect_true(grepl("Güvenlik & Yapılandırma", rendered_tabs$security, fixed = TRUE))
  expect_true(grepl("Tanılama", rendered_tabs$diagnostics, fixed = TRUE))
  expect_true(grepl("AI_KEYS_MASTER", rendered_tabs$security, fixed = TRUE))

  all_rendered <- paste(unlist(rendered_tabs, use.names = FALSE), collapse = "\n")
  for (secret in e2e_health_secret_texts(config)) {
    expect_false(
      grepl(secret, all_rendered, fixed = TRUE),
      info = paste("Gizli değer render edilmiş sağlık sekmelerine sızmamalı:", secret)
    )
  }

  expect_true(grepl("İ", all_rendered, fixed = TRUE) || grepl("Görsel", all_rendered, fixed = TRUE))
})

test_that("runtime health dashboard files keep offline refresh and cleanup contracts wired", {
  health_checks_text <- e2e_health_read_repo_text("R/helpers_health_checks.R")
  health_module_text <- e2e_health_read_repo_text("R/module_health.R")
  ui_text <- e2e_health_read_repo_text("ui.R")
  health_js_text <- e2e_health_read_repo_text("www/js/health_dashboard.js")

  public_guard_pos <- regexpr("health_is_public_url(endpoint)", health_checks_text, fixed = TRUE)[[1]]
  network_get_pos <- regexpr("httr::GET(endpoint", health_checks_text, fixed = TRUE)[[1]]

  expect_gt(public_guard_pos, 0L)
  expect_gt(network_get_pos, 0L)
  expect_true(
    public_guard_pos < network_get_pos,
    info = "Public URL guard, httr::GET çağrısından önce kalmalı."
  )

  required_health_module_patterns <- c(
    "health_collect_checks(perf_tracker = perf_tracker, include_slow = TRUE)",
    "invalidateLater(120000)",
    "observeEvent(input$refresh_health",
    "session$sendCustomMessage(\"removeHealthTooltips\"",
    "session$sendCustomMessage(\"initHealthTooltips\"",
    "showToast(session, \"Sistem durumu güncellendi\", \"success\")"
  )

  missing_module <- required_health_module_patterns[!vapply(
    required_health_module_patterns,
    function(pattern) grepl(pattern, health_module_text, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  expect_equal(
    missing_module,
    character(0),
    info = paste("Health module refresh sözleşmesi eksik:", paste(missing_module, collapse = ", "))
  )

  required_js_patterns <- c(
    "Shiny.addCustomMessageHandler(\"updateHealthTimestamp\"",
    "Shiny.addCustomMessageHandler(\"initHealthTooltips\"",
    "Shiny.addCustomMessageHandler(\"removeHealthTooltips\"",
    ".off(\"click.healthPath\"",
    "beforeunload",
    "removeHealthTooltips"
  )

  missing_js <- required_js_patterns[!vapply(
    required_js_patterns,
    function(pattern) grepl(pattern, health_js_text, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  expect_equal(
    missing_js,
    character(0),
    info = paste("Health JS hook sözleşmesi eksik:", paste(missing_js, collapse = ", "))
  )

  expect_true(grepl("css/health_check.css", ui_text, fixed = TRUE))
  expect_true(grepl("js/health_dashboard.js", health_module_text, fixed = TRUE))
  expect_false(grepl("https://", health_js_text, fixed = TRUE))
  expect_false(grepl("http://", health_js_text, fixed = TRUE))
})