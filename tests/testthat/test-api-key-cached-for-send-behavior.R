# ==============================================================================
# Dosya Yolu: tests/testthat/test-api-key-cached-for-send-behavior.R
# Açıklama: mb_api_key_get_cached_for_send() oturum-belleği önbelleği davranışı.
#           Önbellek isabeti tam çözümlemeyi atlar; sahip değişimi/kaydetme/temizleme
#           önbelleği geçersiz kılar. Gerçek üretim fonksiyonları çağrılır;
#           Shiny/DB/ağ GEREKMEZ. Sahte oturum (environment userData) kullanılır.
# ==============================================================================

.apikeycache_source_once <- function() {
  if (exists("mb_api_key_get_cached_for_send", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_api_key_identity.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

# Kimliği doğrulanmış sahte oturum: userData environment olmalı.
.apikeycache_fake_session <- function(username = "ownerA", key = "key-fake-1") {
  ud <- new.env(parent = emptyenv())
  ud$auth_initialized <- TRUE
  ud$system_username <- username
  if (!is.null(key)) {
    ud$ai_api_key <- key
    ud$ai_api_key_owner <- username
  }
  list(userData = ud)
}

testthat::test_that("ilk çağrı (önbellek yok) tam çözümlemeye düşer ve önbelleği doldurur", {
  .apikeycache_source_once()
  sess <- .apikeycache_fake_session(username = "ownerA", key = "key-fake-1")

  res <- mb_api_key_get_cached_for_send(sess, require_auth = TRUE)

  testthat::expect_identical(res$key, "key-fake-1")
  testthat::expect_identical(res$source, "personal")
  testthat::expect_false(isTRUE(res$cached))

  # Önbellek oturuma yazıldı.
  cache <- get("ai_api_key_send_cache", envir = sess$userData, inherits = FALSE)
  testthat::expect_identical(cache$owner, "ownerA")
  testthat::expect_identical(cache$key, "key-fake-1")
})

testthat::test_that("önbellek isabeti tam çözümlemeyi (mb_api_key_get_effective_key) ÇAĞIRMAZ", {
  .apikeycache_source_once()
  sess <- .apikeycache_fake_session(username = "ownerA", key = "key-fake-1")

  # Önbelleği doldur.
  first <- mb_api_key_get_cached_for_send(sess, require_auth = TRUE)
  testthat::expect_false(isTRUE(first$cached))

  # Tam çözümlemeyi say; isabet halinde çağrılmamalı.
  call_count <- 0L
  old_fn <- get("mb_api_key_get_effective_key", envir = .GlobalEnv)
  assign("mb_api_key_get_effective_key", function(...) {
    call_count <<- call_count + 1L
    list(key = "SHOULD_NOT_BE_USED", source = "personal", owner = list(username = "ownerA"))
  }, envir = .GlobalEnv)
  on.exit(assign("mb_api_key_get_effective_key", old_fn, envir = .GlobalEnv), add = TRUE)

  hit <- mb_api_key_get_cached_for_send(sess, require_auth = TRUE)

  testthat::expect_true(isTRUE(hit$cached))
  testthat::expect_identical(hit$key, "key-fake-1")
  testthat::expect_identical(call_count, 0L)
})

testthat::test_that("sahip değişimi önbelleği geçersiz kılar (tam çözümleme tekrar çağrılır)", {
  .apikeycache_source_once()
  sess <- .apikeycache_fake_session(username = "ownerA", key = "key-fake-1")

  mb_api_key_get_cached_for_send(sess, require_auth = TRUE)  # ownerA önbelleği

  # Kimliği doğrulanmış kullanıcı değişti (ownerB) ve onun anahtarı var.
  sess$userData$system_username <- "ownerB"
  sess$userData$ai_api_key <- "key-fake-2"
  sess$userData$ai_api_key_owner <- "ownerB"

  call_count <- 0L
  old_fn <- get("mb_api_key_get_effective_key", envir = .GlobalEnv)
  assign("mb_api_key_get_effective_key", function(...) {
    call_count <<- call_count + 1L
    list(key = "key-fake-2", source = "personal", owner = list(username = "ownerB"))
  }, envir = .GlobalEnv)
  on.exit(assign("mb_api_key_get_effective_key", old_fn, envir = .GlobalEnv), add = TRUE)

  res <- mb_api_key_get_cached_for_send(sess, require_auth = TRUE)

  testthat::expect_false(isTRUE(res$cached))
  testthat::expect_identical(call_count, 1L)
  testthat::expect_identical(res$key, "key-fake-2")
})

testthat::test_that("anahtar kaydetme (set_session_key) gönderim önbelleğini temizler", {
  .apikeycache_source_once()
  sess <- .apikeycache_fake_session(username = "ownerA", key = "key-fake-1")

  mb_api_key_get_cached_for_send(sess, require_auth = TRUE)
  testthat::expect_true(exists("ai_api_key_send_cache", envir = sess$userData, inherits = FALSE))

  mb_api_key_set_session_key(sess, "key-fake-new", owner = list(username = "ownerA"))

  testthat::expect_false(exists("ai_api_key_send_cache", envir = sess$userData, inherits = FALSE))
  testthat::expect_identical(get("ai_api_key", envir = sess$userData, inherits = FALSE), "key-fake-new")
})

testthat::test_that("anahtar temizleme (clear_session_key) gönderim önbelleğini de temizler", {
  .apikeycache_source_once()
  sess <- .apikeycache_fake_session(username = "ownerA", key = "key-fake-1")

  mb_api_key_get_cached_for_send(sess, require_auth = TRUE)
  testthat::expect_true(exists("ai_api_key_send_cache", envir = sess$userData, inherits = FALSE))

  mb_api_key_clear_session_key(sess)

  testthat::expect_false(exists("ai_api_key_send_cache", envir = sess$userData, inherits = FALSE))
  testthat::expect_false(exists("ai_api_key", envir = sess$userData, inherits = FALSE))
})

# ------------------------------------------------------------------------------
# 401/403/AUTH hata yolunda gönderim önbelleği geçersiz kılma
# ------------------------------------------------------------------------------
testthat::test_that("mb_api_key_error_is_auth yetkilendirme hatalarını tanır, diğerlerini değil", {
  .apikeycache_source_once()

  testthat::expect_true(mb_api_key_error_is_auth("API_HTTP_ERROR_401"))
  testthat::expect_true(mb_api_key_error_is_auth("API_HTTP_ERROR_403"))
  testthat::expect_true(mb_api_key_error_is_auth("AUTH_MISSING_KEY: anahtar yok"))
  testthat::expect_true(mb_api_key_error_is_auth("HTTP 401 Unauthorized"))
  testthat::expect_true(mb_api_key_error_is_auth("403 Forbidden"))

  # Yetkilendirme dışı hatalar.
  testthat::expect_false(mb_api_key_error_is_auth("STREAM_ABORTED_BY_USER"))
  testthat::expect_false(mb_api_key_error_is_auth("Zaman aşımı / timeout"))
  testthat::expect_false(mb_api_key_error_is_auth("API_HTTP_ERROR_500"))
  testthat::expect_false(mb_api_key_error_is_auth(""))
  testthat::expect_false(mb_api_key_error_is_auth(NULL))
})

testthat::test_that("mb_api_key_invalidate_send_cache yalnızca gönderim önbelleğini siler, oturum anahtarını korur", {
  .apikeycache_source_once()
  sess <- .apikeycache_fake_session(username = "ownerA", key = "key-fake-1")

  mb_api_key_get_cached_for_send(sess, require_auth = TRUE)
  testthat::expect_true(exists("ai_api_key_send_cache", envir = sess$userData, inherits = FALSE))

  invalidated <- mb_api_key_invalidate_send_cache(sess)

  testthat::expect_true(isTRUE(invalidated))
  testthat::expect_false(exists("ai_api_key_send_cache", envir = sess$userData, inherits = FALSE))
  # Oturum anahtarı KORUNUR.
  testthat::expect_identical(get("ai_api_key", envir = sess$userData, inherits = FALSE), "key-fake-1")
})

testthat::test_that("auth hatasında önbellek geçersiz kılınır; sonraki çağrı tekrar ıska olur", {
  .apikeycache_source_once()
  sess <- .apikeycache_fake_session(username = "ownerA", key = "key-fake-1")

  mb_api_key_get_cached_for_send(sess, require_auth = TRUE)  # önbellek dolu

  # Auth hatası -> önbellek geçersiz.
  res_auth <- mb_api_key_invalidate_send_cache_on_auth_error(sess, "API_HTTP_ERROR_401")
  testthat::expect_true(isTRUE(res_auth))
  testthat::expect_false(exists("ai_api_key_send_cache", envir = sess$userData, inherits = FALSE))

  # Sonraki çağrı tekrar tam çözümlemeye düşer (ıska).
  next_call <- mb_api_key_get_cached_for_send(sess, require_auth = TRUE)
  testthat::expect_false(isTRUE(next_call$cached))
})

testthat::test_that("yetkilendirme dışı hatada önbellek korunur (no-op)", {
  .apikeycache_source_once()
  sess <- .apikeycache_fake_session(username = "ownerA", key = "key-fake-1")

  mb_api_key_get_cached_for_send(sess, require_auth = TRUE)

  res_nonauth <- mb_api_key_invalidate_send_cache_on_auth_error(sess, "STREAM_ABORTED_BY_USER")
  testthat::expect_false(isTRUE(res_nonauth))
  # Önbellek hâlâ duruyor -> sonraki çağrı isabet.
  testthat::expect_true(exists("ai_api_key_send_cache", envir = sess$userData, inherits = FALSE))
  hit <- mb_api_key_get_cached_for_send(sess, require_auth = TRUE)
  testthat::expect_true(isTRUE(hit$cached))
})

# Statik sözleşme: ana yanıt yolları auth hatasında gönderim önbelleğini
# geçersiz kılan yardımcıyı çağırmalı.
testthat::test_that("LLM hata yolları auth-cache geçersiz kılma yardımcısını çağırır", {
  for (rel in c(
    "R/server_handler_true_streaming.R",
    "R/server_handler_streaming_tts.R",
    "R/server_llm_response_handlers.R"
  )) {
    lines <- readLines(
      file.path(resolve_repo_root_for_tests(), rel),
      warn = FALSE, encoding = "UTF-8"
    )
    testthat::expect_true(
      any(grepl("mb_api_key_invalidate_send_cache_on_auth_error\\(", lines)),
      info = sprintf("%s auth hatasında gönderim önbelleğini geçersiz kılmalı", rel)
    )
  }
})

testthat::test_that("anahtar değeri loglanmaz (yardımcı sessizdir)", {
  .apikeycache_source_once()
  sess <- .apikeycache_fake_session(username = "ownerA", key = "key-fake-secret-123")

  captured <- character()
  old_log <- if (exists("log_info", envir = .GlobalEnv, inherits = FALSE)) get("log_info", envir = .GlobalEnv) else NULL
  assign("log_info", function(msg, ...) captured <<- c(captured, as.character(msg)), envir = .GlobalEnv)
  on.exit({
    if (is.null(old_log)) {
      if (exists("log_info", envir = .GlobalEnv, inherits = FALSE)) rm("log_info", envir = .GlobalEnv)
    } else {
      assign("log_info", old_log, envir = .GlobalEnv)
    }
  }, add = TRUE)

  mb_api_key_get_cached_for_send(sess, require_auth = TRUE)
  mb_api_key_get_cached_for_send(sess, require_auth = TRUE)

  testthat::expect_false(any(grepl("key-fake-secret-123", captured, fixed = TRUE)))
})
