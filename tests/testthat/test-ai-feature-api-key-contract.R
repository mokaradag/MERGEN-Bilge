# ==============================================================================
# Dosya Yolu: tests/testthat/test-ai-feature-api-key-contract.R
# Açıklama:   Sohbet dışı özelliklerin kişisel/kurumsal API anahtarı çözümleme
#             sözleşmesini doğrular.
# ==============================================================================

source(
  file.path(repo_root_for_tests, "R", "helpers_api_key_identity.R"),
  encoding = "UTF-8",
  local = globalenv()
)

source(
  file.path(repo_root_for_tests, "R", "helpers_feature_api_key.R"),
  encoding = "UTF-8",
  local = globalenv()
)

.make_feature_api_key_session <- function(auth_initialized = TRUE,
                                          system_username = "user_a",
                                          ai_api_key = NULL,
                                          ai_api_key_owner = NULL) {
  user_data <- new.env(parent = emptyenv())
  user_data$auth_initialized <- auth_initialized
  user_data$system_username <- system_username
  user_data$user_id <- 42L
  user_data$auth_source <- "keycloak"
  user_data$user_identity <- list(username = system_username)
  user_data$user_config <- list(KullaniciAdi = system_username)

  if (!is.null(ai_api_key)) {
    user_data$ai_api_key <- ai_api_key
  }

  if (!is.null(ai_api_key_owner)) {
    user_data$ai_api_key_owner <- ai_api_key_owner
  }

  list(userData = user_data)
}

.with_default_api_key_env <- function(code) {
  old_env <- Sys.getenv(
    c(
      "MERGEN_ALLOW_DEFAULT_API_KEY",
      "MERGEN_REQUIRE_PERSONAL_API_KEY",
      "MERGEN_DEFAULT_API_KEY"
    ),
    unset = NA_character_
  )

  on.exit({
    for (nm in names(old_env)) {
      if (is.na(old_env[[nm]])) {
        Sys.unsetenv(nm)
      } else {
        do.call(
          Sys.setenv,
          as.list(stats::setNames(old_env[[nm]], nm))
        )
      }
    }
  }, add = TRUE)

  Sys.setenv(
    MERGEN_ALLOW_DEFAULT_API_KEY = "TRUE",
    MERGEN_REQUIRE_PERSONAL_API_KEY = "FALSE",
    MERGEN_DEFAULT_API_KEY = "test-default-key"
  )

  force(code)
}

test_that("özellik anahtarı kişisel anahtarı kurum ve servis anahtarına tercih eder", {
  .with_default_api_key_env({
    session <- .make_feature_api_key_session(
      system_username = "user_a"
    )

    mb_api_key_set_session_key(
      session,
      "test-personal-key",
      owner = list(username = "user_a")
    )

    key <- mb_api_key_get_feature_key_value(
      session = session,
      service_key = "test-service-key",
      fallback_key = "test-legacy-key",
      require_auth = TRUE,
      prefer_service_key_after_personal = TRUE
    )

    expect_equal(key, "test-personal-key")
  })
})

test_that("TTS servis anahtarı kişisel anahtar yokken kurum anahtarından önce gelir", {
  .with_default_api_key_env({
    session <- .make_feature_api_key_session(
      system_username = "user_without_personal_key"
    )

    key <- mb_api_key_get_feature_key_value(
      session = session,
      service_key = "test-tts-service-key",
      fallback_key = "test-legacy-key",
      require_auth = TRUE,
      prefer_service_key_after_personal = TRUE
    )

    expect_equal(key, "test-tts-service-key")
  })
})

test_that("kişisel ve servis anahtarı yoksa izinli kurum anahtarı döner", {
  .with_default_api_key_env({
    session <- .make_feature_api_key_session(
      system_username = "user_without_personal_key"
    )

    key <- mb_api_key_get_feature_key_value(
      session = session,
      service_key = "",
      fallback_key = "test-legacy-key",
      require_auth = TRUE,
      prefer_service_key_after_personal = FALSE
    )

    expect_equal(key, "test-default-key")
  })
})

