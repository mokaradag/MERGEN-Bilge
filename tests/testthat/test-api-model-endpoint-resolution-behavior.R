# ==============================================================================
# Dosya Yolu: tests/testthat/test-api-model-endpoint-resolution-behavior.R
# Açıklama: R/helpers_api_model_config.R uç nokta / kimlik bilgisi / araç modu
#           çözümleme yardımcılarının DAVRANIŞSAL testleri. Mevcut sözleşme testi
#           (test-api-model-config-refactor-contract.R) yalnızca temel mutlu yolu
#           kapsar; burada FALLBACK ve KENAR durumları genişletilir:
#             - doğrudan URL uç nokta anahtarı
#             - varsayılan anahtar / map'ten türetilen varsayılan / ilk endpoint adı
#             - listedeki ilk boş olmayan endpoint'e düşme
#             - eski config$local_llm_endpoint / config$local_llm$endpoint
#             - eksik/boş config bölümleri
#             - kullanıcı yönetimli olmayan modelin user-managed modele düşmesi
#             - araç modu config bulma ve ana aksiyon filtreleme/varsayılanları
#           Tüm çağrılara sentetik config= geçirilir; global api_config'e dokunulmaz.
#           Shiny/HTTP/DB/ağ GEREKMEZ; yalnızca saf çözümleme.
# ==============================================================================

.apimodelep_source_once <- function() {
  root <- resolve_repo_root_for_tests()
  # config_api.R fonksiyonları %||% null-coalesce operatörüne bağlıdır; üretim
  # (utils_common.R) tanımıyla birebir aynı operatör yalnızca eksikse tanımlanır.
  if (!exists("%||%", inherits = TRUE)) {
    assign("%||%", function(a, b) if (is.null(a)) b else a, envir = globalenv())
  }
  if (!exists("resolve_local_llm_endpoint", mode = "function", inherits = TRUE)) {
    source(file.path(root, "R", "helpers_api_model_config.R"),
           encoding = "UTF-8", local = globalenv())
  }
  # get_tool_mode_config / resolve_tool_model_for_family / build_main_actions_data_from_config
  # araç-runtime ayrımıyla helpers_api_model_tool_runtime.R'a taşındı.
  if (!exists("get_tool_mode_config", mode = "function", inherits = TRUE)) {
    source(file.path(root, "R", "helpers_api_model_tool_runtime.R"),
           encoding = "UTF-8", local = globalenv())
  }
  invisible(TRUE)
}

# ------------------------------------------------------------------------------
# resolve_local_llm_endpoint
# ------------------------------------------------------------------------------
testthat::test_that("resolve_local_llm_endpoint model haritasındaki doğrudan URL anahtarını döndürür", {
  .apimodelep_source_once()
  cfg <- list(
    local_llm_endpoints = list(primary = "http://primary.test/v1"),
    local_model_endpoint_map = c("model-direct" = "http://direct.test/v9/chat")
  )
  # Anahtar endpoints listesinde yok ama http(s):// ile başlıyor -> anahtarın kendisi döner.
  testthat::expect_identical(
    resolve_local_llm_endpoint("model-direct", config = cfg),
    "http://direct.test/v9/chat"
  )
})

testthat::test_that("resolve_local_llm_endpoint eşlenmeyen modelde varsayılan anahtara düşer", {
  .apimodelep_source_once()
  cfg <- list(
    local_llm_endpoints = list(
      primary = "http://primary.test/v1",
      secondary = "http://secondary.test/v1"
    ),
    local_llm_default_endpoint_key = "secondary",
    local_model_endpoint_map = c("bilinen" = "primary")
  )
  testthat::expect_identical(
    resolve_local_llm_endpoint("bilinmeyen-model", config = cfg),
    "http://secondary.test/v1"
  )
})

testthat::test_that("resolve_local_llm_endpoint ilk modelin map anahtarından varsayılanı türetir", {
  .apimodelep_source_once()
  cfg <- list(
    local_models = c("Birincil" = "model-primary"),
    local_llm_endpoints = list(
      primary = "http://primary.test/v1",
      secondary = "http://secondary.test/v1"
    ),
    local_model_endpoint_map = c("model-primary" = "secondary")
  )
  # Açık varsayılan anahtar yok; ilk model 'secondary'ye eşlendiği için o seçilir.
  testthat::expect_identical(
    resolve_local_llm_endpoint(NULL, config = cfg),
    "http://secondary.test/v1"
  )
})

testthat::test_that("resolve_local_llm_endpoint hiç ipucu yoksa ilk endpoint adına düşer", {
  .apimodelep_source_once()
  cfg <- list(
    local_llm_endpoints = list(
      alpha = "http://alpha.test/v1",
      beta = "http://beta.test/v1"
    )
  )
  testthat::expect_identical(
    resolve_local_llm_endpoint(NULL, config = cfg),
    "http://alpha.test/v1"
  )
})

