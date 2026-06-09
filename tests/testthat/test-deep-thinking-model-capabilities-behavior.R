# ==============================================================================
# Dosya Yolu: tests/testthat/test-deep-thinking-model-capabilities-behavior.R
# Açıklama: R/helpers_deep_thinking_model_capabilities.R saf yardımcılarının
#           DAVRANIŞSAL testleri. Derin Düşünme model kimliği toplama, yetenek
#           tablosu tamamlama (var olan açık tanım kazanır), endpoint haritası
#           güvenli ekleme ve eski iki-blok config_api.R mekanizmasının sıralı
#           bileşimiyle birebir denklik doğrulanır. Shiny/DB/LLM/ağ gerekmez.
# ==============================================================================

.dtcap_repo_root <- function() {
  if (exists("repo_root_for_tests", inherits = TRUE)) {
    return(get("repo_root_for_tests", inherits = TRUE))
  }
  normalizePath(file.path(getwd(), "..", ".."), winslash = "/", mustWork = TRUE)
}

.dtcap_source_once <- function() {
  if (!exists("apply_deep_thinking_model_capabilities", envir = globalenv(),
              mode = "function", inherits = TRUE)) {
    source(
      file.path(.dtcap_repo_root(), "R", "helpers_deep_thinking_model_capabilities.R"),
      encoding = "UTF-8",
      local = globalenv()
    )
  }
  invisible(TRUE)
}

# Sentetik api_config fixture'ı (gerçek üretim model adları kullanılmaz).
.dtcap_fixture <- function() {
  list(
    local_model_endpoint_map = c(
      "model-a" = "primary",
      "model-b" = "secondary"
    ),
    deep_thinking_models = list(
      mcp_excel = list(low = "deep-low-x", high = "deep-high-x"),
      coding    = list(low = "model-a",    high = "deep-high-y")
    ),
    local_model_capabilities = list(
      "model-a" = list(
        thinking = TRUE,
        omit_temperature = TRUE,
        stream_reasoning = TRUE,
        allow_reasoning_fallback = TRUE
      ),
      "model-b" = list(
        thinking = FALSE,
        omit_temperature = FALSE,
        stream_reasoning = FALSE,
        allow_reasoning_fallback = FALSE
      ),
      "deep-high-y" = list(
        thinking = TRUE,
        omit_temperature = FALSE,
        stream_reasoning = TRUE,
        allow_reasoning_fallback = TRUE,
        request_overrides = list(
          chat_template_kwargs = list(enable_thinking = TRUE)
        )
      )
    )
  )
}

# Eski config_api.R iki-blok mekanizmasının birebir simülasyonu (referans).
# Blok 1: tabloda olmayan modele şablon kaydı + endpoint haritası tamamlama.
# Blok 2: tüm deep modellere modifyList(defaults, existing) tamamlaması.
.dtcap_legacy_two_block <- function(api_config, deep_model_ids) {
  template <- list(
    thinking = TRUE,
    omit_temperature = TRUE,
    stream_reasoning = TRUE,
    allow_reasoning_fallback = TRUE,
    request_overrides = list()
  )

  for (model_id in deep_model_ids) {
    model_id <- as.character(model_id)[1]
    if (is.na(model_id) || !nzchar(model_id)) next

    if (is.null(api_config$local_model_capabilities[[model_id]])) {
      api_config$local_model_capabilities[[model_id]] <- template
    }

    endpoint_map <- api_config$local_model_endpoint_map
    if (is.null(endpoint_map)) endpoint_map <- character()
    endpoint_map_names <- names(endpoint_map)
    endpoint_mapped <- !is.null(endpoint_map_names) &&
      model_id %in% endpoint_map_names &&
      !is.na(endpoint_map[model_id]) &&
      nzchar(as.character(endpoint_map[model_id])[1])
    if (!isTRUE(endpoint_mapped)) {
      endpoint_map[model_id] <- "primary"
      api_config$local_model_endpoint_map <- endpoint_map
    }
  }

  ids2 <- unique(unname(unlist(api_config$deep_thinking_models,
                               recursive = TRUE, use.names = FALSE)))
  ids2 <- ids2[!is.na(ids2) & nzchar(as.character(ids2))]

  for (model_id in ids2) {
    existing <- api_config$local_model_capabilities[[model_id]]
    if (!is.list(existing)) existing <- list()
    api_config$local_model_capabilities[[model_id]] <- utils::modifyList(
      template, existing, keep.null = TRUE
    )
  }

  api_config
}

testthat::test_that("deep model kimliği toplama: NA/boş ayıklanır, benzersizleşir", {
  .dtcap_source_once()

  cfg <- .dtcap_fixture()
  cfg$deep_thinking_models$coding$low <- ""
  cfg$deep_thinking_models$mcp_excel$high <- "deep-low-x"

  ids <- collect_deep_thinking_model_ids(cfg)

  testthat::expect_identical(sort(ids), sort(c("deep-low-x", "deep-high-y")))
  testthat::expect_identical(collect_deep_thinking_model_ids(NULL), character(0))
  testthat::expect_identical(collect_deep_thinking_model_ids(list()), character(0))
})