test_that("kurum anahtarı yoksa eski fallback anahtar kullanılabilir", {
  old_env <- Sys.getenv(
    c(
      "MERGEN_ALLOW_DEFAULT_API_KEY",
      "MERGEN_REQUIRE_PERSONAL_API_KEY",
      "MERGEN_DEFAULT_API_KEY"
    ),
    unset = NA_character_
  )

  on.exit({
    for (nm in names(old_env)) {
      if (is.na(old_env[[nm]])) {
        Sys.unsetenv(nm)
      } else {
        do.call(
          Sys.setenv,
          as.list(stats::setNames(old_env[[nm]], nm))
        )
      }
    }
  }, add = TRUE)

  Sys.setenv(
    MERGEN_ALLOW_DEFAULT_API_KEY = "FALSE",
    MERGEN_REQUIRE_PERSONAL_API_KEY = "FALSE",
    MERGEN_DEFAULT_API_KEY = "test-default-key"
  )

  session <- .make_feature_api_key_session(
    system_username = "user_without_personal_key"
  )

  key <- mb_api_key_get_feature_key_value(
    session = session,
    service_key = "",
    fallback_key = "test-legacy-key",
    require_auth = TRUE,
    prefer_service_key_after_personal = FALSE
  )

  expect_equal(key, "test-legacy-key")
})

test_that("require_auth: kullanıcı adı taşımayan sahip nesnesi anahtar almaz", {
  # `plan$owner` yalnızca NULL denetlenirse `list()` ya da kullanıcı adsız bir
  # sahip nesnesi kapıyı geçiyor ve SSO hazır olmadan kurum/servis anahtarıyla
  # işlem başlatılabiliyordu.
  eski <- mb_api_key_get_effective_key
  on.exit(assign("mb_api_key_get_effective_key", eski, envir = globalenv()), add = TRUE)

  for (sahte_owner in list(list(), list(username = ""), list(username = NULL), "user_a")) {
    assign(
      "mb_api_key_get_effective_key",
      local({
        o <- sahte_owner
        function(...) list(key = "", source = "missing", owner = o)
      }),
      envir = globalenv()
    )

    expect_equal(
      mb_api_key_get_feature_key_value(
        session = .make_feature_api_key_session(),
        service_key = "test-service-key",
        fallback_key = "test-legacy-key",
        require_auth = TRUE,
        prefer_service_key_after_personal = TRUE
      ),
      ""
    )
  }
})

test_that("TTS ve AI Uzman doğrudan oturum anahtarı okumaz", {
  tts_lines <- readLines(
    file.path(repo_root_for_tests, "R", "module_tts.R"),
    warn = FALSE,
    encoding = "UTF-8"
  )

  ai_expert_lines <- readLines(
    file.path(repo_root_for_tests, "R", "server_ai_expert_handlers.R"),
    warn = FALSE,
    encoding = "UTF-8"
  )

  expect_true(any(grepl("mb_api_key_get_feature_key_value\\(", tts_lines)))
  expect_true(any(grepl("mb_api_key_get_feature_key_value\\(", ai_expert_lines)))

  expect_false(any(grepl("session\\$userData\\$ai_api_key", tts_lines)))
  expect_false(any(grepl("session\\$userData\\$ai_api_key", ai_expert_lines)))
})

