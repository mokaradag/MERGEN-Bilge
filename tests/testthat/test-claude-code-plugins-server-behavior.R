# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-plugins-server-behavior.R
# Açıklama: claudeCodePluginsServer çalışma zamanı davranışını shiny::testServer
#           ile doğrular. Sayfa açılınca yerel pluginler (gerçek
#           bilge_yolac_plugins/ dizini) taranır, sayaç rozeti güncellenir ve
#           liste UI'si pluginleri içerir. CLI/ağ GEREKMEZ; tarama yereldir.
# ==============================================================================

suppressMessages(library(shiny))

repo_root_ccp <- resolve_repo_root_for_tests()

.ccp_env <- new.env(parent = globalenv())
.ccp_env$`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
for (.fn in c("log_info", "log_warn", "log_error", "log_debug")) {
  .ccp_env[[.fn]] <- function(...) invisible(NULL)
}
for (.f in c(
  "R/helpers_claude_code_path_policy.R",
  "R/config_claude_code_plugins.R",
  "R/helpers_claude_code_plugins.R",
  "R/module_claude_code_plugins.R"
)) {
  source(file.path(repo_root_ccp, .f), encoding = "UTF-8", local = .ccp_env)
}

# testServer için sarmalayıcı: claudeCodePluginsServer moduleServer değildir,
# (input, output, session, ns, rv) alır; standart imzaya köprüleriz.
.ccp_srv <- function(input, output, session) {
  .ccp_env$claudeCodePluginsServer(
    input, output, session,
    ns = shiny::NS("ccp"),
    rv = shiny::reactiveValues()
  )
}

test_that("claudeCodePluginsServer açılışta yerel pluginleri tarar ve sayaç gönderir", {
  testServer(.ccp_srv, {
    # resolve_app_root() bilge_yolac_plugins/'i bulabilsin diye app kökünü
    # repo köküne sabitle (testServer normalde farklı bir appDir kullanır).
    old_appdir <- shiny::getShinyOption("appDir")
    shiny::shinyOptions(appDir = repo_root_ccp)
    withr::defer(shiny::shinyOptions(appDir = old_appdir))

    captured <- new.env(parent = emptyenv())
    captured$count <- NULL
    captured$n_calls <- 0L
    session$sendCustomMessage <- function(type, message) {
      if (identical(type, "cc-plugins-update-count")) {
        captured$count <- message$count
        captured$n_calls <- captured$n_calls + 1L
      }
      invisible(NULL)
    }

    # Çıktıyı okumak flush'ı tetikler -> otomatik tarama observer'ı çalışır
    ui_html <- paste(as.character(output$local_plugins_ui), collapse = "\n")

    expect_false(is.null(captured$count))
    expect_gt(captured$count, 0L)          # repo'da pluginler var
    expect_true(nzchar(ui_html))
    # Bilinen bir plugin adı listede görünmeli
    expect_true(grepl("code-review", ui_html, fixed = TRUE) ||
                  grepl("office", ui_html, fixed = TRUE))
  })
})

test_that("claudeCodePluginsServer Yenile düğmesi yeniden tarar", {
  testServer(.ccp_srv, {
    # resolve_app_root() bilge_yolac_plugins/'i bulabilsin diye app kökünü
    # repo köküne sabitle (testServer normalde farklı bir appDir kullanır).
    old_appdir <- shiny::getShinyOption("appDir")
    shiny::shinyOptions(appDir = repo_root_ccp)
    withr::defer(shiny::shinyOptions(appDir = old_appdir))

    captured <- new.env(parent = emptyenv())
    captured$n_calls <- 0L
    session$sendCustomMessage <- function(type, message) {
      if (identical(type, "cc-plugins-update-count")) {
        captured$n_calls <- captured$n_calls + 1L
      }
      invisible(NULL)
    }

    # İlk flush (otomatik tarama)
    invisible(paste(as.character(output$local_plugins_ui), collapse = "\n"))
    first_calls <- captured$n_calls
    expect_gt(first_calls, 0L)

    # Yenile düğmesi -> ek bir tarama/sayaç gönderimi
    session$setInputs(refresh_plugins = 1L)
    invisible(paste(as.character(output$local_plugins_ui), collapse = "\n"))
    expect_gt(captured$n_calls, first_calls)
  })
})