testthat::test_that("bilinmeyen deep model: güvenli varsayılan yetenek + primary endpoint açılır", {
  .dtcap_source_once()

  out <- apply_deep_thinking_model_capabilities(.dtcap_fixture())

  caps <- out$local_model_capabilities[["deep-low-x"]]
  testthat::expect_true(caps$thinking)
  testthat::expect_true(caps$omit_temperature)
  testthat::expect_true(caps$stream_reasoning)
  testthat::expect_true(caps$allow_reasoning_fallback)
  testthat::expect_identical(caps$request_overrides, list())

  testthat::expect_identical(
    unname(out$local_model_endpoint_map["deep-low-x"]),
    "primary"
  )
  # Harita adlandırılmış karakter vektörü olarak kalmalıdır.
  testthat::expect_true(is.character(out$local_model_endpoint_map))
})

testthat::test_that("var olan açık tanım kazanır; yalnızca eksik alanlar tamamlanır", {
  .dtcap_source_once()

  out <- apply_deep_thinking_model_capabilities(.dtcap_fixture())

  # deep-high-y: açık tanımdaki omit_temperature = FALSE ve özel
  # request_overrides değerleri varsayılana ezilmemelidir.
  caps_y <- out$local_model_capabilities[["deep-high-y"]]
  testthat::expect_false(caps_y$omit_temperature)
  testthat::expect_true(caps_y$request_overrides$chat_template_kwargs$enable_thinking)

  # model-a: tabloda tanımlı bir deep model; eksik request_overrides alanı
  # boş liste ile tamamlanır, diğer değerleri korunur.
  caps_a <- out$local_model_capabilities[["model-a"]]
  testthat::expect_true(caps_a$thinking)
  testthat::expect_identical(caps_a$request_overrides, list())

  # Mevcut endpoint eşlemesi korunur (model-a primary idi, öyle kalır).
  testthat::expect_identical(unname(out$local_model_endpoint_map["model-a"]), "primary")

  # Deep olmayan model-b yetenekleri hiç dokunulmadan kalır.
  testthat::expect_null(out$local_model_capabilities[["model-b"]]$request_overrides)
})

testthat::test_that("boş/geçersiz girişlerde güvenli davranış korunur", {
  .dtcap_source_once()

  # api_config liste değilse olduğu gibi döner.
  testthat::expect_identical(apply_deep_thinking_model_capabilities(NULL), NULL)

  # Deep model listesi boşsa yapı değişmez.
  cfg <- .dtcap_fixture()
  cfg$deep_thinking_models <- list()
  testthat::expect_identical(apply_deep_thinking_model_capabilities(cfg), cfg)

  # Endpoint haritası NULL ise sıfırdan adlandırılmış vektör kurulur.
  cfg2 <- .dtcap_fixture()
  cfg2$local_model_endpoint_map <- NULL
  out2 <- apply_deep_thinking_model_capabilities(cfg2)
  testthat::expect_identical(unname(out2$local_model_endpoint_map["deep-low-x"]), "primary")

  # NA/boş endpoint değeri "primary" ile onarılır.
  cfg3 <- .dtcap_fixture()
  cfg3$local_model_endpoint_map <- c(cfg3$local_model_endpoint_map, "deep-low-x" = "")
  out3 <- apply_deep_thinking_model_capabilities(cfg3)
  testthat::expect_identical(unname(out3$local_model_endpoint_map["deep-low-x"]), "primary")
})

testthat::test_that("birleşik helper, eski iki-blok mekanizmasının bileşimiyle birebir aynıdır", {
  .dtcap_source_once()

  fixtures <- list(
    .dtcap_fixture(),
    local({
      cfg <- .dtcap_fixture()
      cfg$local_model_endpoint_map <- NULL
      cfg
    }),
    local({
      cfg <- .dtcap_fixture()
      cfg$deep_thinking_models$coding$high <- "model-b"
      cfg
    }),
    local({
      cfg <- .dtcap_fixture()
      cfg$deep_thinking_models <- list(
        mcp_excel = list(low = "", high = NA_character_),
        coding    = list(low = "tek-gecerli-model", high = "tek-gecerli-model")
      )
      cfg
    })
  )

  for (cfg in fixtures) {
    ids <- collect_deep_thinking_model_ids(cfg)
    legacy <- .dtcap_legacy_two_block(cfg, ids)
    birlesik <- apply_deep_thinking_model_capabilities(cfg)

    testthat::expect_identical(
      birlesik$local_model_capabilities,
      legacy$local_model_capabilities,
      info = "Yetenek tablosu eski iki-blok bileşiminden sapmamalıdır."
    )
    testthat::expect_identical(
      birlesik$local_model_endpoint_map,
      legacy$local_model_endpoint_map,
      info = "Endpoint haritası eski iki-blok bileşiminden sapmamalıdır."
    )
  }
})
