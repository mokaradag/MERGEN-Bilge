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
    env$fm_register_owner_reset(session, session$ns, function() mv, list(), bekleyen,
                                function(tetik) yenilenen <<- c(yenilenen, tetik), function() TRUE)
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

    # A -> B: yalnız yeni sahibin envanteri yüklenir.
    mv$file_contents <- list(f2 = list(datapath = "/k/user_7/b.txt"))
    veri$write_identity(list(username = "b"), 8L, list(), TRUE, "keycloak")
    session$flushReact()
    expect_length(shiny::isolate(mv$file_contents), 0L)
    expect_identical(yenilenen, "owner_change")
    expect_false(shiny::isolate(bekleyen()))
  })
})

test_that("Dosya Yönetimi indirmesi kimlik doğrulanmadan önbellek yolunu kopyalamaz", {
  kaynak <- paste(readLines(file.path(resolve_repo_root_for_tests(), "R", "module_file_manager.R"),
                            encoding = "UTF-8", warn = FALSE), collapse = "\n")
  expect_true(grepl('if (!is_auth_ready() && isTRUE(SSO_ENABLED)) stop("Oturum kimliği doğrulanmadı.")',
                    kaynak, fixed = TRUE))
  expect_true(grepl("fm_register_owner_reset(session, ns, get_module_values, upload_runtime$controller",
                    kaynak, fixed = TRUE))
})
