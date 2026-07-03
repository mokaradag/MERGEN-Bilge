# ==============================================================================
# Dosya Yolu: tests/testthat/test-startup-lane-resolver-behavior.R
# Açıklama: R/helpers_startup_lane.R başlangıç şeridi (startup lane) saf
#           çözümleme yardımcılarının DAVRANIŞSAL testleri. Ağ/DB/LLM/tarayıcı
#           GEREKMEZ; tüm testler deterministik ve çevrimdışıdır.
#
#           Sözleşme:
#           - Tercih önceliği: kayıtlı tercih > MERGEN_STARTUP_LANE > ask_once
#           - Geçersiz değerler güvenli biçimde varsayılana düşer
#           - fast_lane / rich_lane / ask_once dışına asla çıkılmaz
#           - Hızlı/zengin hazır-olma anahtar kümeleri istemci (app_loading.js)
#             ve sunucu (module_boot_readiness.R) sözleşmeleriyle hizalıdır
# ==============================================================================

.source_startup_lane_for_test <- function() {
  env <- new.env(parent = globalenv())
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_startup_lane.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

testthat::test_that("mergen_normalize_startup_lane kanonik değerleri korur", {
  env <- .source_startup_lane_for_test()
  testthat::expect_identical(env$mergen_normalize_startup_lane("fast_lane"), "fast_lane")
  testthat::expect_identical(env$mergen_normalize_startup_lane("rich_lane"), "rich_lane")
  testthat::expect_identical(env$mergen_normalize_startup_lane("ask_once"), "ask_once")
})

testthat::test_that("mergen_normalize_startup_lane takma adları ve biçim gürültüsünü tolere eder", {
  env <- .source_startup_lane_for_test()
  testthat::expect_identical(env$mergen_normalize_startup_lane("FAST"), "fast_lane")
  testthat::expect_identical(env$mergen_normalize_startup_lane("  Rich_Lane  "), "rich_lane")
  testthat::expect_identical(env$mergen_normalize_startup_lane("normal"), "rich_lane")
  testthat::expect_identical(env$mergen_normalize_startup_lane("hizli"), "fast_lane")
  testthat::expect_identical(env$mergen_normalize_startup_lane("zengin"), "rich_lane")
  testthat::expect_identical(env$mergen_normalize_startup_lane("ask"), "ask_once")
})

testthat::test_that("mergen_normalize_startup_lane geçersiz değerleri güvenli varsayılana düşürür", {
  env <- .source_startup_lane_for_test()
  testthat::expect_identical(env$mergen_normalize_startup_lane(NULL), "ask_once")
  testthat::expect_identical(env$mergen_normalize_startup_lane(""), "ask_once")
  testthat::expect_identical(env$mergen_normalize_startup_lane(NA_character_), "ask_once")
  testthat::expect_identical(env$mergen_normalize_startup_lane("turbo_lane"), "ask_once")
  testthat::expect_identical(env$mergen_normalize_startup_lane(list()), "ask_once")
  testthat::expect_identical(env$mergen_normalize_startup_lane(42), "ask_once")
  # Özel varsayılan da desteklenir (sunucu tarafında rich_lane'e düşme)
  testthat::expect_identical(
    env$mergen_normalize_startup_lane("gecersiz", default = "rich_lane"),
    "rich_lane"
  )
  # Geçersiz default bile güvenlidir
  testthat::expect_identical(
    env$mergen_normalize_startup_lane("gecersiz", default = "olmayan_serit"),
    "ask_once"
  )
})

testthat::test_that("mergen_startup_lane_env_default ortam değişkenini normalize eder", {
  env <- .source_startup_lane_for_test()
  testthat::expect_identical(env$mergen_startup_lane_env_default("fast_lane"), "fast_lane")
  testthat::expect_identical(env$mergen_startup_lane_env_default("rich_lane"), "rich_lane")
  testthat::expect_identical(env$mergen_startup_lane_env_default("ask_once"), "ask_once")
  testthat::expect_identical(env$mergen_startup_lane_env_default(""), "ask_once")
  testthat::expect_identical(env$mergen_startup_lane_env_default("bozuk-deger"), "ask_once")

  # Gerçek ortam değişkeni okuma yolu da izole doğrulanır.
  withr::with_envvar(c(MERGEN_STARTUP_LANE = "fast_lane"), {
    testthat::expect_identical(env$mergen_startup_lane_env_default(), "fast_lane")
  })
  withr::with_envvar(c(MERGEN_STARTUP_LANE = NA), {
    testthat::expect_identical(env$mergen_startup_lane_env_default(), "ask_once")
  })
})

testthat::test_that("mergen_resolve_startup_lane tercih önceliğini uygular", {
  env <- .source_startup_lane_for_test()

  # 1) Kayıtlı tercih her zaman kazanır
  testthat::expect_identical(
    env$mergen_resolve_startup_lane(stored = "fast_lane", env_default = "rich_lane"),
    "fast_lane"
  )
  testthat::expect_identical(
    env$mergen_resolve_startup_lane(stored = "rich_lane", env_default = "fast_lane"),
    "rich_lane"
  )

  # 2) Kayıtlı tercih yoksa ortam varsayılanı
  testthat::expect_identical(
    env$mergen_resolve_startup_lane(stored = NULL, env_default = "fast_lane"),
    "fast_lane"
  )
  testthat::expect_identical(
    env$mergen_resolve_startup_lane(stored = "gecersiz", env_default = "rich_lane"),
    "rich_lane"
  )

  # 3) İkisi de kesin değilse ask_once (ilk açılış seçicisi)
  testthat::expect_identical(
    env$mergen_resolve_startup_lane(stored = NULL, env_default = "ask_once"),
    "ask_once"
  )
  testthat::expect_identical(
    env$mergen_resolve_startup_lane(stored = "ask_once", env_default = "bozuk"),
    "ask_once"
  )
})

testthat::test_that("mergen_startup_lane_is_fast yalnızca fast_lane için TRUE döner", {
  env <- .source_startup_lane_for_test()
  testthat::expect_true(env$mergen_startup_lane_is_fast("fast_lane"))
  testthat::expect_true(env$mergen_startup_lane_is_fast("FAST"))
  testthat::expect_false(env$mergen_startup_lane_is_fast("rich_lane"))
  testthat::expect_false(env$mergen_startup_lane_is_fast("ask_once"))
  testthat::expect_false(env$mergen_startup_lane_is_fast(NULL))
  testthat::expect_false(env$mergen_startup_lane_is_fast("bozuk"))
})

testthat::test_that("hazır-olma anahtar kümeleri şerit sözleşmeleriyle hizalıdır", {
  env <- .source_startup_lane_for_test()

  fast_keys <- env$mergen_fast_lane_required_boot_keys()
  rich_keys <- env$mergen_rich_lane_required_boot_keys()

  # Hızlı şerit yalnızca sohbet kabuğu hazırlığını bekler
  testthat::expect_identical(
    fast_keys,
    c("connect", "auth_ready", "welcome_client_ready")
  )
  # Hızlı şerit medya/galeri/dosya indeksini BEKLEMEZ
  testthat::expect_false("character_media_ready" %in% fast_keys)
  testthat::expect_false("file_index_ready" %in% fast_keys)
  testthat::expect_false("saved_chats_preview_ready" %in% fast_keys)

  # Zengin şerit mevcut boot-readiness zorunlu kümesiyle aynı kalır
  testthat::expect_identical(
    sort(rich_keys),
    sort(c(
      "auth_ready", "saved_chats_preview_ready", "file_index_ready",
      "character_media_ready", "welcome_client_ready"
    ))
  )
})

testthat::test_that("zengin şerit anahtarları module_boot_readiness varsayılanıyla birebir aynıdır", {
  env <- .source_startup_lane_for_test()

  boot_env <- new.env(parent = globalenv())
  boot_env$`%||%` <- function(a, b) if (is.null(a)) b else a
  source(
    file.path(resolve_repo_root_for_tests(), "R", "module_boot_readiness.R"),
    encoding = "UTF-8",
    local = boot_env
  )

  fake_session <- list(
    sendCustomMessage = function(type, payload) invisible(NULL)
  )
  ready <- boot_env$bootReadinessInit(fake_session)

  testthat::expect_setequal(
    ready$required,
    env$mergen_rich_lane_required_boot_keys()
  )
})
