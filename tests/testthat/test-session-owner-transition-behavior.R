# ==============================================================================
# Dosya Yolu: tests/testthat/test-session-owner-transition-behavior.R
# Açıklama: Aynı Shiny oturumunda kullanıcı değişimi (A -> B) ve kimlik kaybı.
#           A'nın dosya kayıt defteri, özetleri ve kişisel API anahtarı B'ye
#           kalmaz; kayıtlı kancalar (süren özet işinin iptali) çalışır ve
#           reaktif kimlik sinyali artar.
# ==============================================================================

.owner_env <- function() {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  source(file.path(kok, "R", "utils_session_cleanup.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "helpers_user_session_identity.R"), encoding = "UTF-8", local = env)
  env
}

.owner_session <- function() {
  list(userData = new.env(parent = emptyenv()))
}

test_that("A -> B geçişi kullanıcıya bağlı depoları ve kişisel anahtarı temizler", {
  env <- .owner_env()
  oturum <- .owner_session()
  veri <- env$make_user_session_data_accessors(oturum)
  veri$write_identity(list(username = "a"), 7L, list(), TRUE, "keycloak")
  oturum$userData$current_session_files <- list(a.txt = list(path = "/k/user_7/a.txt"))
  oturum$userData$file_summaries <- list(a.txt = "ozet")
  oturum$userData$ai_api_key <- "anahtar-a"

  # Aynı kullanıcı profil tazelemesi depoları silmez.
  veri$write_identity(list(username = "a"), 7L, list(), TRUE, "keycloak")
  expect_length(oturum$userData$current_session_files, 1L)
  expect_identical(oturum$userData$ai_api_key, "anahtar-a")

  veri$write_identity(list(username = "b"), 8L, list(), TRUE, "keycloak")
  expect_length(oturum$userData$current_session_files, 0L)
  expect_length(oturum$userData$file_summaries, 0L)
  expect_null(oturum$userData$ai_api_key)
})

test_that("kimlik kaybı kancaları çalıştırır; A -> 0 -> B de sahip değişimi sayılır", {
  env <- .owner_env()
  oturum <- .owner_session()
  veri <- env$make_user_session_data_accessors(oturum)
  nedenler <- character(0)
  kaldir <- env$mergen_session_on_owner_change(oturum, function(neden) nedenler <<- c(nedenler, neden))

  veri$write_identity(list(username = "a"), 7L, list(), TRUE, "keycloak")
  oturum$userData$current_session_files <- list(a.txt = list(path = "/k/a.txt"))
  veri$set_auth_placeholder()
  expect_identical(nedenler, "kimlik_kaybi")
  # Kimlik kaybında aynı kullanıcı dönebilir; dosyalar korunur.
  expect_length(oturum$userData$current_session_files, 1L)

  veri$write_identity(list(username = "b"), 8L, list(), TRUE, "keycloak")
  expect_identical(nedenler, c("kimlik_kaybi", "sahip_degisti"))
  expect_length(oturum$userData$current_session_files, 0L)

  kaldir()
  veri$write_identity(list(username = "a"), 7L, list(), TRUE, "keycloak")
  expect_length(nedenler, 2L)
})

test_that("reaktif kimlik sinyali yalnız kimlik değişince artar", {
  env <- .owner_env()
  oturum <- .owner_session()
  veri <- env$make_user_session_data_accessors(oturum)
  sinyal <- env$mergen_session_identity_signal(oturum)
  veri$write_identity(list(username = "a"), 7L, list(), TRUE, "keycloak")
  expect_identical(shiny::isolate(sinyal()), 1L)
  veri$write_identity(list(username = "a"), 7L, list(), TRUE, "keycloak")
  expect_identical(shiny::isolate(sinyal()), 1L)
  veri$set_auth_placeholder()
  expect_identical(shiny::isolate(sinyal()), 2L)
  # Oturum ortamı olmayan çağıran için sabit sinyal döner.
  expect_identical(env$mergen_session_identity_signal(list())(), 0L)
})

test_that("sahip değişimi özet iş kayıtlarını temizler; değişim ve kimlik kaybı kimlik neslini artırır", {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_user_session_identity.R"),
         encoding = "UTF-8", local = env)
  ud <- new.env()
  ud$kimlik_sahibi <- 5L
  ud$file_summary_jobs <- list(a.txt = list(jeton = "is-1", durdur = ""))
  env$mergen_session_owner_transition(ud, 5L, 5L)
  expect_null(ud$kimlik_nesli)
  env$mergen_session_owner_transition(ud, 5L, 6L)
  expect_identical(ud$file_summary_jobs, list())
  expect_identical(ud$kimlik_nesli, 1L)
  env$mergen_session_owner_transition(ud, 6L, 0L)
  expect_identical(ud$kimlik_nesli, 2L)
})

test_that("Dosya Yönetimi sahip değişiminde ve kimlik kaybında önbelleğini, yüklemesini ve seçimini bırakır", {
  testthat::skip_if_not_installed("shiny")
  env <- .owner_env()
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_file_manager_session_registry.R"),
         encoding = "UTF-8", local = env)
  iptal <- 0L
  env$file_ingestion_cancel_controller <- function(controller) iptal <<- iptal + 1L
  kapanan_modal <- 0L
  testthat::local_mocked_bindings(removeModal = function(...) kapanan_modal <<- kapanan_modal + 1L,
                                  .package = "shiny")
  shiny::testServer(function(input, output, session) NULL, {
    mv <- shiny::reactiveValues(files = data.frame(Ad = "a.txt"), file_contents = list(f1 = list(datapath = "/k/user_7/a.txt")),
                                files_in_context = list(f1 = TRUE), file_id_to_delete = "f1")
    bekleyen <- shiny::reactiveVal(FALSE)
    yenilenen <- character(0)
    gecici <- tempfile("fm_")
    writeLines("x", gecici)
    session$userData$temp_files <- list(f1 = gecici)
    veri <- env$make_user_session_data_accessors(session)
    veri$write_identity(list(username = "a"), 7L, list(), TRUE, "keycloak")
    cikarilan <- character(0)
    session$userData$current_session_files <- list(a.txt = list(path = "/k/user_7/a.txt"))
    env$fm_register_owner_reset(session, session$ns, function() mv, list(), bekleyen,
                                function(tetik) yenilenen <<- c(yenilenen, tetik),
                                function() isTRUE(session$userData$auth_initialized),
                                function(ad) cikarilan <<- c(cikarilan, ad))
    session$flushReact()

    # Kimlik kaybı: önbellek boşalır, indirme yolu kalmaz; yeniden tarama yapılmaz.
    veri$set_auth_placeholder()
    session$flushReact()
    expect_length(shiny::isolate(mv$file_contents), 0L)
    expect_length(shiny::isolate(mv$files_in_context), 0L)
    expect_identical(nrow(shiny::isolate(mv$files)), 0L)
    expect_null(shiny::isolate(mv$file_id_to_delete))
    expect_false(file.exists(gecici))
    expect_identical(iptal, 1L)
    expect_length(yenilenen, 0L)
    expect_identical(cikarilan, "a.txt")
    # Önceki sahibin açık onay pencereleri kapatılır.
    expect_identical(kapanan_modal, 1L)
    expect_length(session$userData$current_session_files, 0L)

    # A -> B: yalnız yeni sahibin envanteri yüklenir.
    mv$file_contents <- list(f2 = list(datapath = "/k/user_7/b.txt"))
    veri$write_identity(list(username = "b"), 8L, list(), TRUE, "keycloak")
    session$flushReact()
    expect_length(shiny::isolate(mv$file_contents), 0L)
    expect_identical(yenilenen, "owner_change")
    expect_false(shiny::isolate(bekleyen()))
  })
})

