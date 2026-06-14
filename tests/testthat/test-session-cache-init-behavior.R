# ==============================================================================
# Dosya Yolu: tests/testthat/test-session-cache-init-behavior.R
# Açıklama: server_session_cache.R içindeki sessionCacheInit davranışını doğrular.
#           Bu fonksiyon oturum bazlı önbellek + MCP kayıt defteri yönetimi için
#           bir fonksiyon listesi döndürür. Döndürülen API test edilir:
#           cache_session_token (boş -> sess_<zaman>, güvensiz karakter sanitize),
#           setup_user_session (kullanıcıya özel dizin + onSessionEnded kaydı),
#           cache_mcp_file_locally (geçici dosyayı önbelleğe kopyalama + güvenli
#           dönüş/NULL), update_mcp_registry_snapshot (snapshot helper'ına devir),
#           get_cache_dir. Tüm yol/MCP bağımlılıkları env'e stub'lanır; gerçek
#           ağ/DB yoktur, yalnızca geçici dosya sistemi. Çevrimdışı, deterministik.
# ==============================================================================

# Türkçe yorum: server_session_cache.R'yi yalıtılmış ortama yükler; serbest yol/MCP
# bağımlılıkları güvenli stub'larla değiştirilir.
.sessionCacheEnv <- function(snapshot_rec = NULL) {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  source(file.path(kok, "R", "server_session_cache.R"), encoding = "UTF-8", local = env)
  env$safe_windows_short_path <- function(path, must_exist = FALSE) path
  env$path_exists_relaxed <- function(path) file.exists(path)
  env$normalize_excel_path <- function(path, must_exist = FALSE) path
  env$session_runtime_store_snapshot_mcp <- function(session, files_snapshot = NULL) {
    if (!is.null(snapshot_rec)) {
      snapshot_rec$called <- TRUE
      snapshot_rec$files <- files_snapshot
    }
    invisible(NULL)
  }
  env
}

# Türkçe yorum: sessionCacheInit için sahte oturum (token + userData + onSessionEnded)
.fakeCacheSession <- function(token = "test-token", ended_rec = NULL) {
  session <- new.env(parent = emptyenv())
  session$token <- token
  session$userData <- new.env(parent = emptyenv())
  session$onSessionEnded <- function(cb) {
    if (!is.null(ended_rec)) { ended_rec$called <- TRUE; ended_rec$cb <- cb }
    invisible(NULL)
  }
  session
}

test_that("sessionCacheInit beklenen API fonksiyonlarını döndürür", {
  env <- .sessionCacheEnv()
  cache <- env$sessionCacheInit(.fakeCacheSession())
  expect_true(is.list(cache))
  beklenen <- c("mcp_saved_path", "cache_root", "cache_session_token",
                "setup_user_session", "cache_mcp_file_locally",
                "update_mcp_registry_snapshot", "get_cache_dir")
  expect_true(all(beklenen %in% names(cache)))
  expect_true(is.function(cache$cache_session_token))
  expect_true(nzchar(cache$cache_root))
})

test_that("cache_session_token boş belirteç için sess_ önekli üretir, güvensiz karakteri sanitize eder", {
  env <- .sessionCacheEnv()
  cache <- env$sessionCacheInit(.fakeCacheSession())
  # Türkçe yorum: boş/NULL -> zaman damgalı sess_ öneki
  expect_true(grepl("^sess_", cache$cache_session_token(NULL)))
  expect_true(grepl("^sess_", cache$cache_session_token("")))
  # Türkçe yorum: güvensiz karakterler _ ile değiştirilir
  expect_identical(cache$cache_session_token("a/b c:d"), "a_b_c_d")
  # Türkçe yorum: güvenli karakterler korunur
  expect_identical(cache$cache_session_token("valid-tok_1"), "valid-tok_1")
})

test_that("setup_user_session kullanıcıya özel dizin oluşturur ve onSessionEnded kaydeder", {
  env <- .sessionCacheEnv()
  ended <- new.env(parent = emptyenv()); ended$called <- FALSE
  cache <- env$sessionCacheInit(.fakeCacheSession(token = "tok1", ended_rec = ended))
  dir <- cache$setup_user_session(7L)
  expect_true(dir.exists(dir))
  expect_true(grepl("user_7", dir, fixed = TRUE))
  # Türkçe yorum: oturum sonu temizliği için onSessionEnded kaydedilmeli
  expect_true(ended$called)
  expect_true(is.function(ended$cb))
  # Türkçe yorum: get_cache_dir kurulan dizini döndürmeli
  expect_identical(cache$get_cache_dir(), dir)
})

test_that("cache_mcp_file_locally geçici dosyayı önbelleğe kopyalar", {
  env <- .sessionCacheEnv()
  cache <- env$sessionCacheInit(.fakeCacheSession())
  cache$setup_user_session(3L)

  src <- tempfile(fileext = ".xlsx")
  writeLines("önbellek test içeriği", src)
  dest <- cache$cache_mcp_file_locally(src)
  expect_false(is.null(dest))
  expect_true(file.exists(dest))
  expect_identical(basename(dest), basename(src))
})

test_that("cache_mcp_file_locally boş/var olmayan kaynak için NULL döner", {
  env <- .sessionCacheEnv()
  cache <- env$sessionCacheInit(.fakeCacheSession())
  cache$setup_user_session(3L)
  expect_null(cache$cache_mcp_file_locally(""))
  expect_null(cache$cache_mcp_file_locally(NULL))
  expect_null(cache$cache_mcp_file_locally(file.path(tempdir(), "olmayan_dosya_xyz.xlsx")))
})

test_that("update_mcp_registry_snapshot snapshot helper'ını dosyalarla çağırır", {
  rec <- new.env(parent = emptyenv()); rec$called <- FALSE
  env <- .sessionCacheEnv(snapshot_rec = rec)
  cache <- env$sessionCacheInit(.fakeCacheSession())
  # Türkçe yorum: init sırasında bir kez (NULL ile) çağrılmış olur; sıfırla
  rec$called <- FALSE; rec$files <- NULL
  cache$update_mcp_registry_snapshot(list(a = 1, b = 2))
  expect_true(rec$called)
  expect_identical(rec$files, list(a = 1, b = 2))
})

test_that("sessionCacheInit başlangıçta MCP snapshot nesnesini bir kez kurar", {
  rec <- new.env(parent = emptyenv()); rec$called <- FALSE
  env <- .sessionCacheEnv(snapshot_rec = rec)
  env$sessionCacheInit(.fakeCacheSession())
  # Türkçe yorum: init, session_runtime_store_snapshot_mcp(session)'ı çağırmalı
  expect_true(rec$called)
})
