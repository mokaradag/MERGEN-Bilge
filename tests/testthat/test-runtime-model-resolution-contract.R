# ==============================================================================
# Dosya Yolu: tests/testthat/test-runtime-model-resolution-contract.R
# Açıklama: resolve_runtime_model_for_request() ve resolve_deep_thinking_model()
#           saf model çözümleme kararlarını davranışsal olarak kapsar. Özellikle
#           Derin Düşünme açık/kapalı, low/high seviye, coding ve mcp_excel
#           ailelerinin ayrışması, derin model yapılandırılmadığında normal
#           modele güvenli geri dönüş ve aile/local_models fallback yolları
#           doğrulanır. Model adlarına değil, çözümleme mantığına bağlıdır.
#           Shiny, DB, HTTP veya gerçek api_config gerektirmez.
# ==============================================================================

.find_runtime_model_repo_root <- function() {
  candidates <- unique(normalizePath(
    c(getwd(), file.path(getwd(), ".."), file.path(getwd(), "..", "..")),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "R"))) {
      return(candidate)
    }
  }

  stop("Runtime model çözümleme testi repo kökünü bulamadı.", call. = FALSE)
}

repo_root_runtime_model <- .find_runtime_model_repo_root()

# İzole çalıştırmada bağımlılıkları güvenli hazırla.
if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
}

source(
  file.path(repo_root_runtime_model, "R", "helpers_api_model_tool_runtime.R"),
  encoding = "UTF-8",
  local = globalenv()
)

# Tam yapılandırma: hem normal hem derin model haritaları mevcut.
.runtime_model_fake_config <- function() {
  list(
    local_models = c("Varsayilan" = "fallback-model"),
    tool_mode_config = list(
      mcp_excel = list(family = "mcp_excel", model_id = "excel-normal-model"),
      coding = list(family = "coding", model_id = "coding-normal-model"),
      summarization = list(family = "summarization", model_id = "sum-normal-model")
    ),
    deep_thinking_models = list(
      mcp_excel = list(low = "excel-deep-low-model", high = "excel-deep-high-model"),
      coding = list(low = "coding-deep-low-model", high = "coding-deep-high-model")
    )
  )
}

# --- resolve_deep_thinking_model() doğrudan davranışı -------------------------

test_that("derin model çözümü: bilinmeyen/boş aile NULL döner", {
  cfg <- .runtime_model_fake_config()
  expect_null(resolve_deep_thinking_model(NULL, "low", config = cfg))
  expect_null(resolve_deep_thinking_model("", "low", config = cfg))
  expect_null(resolve_deep_thinking_model("bilinmeyen", "low", config = cfg))
})

test_that("derin model çözümü: seviye ve büyük/küçük harf davranışı", {
  cfg <- .runtime_model_fake_config()
  expect_identical(resolve_deep_thinking_model("mcp_excel", "high", config = cfg), "excel-deep-high-model")
  expect_identical(resolve_deep_thinking_model("mcp_excel", "low", config = cfg), "excel-deep-low-model")
  # Seviye verilmezse varsayılan low.
  expect_identical(resolve_deep_thinking_model("coding", config = cfg), "coding-deep-low-model")
  # Seviye büyük/küçük harf duyarsız.
  expect_identical(resolve_deep_thinking_model("coding", "HIGH", config = cfg), "coding-deep-high-model")
  # Tanınmayan seviye low'a düşer.
  expect_identical(resolve_deep_thinking_model("coding", "orta", config = cfg), "coding-deep-low-model")
})

test_that("derin model çözümü: boş model değeri NULL sayılır", {
  cfg <- .runtime_model_fake_config()
  cfg$deep_thinking_models$mcp_excel$low <- ""
  expect_null(resolve_deep_thinking_model("mcp_excel", "low", config = cfg))
})

# --- resolve_runtime_model_for_request() karar matrisi ------------------------