test_that("Dosya Yönetimi aynı kullanıcının yeniden girişinde envanteri yeniden yükler", {
  testthat::skip_if_not_installed("shiny")
  env <- .owner_env()
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_file_manager_session_registry.R"),
         encoding = "UTF-8", local = env)
  env$file_ingestion_cancel_controller <- function(controller) invisible(NULL)
  shiny::testServer(function(input, output, session) NULL, {
    mv <- shiny::reactiveValues(files = data.frame(Ad = "a.txt"), file_contents = list(),
                                files_in_context = list(), file_id_to_delete = NULL)
    bekleyen <- shiny::reactiveVal(FALSE)
    yenilenen <- character(0)
    veri <- env$make_user_session_data_accessors(session)
    veri$write_identity(list(username = "a"), 7L, list(), TRUE, "keycloak")
    env$fm_register_owner_reset(session, session$ns, function() mv, list(), bekleyen,
                                function(tetik) yenilenen <<- c(yenilenen, tetik),
                                function() isTRUE(session$userData$auth_initialized))
    session$flushReact()
    veri$set_auth_placeholder()
    session$flushReact()
    expect_length(yenilenen, 0L)
    expect_true(shiny::isolate(bekleyen()))
    veri$write_identity(list(username = "a"), 7L, list(), TRUE, "keycloak")
    session$flushReact()
    expect_identical(yenilenen, "owner_change")
    expect_false(shiny::isolate(bekleyen()))
    # Olağan profil tazelemesi yeniden yükleme yapmaz.
    veri$write_identity(list(username = "a"), 7L, list(), TRUE, "keycloak")
    session$flushReact()
    expect_identical(yenilenen, "owner_change")
  })
})

