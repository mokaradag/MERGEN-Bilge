# ==============================================================================
# Dosya Yolu: tests/testthat/test-mcp-file-resolver-behavior.R
# Açıklama: R/helpers_mcp_file_resolver.R oturum dosya kayıt defteri ve dosya
#           adı/yol çözümleme yardımcılarının DAVRANIŞSAL testleri. Mevcut MCP
#           testleri çoğunlukla kaynak-düzeni sözleşmesini ve excel resolve'u
#           kapsar; burada gerçek üretim fonksiyonları sentetik oturum + geçici
#           dosyalarla çağrılır:
#             ensure/reset/update_session_file_registry, register_uploaded_file,
#             get_default_file_name, auto_file_name, resolve_file_argument.
#           Güvenlik sözleşmesi: mutlak yol reddi, varsayılan kapalı cross-bucket
#           arama, yalnızca aynı kullanıcı klasöründe rehydrate.
#           Shiny/DB/ağ GEREKMEZ. Bağımlı helper'lar (path_exists_relaxed,
#           resolve_readable_path, normalize_excel_path, mcp_debug_log,
#           get_session_user_id) deterministik stub'larla sağlanır ve global
#           helpers_mcp_tools bağı test sırasında izole edilip sonunda geri
#           yüklenir.
# ==============================================================================

# Temiz bir helpers_mcp_tools stub ortamı kurar, resolver'ı kaynaktan yükler ve
# test bittiğinde önceki global bağı geri yükler. Dönen değer stub ortamıdır.
.mcpresolver_install <- function() {
  root <- resolve_repo_root_for_tests()

  had <- exists("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)
  old <- if (had) get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE) else NULL

  env <- new.env(parent = globalenv())

  # Deterministik bağımlılık stub'ları (gerçek dosya sistemi üzerinden çalışır).
  env$path_exists_relaxed <- function(p) {
    is.character(p) && length(p) == 1L && nzchar(p) && file.exists(p)
  }
  env$resolve_readable_path <- function(p) p
  env$normalize_excel_path <- function(p) p
  env$mcp_debug_log <- function(...) invisible(NULL)
  env$get_session_user_id <- function(session = NULL) {
    if (is.null(session) || is.null(session$userData)) return(NULL)
    ud <- session$userData
    value <- if (is.environment(ud)) {
      if (exists("user_id", envir = ud, inherits = FALSE)) {
        get("user_id", envir = ud, inherits = FALSE)
      } else {
        NULL
      }
    } else {
      ud[["user_id"]]
    }
    if (is.null(value) || length(value) == 0L) return(NULL)
    as.character(value[1])
  }
  # resolve_uploaded_file stub'u "" döndürerek rehydrate'ı deterministik biçimde
  # aynı-kullanıcı klasörü (mcp_base_dir/user_<id>) dalına yönlendirir.
  env$resolve_uploaded_file <- function(arg, user_id = NULL) ""

  assign("helpers_mcp_tools", env, envir = globalenv())

  source(
    file.path(root, "R", "helpers_mcp_file_resolver.R"),
    encoding = "UTF-8", local = globalenv()
  )

  withr::defer(
    {
      if (had) {
        assign("helpers_mcp_tools", old, envir = globalenv())
      } else if (exists("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)) {
        rm("helpers_mcp_tools", envir = globalenv())
      }
    },
    envir = parent.frame()
  )

  get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)
}

# environment tabanlı userData ile sahte oturum.
.mcpresolver_session <- function(uid = NULL) {
  ud <- new.env(parent = emptyenv())
  if (!is.null(uid)) ud$user_id <- uid
  list(userData = ud)
}

# Geçici, gerçek bir dosya oluşturup yolunu döndürür.
.mcpresolver_tempfile <- function(ext = ".xlsx", content = "veri") {
  f <- tempfile(fileext = ext)
  writeLines(content, f)
  f
}