test_that("mcp_excel derin low/high doğru derin modeli seçer", {
  cfg <- .runtime_model_fake_config()
  expect_identical(
    resolve_runtime_model_for_request("mcp_excel", excel_deep_on = TRUE, excel_deep_level = "low", config = cfg),
    "excel-deep-low-model"
  )
  expect_identical(
    resolve_runtime_model_for_request("mcp_excel", excel_deep_on = TRUE, excel_deep_level = "high", config = cfg),
    "excel-deep-high-model"
  )
})

test_that("coding derin low/high doğru derin modeli seçer", {
  cfg <- .runtime_model_fake_config()
  expect_identical(
    resolve_runtime_model_for_request("coding", coding_deep_on = TRUE, coding_deep_level = "low", config = cfg),
    "coding-deep-low-model"
  )
  expect_identical(
    resolve_runtime_model_for_request("coding", coding_deep_on = TRUE, coding_deep_level = "high", config = cfg),
    "coding-deep-high-model"
  )
})

test_that("derin kapalıyken normal aile modeli kullanılır", {
  cfg <- .runtime_model_fake_config()
  expect_identical(
    resolve_runtime_model_for_request("mcp_excel", excel_deep_on = FALSE, config = cfg),
    "excel-normal-model"
  )
  expect_identical(
    resolve_runtime_model_for_request("coding", coding_deep_on = FALSE, config = cfg),
    "coding-normal-model"
  )
})

test_that("çapraz aile bayrakları birbirine sızmaz", {
  cfg <- .runtime_model_fake_config()
  # coding ailesi excel derin bayrağından etkilenmemeli.
  expect_identical(
    resolve_runtime_model_for_request(
      "coding",
      excel_deep_on = TRUE, excel_deep_level = "high",
      coding_deep_on = FALSE,
      config = cfg
    ),
    "coding-normal-model"
  )
  # mcp_excel ailesi coding derin bayrağından etkilenmemeli.
  expect_identical(
    resolve_runtime_model_for_request(
      "mcp_excel",
      excel_deep_on = FALSE,
      coding_deep_on = TRUE, coding_deep_level = "high",
      config = cfg
    ),
    "excel-normal-model"
  )
})

test_that("derin desteklemeyen aile derin bayrakları yok sayar", {
  cfg <- .runtime_model_fake_config()
  expect_identical(
    resolve_runtime_model_for_request(
      "summarization",
      excel_deep_on = TRUE, coding_deep_on = TRUE,
      config = cfg
    ),
    "sum-normal-model"
  )
})

test_that("derin açık ama derin yapılandırma yoksa normal modele güvenli döner", {
  # Bu, 'değişen modeller' regresyonunun güvenlik sınırıdır.
  cfg <- .runtime_model_fake_config()
  cfg$deep_thinking_models$mcp_excel <- NULL
  expect_identical(
    resolve_runtime_model_for_request("mcp_excel", excel_deep_on = TRUE, excel_deep_level = "high", config = cfg),
    "excel-normal-model"
  )

  # Derin model değeri boşsa da normal model korunur.
  cfg2 <- .runtime_model_fake_config()
  cfg2$deep_thinking_models$coding$low <- ""
  expect_identical(
    resolve_runtime_model_for_request("coding", coding_deep_on = TRUE, coding_deep_level = "low", config = cfg2),
    "coding-normal-model"
  )
})

test_that("aile modeli yoksa fallback zinciri uygulanır", {
  cfg <- .runtime_model_fake_config()
  # Bilinmeyen aile + açık fallback_model.
  expect_identical(
    resolve_runtime_model_for_request("bilinmeyen", fallback_model = "explicit-fallback", config = cfg),
    "explicit-fallback"
  )
  # Bilinmeyen aile + fallback yok -> config$local_models[1].
  expect_identical(
    resolve_runtime_model_for_request("bilinmeyen", fallback_model = NULL, config = cfg),
    "fallback-model"
  )
})

test_that("sonuç her zaman tek elemanlı karakterdir", {
  cfg <- .runtime_model_fake_config()
  out <- resolve_runtime_model_for_request("mcp_excel", excel_deep_on = TRUE, excel_deep_level = "high", config = cfg)
  expect_type(out, "character")
  expect_length(out, 1L)
})
