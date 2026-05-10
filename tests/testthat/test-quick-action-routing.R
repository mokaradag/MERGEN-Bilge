# ==============================================================================
# Dosya Yolu: tests/testthat/test-quick-action-routing.R
# Açıklama: Hızlı işlem kimliği, araç ailesi, ayar bayrağı ve model seçimi
#           davranışını gerçek config helper'ları üzerinden doğrular.
# ==============================================================================

.find_quick_action_routing_repo_root <- function() {
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

  stop("Quick action routing test repo kökünü bulamadı.", call. = FALSE)
}

repo_root_quick_action_routing <- .find_quick_action_routing_repo_root()

if (!exists("resolve_repo_root_for_tests", envir = globalenv(), inherits = FALSE)) {
  source(
    file.path(repo_root_quick_action_routing, "tests", "testthat", "helper_bootstrap.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
}

repo_root_quick_action_routing <- resolve_repo_root_for_tests()

if (!exists("e2e_regression_config", envir = globalenv(), inherits = FALSE)) {
  source(
    file.path(
      repo_root_quick_action_routing,
      "tests",
      "testthat",
      "helper_e2e_race_harness.R"
    ),
    encoding = "UTF-8",
    local = globalenv()
  )
}

source(
  file.path(repo_root_quick_action_routing, "R", "utils_common.R"),
  encoding = "UTF-8",
  local = globalenv()
)

source(
  file.path(repo_root_quick_action_routing, "R", "helpers_api_model_config.R"),
  encoding = "UTF-8",
  local = globalenv()
)

source(
  file.path(repo_root_quick_action_routing, "R", "helpers_quick_action_intro_messages.R"),
  encoding = "UTF-8",
  local = globalenv()
)

.quick_action_expected_routes <- function() {
  data.frame(
    action_id = c(
      "project-process",
      "app-expert",
      "resource-analysis",
      "excel-analysis",
      "image-creation",
      "coding-support",
      "summarization"
    ),
    family = c(
      "process",
      "app_expert",
      "sql_analysis",
      "mcp_excel",
      "image",
      "coding",
      "summarization"
    ),
    setting_flag = c(
      "enable_process_tools",
      "enable_app_expert_tools",
      "enable_rdata_tools",
      "enable_mcp_tools",
      "enable_image_tools",
      "enable_coding_tools",
      "enable_summarization_tools"
    ),
    model_id = c(
      "technical name 1",
      "technical name 6",
      "technical name 3",
      "technical name 4",
      "dall-e-3",
      "technical name 5",
      "technical name 2"
    ),
    stringsAsFactors = FALSE
  )
}

test_that("her hızlı işlem kimliği doğru araç ailesi, bayrak ve modele çözülür", {
  config <- e2e_regression_config()
  expected <- .quick_action_expected_routes()
  actions <- build_main_actions_data_from_config(config)
  action_ids <- vapply(actions, function(action) action$id %||% "", character(1))

  expect_setequal(action_ids, expected$action_id)

  for (i in seq_len(nrow(expected))) {
    row <- expected[i, , drop = FALSE]

    cfg <- get_tool_mode_config(
      row$action_id,
      by = "quick_action_id",
      config = config
    )

    expect_true(is.list(cfg), info = row$action_id)
    expect_identical(cfg$family, row$family)
    expect_identical(cfg$setting_flag, row$setting_flag)
    expect_identical(cfg$model_id, row$model_id)

    expect_identical(
      resolve_tool_model_for_family(row$family, fallback_model = "fallback", config = config),
      row$model_id
    )

    expect_identical(
      resolve_tool_model_for_flag(row$setting_flag, fallback_model = "fallback", config = config),
      row$model_id
    )

    action <- actions[[match(row$action_id, action_ids)]]
    expect_identical(action$model_value, row$model_id)
  }
})

test_that("her hızlı işlem uygulandığında yalnızca tek araç bayrağı aktif kalır", {
  config <- e2e_regression_config()
  expected <- .quick_action_expected_routes()

  for (i in seq_len(nrow(expected))) {
    row <- expected[i, , drop = FALSE]

    state <- e2e_new_quick_action_state(config)
    state <- e2e_apply_quick_action(
      state,
      action_id = row$action_id,
      user_name = "İdil"
    )

    active_flags <- e2e_active_flags(state)

    expect_identical(active_flags, row$setting_flag, info = row$action_id)
    expect_identical(
      sum(vapply(e2e_tool_flags(), function(flag) isTRUE(state$settings[[flag]]), logical(1))),
      1L,
      info = row$action_id
    )
    expect_identical(state$settings$model_selection, row$model_id)
    expect_false(state$values$show_welcome)
    expect_identical(state$llm_calls, 0L)
  }
})

test_that("hızlı işlem config içinde yinelenen id, aile veya araç bayrağı yoktur", {
  config <- e2e_regression_config()
  all_cfg <- config$tool_mode_config
  expected <- .quick_action_expected_routes()

  collect_field <- function(field) {
    vapply(all_cfg, function(cfg) cfg[[field]] %||% "", character(1))
  }

  quick_action_ids <- collect_field("quick_action_id")
  families <- collect_field("family")
  setting_flags <- collect_field("setting_flag")
  model_ids <- collect_field("model_id")

  expect_false(anyDuplicated(quick_action_ids[nzchar(quick_action_ids)]) > 0L)
  expect_false(anyDuplicated(families[nzchar(families)]) > 0L)
  expect_false(anyDuplicated(setting_flags[nzchar(setting_flags)]) > 0L)

  expect_setequal(quick_action_ids, expected$action_id)
  expect_setequal(families, expected$family)
  expect_setequal(setting_flags, expected$setting_flag)

  for (model_id in model_ids) {
    expect_true(
      model_id %in% unname(config$local_models) || identical(model_id, "dall-e-3"),
      info = sprintf("Beklenmeyen hızlı işlem modeli: %s", model_id)
    )
  }
})