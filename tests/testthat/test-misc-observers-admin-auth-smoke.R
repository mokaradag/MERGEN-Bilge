# ==============================================================================
# Dosya Yolu: tests/testthat/test-misc-observers-admin-auth-smoke.R
# Açıklama: miscObserversInit() yetkilendirme davranışı runtime smoke testi.
#           Yönetici analitik modüllerinin YALNIZCA ADMIN yetkisinde
#           başlatılmasını (USER iken hiç başlatılmamasını) ve mesaj sayısı
#           çıktısını gerçek reaktif tur içinde doğrular. Yetki kapısı yan
#           etki (adminXServer çağrıları) üzerinden ölçülür; bu, bare
#           reactive output okuma belirsizliğinden kaçınan sağlam bir
#           güvenlik-duyarlı davranış kontrolüdür. DB/LLM/tarayıcı gerekmez.
# ==============================================================================

.misc_observers_source_once <- function() {
  if (exists("miscObserversInit", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }

  source(
    file.path(resolve_repo_root_for_tests(), "R", "server_observers_misc.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  invisible(TRUE)
}

# adminXServer() fonksiyonları no-op recorder ile değiştirilir; çağrı sayısı
# yetkilendirme kapısının doğru çalışıp çalışmadığını ölçer.
.with_recording_admin_servers <- function(recorder) {
  names <- c(
    "adminAnalyticsServer", "adminGeriBildirimServer",
    "adminHataAnaliziServer", "adminYanitAnaliziServer"
  )
  had <- vapply(names, exists, logical(1), envir = globalenv(), inherits = FALSE)
  old <- lapply(names, function(nm) {
    if (exists(nm, envir = globalenv(), inherits = FALSE)) get(nm, envir = globalenv()) else NULL
  })
  names(old) <- names

  # Sayaçlar 0L olarak başlatılır; böylece USER yolunda "çağrılmadı" durumu
  # NULL belirsizliği olmadan 0L ile net biçimde doğrulanır.
  for (nm in names) {
    recorder[[nm]] <- 0L
  }

  for (nm in names) {
    local({
      key <- nm
      assign(key, function(...) {
        recorder[[key]] <- recorder[[key]] + 1L
        invisible(NULL)
      }, envir = globalenv())
    })
  }

  list(
    restore = function() {
      for (nm in names) {
        if (isTRUE(had[[nm]])) {
          assign(nm, old[[nm]], envir = globalenv())
        } else if (exists(nm, envir = globalenv(), inherits = FALSE)) {
          rm(list = nm, envir = globalenv())
        }
      }
    }
  )
}

.build_misc_observer_deps <- function() {
  list(
    file_manager_data = list(
      message_trigger = shiny::reactiveVal(0),
      get_message = function() NULL,
      file_contents = function() list()
    ),
    filePreview = list(),
    add_message = function(...) invisible(TRUE),
    api_key = list(open = function(...) invisible(TRUE))
  )
}

# miscObserversInit init anında shinydashboard::renderMenu'yu niteliksiz çağırır;
# bu sembol arama yolunda yoksa test güvenle atlanır (başarısız olmaz).
.skip_unless_renderMenu <- function() {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  if (!exists("renderMenu", mode = "function")) {
    testthat::skip("shinydashboard arama yolunda ekli değil (renderMenu yok)")
  }
}

testthat::test_that("miscObserversInit USER yetkisinde yönetici modüllerini başlatmaz", {
  .skip_unless_renderMenu()
  .misc_observers_source_once()

  rec <- new.env()
  admin_stub <- .with_recording_admin_servers(rec)
  on.exit(admin_stub$restore(), add = TRUE)

  deps <- .build_misc_observer_deps()

  shiny::testServer(function(input, output, session) {
    values <- shiny::reactiveValues(
      messages = list(list(id = "a"), list(id = "b")),
      liked_messages = character(0),
      disliked_messages = character(0),
      show_welcome = TRUE
    )

    miscObserversInit(
      input = input, output = output, session = session, values = values,
      file_manager_data = deps$file_manager_data,
      filePreview = deps$filePreview,
      add_message = deps$add_message,
      api_key = deps$api_key,
      user_config = function() list(auth_level = "USER"),
      pool = NULL
    )
  }, {
    session$flushReact()

    # USER -> hiçbir yönetici modülü başlatılmamalı (sayaç 0L kalmalı).
    testthat::expect_identical(rec$adminAnalyticsServer, 0L)
    testthat::expect_identical(rec$adminGeriBildirimServer, 0L)

    # Mesaj sayısı çıktısı (renderText) mevcut mesaj sayısını yansıtmalı.
    testthat::expect_identical(output$message_count, "2")
  })
})

testthat::test_that("miscObserversInit ADMIN yetkisinde yönetici modüllerini başlatır", {
  .skip_unless_renderMenu()
  .misc_observers_source_once()

  rec <- new.env()
  admin_stub <- .with_recording_admin_servers(rec)
  on.exit(admin_stub$restore(), add = TRUE)

  deps <- .build_misc_observer_deps()

  shiny::testServer(function(input, output, session) {
    values <- shiny::reactiveValues(
      messages = list(),
      liked_messages = character(0),
      disliked_messages = character(0),
      show_welcome = FALSE
    )

    miscObserversInit(
      input = input, output = output, session = session, values = values,
      file_manager_data = deps$file_manager_data,
      filePreview = deps$filePreview,
      add_message = deps$add_message,
      api_key = deps$api_key,
      # auth_level boşluk/küçük harf içerse de normalize edilmeli (trimws+toupper).
      user_config = function() list(auth_level = "  admin  "),
      pool = NULL
    )
  }, {
    session$flushReact()

    # ADMIN -> yönetici analitik modülleri tam olarak bir kez başlatılmalı.
    testthat::expect_identical(rec$adminAnalyticsServer, 1L)
    testthat::expect_identical(rec$adminGeriBildirimServer, 1L)
    testthat::expect_identical(rec$adminHataAnaliziServer, 1L)
    testthat::expect_identical(rec$adminYanitAnaliziServer, 1L)

    # Boş mesaj listesi "0" üretmeli.
    testthat::expect_identical(output$message_count, "0")
  })
})
