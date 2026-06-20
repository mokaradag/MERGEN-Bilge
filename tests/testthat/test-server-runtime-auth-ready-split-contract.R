# ==============================================================================
# Dosya Yolu: tests/testthat/test-server-runtime-auth-ready-split-contract.R
# Açıklama: ServerRuntimeContext'in SSO sonrası (post-auth) işleri + yenilenebilir
#           modül wiring katmanının R/server_runtime_context.R'den ayrılıp
#           R/server_runtime_auth_ready.R dosyasına taşındığını dondurur.
#           serverRuntimeOnSsoAuthReady, serverRuntimeRefreshModuleOnSsoAuthReady
#           ve serverRuntimeAttachRefreshableModule artık ayrı dosyadadır; modül
#           kayıt yardımcıları (AttachModule/GetModule/ExposeSessionData) ve
#           context init/attach/require yardımcıları context dosyasında kalır.
#
#           Bu yapısal bir sözleşme + odaklı davranış testidir; derin SSO zamanlama
#           kapsaması test-server-runtime-context.R ve
#           test-e2e-sso-identity-readiness-regression.R içindedir. Uygulamayı
#           başlatmaz; DB, LLM, tarayıcı veya ağ GEREKMEZ.
# ==============================================================================

repo_root_ar <- resolve_repo_root_for_tests()

