# ==============================================================================
# Dosya Yolu: tests/testthat/test-server-wiring-guard-behavior.R
# Açıklama: Server modül bağlama (wiring) katmanının saf sözleşme guard'ları
#           için davranış testleri: .server_wiring_*, sohbet motoru bağımlılık
#           bundle'ı ve çekirdek etkileşim/gözlemci bundle guard'ları. Eksik
#           alan/fonksiyonlarda Türkçe hata + sahip etiketi, geçerli girdide
#           sınıflı bundle üretimi doğrulanır. Çevrimdışı ve deterministik.
# ==============================================================================

.wiringGuardEnv <- function() {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  # Çalışma zamanı sırasıyla aynı: önce düşük seviye sözleşmeler, sonra wiring
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

# Geçerli bir sohbet motoru bağımlılık listesi üretir
.makeChatEngineDeps <- function() {
  list(
    settings_data = list(model_selection = "test-model"),
    # api_key fonksiyon olmak zorunda değildir; değeri doğrulanmaz. Secret
    # tarayıcı eşleşmesini önlemek için kısa, anlamsız bir yer tutucu.
    api_key = "ph-key",
    user_config_rv = function() list(name = "Test"),
    perf_tracker = list(
      track_error = function(...) invisible(NULL),
      track_request = function(...) invisible(NULL)
    ),
    ai_processor = list(call_llm_non_streaming = function(...) invisible(NULL)),
    tts_processor = list(),
    tts_visualizer = list(),
    stt_data = list(),
    saved_chats_data = list(),
    send_message_fns = new.env(parent = emptyenv()),
    send_message_proxy = function(...) invisible(NULL),
    api_config = list(local_models = c("m1"))
  )
}

# Geçerli bir çekirdek etkileşim bundle alan listesi üretir
.makeCoreBundleFields <- function() {
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

testthat::test_that(".server_wiring_stop ve temel wiring guard'ları Türkçe hatayla durdurur", {
  env <- .wiringGuardEnv()

  testthat::expect_error(env$.server_wiring_stop("özel hata"), "özel hata")

  # Geçersiz fonksiyon: sahip etiketi server_module_wiring hata mesajında görünür
  testthat::expect_error(
    env$.server_wiring_require_function("fonksiyon değil", "deneme_fn"),
    "server_module_wiring"
  )
  testthat::expect_error(
    env$.server_wiring_require_function(NULL, "deneme_fn"),
    "deneme_fn"
  )

  # Geçerli fonksiyon sorunsuz geçer
  testthat::expect_true(env$.server_wiring_require_function(function() NULL, "deneme_fn"))

  # Adlandırılmış fonksiyon listesi: eksik olan adıyla raporlanır
  testthat::expect_error(
    env$.server_wiring_require_functions(list(iyi = function() NULL, kotu = 42)),
    "kotu"
  )
  testthat::expect_true(
    env$.server_wiring_require_functions(list(a = function() NULL, b = function() NULL))
  )

  # Ortam sözleşmesi: ortam olmayan girdi sahiple raporlanır
  testthat::expect_error(
    env$.server_wiring_require_environment(list(), "deneme_env"),
    "deneme_env"
  )
  testthat::expect_true(
    env$.server_wiring_require_environment(new.env(), "deneme_env")
  )
})

testthat::test_that(".server_wiring_require_context yalnızca gerçek runtime context kabul eder", {
  env <- .wiringGuardEnv()

  # Sahte ama doğru sınıflı environment context kabul edilir
  ctx <- new.env(parent = emptyenv())
  class(ctx) <- c("mergen_server_runtime_context", "environment")
  testthat::expect_true(env$.server_wiring_require_context(ctx, "deneme_sahibi"))

  # Liste, sınıfsız environment ve NULL reddedilir; sahip etiketi mesajda
  testthat::expect_error(env$.server_wiring_require_context(list(), "deneme_sahibi"), "deneme_sahibi")
  testthat::expect_error(env$.server_wiring_require_context(new.env(), "deneme_sahibi"), "deneme_sahibi")
  testthat::expect_error(env$.server_wiring_require_context(NULL, "deneme_sahibi"), "deneme_sahibi")
})

testthat::test_that("sohbet motoru bağımlılık bundle'ı eksik alan ve fonksiyonları yakalar", {
  env <- .wiringGuardEnv()

  # Liste olmayan girdi reddedilir
  testthat::expect_error(
    env$.server_wiring_require_chat_engine_deps("liste değil"),
    "liste olmalıdır"
  )

  # Eksik zorunlu alan adıyla raporlanır
  eksik <- .makeChatEngineDeps()
  eksik$saved_chats_data <- NULL
  testthat::expect_error(
    env$.server_wiring_require_chat_engine_deps(eksik),
    "saved_chats_data"
  )

  # send_message_fns ortam olmak zorundadır
  yanlis_env <- .makeChatEngineDeps()
  yanlis_env$send_message_fns <- list()
  testthat::expect_error(
    env$.server_wiring_require_chat_engine_deps(yanlis_env),
    "send_message_fns"
  )

  # perf_tracker$track_error fonksiyon değilse adıyla yakalanır
  yanlis_fn <- .makeChatEngineDeps()
  yanlis_fn$perf_tracker$track_error <- "fonksiyon değil"
  testthat::expect_error(
    env$.server_wiring_require_chat_engine_deps(yanlis_fn),
    "perf_tracker_track_error"
  )

  # Geçerli bağımlılıklar sorunsuz geçer
  testthat::expect_true(env$.server_wiring_require_chat_engine_deps(.makeChatEngineDeps()))
})

testthat::test_that("serverBuildChatEngineDependencyBundle sınıflı bundle üretir ve media fallback uygular", {
  env <- .wiringGuardEnv()
  deps <- .makeChatEngineDeps()

  bundle <- env$serverBuildChatEngineDependencyBundle(
    settings_data = deps$settings_data,
    api_key = deps$api_key,
    user_config_rv = deps$user_config_rv,
    perf_tracker = deps$perf_tracker,
    saved_chats_data = deps$saved_chats_data,
    send_message_fns = deps$send_message_fns,
    send_message_proxy = deps$send_message_proxy,
    api_config = deps$api_config,
    # ai_processor/tts/stt doğrudan verilmiyor; media_modules'tan dolmalı
    media_modules = list(
      ai_processor = deps$ai_processor,
      tts_processor = list(soz = "tts"),
      tts_visualizer = list(soz = "viz"),
      stt_data = list(soz = "stt"),
      feedback_modal = list(soz = "fb")
    )
  )

  testthat::expect_s3_class(bundle, "mergen_chat_engine_dependency_bundle")
  # media_modules fallback gerçekten alanları doldurmuş olmalı
  testthat::expect_identical(bundle$tts_processor$soz, "tts")
  testthat::expect_identical(bundle$stt_data$soz, "stt")
  testthat::expect_identical(bundle$feedback_modal$soz, "fb")

  # Açık verilen değer media_modules'a karşı önceliklidir
  bundle2 <- env$serverBuildChatEngineDependencyBundle(
    settings_data = deps$settings_data,
    api_key = deps$api_key,
    user_config_rv = deps$user_config_rv,
    perf_tracker = deps$perf_tracker,
    saved_chats_data = deps$saved_chats_data,
    send_message_fns = deps$send_message_fns,
    send_message_proxy = deps$send_message_proxy,
    api_config = deps$api_config,
    ai_processor = deps$ai_processor,
    tts_processor = list(soz = "acik-deger"),
    tts_visualizer = list(),
    stt_data = list(),
    media_modules = list(tts_processor = list(soz = "media-deger"))
  )
  testthat::expect_identical(bundle2$tts_processor$soz, "acik-deger")
})

testthat::test_that(".server_wiring_resolve_chat_engine_deps mevcut bundle'ı korur, yoksa kurar", {
  env <- .wiringGuardEnv()
  deps <- .makeChatEngineDeps()

  hazir_bundle <- do.call(env$serverBuildChatEngineDependencyBundle, deps)

  # Mevcut bundle aynen geri döner (yeniden kurulmaz)
  geri <- env$.server_wiring_resolve_chat_engine_deps(
    hazir_bundle,
    settings_data = NULL, api_key = NULL, user_config_rv = NULL,
    perf_tracker = NULL, saved_chats_data = NULL, send_message_fns = NULL,
    send_message_proxy = NULL, api_config = NULL
  )
  testthat::expect_identical(geri, hazir_bundle)

  # NULL bundle: verilen parçalardan yeni bundle kurulur
  yeni <- do.call(
    env$.server_wiring_resolve_chat_engine_deps,
    c(list(NULL), deps)
  )
  testthat::expect_s3_class(yeni, "mergen_chat_engine_dependency_bundle")
})

testthat::test_that("çekirdek etkileşim bundle guard'ı alan/fonksiyon/ortam sözleşmesini uygular", {
  env <- .wiringGuardEnv()

  # Liste olmayan girdi sahip etiketiyle reddedilir
  testthat::expect_error(
    env$.server_core_interaction_require_bundle("liste değil", owner = "deneme_bundle"),
    "deneme_bundle"
  )

  # Eksik alan adıyla raporlanır
  eksik <- .makeCoreBundleFields()
  eksik$welcome_fns <- NULL
  testthat::expect_error(
    env$.server_core_interaction_require_bundle(eksik),
    "welcome_fns"
  )

  # media_modules listesinde ai_expert zorunludur
  eksik_media <- .makeCoreBundleFields()
  eksik_media$media_modules <- list(tts_processor = list())
  testthat::expect_error(
    env$.server_core_interaction_require_bundle(eksik_media),
    "ai_expert"
  )

  # welcome_fns ortam olmak zorundadır
  yanlis_welcome <- .makeCoreBundleFields()
  yanlis_welcome$welcome_fns <- list()
  testthat::expect_error(
    env$.server_core_interaction_require_bundle(yanlis_welcome),
    "welcome_fns"
  )

  # Geçerli bundle: serverBuildCoreInteractionBundle sınıflı nesne üretir
  bundle <- do.call(env$serverBuildCoreInteractionBundle, .makeCoreBundleFields())
  testthat::expect_s3_class(bundle, "mergen_core_interaction_bundle")
})

testthat::test_that("çekirdek gözlemci bundle guard'ı zorunlu alanları ve media sözleşmesini uygular", {
  env <- .wiringGuardEnv()

  testthat::expect_error(
    env$.server_core_observer_require_bundle("liste değil"),
    "liste olmalıdır"
  )

  # Gözlemci bundle'ı daha dar bir alan kümesi ister
  eksik <- list(
    settings_data = list(),
    api_config = list(),
    media_modules = list(ai_expert = list(), tts_processor = list()),
    render_welcome_screen = function(...) NULL,
    start_new_chat = function(...) NULL
    # send_message eksik
  )
  testthat::expect_error(
    env$.server_core_observer_require_bundle(eksik),
    "send_message"
  )

  # media_modules tts_processor eksikse adıyla raporlanır
  eksik_media <- .makeCoreBundleFields()
  eksik_media$media_modules <- list(ai_expert = list())
  testthat::expect_error(
    env$.server_core_observer_require_bundle(eksik_media),
    "tts_processor"
  )

  # Geçerli (geniş) bundle gözlemci guard'ından da geçer
  testthat::expect_true(
    env$.server_core_observer_require_bundle(.makeCoreBundleFields())
  )

  # Context guard'ı: sınıflı environment ister
  ctx <- new.env(parent = emptyenv())
  class(ctx) <- c("mergen_server_runtime_context", "environment")
  testthat::expect_true(env$.server_core_observer_require_context(ctx))
  testthat::expect_error(
    env$.server_core_observer_require_context(list()),
    "runtime context"
  )
})