testthat::test_that("resolve_local_llm_endpoint boş varsayılan anahtardan ilk dolu endpoint'e düşer", {
  .apimodelep_source_once()
  cfg <- list(
    local_llm_endpoints = list(empty = "", good = "http://good.test/v1"),
    local_llm_default_endpoint_key = "empty"
  )
  # 'empty' boş; pick_endpoint NULL döndürür, döngü ilk dolu endpoint'i bulur.
  testthat::expect_identical(
    resolve_local_llm_endpoint(NULL, config = cfg),
    "http://good.test/v1"
  )
})

testthat::test_that("resolve_local_llm_endpoint eski config$local_llm_endpoint ve iç içe alanı kullanır", {
  .apimodelep_source_once()
  # Endpoints listesi yok -> default_endpoint (eski düz alan) döner.
  cfg_flat <- list(local_llm_endpoint = "http://legacy.test/v1")
  testthat::expect_identical(
    resolve_local_llm_endpoint(NULL, config = cfg_flat),
    "http://legacy.test/v1"
  )

  # Düz alan yok ama iç içe config$local_llm$endpoint var.
  cfg_nested <- list(local_llm = list(endpoint = "http://nested.test/v1"))
  testthat::expect_identical(
    resolve_local_llm_endpoint(NULL, config = cfg_nested),
    "http://nested.test/v1"
  )
})

testthat::test_that("resolve_local_llm_endpoint tamamen boş config için boş dize döndürür", {
  .apimodelep_source_once()
  testthat::expect_identical(resolve_local_llm_endpoint(NULL, config = list()), "")
})

# ------------------------------------------------------------------------------
# resolve_local_llm_credentials
# ------------------------------------------------------------------------------
testthat::test_that("resolve_local_llm_credentials map+key ile çözümler, bayrak yoksa user key serbest", {
  .apimodelep_source_once()
  cfg <- list(
    local_llm_endpoints = list(primary = "http://primary.test/v1"),
    local_model_endpoint_map = c("m1" = "primary"),
    local_llm_endpoint_keys = list(primary = "key-123")
  )
  creds <- resolve_local_llm_credentials("m1", config = cfg)
  testthat::expect_identical(creds$endpoint, "http://primary.test/v1")
  testthat::expect_identical(creds$endpoint_key, "primary")
  testthat::expect_identical(creds$default_api_key, "key-123")
  testthat::expect_true(isTRUE(creds$allow_user_key))   # bayrak listesi boş -> varsayılan TRUE
})

testthat::test_that("resolve_local_llm_credentials eşlenmeyen modelde varsayılan anahtar kimliğini kullanır", {
  .apimodelep_source_once()
  cfg <- list(
    local_llm_endpoints = list(
      primary = "http://primary.test/v1",
      secondary = "http://secondary.test/v1"
    ),
    local_llm_default_endpoint_key = "secondary",
    local_llm_endpoint_keys = list(secondary = "sec-key")
  )
  creds <- resolve_local_llm_credentials("eslenmeyen", config = cfg)
  testthat::expect_identical(creds$endpoint_key, "secondary")
  testthat::expect_identical(creds$endpoint, "http://secondary.test/v1")
  testthat::expect_identical(creds$default_api_key, "sec-key")
})

testthat::test_that("resolve_local_llm_credentials user-managed bayrağı TRUE iken anahtar boşsa boş dize verir", {
  .apimodelep_source_once()
  cfg <- list(
    local_llm_endpoints = list(primary = "http://primary.test/v1"),
    local_model_endpoint_map = c("m1" = "primary"),
    local_llm_endpoint_keys = list(),                    # anahtar tanımlı değil
    local_llm_endpoint_user_managed = c(primary = TRUE)
  )
  creds <- resolve_local_llm_credentials("m1", config = cfg)
  testthat::expect_identical(creds$default_api_key, "")
  testthat::expect_true(isTRUE(creds$allow_user_key))
})

# ------------------------------------------------------------------------------
# determine_api_key_validation_target
# ------------------------------------------------------------------------------
testthat::test_that("determine_api_key_validation_target user-managed modelde fallback YAPMAZ", {
  .apimodelep_source_once()
  cfg <- list(
    local_models = c("Birincil" = "model-primary"),
    local_llm_endpoints = list(primary = "http://primary.test/v1"),
    local_model_endpoint_map = c("model-primary" = "primary"),
    local_llm_endpoint_user_managed = c(primary = TRUE)
  )
  hedef <- determine_api_key_validation_target("model-primary", config = cfg)
  testthat::expect_identical(hedef$model_id, "model-primary")
  testthat::expect_identical(hedef$endpoint_key, "primary")
  testthat::expect_true(isTRUE(hedef$allow_user_key))
  testthat::expect_false(isTRUE(hedef$fallback_used))
  testthat::expect_identical(hedef$requested_model_id, "model-primary")
})

