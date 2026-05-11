# ==============================================================================
# Dosya Yolu: tests/testthat/test-followup-suggestions-regression.R
# Açıklama: Takip sorusu önerileri için regresyon testleri.
# ==============================================================================

test_that("followup suggestions are generated when enable_followups is TRUE", {
  repo_root <- resolve_repo_root_for_tests()

  source(file.path(repo_root, "R/helpers_followup_questions.R"), encoding = "UTF-8")
  source(file.path(repo_root, "R/module_followup_questions.R"), encoding = "UTF-8")

  # Test sırasında AI çağrısı yapılmasın.
  old_generate_ai_followups <- get("generate_ai_followups", envir = .GlobalEnv)
  assign("generate_ai_followups", function(...) NULL, envir = .GlobalEnv)
  on.exit(assign("generate_ai_followups", old_generate_ai_followups, envir = .GlobalEnv), add = TRUE)

  settings_data <- list(
    enable_followups = TRUE,
    model_selection = "test-model"
  )

  followup_tools <- create_followup_suggestions_tool()
  fallback_followup_tool <- create_followup_suggestions_tool()

  suggestions <- build_followup_suggestions(
    user_text = "Bu proje planını nasıl iyileştirebilirim?",
    ai_text = "Proje planında riskleri, kaynakları ve takvimi birlikte değerlendirmek gerekir.",
    settings_data = settings_data,
    session = NULL,
    api_config = list(local_models = c("test-model")),
    followup_tools = followup_tools,
    fallback_followup_tool = fallback_followup_tool
  )

  expect_type(suggestions, "character")
  expect_gte(length(suggestions), 2)
  expect_lte(length(suggestions), 3)
  expect_true(all(nzchar(suggestions)))
  expect_true(all(grepl("\\?$", suggestions)))
})


test_that("followup suggestions are not generated when enable_followups is FALSE", {
  repo_root <- resolve_repo_root_for_tests()

  source(file.path(repo_root, "R/helpers_followup_questions.R"), encoding = "UTF-8")
  source(file.path(repo_root, "R/module_followup_questions.R"), encoding = "UTF-8")

  settings_data <- list(
    enable_followups = FALSE,
    model_selection = "test-model"
  )

  followup_tools <- create_followup_suggestions_tool()
  fallback_followup_tool <- create_followup_suggestions_tool()

  suggestions <- build_followup_suggestions(
    user_text = "Bu proje planını nasıl iyileştirebilirim?",
    ai_text = "Proje planında riskleri, kaynakları ve takvimi birlikte değerlendirmek gerekir.",
    settings_data = settings_data,
    session = NULL,
    api_config = list(local_models = c("test-model")),
    followup_tools = followup_tools,
    fallback_followup_tool = fallback_followup_tool
  )

  expect_null(suggestions)
})