test_that("Dosya Yönetimi indirmesi kimlik doğrulanmadan önbellek yolunu kopyalamaz", {
  kaynak <- read_source_text_utf8(file.path(resolve_repo_root_for_tests(), "R", "module_file_manager.R"))
  expect_true(grepl('if (!is_auth_ready() && isTRUE(SSO_ENABLED)) stop("Oturum kimliği doğrulanmadı.")',
                    kaynak, fixed = TRUE))
  expect_true(grepl("fm_register_owner_reset(session, ns, get_module_values, upload_runtime$controller",
                    kaynak, fixed = TRUE))
  # "Tümünü Sil" onayı açıldığı kimlik nesline bağlıdır; nesil değiştiyse silinmez.
  onay <- regmatches(kaynak, regexpr("observeEvent\\(input\\$confirm_clear_files, \\{[\\s\\S]*?fm_clear_user_bucket_safely", kaynak, perl = TRUE))
  expect_length(onay, 1L)
  expect_true(grepl("if (!identical(module_values$temizlik_nesli, fm_owner_generation(session))) return(", onay, fixed = TRUE))
  expect_true(grepl("module_values$temizlik_nesli <- fm_owner_generation(session)", kaynak, fixed = TRUE))
  env2 <- .owner_env()
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_file_manager_session_registry.R"),
         encoding = "UTF-8", local = env2)
  oturum <- .owner_session()
  nesil <- env2$fm_owner_generation(oturum)
  env2$mergen_session_owner_transition(oturum$userData, 7L, 0L)
  expect_false(identical(nesil, env2$fm_owner_generation(oturum)))
})

test_that("oturum başka kullanıcıya geçince açık söyleşi, kayıtlı liste ve süren yanıt bırakılır", {
  testthat::skip_if_not_installed("shiny")
  env <- .owner_env()
  source(file.path(resolve_repo_root_for_tests(), "R", "server_init_session_state.R"),
         encoding = "UTF-8", local = env)
  kimlik <- list(resolve_current_user_id = function() 0L, is_sso_active = function() FALSE,
                 is_auth_ready = function() TRUE)
  env$load_feedback_from_db <- function(...) NULL
  shiny::testServer(function(input, output, session) NULL, {
    durum <- env$serverInitSessionState(session, kimlik)
    session$userData$kimlik_sahibi <- 7L
    durum$values$messages <- list(list(role = "user", content = "A mesajı"))
    durum$values$saved_chats <- list(a = list(title = "A"))
    durum$values$current_chat_id <- "a"
    durum$values$show_welcome <- FALSE
    durum$values$is_sending <- TRUE
    durum$active_request_id("istek-a")
    durum$session_files(list(a.txt = list(name = "a.txt")))
    env$mergen_session_owner_transition(session$userData, 7L, 8L)
    expect_length(shiny::isolate(durum$values$messages), 0L)
    expect_length(shiny::isolate(durum$values$saved_chats), 0L)
    expect_null(shiny::isolate(durum$values$current_chat_id))
    expect_true(shiny::isolate(durum$values$show_welcome))
    expect_false(shiny::isolate(durum$values$is_sending))
    expect_false(shiny::isolate(durum$values$typing))
    expect_true(shiny::isolate(durum$stop_generation()))
    expect_true(startsWith(shiny::isolate(durum$active_request_id()), "cancelled_"))
    expect_length(shiny::isolate(durum$session_files()), 0L)
  })
})