.read_repo_text_auth_ready_split <- function(rel_path) {
  abs_path <- file.path(repo_root_ar, rel_path)
  if (!file.exists(abs_path)) {
    stop(sprintf("Dosya bulunamadı: %s", rel_path), call. = FALSE)
  }
  size <- suppressWarnings(file.info(abs_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }
  con <- file(abs_path, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )
  if (is.na(txt)) txt <- ""
  txt <- gsub("\r\n?|\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

# Context'ten ayrılıp auth-ready dosyasına taşınan fonksiyonlar.
.auth_ready_fns <- c(
  "serverRuntimeOnSsoAuthReady",
  "serverRuntimeRefreshModuleOnSsoAuthReady",
  "serverRuntimeAttachRefreshableModule"
)

# Context dosyasında KALMASI gereken modül kayıt + context yardımcıları.
.context_kept_fns <- c(
  "serverRuntimeContextInit",
  "serverRuntimeAttachModule",
  "serverRuntimeGetModule",
  "serverRuntimeExposeSessionData",
  "serverRuntimeRequireIdentity"
)

.source_runtime_auth_ready_env <- function() {
  env <- new.env(parent = globalenv())
  for (f in c(
    "R/helpers_server_runtime_contracts.R",
    "R/helpers_server_runtime_named_contracts.R",
    "R/server_runtime_context.R",
    "R/server_runtime_auth_ready.R"
  )) {
    suppressWarnings(source(file.path(repo_root_ar, f), encoding = "UTF-8", local = env))
  }
  env
}

# class'ı doğru ayarlanmış minimal sahte runtime context.
.fake_auth_ctx <- function(sso_active = TRUE, authenticated = TRUE, auth_ready = TRUE) {
  ctx <- new.env(parent = emptyenv())
  class(ctx) <- c("mergen_server_runtime_context", "environment")
  ctx$identity <- list(
    is_sso_active = function() isTRUE(sso_active),
    is_auth_ready = function() isTRUE(auth_ready)
  )
  ctx$sso_state <- list(authenticated = authenticated)
  ctx$modules <- list()
  ctx$session <- list(userData = new.env(parent = emptyenv()))
  ctx
}

test_that("auth-ready dosyası mevcuttur ve üç wiring fonksiyonunu gösterir", {
  auth_path <- file.path(repo_root_ar, "R", "server_runtime_auth_ready.R")
  expect_true(
    file.exists(auth_path),
    info = "R/server_runtime_auth_ready.R dosyası eklenmelidir."
  )

  env <- .source_runtime_auth_ready_env()
  for (fn in c(.auth_ready_fns, .context_kept_fns)) {
    expect_true(
      exists(fn, envir = env, mode = "function", inherits = FALSE),
      info = sprintf("Eksik fonksiyon: %s", fn)
    )
  }
})

test_that("runtime manifest context -> auth_ready -> function_slot sırasını korur", {
  expect_source_manifest_order_for_tests(
    c(
      "R/server_runtime_context.R",
      "R/server_runtime_auth_ready.R",
      "R/server_runtime_function_slot.R"
    ),
    label = "Kaynak sırası context -> auth_ready -> function_slot olmalıdır:"
  )
})

test_that("context dosyası auth-ready fonksiyonlarını artık inline tutmaz", {
  ctx_txt <- .read_repo_text_auth_ready_split("R/server_runtime_context.R")
  for (fn in .auth_ready_fns) {
    expect_false(
      grepl(sprintf("%s <- function", fn), ctx_txt, fixed = TRUE),
      info = sprintf("Bu fonksiyon artık server_runtime_auth_ready.R'de olmalıdır: %s", fn)
    )
  }
  # Modül kayıt + context yardımcıları context dosyasında korunmalıdır.
  for (fn in .context_kept_fns) {
    expect_true(
      grepl(sprintf("%s <- function", fn), ctx_txt, fixed = TRUE),
      info = sprintf("Bu fonksiyon context dosyasında kalmalıdır: %s", fn)
    )
  }
})

test_that("auth-ready dosyası wiring fonksiyonlarını tanımlar, modül kaydını yeniden tanımlamaz", {
  auth_txt <- .read_repo_text_auth_ready_split("R/server_runtime_auth_ready.R")
  for (fn in .auth_ready_fns) {
    expect_true(
      grepl(sprintf("%s <- function", fn), auth_txt, fixed = TRUE),
      info = sprintf("Auth-ready dosyası şu fonksiyonu içermelidir: %s", fn)
    )
  }
  # Modül kayıt yardımcıları tek kaynak olarak context dosyasında kalmalıdır.
  for (fn in c("serverRuntimeAttachModule", "serverRuntimeGetModule",
               "serverRuntimeExposeSessionData")) {
    expect_false(
      grepl(sprintf("%s <- function", fn), auth_txt, fixed = TRUE),
      info = sprintf("Bu yardımcı context dosyasında kalmalıdır: %s", fn)
    )
  }
})

test_that("serverRuntimeOnSsoAuthReady yerel modda no-op'tur (callback çağrılmaz)", {
  env <- .source_runtime_auth_ready_env()
  ctx <- .fake_auth_ctx(sso_active = FALSE)
  called <- new.env(); called$hit <- FALSE

  result <- env$serverRuntimeOnSsoAuthReady(
    ctx = ctx,
    callback = function(ctx) called$hit <- TRUE,
    observe_event_fn = function(...) stop("gözlemci kurulmamalı"),
    req_fn = function(...) invisible(NULL)
  )

  expect_false(isTRUE(result))
  expect_false(called$hit)
})

test_that("serverRuntimeOnSsoAuthReady kimlik-hazır SSO oturumunda callback'i HEMEN çalıştırır", {
  env <- .source_runtime_auth_ready_env()
  ctx <- .fake_auth_ctx(sso_active = TRUE, authenticated = TRUE, auth_ready = TRUE)
  called <- new.env(); called$hit <- FALSE

  result <- env$serverRuntimeOnSsoAuthReady(
    ctx = ctx,
    callback = function(ctx) called$hit <- TRUE,
    # Hazırsa gözlemci kurulmamalı; kurulursa testi düşür.
    observe_event_fn = function(...) stop("hazır oturumda gözlemci kurulmamalı"),
    req_fn = function(...) invisible(NULL)
  )

  expect_true(isTRUE(result))
  expect_true(called$hit)
})

test_that("serverRuntimeAttachRefreshableModule modülü kaydeder ve oturum anahtarını yayar", {
  env <- .source_runtime_auth_ready_env()
  ctx <- .fake_auth_ctx(sso_active = FALSE)  # yerel mod: yenileme gözlemcisi kurulmaz
  module_value <- list(refresh = function() invisible(TRUE))

  out <- env$serverRuntimeAttachRefreshableModule(
    ctx = ctx,
    name = "test_module",
    value = module_value,
    required_functions = "refresh",
    refresh_function = "refresh",
    expose_session_key = "test_module_data"
  )

  expect_true(env$is_server_runtime_context(out))
  expect_identical(env$serverRuntimeGetModule(ctx, "test_module"), module_value)
  expect_identical(ctx$session$userData[["test_module_data"]], module_value)
})

test_that("serverRuntimeRefreshModuleOnSsoAuthReady SSO modunda eksik modülü reddeder", {
  env <- .source_runtime_auth_ready_env()
  ctx <- .fake_auth_ctx(sso_active = TRUE, authenticated = FALSE, auth_ready = FALSE)

  expect_error(
    env$serverRuntimeRefreshModuleOnSsoAuthReady(
      ctx = ctx,
      module_name = "olmayan_modul",
      refresh_function = "refresh",
      observe_event_fn = function(...) invisible(NULL),
      req_fn = function(...) invisible(NULL)
    )
  )
})
