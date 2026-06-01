# ==============================================================================
# Dosya Yolu: tests/testthat/test-mcp-context-behavior.R
# Açıklama: R/helpers_mcp_context.R içindeki MCP bootstrap yardımcılarının
#           DAVRANIŞSAL testleri. Mevcut test-mcp-session-user-id-contract.R ve
#           test-mcp-debug-output-contract.R yalnızca KAYNAK metnini tarar;
#           burada gerçek üretim fonksiyonları çağrılır ve dönen değerler
#           doğrulanır:
#             - helpers_mcp_tools$get_session_user_id (kimlik çözümleme/placeholder)
#             - helpers_mcp_tools$mcp_debug_enabled (opsiyon/ortam kapısı)
#             - helpers_mcp_tools$mcp_debug_log (kapalıyken sessiz, açıkken log yolu)
#           Güvenlik sözleşmesi: placeholder kimlikler (0/unknown/null/na/nan/boş)
#           gerçek kullanıcı kimliği gibi kullanılmamalıdır.
#           Shiny/DB/ağ GEREKMEZ; sentetik liste/environment oturumları kullanılır.
# ==============================================================================

.mcpctx_source_once <- function() {
  g <- if (exists("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)) {
    get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)
  } else {
    NULL
  }

  if (!is.null(g) && is.environment(g) &&
      exists("get_session_user_id", envir = g, inherits = FALSE)) {
    return(invisible(TRUE))
  }

  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_mcp_context.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

# environment tabanlı userData ile sahte oturum (Shiny session$userData benzeri).
.mcpctx_env_session <- function(...) {
  ud <- new.env(parent = emptyenv())
  vals <- list(...)
  for (nm in names(vals)) assign(nm, vals[[nm]], envir = ud)
  list(userData = ud)
}

# list tabanlı userData ile sahte oturum.
.mcpctx_list_session <- function(...) {
  list(userData = list(...))
}

# Bir ifadenin uyarı üretip üretmediğini sürüm-bağımsız ölçer.
.mcpctx_warned <- function(expr) {
  warned <- FALSE
  withCallingHandlers(
    force(expr),
    warning = function(w) {
      warned <<- TRUE
      invokeRestart("muffleWarning")
    }
  )
  warned
}

# ------------------------------------------------------------------------------
# get_session_user_id
# ------------------------------------------------------------------------------
testthat::test_that("get_session_user_id NULL oturum ve userData yokken NULL döner", {
  .mcpctx_source_once()
  testthat::expect_null(helpers_mcp_tools$get_session_user_id(NULL))
  testthat::expect_null(helpers_mcp_tools$get_session_user_id(list()))
  # userData açıkça NULL
  testthat::expect_null(helpers_mcp_tools$get_session_user_id(list(userData = NULL)))
})

testthat::test_that("get_session_user_id environment ve list userData'dan kimliği çözer", {
  .mcpctx_source_once()
  # environment-backed
  s_env <- .mcpctx_env_session(user_id = 42L)
  testthat::expect_identical(helpers_mcp_tools$get_session_user_id(s_env), "42")
  testthat::expect_type(helpers_mcp_tools$get_session_user_id(s_env), "character")

  # list-backed
  s_list <- .mcpctx_list_session(userId = "7")
  testthat::expect_identical(helpers_mcp_tools$get_session_user_id(s_list), "7")
})

testthat::test_that("get_session_user_id alan önceliğini (user_id > userId > id > userID) korur", {
  .mcpctx_source_once()
  # user_id, id'den önce gelir
  testthat::expect_identical(
    helpers_mcp_tools$get_session_user_id(.mcpctx_list_session(id = "ID", user_id = "11")),
    "11"
  )
  # userId, id'den önce gelir
  testthat::expect_identical(
    helpers_mcp_tools$get_session_user_id(.mcpctx_list_session(id = "ID", userId = "UID")),
    "UID"
  )
  # id, userID'den önce gelir
  testthat::expect_identical(
    helpers_mcp_tools$get_session_user_id(.mcpctx_list_session(userID = "UU", id = "II")),
    "II"
  )
  # tek başına userID son fallback olarak çözülür
  testthat::expect_identical(
    helpers_mcp_tools$get_session_user_id(.mcpctx_list_session(userID = "55")),
    "55"
  )
  # environment userData'da da öncelik korunur
  testthat::expect_identical(
    helpers_mcp_tools$get_session_user_id(.mcpctx_env_session(id = "9", user_id = "1")),
    "1"
  )
})

testthat::test_that("get_session_user_id placeholder kimlikleri reddeder", {
  .mcpctx_source_once()
  # Boş, sadece-boşluk ve bilinen placeholder değerleri NULL döndürmeli (büyük/küçük harf duyarsız).
  placeholderlar <- c("", " ", "0", "unknown", "UNKNOWN", "null", "NULL",
                      "na", "NA", "nan", "NaN")
  for (deger in placeholderlar) {
    testthat::expect_null(
      helpers_mcp_tools$get_session_user_id(.mcpctx_list_session(user_id = deger)),
      info = deger
    )
  }
})

testthat::test_that("get_session_user_id sayısalı kırpılmış karaktere çevirir ve vektörde ilk öğeyi alır", {
  .mcpctx_source_once()
  # Sayısal -> karakter
  testthat::expect_identical(
    helpers_mcp_tools$get_session_user_id(.mcpctx_list_session(user_id = 13)),
    "13"
  )
  # Baştaki/sondaki boşluklar kırpılır
  testthat::expect_identical(
    helpers_mcp_tools$get_session_user_id(.mcpctx_env_session(user_id = "  88  ")),
    "88"
  )
  # Vektör verilirse ilk öğe kullanılır
  testthat::expect_identical(
    helpers_mcp_tools$get_session_user_id(.mcpctx_list_session(user_id = c(3, 4))),
    "3"
  )
})

# ------------------------------------------------------------------------------
# mcp_debug_enabled
# ------------------------------------------------------------------------------
testthat::test_that("mcp_debug_enabled varsayılan kapalı, opsiyon ile açılır", {
  .mcpctx_source_once()
  withr::local_options(mergen.mcp.debug = FALSE)
  withr::with_envvar(c(MERGEN_MCP_DEBUG = "false"), {
    testthat::expect_false(helpers_mcp_tools$mcp_debug_enabled())
  })

  # Opsiyon TRUE iken ortam değişkenine bakılmaksızın açık olur.
  withr::local_options(mergen.mcp.debug = TRUE)
  withr::with_envvar(c(MERGEN_MCP_DEBUG = "false"), {
    testthat::expect_true(helpers_mcp_tools$mcp_debug_enabled())
  })
})

testthat::test_that("mcp_debug_enabled ortam değişkeninin truthy/falsy değerlerini ayırt eder", {
  .mcpctx_source_once()
  withr::local_options(mergen.mcp.debug = FALSE)

  truthy <- c("1", "true", "t", "yes", "y", "on", "TRUE", "On", " yes ")
  for (deger in truthy) {
    withr::with_envvar(c(MERGEN_MCP_DEBUG = deger), {
      testthat::expect_true(helpers_mcp_tools$mcp_debug_enabled(), info = deger)
    })
  }

  falsy <- c("0", "false", "no", "off", "", "hayir")
  for (deger in falsy) {
    withr::with_envvar(c(MERGEN_MCP_DEBUG = deger), {
      testthat::expect_false(helpers_mcp_tools$mcp_debug_enabled(), info = deger)
    })
  }
})

# ------------------------------------------------------------------------------
# mcp_debug_log
# ------------------------------------------------------------------------------
testthat::test_that("mcp_debug_log kapalıyken sessizce ve invisible NULL döner", {
  .mcpctx_source_once()
  withr::local_options(mergen.mcp.debug = FALSE)
  withr::with_envvar(c(MERGEN_MCP_DEBUG = "false"), {
    sonuc <- NULL
    testthat::expect_silent(sonuc <- helpers_mcp_tools$mcp_debug_log("herhangi bir mesaj"))
    testthat::expect_null(sonuc)
  })
})

testthat::test_that("mcp_debug_log açıkken log_debug yoluna normalize edilmiş mesajı geçirir", {
  .mcpctx_source_once()
  withr::local_options(mergen.mcp.debug = TRUE)

  # log_debug'u geçici yakalayıcı ile değiştir; sonunda eski hale döndür.
  captured <- new.env(parent = emptyenv())
  captured$msg <- NULL
  had <- exists("log_debug", envir = globalenv(), inherits = FALSE)
  old <- if (had) get("log_debug", envir = globalenv(), inherits = FALSE) else NULL
  assign(
    "log_debug",
    function(...) {
      captured$msg <- paste0(...)
      invisible(NULL)
    },
    envir = globalenv()
  )
  withr::defer({
    if (had) {
      assign("log_debug", old, envir = globalenv())
    } else if (exists("log_debug", envir = globalenv(), inherits = FALSE)) {
      rm("log_debug", envir = globalenv())
    }
  })

  sonuc <- NULL
  uyarildi <- .mcpctx_warned(sonuc <- helpers_mcp_tools$mcp_debug_log("ayikla-1"))
  testthat::expect_false(uyarildi)
  testthat::expect_null(sonuc)
  testthat::expect_identical(captured$msg, "ayikla-1")

  # Türkçe mesaj UTF-8 olarak korunur.
  helpers_mcp_tools$mcp_debug_log("Çağrı-Ömer-İş")
  testthat::expect_identical(enc2utf8(captured$msg), enc2utf8("Çağrı-Ömer-İş"))
})
