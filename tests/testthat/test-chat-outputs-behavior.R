# ==============================================================================
# Dosya Yolu: tests/testthat/test-chat-outputs-behavior.R
# Açıklama: R/server_outputs_chat.R chatOutputsInit() header renderUI çıktılarının
#           DAVRANIŞSAL testleri. Bu dosya daha önce hiçbir test tarafından
#           çağrılmıyordu.
#
#           Kapsananlar (shiny::testServer ile output okunarak):
#           - mcp_mode_indicator: aktif araç ailesine göre öncelikli gösterge.
#           - current_model_display: görsel modunda dall-e-3, aksi halde model
#             adı; Derin Düşünme aktifse runtime ipucu.
#           - chat_model_selector_ui: model kataloğu dropdown'u.
#
#           api_config ve resolve_deep_thinking_model küçük stub'larla sağlanır.
#           Gerçek DB/LLM/ağ GEREKMEZ.
# ==============================================================================

.source_chat_outputs_for_test <- function() {
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  # Model kataloğu stub'ı: görünür ad -> kimlik eşlemesi.
  env$api_config <- list(
    local_models = c("Model A" = "m-a", "Model B" = "m-b"),
    local_model_descriptions = list("m-a" = "A modeli açıklaması", "m-b" = "B modeli")
  )
  env$resolve_deep_thinking_model <- function(family, level) paste0("DERIN-", toupper(family))
  source(
    file.path(resolve_repo_root_for_tests(), "R", "server_outputs_chat.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

# Verilen ayarlarla taze bir testServer turunda mcp_mode_indicator HTML'ini döndürür.
.render_chat_output <- function(env, settings, output_id) {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  res <- NULL
  shiny::testServer(function(input, output, session) {
    sd <- do.call(shiny::reactiveValues, settings)
    env$chatOutputsInit(output, sd)
  }, {
    res <<- paste(as.character(output[[output_id]]), collapse = "")
  })
  res
}

# ------------------------------------------------------------------------------
# mcp_mode_indicator: öncelik sırası
# ------------------------------------------------------------------------------
testthat::test_that("mcp_mode_indicator her araç ailesi için doğru Türkçe etiketi gösterir", {
  env <- .source_chat_outputs_for_test()

  testthat::expect_true(grepl("Kod Uzmanı",
    .render_chat_output(env, list(enable_coding_tools = TRUE), "mcp_mode_indicator"), fixed = TRUE))
  testthat::expect_true(grepl("Süreç Yönetimi",
    .render_chat_output(env, list(enable_process_tools = TRUE), "mcp_mode_indicator"), fixed = TRUE))
  testthat::expect_true(grepl("Uygulama Uzmanı",
    .render_chat_output(env, list(enable_app_expert_tools = TRUE), "mcp_mode_indicator"), fixed = TRUE))
  testthat::expect_true(grepl("Görsel Uzmanı",
    .render_chat_output(env, list(enable_image_tools = TRUE), "mcp_mode_indicator"), fixed = TRUE))
  testthat::expect_true(grepl("Dosya Özetleme",
    .render_chat_output(env, list(enable_summarization_tools = TRUE), "mcp_mode_indicator"), fixed = TRUE))
  testthat::expect_true(grepl("Excel Analizi",
    .render_chat_output(env, list(enable_mcp_tools = TRUE), "mcp_mode_indicator"), fixed = TRUE))
  testthat::expect_true(grepl("Proje ve Kaynak Analizi",
    .render_chat_output(env, list(enable_rdata_tools = TRUE), "mcp_mode_indicator"), fixed = TRUE))
})

testthat::test_that("mcp_mode_indicator hiçbir araç aktif değilse boş kalır", {
  env <- .source_chat_outputs_for_test()
  out <- .render_chat_output(env, list(enable_coding_tools = FALSE), "mcp_mode_indicator")
  testthat::expect_identical(out, "")
})

testthat::test_that("mcp_mode_indicator kodlama, Excel'e göre önceliklidir", {
  env <- .source_chat_outputs_for_test()
  # Hem coding hem excel aktif -> coding kazanır (öncelik sırası).
  out <- .render_chat_output(env,
    list(enable_coding_tools = TRUE, enable_mcp_tools = TRUE), "mcp_mode_indicator")
  testthat::expect_true(grepl("Kod Uzmanı", out, fixed = TRUE))
  testthat::expect_false(grepl("Excel Analizi", out, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# current_model_display
# ------------------------------------------------------------------------------
testthat::test_that("current_model_display görsel modunda dall-e-3 gösterir", {
  env <- .source_chat_outputs_for_test()
  out <- .render_chat_output(env, list(enable_image_tools = TRUE), "current_model_display")
  testthat::expect_true(grepl("dall-e-3", out, fixed = TRUE))
})

testthat::test_that("current_model_display seçili model kimliğini görünür ada çevirir", {
  env <- .source_chat_outputs_for_test()
  out <- .render_chat_output(env,
    list(enable_image_tools = FALSE, model_selection = "m-b"), "current_model_display")
  # m-b -> "Model B" görünür adı.
  testthat::expect_true(grepl("Model: Model B", out, fixed = TRUE))
})

testthat::test_that("current_model_display Langflow aracı aktifken model rozetini gizler", {
  # Langflow araçları (Süreç Yönetimi / Uygulama Uzmanı) yerel model taşımaz;
  # model rozeti yanıltıcı olduğundan hiç gösterilmez (runtime=="langflow" tespiti).
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  env$api_config <- list(
    local_models = c("Model A" = "m-a"),
    local_model_descriptions = list("m-a" = "A modeli"),
    tool_mode_config = list(
      process = list(family = "process", setting_flag = "enable_process_tools", runtime = "langflow"),
      app_expert = list(family = "app_expert", setting_flag = "enable_app_expert_tools", runtime = "langflow"),
      coding = list(family = "coding", setting_flag = "enable_coding_tools", model_id = "m-a")
    )
  )
  env$resolve_deep_thinking_model <- function(family, level) paste0("DERIN-", toupper(family))

  kok <- resolve_repo_root_for_tests()
  source(file.path(kok, "R", "helpers_langflow_runtime.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "server_outputs_chat.R"), encoding = "UTF-8", local = env)

  # Süreç Yönetimi aktif -> rozet gizli (NULL render -> boş)
  out_process <- .render_chat_output(env,
    list(enable_process_tools = TRUE, model_selection = "m-a"), "current_model_display")
  testthat::expect_identical(out_process, "")

  # Uygulama Uzmanı aktif -> rozet gizli
  out_app <- .render_chat_output(env,
    list(enable_app_expert_tools = TRUE, model_selection = "m-a"), "current_model_display")
  testthat::expect_identical(out_app, "")

  # Langflow olmayan araç (coding) veya hiçbiri -> rozet gösterilir
  out_coding <- .render_chat_output(env,
    list(enable_coding_tools = TRUE, model_selection = "m-a"), "current_model_display")
  testthat::expect_true(grepl("Model: Model A", out_coding, fixed = TRUE))
})

testthat::test_that("current_model_display Excel Derin Düşünme aktifse runtime ipucunu ekler", {
  env <- .source_chat_outputs_for_test()
  out <- .render_chat_output(env, list(
    enable_image_tools = FALSE, model_selection = "m-a",
    enable_mcp_tools = TRUE, excel_deep_thinking = TRUE, excel_deep_level = "low"
  ), "current_model_display")
  # title özniteliğinde Derin Düşünme ipucu (stub: DERIN-MCP_EXCEL) yer almalı.
  testthat::expect_true(grepl("Derin Düşünme: DERIN-MCP_EXCEL", out, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# chat_model_selector_ui
# ------------------------------------------------------------------------------
testthat::test_that("chat_model_selector_ui model kataloğunu ve seçili modeli işaretler", {
  testthat::skip_if_not_installed("shinyWidgets")
  suppressMessages(library(shinyWidgets))
  env <- .source_chat_outputs_for_test()
  out <- .render_chat_output(env, list(model_selection = "m-a"), "chat_model_selector_ui")
  testthat::expect_true(grepl("Model Kataloğu", out, fixed = TRUE))
  testthat::expect_true(grepl("Model A", out, fixed = TRUE))
  testthat::expect_true(grepl("Model B", out, fixed = TRUE))
  # Seçili model (m-a) 'active' sınıfı almalı.
  testthat::expect_true(grepl("model-option active", out, fixed = TRUE))
})
