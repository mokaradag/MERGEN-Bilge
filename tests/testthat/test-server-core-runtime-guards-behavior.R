# ==============================================================================
# Dosya Yolu: tests/testthat/test-server-core-runtime-guards-behavior.R
# Açıklama: Çekirdek etkileşim/gözlemci runtime bağlama katmanının saf sözleşme
#           guard'ları için davranış testleri. test-server-wiring-guard-behavior.R
#           bundle-seviyesi guard'ları kapsıyordu; bu dosya o testte İSİMLE
#           çağrılmayan yardımcıları tamamlar: .server_runtime_stop,
#           .server_core_interaction_stop/_require_context/_require_values/
#           _require_functions/_resolve_bundle ve .server_core_observer_
#           require_functions/_call_with_optional_boot_ready. Saf, çevrimdışı,
#           deterministik; Türkçe hata + sahip etiketi doğrulanır.
# ==============================================================================

# Türkçe yorum: Runtime sırasıyla aynı: önce düşük seviye sözleşmeler, sonra wiring.
.coreGuardEnv <- function() {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  for (f in c(
    "R/helpers_server_runtime_contracts.R",
    "R/helpers_server_runtime_named_contracts.R",
    "R/server_module_wiring.R",
    "R/server_chat_engine_dependencies.R",
    "R/server_core_interaction_runtime.R",
    "R/server_core_observer_runtime.R"
  )) {
    source(file.path(kok, f), encoding = "UTF-8", local = env)
  }
  env
}

# Geçerli bir çekirdek etkileşim bundle alan listesi (wiring testiyle aynı şekil)
.coreBundleFields <- function() {
  list(
    settings_data = list(),
    api_config = list(),
    media_modules = list(ai_expert = list(), tts_processor = list()),
    render_welcome_screen = function(...) invisible(NULL),
    start_new_chat = function(...) invisible(NULL),
    send_message = function(...) invisible(NULL),
    load_chat_in_progress = function(...) invisible(NULL),
    welcome_fns = new.env(parent = emptyenv()),
    user_config_provider = function(...) list(),
    user_first_name_fn = function(...) ""
  )
}

# Sınıflı geçerli runtime context
.fakeRuntimeCtx <- function() {
  ctx <- new.env(parent = emptyenv())
  class(ctx) <- c("mergen_server_runtime_context", "environment")
  ctx
}

test_that(".server_runtime_stop verilen Türkçe mesajla durur", {
  env <- .coreGuardEnv()
  expect_error(env$.server_runtime_stop("özel boot hatası"), "özel boot hatası")
})

test_that(".server_core_interaction_stop mesajı .server_runtime_stop ile iletir", {
  env <- .coreGuardEnv()
  expect_error(env$.server_core_interaction_stop("etkileşim durdu"), "etkileşim durdu")
})

test_that(".server_core_interaction_require_context yalnızca gerçek context kabul eder", {
  env <- .coreGuardEnv()
  expect_true(env$.server_core_interaction_require_context(.fakeRuntimeCtx()))
  expect_error(env$.server_core_interaction_require_context(list()), "runtime context")
  expect_error(env$.server_core_interaction_require_context(NULL), "runtime context")
  expect_error(env$.server_core_interaction_require_context(new.env()), "runtime context")
})

test_that(".server_core_interaction_require_values eksik alanda sahip etiketiyle durur", {
  env <- .coreGuardEnv()
  expect_true(env$.server_core_interaction_require_values(
    list(a = 1, b = 2), c("a", "b"), "deneme_sahibi"
  ))
  expect_error(
    env$.server_core_interaction_require_values(list(a = 1), c("a", "eksik"), "deneme_sahibi"),
    "deneme_sahibi"
  )
})

test_that(".server_core_interaction_require_functions fonksiyon olmayan değeri reddeder", {
  env <- .coreGuardEnv()
  expect_true(env$.server_core_interaction_require_functions(list(
    f = function() NULL, g = function(x) x
  )))
  expect_error(
    env$.server_core_interaction_require_functions(list(iyi = function() NULL, kotu = 42)),
    "kotu"
  )
})