# ------------------------------------------------------------------------------
# ensure / reset session file registry
# ------------------------------------------------------------------------------
testthat::test_that("ensure_session_file_registry NULL oturumda zararsızdır ve yeni oturumda boş liste kurar", {
  h <- .mcpresolver_install()
  testthat::expect_null(h$ensure_session_file_registry(NULL))

  s <- .mcpresolver_session()
  h$ensure_session_file_registry(s)
  testthat::expect_true(is.list(s$userData$current_session_files))
  testthat::expect_length(s$userData$current_session_files, 0L)
})

testthat::test_that("reset_session_file_registry mevcut kaydı temizler", {
  h <- .mcpresolver_install()
  s <- .mcpresolver_session()
  s$userData$current_session_files <- list(x = list(path = "/p", name = "x"))
  testthat::expect_true(h$reset_session_file_registry(s))
  testthat::expect_length(s$userData$current_session_files, 0L)
})

# ------------------------------------------------------------------------------
# update_session_file_path
# ------------------------------------------------------------------------------
testthat::test_that("update_session_file_path token/ad eşleşmesinde path ve datapath'i günceller", {
  h <- .mcpresolver_install()
  s <- .mcpresolver_session()
  tf <- .mcpresolver_tempfile()
  h$register_uploaded_file(s, "tokA", tf, display_name = "adA.xlsx")

  # Token ile güncelleme
  upd <- h$update_session_file_path(s, "tokA", "/yeni/yol.xlsx")
  obj <- s$userData$current_session_files[["tokA"]]
  testthat::expect_true(upd)
  testthat::expect_identical(obj$path, "/yeni/yol.xlsx")
  testthat::expect_identical(obj$datapath, "/yeni/yol.xlsx")

  # Görünen ad ile güncelleme
  upd2 <- h$update_session_file_path(s, "adA.xlsx", "/by/name.xlsx")
  testthat::expect_true(upd2)
  testthat::expect_identical(
    s$userData$current_session_files[["tokA"]]$path,
    "/by/name.xlsx"
  )
})

testthat::test_that("update_session_file_path eksik oturum/yeni yol veya eşleşme yokken invisible FALSE döner", {
  h <- .mcpresolver_install()
  testthat::expect_false(h$update_session_file_path(NULL, "t", "/new"))

  s <- .mcpresolver_session()
  tf <- .mcpresolver_tempfile()
  h$register_uploaded_file(s, "tokA", tf, display_name = "adA.xlsx")

  testthat::expect_false(h$update_session_file_path(s, "tokA", ""))
  testthat::expect_false(h$update_session_file_path(s, "ghost", "/z"))
})

# ------------------------------------------------------------------------------
# register_uploaded_file
# ------------------------------------------------------------------------------
testthat::test_that("register_uploaded_file boş token ve var olmayan yolu reddeder", {
  h <- .mcpresolver_install()
  s <- .mcpresolver_session()
  tf <- .mcpresolver_tempfile()

  testthat::expect_false(h$register_uploaded_file(s, "", tf))
  testthat::expect_false(h$register_uploaded_file(s, "tok", "/no/such/file.xlsx"))
  testthat::expect_length(s$userData$current_session_files, 0L)
})

testthat::test_that("register_uploaded_file normalize edilmiş yolu ve görünen adı saklar", {
  h <- .mcpresolver_install()
  s <- .mcpresolver_session()
  tf <- .mcpresolver_tempfile()

  ok <- h$register_uploaded_file(s, "tok1", tf, display_name = "Görsel.xlsx")
  testthat::expect_true(ok)
  obj <- s$userData$current_session_files[["tok1"]]
  testthat::expect_identical(obj$path, tf)
  testthat::expect_identical(enc2utf8(obj$name), enc2utf8("Görsel.xlsx"))

  # display_name verilmezse basename kullanılır
  tf2 <- .mcpresolver_tempfile(ext = ".csv")
  h$register_uploaded_file(s, "tok2", tf2)
  testthat::expect_identical(
    s$userData$current_session_files[["tok2"]]$name,
    basename(tf2)
  )
})