# Metin taraması tek başına yetmez: helper adı bir YORUM satırında geçerken
# kimlik bilgisi yine `session$userData[["ai_api_key"]]` üzerinden okunabilirdi.
# Üretim kapanışları dosyadan AST ile çıkarılıp izole bir ortamda ÇALIŞTIRILIR.
.feature_key_extract_fn <- function(rel_path, name) {
  ifadeler <- parse(
    file.path(repo_root_for_tests, "R", rel_path),
    keep.source = FALSE,
    encoding = "UTF-8"
  )

  bulunan <- NULL
  gez <- function(dugum) {
    if (!is.null(bulunan)) return(invisible(NULL))
    if (is.call(dugum)) {
      basi <- paste(deparse(dugum[[1]]), collapse = "")
      if (basi %in% c("<-", "<<-", "=") && length(dugum) >= 3L &&
          identical(paste(deparse(dugum[[2]]), collapse = ""), name)) {
        bulunan <<- dugum[[3]]
        return(invisible(NULL))
      }
    }
    if (is.call(dugum) || is.expression(dugum) || is.list(dugum) || is.pairlist(dugum)) {
      basla <- if (is.call(dugum)) 2L else 1L
      if (length(dugum) >= basla) {
        for (idx in seq.int(basla, length(dugum))) {
          # Boş argüman boş sembol olarak gelir; CLAUDE.md AST kuralı gereği
          # doğrudan indeksleyip quote(expr = ) ile karşılaştırılır.
          if (identical(dugum[[idx]], quote(expr = ))) next
          gez(dugum[[idx]])
        }
      }
    }
    invisible(NULL)
  }

  for (idx in seq_along(ifadeler)) gez(ifadeler[[idx]])
  bulunan
}

test_that("TTS anahtar çözümlemesi yalnızca yetki farkındalı helper sonucunu döndürür", {
  ifade <- .feature_key_extract_fn("module_tts.R", "resolve_tts_api_key")
  expect_false(is.null(ifade))

  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  env$tts_config <- list(api_key = "servis-anahtari")
  # Oturumda FARKLI bir sentinel durur; istek yoluna ulaşmamalıdır.
  env$session <- list(userData = list(ai_api_key = "OTURUM-SENTINEL"))
  env$mb_api_key_get_feature_key_value <- function(...) "HELPER-SENTINEL"

  cozumleyici <- eval(ifade, envir = env)
  expect_true(is.function(cozumleyici))
  expect_identical(cozumleyici(), "HELPER-SENTINEL")
})

test_that("AI Uzman istek parametreleri yalnızca yetki farkındalı helper sonucunu taşır", {
  ifade <- .feature_key_extract_fn("server_ai_expert_handlers.R", "prepare_llm_params")
  expect_false(is.null(ifade))

  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  env$isolate <- function(x) x
  env$safe_trimws <- function(x) trimws(as.character(x)[1])
  env$normalize_character_id <- function(x) "emre"
  env$get_characters_data <- function() list(styles = list(list(id = "emre")))
  env$settings_data <- list(selected_character = "emre")
  env$user_first_name <- "Test"
  env$session <- list(userData = list(ai_api_key = "OTURUM-SENTINEL"))
  env$mb_api_key_get_feature_key_value <- function(...) "HELPER-SENTINEL"

  hazirla <- eval(ifade, envir = env)
  expect_true(is.function(hazirla))

  params <- hazirla("emre")
  expect_identical(params$api_key, "HELPER-SENTINEL")
})

test_that("özellik anahtarı helper'ı manifestte TTS ve AI Uzman modüllerinden önce yüklenir", {
  manifest_lines <- readLines(
    file.path(repo_root_for_tests, "R", "config_source_manifest.R"),
    warn = FALSE,
    encoding = "UTF-8"
  )

  helper_pos <- grep("\"R/helpers_feature_api_key\\.R\"", manifest_lines)
  ai_expert_pos <- grep("\"R/server_ai_expert_handlers\\.R\"", manifest_lines)
  tts_pos <- grep("\"R/module_tts\\.R\"", manifest_lines)

  expect_length(helper_pos, 1)
  expect_length(ai_expert_pos, 1)
  expect_length(tts_pos, 1)

  expect_lt(helper_pos, ai_expert_pos)
  expect_lt(helper_pos, tts_pos)
})