test_that(".server_core_interaction_resolve_bundle NULL bundle'ı alanlardan inşa eder", {
  env <- .coreGuardEnv()
  fields <- .coreBundleFields()
  bundle <- env$.server_core_interaction_resolve_bundle(
    core_bundle = NULL,
    settings_data = fields$settings_data,
    api_config = fields$api_config,
    media_modules = fields$media_modules,
    render_welcome_screen = fields$render_welcome_screen,
    start_new_chat = fields$start_new_chat,
    send_message = fields$send_message,
    load_chat_in_progress = fields$load_chat_in_progress,
    welcome_fns = fields$welcome_fns,
    user_config_provider = fields$user_config_provider,
    user_first_name_fn = fields$user_first_name_fn
  )
  expect_true(inherits(bundle, "mergen_core_interaction_bundle"))
  expect_true(is.function(bundle$send_message))
})

test_that(".server_core_interaction_resolve_bundle var olan geçerli bundle'ı doğrulayıp döndürür", {
  env <- .coreGuardEnv()
  mevcut <- do.call(env$serverBuildCoreInteractionBundle, .coreBundleFields())
  out <- env$.server_core_interaction_resolve_bundle(
    core_bundle = mevcut,
    settings_data = NULL, api_config = NULL, media_modules = NULL,
    render_welcome_screen = NULL, start_new_chat = NULL, send_message = NULL,
    load_chat_in_progress = NULL, welcome_fns = NULL,
    user_config_provider = NULL, user_first_name_fn = NULL
  )
  expect_identical(out, mevcut)
})

test_that(".server_core_interaction_resolve_bundle geçersiz var olan bundle'da durur", {
  env <- .coreGuardEnv()
  bozuk <- .coreBundleFields()
  bozuk$send_message <- NULL  # zorunlu alan eksik
  expect_error(
    env$.server_core_interaction_resolve_bundle(
      core_bundle = bozuk,
      settings_data = NULL, api_config = NULL, media_modules = NULL,
      render_welcome_screen = NULL, start_new_chat = NULL, send_message = NULL,
      load_chat_in_progress = NULL, welcome_fns = NULL,
      user_config_provider = NULL, user_first_name_fn = NULL
    )
  )
})

test_that(".server_core_observer_require_functions fonksiyon olmayanı reddeder", {
  env <- .coreGuardEnv()
  expect_true(env$.server_core_observer_require_functions(list(f = function() NULL)))
  expect_error(
    env$.server_core_observer_require_functions(list(iyi = function() NULL, kotu = "x")),
    "kotu"
  )
})

test_that(".server_core_observer_call_with_optional_boot_ready boot_ready'yi yalnızca uygun fn'e geçirir", {
  env <- .coreGuardEnv()

  # 1) boot_ready parametresi olan fn + boot_ready dolu -> geçirilir
  fn_explicit <- function(x, boot_ready = NULL) list(x = x, br = boot_ready)
  r1 <- env$.server_core_observer_call_with_optional_boot_ready(
    fn_explicit, list(x = 1L), boot_ready = "BR"
  )
  expect_identical(r1$br, "BR")

  # 2) ... alan fn + boot_ready dolu -> geçirilir
  fn_dots <- function(x, ...) { d <- list(...); list(x = x, br = d$boot_ready) }
  r2 <- env$.server_core_observer_call_with_optional_boot_ready(
    fn_dots, list(x = 2L), boot_ready = "BR2"
  )
  expect_identical(r2$br, "BR2")

  # 3) boot_ready NULL ise, fn kabul etse bile geçirilmez
  r3 <- env$.server_core_observer_call_with_optional_boot_ready(
    fn_explicit, list(x = 3L), boot_ready = NULL
  )
  expect_null(r3$br)

  # 4) boot_ready'yi kabul etmeyen (ne param ne ...) fn'e boot_ready ENJEKTE EDİLMEZ
  #    (aksi halde do.call kullanılmayan argüman hatası verirdi)
  fn_strict <- function(x) list(x = x)
  r4 <- env$.server_core_observer_call_with_optional_boot_ready(
    fn_strict, list(x = 4L), boot_ready = "BR4"
  )
  expect_identical(r4$x, 4L)
})
