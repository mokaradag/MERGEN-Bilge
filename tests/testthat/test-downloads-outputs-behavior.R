# ==============================================================================
# Dosya Yolu: tests/testthat/test-downloads-outputs-behavior.R
# Açıklama: R/server_outputs_downloads.R çıktı başlatıcılarının DAVRANIŞSAL
#           testleri. Bu dosya daha önce hiçbir test tarafından çağrılmıyordu.
#
#           Kapsananlar (shiny::testServer ile):
#           - downloadOutputsInit -> file_prompt_indicator_ui: ekli dosya
#             göstergesi (dosya yoksa boş, varsa sayı + adlar).
#           - widgetDependencyOutputsInit: highcharter/plotly yoksa bile hata
#             vermeden çıktı tanımlama (zarif düşüş).
#
#           Gerçek DB/LLM/indirme GEREKMEZ; fetch_user_activity_logs stub'lanır.
# ==============================================================================

.source_downloads_for_test <- function() {
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  env$fetch_user_activity_logs <- function(uid) {
    data.frame(user_id = uid, event = "test", stringsAsFactors = FALSE)
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "server_outputs_downloads.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

# ------------------------------------------------------------------------------
# file_prompt_indicator_ui
# ------------------------------------------------------------------------------
testthat::test_that("file_prompt_indicator_ui ekli dosya yokken boş kalır", {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  env <- .source_downloads_for_test()

  shiny::testServer(function(input, output, session) {
    session_files <- shiny::reactiveVal(list())
    env$downloadOutputsInit(output, session, session_files, current_user_id = 1L)
  }, {
    # req(length>0) başarısız olunca renderUI sessiz hata verir; testServer'da
    # çıktıyı okumak bu sessiz hatayı yeniden yükseltir. Bu, guard'ın etkin
    # olduğunun (içerik üretilmediğinin) gözlemlenebilir imzasıdır.
    testthat::expect_error(force(output$file_prompt_indicator_ui))
  })
})

testthat::test_that("file_prompt_indicator_ui ekli dosyaları sayı ve adlarıyla listeler", {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  env <- .source_downloads_for_test()

  res <- NULL
  shiny::testServer(function(input, output, session) {
    session_files <- shiny::reactiveVal(list(
      "Türkçe_özet.pdf" = list(path = "/x"),
      "rapor.txt" = list(path = "/y")
    ))
    env$downloadOutputsInit(output, session, session_files, current_user_id = 1L)
  }, {
    res <<- paste(as.character(output$file_prompt_indicator_ui), collapse = "")
  })
  testthat::expect_true(grepl("Ekli Dosyalar (2):", res, fixed = TRUE))
  testthat::expect_true(grepl("Türkçe_özet.pdf", res, fixed = TRUE))
  testthat::expect_true(grepl("rapor.txt", res, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# widgetDependencyOutputsInit (zarif düşüş)
# ------------------------------------------------------------------------------
testthat::test_that("widgetDependencyOutputsInit eksik widget paketlerinde hatasız çalışır", {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  env <- .source_downloads_for_test()

  # App VM'de plotly kurulu olsa bile bu test fallback dalını hedefler.
  # widgetDependencyOutputsInit() fonksiyonu env içinde source edildiği için,
  # requireNamespace burada lexical lookup ile env$requireNamespace üzerinden çözülür.
  env$requireNamespace <- function(package, quietly = FALSE, ...) {
    if (identical(package, "plotly")) {
      return(FALSE)
    }

    base::requireNamespace(package, quietly = quietly, ...)
  }

  testthat::expect_no_error(
    shiny::testServer(function(input, output, session) {
      env$widgetDependencyOutputsInit(output)
    }, {
      # plotly yokmuş gibi davranıldığında deps_pl/plotly_html renderUI(NULL)
      # olarak tanımlanır; okuma hata fırlatmamalı.
      testthat::expect_no_error(force(output$deps_pl))
      testthat::expect_no_error(force(output$plotly_html))
    })
  )
})