# ------------------------------------------------------------------------------
# get_default_file_name / auto_file_name
# ------------------------------------------------------------------------------
testthat::test_that("get_default_file_name tek dosyada adı, birden çok farklı adda NULL döner", {
  h <- .mcpresolver_install()
  s <- .mcpresolver_session()
  tf <- .mcpresolver_tempfile()
  h$register_uploaded_file(s, "only", tf, display_name = "rapor.csv")
  testthat::expect_identical(h$get_default_file_name(s), "rapor.csv")

  tf2 <- .mcpresolver_tempfile()
  h$register_uploaded_file(s, "two", tf2, display_name = "baska.xlsx")
  testthat::expect_null(h$get_default_file_name(s))
})

testthat::test_that("auto_file_name açık adı korur, yoksa oturum varsayılanına düşer", {
  h <- .mcpresolver_install()
  s <- .mcpresolver_session()
  tf <- .mcpresolver_tempfile()
  h$register_uploaded_file(s, "u", tf, display_name = "tek.csv")

  testthat::expect_identical(h$auto_file_name("explicit.txt", s), "explicit.txt")
  testthat::expect_identical(h$auto_file_name(NULL, s), "tek.csv")
  testthat::expect_identical(h$auto_file_name("", s), "tek.csv")
})

# ------------------------------------------------------------------------------
# resolve_file_argument: girdi/güvenlik kenarları
# ------------------------------------------------------------------------------
testthat::test_that("resolve_file_argument NULL/boş argümanda ok=FALSE döner", {
  h <- .mcpresolver_install()
  s <- .mcpresolver_session()
  testthat::expect_false(h$resolve_file_argument(NULL, s)$ok)
  testthat::expect_false(h$resolve_file_argument("", s)$ok)
})

testthat::test_that("resolve_file_argument var olsa bile mutlak yolu reddeder", {
  h <- .mcpresolver_install()
  s <- .mcpresolver_session()
  tf <- .mcpresolver_tempfile()  # tempfile() mutlak yoldur (Linux'ta /tmp/...)

  sonuc <- h$resolve_file_argument(tf, s)
  testthat::expect_false(sonuc$ok)
  testthat::expect_match(sonuc$error, "Mutlak", fixed = TRUE)
})

# ------------------------------------------------------------------------------
# resolve_file_argument: kayıt defteri eşleşmeleri
# ------------------------------------------------------------------------------
testthat::test_that("resolve_file_argument token/görünen ad/basename ile var olan yola çözer", {
  h <- .mcpresolver_install()
  s <- .mcpresolver_session()
  tf <- .mcpresolver_tempfile()
  h$register_uploaded_file(s, "token123", tf, display_name = "Çalışma.xlsx")

  r_token <- h$resolve_file_argument("token123", s)
  testthat::expect_true(r_token$ok)
  testthat::expect_identical(r_token$path, tf)
  testthat::expect_identical(enc2utf8(r_token$display), enc2utf8("Çalışma.xlsx"))

  r_disp <- h$resolve_file_argument("Çalışma.xlsx", s)
  testthat::expect_true(r_disp$ok)
  testthat::expect_identical(r_disp$path, tf)

  r_base <- h$resolve_file_argument(basename(tf), s)
  testthat::expect_true(r_base$ok)
  testthat::expect_identical(r_base$path, tf)
})

