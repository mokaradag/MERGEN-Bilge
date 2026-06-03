# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-click-observers-behavior.R
# Açıklama: R/server_observers_file_clicks.R fileClickObserversInit()
#           gözlemcilerinin DAVRANIŞSAL testleri. Bu dosya daha önce hiçbir test
#           tarafından çağrılmıyordu.
#
#           Kapsananlar (shiny::testServer + prime-then-set ile tek gözlemci
#           atışı):
#           - source_file_clicked: boş dosya adı guard'ı (showToast, tıklama
#             işleyici çağrılmaz) ve geçerli adda işleyici çağrısı.
#           - analysis_file_clicked: yol çözümleme kararı (www/ öneki, mutlak
#             yol, göreli yol) ve dosya-bulunamadı guard'ı.
#
#           handle_source_file_click / normalize_mcp_path / path_exists_relaxed /
#           openAnyPreview / showToast stub'lanır. Gerçek DB/dosya GEREKMEZ.
# ==============================================================================

.source_file_clicks_for_test <- function() {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  rec <- new.env()
  rec$toasts <- list()
  rec$source_clicks <- 0L
  rec$previews <- 0L
  rec$exists_paths <- character(0)

  env$showToast <- function(session, message, type = "info") {
    rec$toasts[[length(rec$toasts) + 1L]] <- list(message = message, type = type)
    invisible(NULL)
  }
  env$handle_source_file_click <- function(ev, settings_data, api_config, session, filePreview) {
    rec$source_clicks <- rec$source_clicks + 1L
    invisible(NULL)
  }
  # Kimlik (identity) stub: çözülen tam yolu olduğu gibi geri verir.
  env$normalize_mcp_path <- function(path, must_exist = FALSE) path
  # path_exists_relaxed: çözülen yolu kaydeder ve FALSE döner (bulunamadı dalı).
  env$path_exists_relaxed <- function(path) {
    rec$exists_paths <- c(rec$exists_paths, path)
    FALSE
  }
  env$openAnyPreview <- function(...) { rec$previews <- rec$previews + 1L; invisible(NULL) }

  source(
    file.path(resolve_repo_root_for_tests(), "R", "server_observers_file_clicks.R"),
    encoding = "UTF-8",
    local = env
  )
  list(env = env, rec = rec)
}

# Gözlemcileri kurar ve belirtilen input'u prime-then-set ile tetikler.
# Not: MockShinySession observeEvent zamanlaması bazen prime olayını da
# işleyebildiğinden, prime değeri gerçek değerle AYNI guard-türünde seçilir ve
# testler üyelik (%in%) / eşik (>=1, ==0) ile doğrulanır; bu sayede coalescing
# davranışından bağımsız sağlam kalır.
.drive_file_click <- function(fix, input_id, prime_value, real_value) {
  env <- fix$env
  shiny::testServer(function(input, output, session) {
    env$fileClickObserversInit(
      input = input,
      session = session,
      settings_data = list(),
      api_config = list(),
      filePreview = list(open = function(...) invisible(NULL)),
      file_manager_data = list(
        file_removed = shiny::reactiveVal(NULL),
        all_files_cleared = shiny::reactiveVal(FALSE)
      ),
      session_files = shiny::reactiveVal(list())
    )
  }, {
    do.call(session$setInputs, stats::setNames(list(prime_value), input_id))
    do.call(session$setInputs, stats::setNames(list(real_value), input_id))
  })
}

# ------------------------------------------------------------------------------
# source_file_clicked
# ------------------------------------------------------------------------------
testthat::test_that("source_file_clicked geçerli adda kaynak tıklama işleyicisini çağırır", {
  fix <- .source_file_clicks_for_test()
  .drive_file_click(fix, "source_file_clicked", "onceki.pdf", "rapor.pdf")
  testthat::expect_true(fix$rec$source_clicks >= 1L)
})

testthat::test_that("source_file_clicked yalnızca numara içeren ad temizlenince boş guard'a düşer", {
  fix <- .source_file_clicks_for_test()
  # Hem prime hem gerçek değer yalnızca numara: "N) " -> temizlenince "" kalır ->
  # geçersiz kaynak guard'ı; işleyici hiç çağrılmamalı.
  .drive_file_click(fix, "source_file_clicked", "3) ", "7) ")
  testthat::expect_identical(fix$rec$source_clicks, 0L)
  mesajlar <- vapply(fix$rec$toasts, function(t) t$message, character(1))
  testthat::expect_true(any(grepl("Geçersiz kaynak bağlantısı", mesajlar, fixed = TRUE)))
})

# ------------------------------------------------------------------------------
# analysis_file_clicked: yol çözümleme
# ------------------------------------------------------------------------------
testthat::test_that("analysis_file_clicked boş yol için 'Geçersiz dosya yolu' uyarısı verir", {
  fix <- .source_file_clicks_for_test()
  # Hem prime hem gerçek değer boş filepath -> yol çözümlemeye hiç gidilmez.
  .drive_file_click(fix, "analysis_file_clicked", list(filepath = ""), list(filepath = ""))
  mesajlar <- vapply(fix$rec$toasts, function(t) t$message, character(1))
  testthat::expect_true(any(grepl("Geçersiz dosya yolu", mesajlar, fixed = TRUE)))
  # Yol çözümlemeye gidilmemeli (path_exists_relaxed çağrılmaz).
  testthat::expect_length(fix$rec$exists_paths, 0L)
})

testthat::test_that("analysis_file_clicked www/ önekli yolu çalışma dizini altında çözer", {
  fix <- .source_file_clicks_for_test()
  .drive_file_click(fix, "analysis_file_clicked",
                    list(filepath = "www/p/prime.png"), list(filepath = "www/img/x.png"))
  beklenen <- file.path(getwd(), "www/img/x.png")
  testthat::expect_true(beklenen %in% fix$rec$exists_paths)
})

testthat::test_that("analysis_file_clicked mutlak yolu olduğu gibi korur", {
  fix <- .source_file_clicks_for_test()
  .drive_file_click(fix, "analysis_file_clicked",
                    list(filepath = "/a/prime.png"), list(filepath = "/veri/cikti/y.png"))
  testthat::expect_true("/veri/cikti/y.png" %in% fix$rec$exists_paths)
})

testthat::test_that("analysis_file_clicked göreli yolu www altına yerleştirir", {
  fix <- .source_file_clicks_for_test()
  .drive_file_click(fix, "analysis_file_clicked",
                    list(filepath = "p/prime.png"), list(filepath = "rapor/z.png"))
  beklenen <- file.path(getwd(), "www", "rapor/z.png")
  testthat::expect_true(beklenen %in% fix$rec$exists_paths)
})

testthat::test_that("analysis_file_clicked dosya bulunamazsa basename ile uyarır ve önizleme açmaz", {
  fix <- .source_file_clicks_for_test()
  .drive_file_click(fix, "analysis_file_clicked",
                    list(filepath = "www/p/prime.png"), list(filepath = "www/img/yok.png"))
  mesajlar <- vapply(fix$rec$toasts, function(t) t$message, character(1))
  testthat::expect_true(any(grepl("Dosya bulunamadı: yok.png", mesajlar, fixed = TRUE)))
  testthat::expect_identical(fix$rec$previews, 0L)
})
