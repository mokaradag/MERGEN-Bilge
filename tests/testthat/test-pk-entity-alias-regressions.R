# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-entity-alias-regressions.R
# Açıklama: Varlık/alias çözümleme ve ilgili sözleşme gerilemelerini doğrudan
#           sözleşme düzeyinde doğrular.
# ==============================================================================

.find_repo_root_pk_entity_alias <- function() {
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
        dir.exists(file.path(candidate, "R"))) {
      return(candidate)
    }
  }

  stop("Repo kökü bulunamadı.", call. = FALSE)
}

repo_root_pk_entity_alias <- .find_repo_root_pk_entity_alias()

.read_pk_entity_alias <- function(...) {
  paste(readLines(
    file.path(repo_root_pk_entity_alias, ...),
    warn = FALSE,
    encoding = "UTF-8"
  ), collapse = "\n")
}

test_that("Selectize açıkken yapılandırma ipucu bastırılır", {
  css <- .read_pk_entity_alias("www", "css", "settings_page.css")

  expect_true(grepl(
    ":has\\(\\.selectize-input\\.dropdown-active\\)::after",
    css,
    perl = TRUE
  ))
  expect_false(grepl(
    ":has\\(\\.selectize-control\\.dropdown-active\\)::after",
    css,
    perl = TRUE
  ))
})

test_that("mesaj güvenlik tavanı tamsayı taşmasında varsayılana düşer", {
  validation_env <- new.env(parent = baseenv())
  source(
    file.path(repo_root_pk_entity_alias, "R", "helpers_db_validation.R"),
    local = validation_env,
    encoding = "UTF-8"
  )

  withr::with_envvar(c(MERGEN_MAX_MESSAGE_CHARS = "3000000000"), {
    expect_identical(validation_env$mergen_max_message_chars(), 1000000L)
    expect_true(validation_env$validate_message_content("geçerli ileti"))
  })

  withr::with_envvar(c(MERGEN_MAX_MESSAGE_CHARS = "Inf"), {
    expect_identical(validation_env$mergen_max_message_chars(), 1000000L)
  })
})

test_that("MCP ikinci geçişi çıktı token ortam ayarını uygular", {
  second_pass_env <- new.env(parent = baseenv())
  source(
    file.path(repo_root_pk_entity_alias, "R", "helpers_llm_worker_second_pass.R"),
    local = second_pass_env,
    encoding = "UTF-8"
  )

  withr::with_envvar(c(MERGEN_MAX_OUTPUT_TOKENS = "12000"), {
    expect_identical(
      second_pass_env$llm_worker_resolve_max_output_tokens(list()),
      12000L
    )
  })

  withr::with_envvar(c(MERGEN_MAX_OUTPUT_TOKENS = "12000"), {
    expect_identical(
      second_pass_env$llm_worker_resolve_max_output_tokens(
        list(max_output_tokens = 9000L)
      ),
      9000L
    )
  })

  withr::with_envvar(c(MERGEN_MAX_OUTPUT_TOKENS = "3000000000"), {
    expect_identical(
      second_pass_env$llm_worker_resolve_max_output_tokens(list()),
      32768L
    )
  })
})

test_that("yerel CodeMirror yapısı tam çizim ve ucuz refresh sağlar", {
  core_js <- .read_pk_entity_alias("www", "js", "codemirror_compat.js")
  manager_js <- .read_pk_entity_alias("www", "js", "codemirror-manager.js")
  core_css <- .read_pk_entity_alias("www", "css", "codemirror_compat.css")

  expect_false(grepl("extension placeholder", core_js, fixed = TRUE))
  expect_true(grepl("OfflineCodeMirror.prototype.on", core_js, fixed = TRUE))
  expect_true(grepl("OfflineCodeMirror.prototype.setSize", core_js, fixed = TRUE))
  expect_true(grepl("OfflineCodeMirror.prototype.refresh", core_js, fixed = TRUE))
  expect_true(grepl("this._wrapper.CodeMirror = this", core_js, fixed = TRUE))
  expect_true(grepl("self._code.appendChild(row)", core_js, fixed = TRUE))
  expect_true(grepl("OfflineCodeMirror.prototype._needsRender", core_js, fixed = TRUE))
  expect_true(grepl("if (this._needsRender()) this._render();", core_js, fixed = TRUE))
  expect_true(grepl("viewportMargin: Infinity", manager_js, fixed = TRUE))
  expect_true(grepl(".CodeMirror-line-row", core_css, fixed = TRUE))
  expect_false(grepl("min-width: max-content", core_css, fixed = TRUE))
  expect_true(grepl("flex: 1 1 auto", core_css, fixed = TRUE))
})

test_that("özel CodeMirror varlıkları app-owned ratchet kapsamındadır", {
  manifest <- .read_pk_entity_alias("R", "config_ui_assets.R")

  expect_true(grepl('"js/codemirror_compat.js"', manifest, fixed = TRUE))
  expect_true(grepl('"css/codemirror_compat.css"', manifest, fixed = TRUE))
  expect_false(grepl('"codemirror/codemirror.min.js"', manifest, fixed = TRUE))
  expect_false(grepl('"codemirror/codemirror.min.css"', manifest, fixed = TRUE))
})

test_that("yapılandırma ipuçları erişilebilir açıklamalara bağlanır", {
  settings_js <- .read_pk_entity_alias("www", "js", "settings_model_info.js")

  expect_true(grepl("[data-settings-tooltip]", settings_js, fixed = TRUE))
  expect_true(grepl("aria-describedby", settings_js, fixed = TRUE))
  expect_true(grepl("settings-tooltip-sr", settings_js, fixed = TRUE))
  expect_true(grepl("syncSettingsTooltipAccessibility(document)", settings_js, fixed = TRUE))
})