# ------------------------------------------------------------------------------
# resolve_file_argument: aynı-kullanıcı rehydrate
# ------------------------------------------------------------------------------
testthat::test_that("resolve_file_argument eksik depolanan yolu mcp_base_dir/user_<id> içinden rehydrate eder", {
  h <- .mcpresolver_install()
  base <- file.path(tempfile("mcpbase-"))
  uid <- "77"
  user_dir <- file.path(base, paste0("user_", uid))
  dir.create(user_dir, recursive = TRUE, showWarnings = FALSE)
  real <- file.path(user_dir, "veri.xlsx")
  writeLines("x", real)
  withr::defer(unlink(base, recursive = TRUE))

  withr::local_options(mergen.mcp_base_dir = base, mergen.index_path = "")

  s <- .mcpresolver_session(uid = uid)
  # Depolanan yol diskte yok; sadece user_dir'deki gerçek dosya var.
  s$userData$current_session_files[["veri.xlsx"]] <- list(
    path = "/gone/veri.xlsx", name = "veri.xlsx"
  )

  sonuc <- h$resolve_file_argument("veri.xlsx", s)
  testthat::expect_true(sonuc$ok)
  testthat::expect_identical(sonuc$path, real)
  # Kayıt defteri güncellenmiş olmalı.
  testthat::expect_identical(
    s$userData$current_session_files[["veri.xlsx"]]$path,
    real
  )
})

# ------------------------------------------------------------------------------
# resolve_file_argument: cross-bucket varsayılan kapalı
# ------------------------------------------------------------------------------
testthat::test_that("resolve_file_argument cross-bucket aramayı yalnızca açık opt-in ile yapar", {
  h <- .mcpresolver_install()
  base <- file.path(tempfile("mcpbase2-"))
  dir.create(base, recursive = TRUE, showWarnings = FALSE)
  shared <- file.path(base, "shared.xlsx")
  writeLines("s", shared)
  withr::defer(unlink(base, recursive = TRUE))

  # uid yok -> aynı-kullanıcı klasörü taranmaz; dosya yalnızca base kökünde.
  s <- .mcpresolver_session()

  # index yolu yok -> jsonlite gerekmez.
  withr::local_options(
    mergen.mcp_base_dir = base,
    mergen.index_path = "",
    mergen.files_root = "",
    mergen.mcp.allow_cross_bucket_lookup = FALSE
  )

  withr::with_envvar(c(MERGEN_MCP_ALLOW_CROSS_BUCKET_LOOKUP = "false"), {
    r_disabled <- h$resolve_file_argument("shared.xlsx", s)
    testthat::expect_false(r_disabled$ok)
  })

  withr::local_options(mergen.mcp.allow_cross_bucket_lookup = TRUE)
  withr::with_envvar(c(MERGEN_MCP_ALLOW_CROSS_BUCKET_LOOKUP = "false"), {
    r_enabled <- h$resolve_file_argument("shared.xlsx", s)
    testthat::expect_true(r_enabled$ok)
    testthat::expect_identical(r_enabled$path, shared)
  })
})

# ------------------------------------------------------------------------------
# resolve_file_argument: bulunamayan dosya mesajı
# ------------------------------------------------------------------------------
testthat::test_that("resolve_file_argument bulunamadığında bilinen dosyaları/boş listeyi raporlar", {
  h <- .mcpresolver_install()
  withr::local_options(mergen.index_path = "")

  # Kayıt defterinde dosya var ama eşleşme yok -> bilinen ad listelenir.
  s <- .mcpresolver_session()
  tf <- .mcpresolver_tempfile()
  h$register_uploaded_file(s, "knownTok", tf, display_name = "bilinen.xlsx")
  r_err <- h$resolve_file_argument("ghost.xlsx", s)
  testthat::expect_false(r_err$ok)
  testthat::expect_match(r_err$error, "bilinen.xlsx", fixed = TRUE)

  # Boş kayıt defteri -> "(hiç dosya yok)" mesajı.
  s_empty <- .mcpresolver_session()
  r_empty <- h$resolve_file_argument("ghost.xlsx", s_empty)
  testthat::expect_false(r_empty$ok)
  testthat::expect_match(r_empty$error, "hiç dosya yok", fixed = TRUE)
})