test_that("kimlik kaybı süren yanıtı keser, PK iptal jetonunu önce işaretler ve söyleşiyi bırakır", {
  testthat::skip_if_not_installed("shiny")
  env <- .owner_env()
  source(file.path(resolve_repo_root_for_tests(), "R", "server_init_session_state.R"),
         encoding = "UTF-8", local = env)
  kimlik <- list(resolve_current_user_id = function() 0L, is_sso_active = function() FALSE,
                 is_auth_ready = function() TRUE)
  env$load_feedback_from_db <- function(...) NULL
  isaretler <- character(0)
  env$mergen_pk_request_has_cancel_token <- function(session, id) identical(id, "istek-pk")
  shiny::testServer(function(input, output, session) NULL, {
    durum <- env$serverInitSessionState(session, kimlik)
    env$mergen_pk_signal_cancel <- function(id, session = NULL) {
      # İptal jetonu istek kimliği değişmeden önce işaretlenir.
      isaretler <<- c(isaretler, shiny::isolate(durum$active_request_id()))
      invisible(TRUE)
    }
    session$userData$kimlik_sahibi <- 7L
    durum$values$messages <- list(list(role = "user", content = "A mesajı"))
    durum$values$saved_chats <- list(a = list(title = "A"))
    durum$values$current_chat_id <- "a"
    durum$values$is_sending <- TRUE
    durum$active_request_id("istek-pk")
    durum$session_files(list(a.txt = list(name = "a.txt")))
    env$mergen_session_owner_transition(session$userData, 7L, 0L)
    expect_identical(isaretler, "istek-pk")
    expect_true(startsWith(shiny::isolate(durum$active_request_id()), "cancelled_"))
    expect_length(shiny::isolate(durum$values$messages), 0L)
    expect_length(shiny::isolate(durum$values$saved_chats), 0L)
    expect_null(shiny::isolate(durum$values$current_chat_id))
    expect_length(shiny::isolate(durum$session_files()), 0L)
  })
})


test_that("sahip kancaları temizlenmeden önce dosya kayıtlarını görür", {
  env <- .owner_env()
  oturum <- .owner_session()
  oturum$userData$kimlik_sahibi <- 7L
  oturum$userData$current_session_files <- list(a = list(path = "/a"))
  gorulen <- NULL
  env$mergen_session_on_owner_change(oturum, function(neden) {
    gorulen <<- oturum$userData$current_session_files
  })
  env$mergen_session_owner_transition(oturum$userData, 7L, 8L)
  expect_identical(gorulen, list(a = list(path = "/a")))
  expect_length(oturum$userData$current_session_files, 0L)
})


test_that("açılmamış Dosya Yönetimi sahip değişiminde tarama başlatmaz", {
  env <- .owner_env()
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_file_manager_session_registry.R"),
         encoding = "UTF-8", local = env)
  env$file_ingestion_cancel_controller <- function(...) invisible(NULL)
  shiny::testServer(function(input, output, session) NULL, {
    mv <- shiny::reactiveValues(files = data.frame(), file_contents = list(), files_in_context = list())
    bekleyen <- shiny::reactiveVal(TRUE)
    tarama <- 0L
    veri <- env$make_user_session_data_accessors(session)
    veri$write_identity(list(username = "a"), 7L, list(), TRUE, "keycloak")
    env$fm_register_owner_reset(session, session$ns, function() mv, list(), bekleyen,
      function(...) tarama <<- tarama + 1L, function() TRUE)
    veri$write_identity(list(username = "b"), 8L, list(), TRUE, "keycloak")
    session$flushReact()
    expect_identical(tarama, 0L)
    expect_true(shiny::isolate(bekleyen()))
  })
})