testthat::test_that("determine_api_key_validation_target requested NULL iken ilk modeli kullanır", {
  .apimodelep_source_once()
  cfg <- list(
    local_models = c("Birincil" = "model-primary"),
    local_llm_endpoints = list(primary = "http://primary.test/v1"),
    local_model_endpoint_map = c("model-primary" = "primary"),
    local_llm_endpoint_user_managed = c(primary = TRUE)
  )
  hedef <- determine_api_key_validation_target(NULL, config = cfg)
  testthat::expect_identical(hedef$requested_model_id, "model-primary")
  testthat::expect_identical(hedef$model_id, "model-primary")
})

testthat::test_that("determine_api_key_validation_target alternatif yoksa user key'i kapatır", {
  .apimodelep_source_once()
  cfg <- list(
    local_models = c("X" = "model-x"),
    local_llm_endpoints = list(primary = "http://primary.test/v1"),
    local_model_endpoint_map = c("model-x" = "primary"),
    local_llm_endpoint_user_managed = c(primary = FALSE)
  )
  hedef <- determine_api_key_validation_target("model-x", config = cfg)
  testthat::expect_identical(hedef$model_id, "model-x")    # alternatif yok, model değişmez
  testthat::expect_false(isTRUE(hedef$allow_user_key))
  testthat::expect_false(isTRUE(hedef$fallback_used))
})

# ------------------------------------------------------------------------------
# get_tool_mode_config / resolve_tool_model_for_*
# ------------------------------------------------------------------------------
testthat::test_that("get_tool_mode_config family ve quick_action_id ile bulur, yoksa NULL döner", {
  .apimodelep_source_once()
  cfg <- list(
    tool_mode_config = list(
      summarization = list(
        family = "summarization",
        setting_flag = "enable_summarization_tools",
        quick_action_id = "summarization",
        model_id = "summary-model"
      ),
      process = list(
        family = "process",
        setting_flag = "enable_process_tools",
        quick_action_id = "project-process",
        model_id = "process-model"
      )
    )
  )
  by_family <- get_tool_mode_config("process", by = "family", config = cfg)
  testthat::expect_identical(by_family$model_id, "process-model")

  by_qa <- get_tool_mode_config("summarization", by = "quick_action_id", config = cfg)
  testthat::expect_identical(by_qa$model_id, "summary-model")

  testthat::expect_null(get_tool_mode_config("yok", by = "family", config = cfg))
  testthat::expect_null(get_tool_mode_config("x", by = "family", config = list()))
})

testthat::test_that("resolve_tool_model_for_family/flag eşleşme yoksa fallback'e düşer", {
  .apimodelep_source_once()
  cfg <- list(local_models = c("Def" = "fallback-model"), tool_mode_config = list())

  # Eşleşme yok, açık fallback yok -> config$local_models[1]
  testthat::expect_identical(
    resolve_tool_model_for_family("olmayan", config = cfg),
    "fallback-model"
  )
  # Açık fallback verilirse o kullanılır
  testthat::expect_identical(
    resolve_tool_model_for_family("olmayan", fallback_model = "acik-fb", config = cfg),
    "acik-fb"
  )
  testthat::expect_identical(
    resolve_tool_model_for_flag("olmayan_flag", config = cfg),
    "fallback-model"
  )
})

# ------------------------------------------------------------------------------
# build_main_actions_data_from_config
# ------------------------------------------------------------------------------
testthat::test_that("build_main_actions_data_from_config quick_action_id'siz girişleri eler ve varsayılan uygular", {
  .apimodelep_source_once()
  cfg <- list(
    local_models = c("Def" = "def-model"),
    tool_mode_config = list(
      gorunur = list(quick_action_id = "qa1", title = "Baslik 1"),  # model_id/icon yok -> varsayılan
      gizli = list(family = "hidden")                                # quick_action_id yok -> elenir
    )
  )
  actions <- build_main_actions_data_from_config(cfg)
  testthat::expect_length(actions, 1L)
  testthat::expect_identical(actions[[1]]$id, "qa1")
  testthat::expect_identical(actions[[1]]$title, "Baslik 1")
  testthat::expect_identical(actions[[1]]$icon_name, "bolt")          # varsayılan ikon
  testthat::expect_identical(actions[[1]]$themeColor, "#6366f1")      # varsayılan renk
  testthat::expect_identical(actions[[1]]$model_value, "def-model")   # model_id yoksa ilk model
  testthat::expect_identical(actions[[1]]$message, "")                # mesaj yoksa boş dize
})
