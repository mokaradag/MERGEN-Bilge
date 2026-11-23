# ==============================================================================
# Dosya Yolu: tests/testthat/test-image-gallery-observers-behavior.R
# Açıklama: R/server_observers_image_gallery.R imageGalleryObserversInit()
#           söyleşiye yönlendirme guard'larının DAVRANIŞSAL testleri. Bu dosya
#           daha önce hiçbir test tarafından çağrılmıyordu.
#
#           navigate_to_chat gözlemcisi, görsele tıklanınca ilgili söyleşiye
#           gider. Önce kimlik doğrulama guard'ları çalışır: boş/geçersiz chat_id,
#           devam eden yükleme kilidi ve bulunamayan söyleşi. Gözlemci
#           gallery_data$navigate_to_chat reaktif değeri prime-then-set ile
#           tetiklenir. showToast / load_chat_messages_from_db stub'lanır.
#           Gerçek DB GEREKMEZ.
# ==============================================================================

.source_gallery_obs_for_test <- function(load_in_progress = FALSE, db_impl = NULL) {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  suppressMessages({ library(shiny); library(shinyjs) })
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  rec <- new.env(); rec$toasts <- list(); rec$db_calls <- 0L
  env$showToast <- function(session, message, type = "info") {
    rec$toasts[[length(rec$toasts) + 1L]] <- list(message = message, type = type)
    invisible(NULL)
  }
  env$load_chat_messages_from_db <- if (is.function(db_impl)) db_impl else function(chat_id_int, ...) {
    rec$db_calls <- rec$db_calls + 1L
    NULL
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "server_observers_image_gallery.R"),
    encoding = "UTF-8",
    local = env
  )
  list(env = env, rec = rec, load_in_progress = load_in_progress)
}

.toast_msgs <- function(rec) vapply(rec$toasts, function(t) t$message, character(1))

# navigate_to_chat reaktifini prime-then-set ile tetikler.
.drive_navigate <- function(fix, prime_info, real_info, saved_chats = list()) {
  env <- fix$env; rec <- fix$rec
  shiny::testServer(function(input, output, session) {
    nav <- shiny::reactiveVal(NULL)
    lock <- shiny::reactiveVal(fix$load_in_progress)
    values <- shiny::reactiveValues(saved_chats = saved_chats)
    rec$lock <- lock
    # Modülde üç gözlemci var (navigate/delete/clear); hepsinin reaktifi
    # sağlanmazsa init anında NULL() çağrısı "non-function" hatası üretir.
    env$imageGalleryObserversInit(
      input = input, session = session, values = values,
      settings_data = list(),
      gallery_data = list(
        navigate_to_chat = nav,
        delete_image = shiny::reactiveVal(NULL),
        clear_all_images = shiny::reactiveVal(NULL)
      ),
      saved_chats_data = list(),
      current_user_id = 5L,
      load_chat_in_progress = lock
    )
    nav(prime_info)
    nav(real_info)
  }, {
    session$flushReact()
    # Yeni Shiny sürümleri testServer çıkışında modül oturumunu yok eder;
    # kilit değerine blok DIŞINDAN erişim "session has been destroyed"
    # hatası üretir. Bu yüzden anlık görüntü blok İÇİNDE alınır.
    rec$lock_snapshot <- shiny::isolate(lock())
  })
}

# ------------------------------------------------------------------------------
# Boş / eksik chat_id
# ------------------------------------------------------------------------------
testthat::test_that("navigate_to_chat boş chat_id'de 'söyleşi bulunamadı' uyarısı verir", {
  fix <- .source_gallery_obs_for_test()
  .drive_navigate(fix, list(chat_id = ""), list(chat_id = ""))
  testthat::expect_true(any(grepl("ait olduğu söyleşi bulunamadı",
                                  .toast_msgs(fix$rec), fixed = TRUE)))
})

# ------------------------------------------------------------------------------
# Geçersiz (sayısal olmayan) chat_id
# ------------------------------------------------------------------------------
testthat::test_that("navigate_to_chat sayısal olmayan chat_id'de 'Geçersiz söyleşi kimliği' verir", {
  fix <- .source_gallery_obs_for_test()
  .drive_navigate(fix, list(chat_id = "xyz"), list(chat_id = "abc"))
  testthat::expect_true(any(grepl("Geçersiz söyleşi kimliği",
                                  .toast_msgs(fix$rec), fixed = TRUE)))
  # Geçersiz kimlik DB yüklemesine gitmemeli.
  testthat::expect_identical(fix$rec$db_calls, 0L)
})

# ------------------------------------------------------------------------------
# Devam eden yükleme kilidi
# ------------------------------------------------------------------------------
testthat::test_that("navigate_to_chat yükleme sürerken 'lütfen bekleyin' der ve DB'ye gitmez", {
  fix <- .source_gallery_obs_for_test(load_in_progress = TRUE)
  .drive_navigate(fix, list(chat_id = "6"), list(chat_id = "5"))
  testthat::expect_true(any(grepl("lütfen bekleyin", .toast_msgs(fix$rec), fixed = TRUE)))
  testthat::expect_identical(fix$rec$db_calls, 0L)
})

# ------------------------------------------------------------------------------
# Bulunamayan söyleşi
# ------------------------------------------------------------------------------
testthat::test_that("navigate_to_chat okuma hatasında önbellek yoksa okuma hatası bildirir, silindi demez ve kilidi bırakır", {
  fix <- .source_gallery_obs_for_test(load_in_progress = FALSE)  # DB stub NULL döner (okuma hatası)
  .drive_navigate(fix, list(chat_id = "6"), list(chat_id = "5"), saved_chats = list())
  testthat::expect_true(any(grepl("şu anda okunamadı", .toast_msgs(fix$rec), fixed = TRUE)))
  testthat::expect_false(any(grepl("artık mevcut değil veya silinmiş", .toast_msgs(fix$rec), fixed = TRUE)))
  # Yükleme kilidi tekrar serbest bırakılmalı.
  testthat::expect_false(fix$rec$lock_snapshot)
})

testthat::test_that("navigate_to_chat geçerli ama bulunamayan kimlikte DB'den yüklemeyi dener", {
  fix <- .source_gallery_obs_for_test(load_in_progress = FALSE)
  .drive_navigate(fix, list(chat_id = "10"), list(chat_id = "11"), saved_chats = list())
  # Geçerli sayısal kimlik -> en az bir DB yükleme denemesi yapılmalı.
  testthat::expect_true(fix$rec$db_calls >= 1L)
})

testthat::test_that("navigate_to_chat çözülmemiş kimlikte (0) DB okumaz, görünüme dokunmaz ve önbellekteki söyleşiyi silmez", {
  fix <- .source_gallery_obs_for_test(load_in_progress = FALSE)
  env <- fix$env; rec <- fix$rec
  # Görünüm değişiklikleri kaydedilir: kimlik çözülmeden sekme/transkript değişmemeli.
  rec$js <- character(); rec$sekme <- 0L
  env$updateTabItems <- function(...) rec$sekme <- rec$sekme + 1L
  testthat::local_mocked_bindings(runjs = function(code) rec$js <- c(rec$js, code), .package = "shinyjs")
  onbellek <- list("5" = list(title = "Kayıtlı Söyleşi", messages = list(), message_count = 1L, transkript_yenile = TRUE))
  shiny::testServer(function(input, output, session) {
    nav <- shiny::reactiveVal(NULL)
    lock <- shiny::reactiveVal(FALSE)
    values <- shiny::reactiveValues(saved_chats = onbellek)
    env$imageGalleryObserversInit(
      input = input, session = session, values = values,
      settings_data = list(),
      gallery_data = list(
        navigate_to_chat = nav,
        delete_image = shiny::reactiveVal(NULL),
        clear_all_images = shiny::reactiveVal(NULL)
      ),
      saved_chats_data = list(),
      current_user_id = 0L,
      load_chat_in_progress = lock
    )
    nav(list(chat_id = "6"))
    nav(list(chat_id = "5"))
    rec$values <- values
  }, {
    session$flushReact()
    rec$kalan <- names(shiny::isolate(rec$values$saved_chats))
    rec$bayrak <- shiny::isolate(rec$values$saved_chats[["5"]]$transkript_yenile)
    rec$kilit <- shiny::isolate(lock())
  })
  testthat::expect_identical(rec$db_calls, 0L)
  testthat::expect_identical(rec$kalan, "5")
  testthat::expect_true(isTRUE(rec$bayrak))
  testthat::expect_false(any(grepl("artık mevcut değil veya silinmiş", .toast_msgs(rec), fixed = TRUE)))
  # Kimlik guard'ına ulaşıldı: uyarı gösterildi, kilit bırakıldı, görünüm değişmedi.
  testthat::expect_true(any(grepl("Oturum kimliği henüz hazır değil", .toast_msgs(rec), fixed = TRUE)))
  testthat::expect_false(isTRUE(rec$kilit))
  testthat::expect_identical(rec$sekme, 0L)
  testthat::expect_length(rec$js, 0L)
})

testthat::test_that("navigate_to_chat bulunamayan söyleşide yükleniyor görünümünü geri alır ve kimliği silinenlere yazar", {
  fix <- .source_gallery_obs_for_test(load_in_progress = FALSE, db_impl = function(chat_id_int, ...) {
    list(kayit_bulunamadi = TRUE)
  })
  env <- fix$env; rec <- fix$rec
  rec$js <- character()
  env$updateTabItems <- function(...) invisible(NULL)
  testthat::local_mocked_bindings(runjs = function(code) rec$js <- c(rec$js, code), .package = "shinyjs")
  shiny::testServer(function(input, output, session) {
    nav <- shiny::reactiveVal(NULL)
    lock <- shiny::reactiveVal(FALSE)
    values <- shiny::reactiveValues(saved_chats = list("5" = list(title = "Silinmiş", transkript_yenile = TRUE)))
    env$imageGalleryObserversInit(
      input = input, session = session, values = values, settings_data = list(),
      gallery_data = list(navigate_to_chat = nav, delete_image = shiny::reactiveVal(NULL),
                          clear_all_images = shiny::reactiveVal(NULL)),
      saved_chats_data = list(), current_user_id = 7L, load_chat_in_progress = lock
    )
    nav(list(chat_id = "6")); nav(list(chat_id = "5"))
    rec$values <- values; rec$lock <- lock
  }, {
    session$flushReact()
    rec$kalan <- names(shiny::isolate(rec$values$saved_chats))
    rec$kilit <- shiny::isolate(rec$lock())
    rec$silinenler <- session$userData$saved_chats_silinenler
  })
  # Yükleniyor görünümü yıkıcı değildir ve hata yolunda geri alınır.
  testthat::expect_true(any(grepl("image-gallery-chat-loading", rec$js, fixed = TRUE)))
  testthat::expect_false(any(grepl(".html('<div class", rec$js, fixed = TRUE)))
  testthat::expect_true(grepl("data-mergen-galeri-gizli", utils::tail(rec$js, 1L), fixed = TRUE))
  testthat::expect_true(grepl(".remove()", utils::tail(rec$js, 1L), fixed = TRUE))
  testthat::expect_length(rec$kalan, 0L)
  testthat::expect_false(isTRUE(rec$kilit))
  testthat::expect_identical(rec$silinenler, "5")
})

# Başarılı galeri yönlendirmesi tanımsız değişkenle düşmez: söyleşi açılır,
# başarı bildirimi gösterilir ve yükleme kilidi gecikmeli geri çağrıyla bırakılır.
.galeri_basari_calistir <- function(saved_chats, db_impl, kimlik = 7L) {
  fix <- .source_gallery_obs_for_test(load_in_progress = FALSE, db_impl = db_impl)
  env <- fix$env; rec <- fix$rec
  rec$gecikmeler <- 0L; rec$basari <- 0L
  env$updateTabItems <- function(...) invisible(NULL)
  env$load_feedback_from_db <- function(...) list(liked = character(), disliked = character())
  env$normalize_character_id <- function(x) x %||% ""
  env$get_characters_data <- function() NULL
  env$render_message_bubble_ui <- function(msg, ...) shiny::div(msg$content %||% "")
  env$resolve_runtime_user_id <- function() kimlik
  env$mergen_show_chat_loaded_toast <- function(...) rec$basari <- rec$basari + 1L
  testthat::local_mocked_bindings(
    runjs = function(code) invisible(NULL),
    delay = function(ms, expr) { rec$gecikmeler <- rec$gecikmeler + 1L; force(expr) },
    .package = "shinyjs"
  )
  shiny::testServer(function(input, output, session) {
    nav <- shiny::reactiveVal(NULL)
    lock <- shiny::reactiveVal(FALSE)
    values <- shiny::reactiveValues(saved_chats = saved_chats, messages = list())
    env$imageGalleryObserversInit(
      input = input, session = session, values = values,
      settings_data = shiny::reactiveValues(selected_character = NULL),
      gallery_data = list(navigate_to_chat = nav, delete_image = shiny::reactiveVal(NULL),
                          clear_all_images = shiny::reactiveVal(NULL)),
      saved_chats_data = list(), current_user_id = kimlik, load_chat_in_progress = lock
    )
    nav(list(chat_id = "6")); nav(list(chat_id = "5"))
    rec$values <- values; rec$lock <- lock
  }, {
    session$flushReact()
    rec$kilit <- shiny::isolate(rec$lock())
    rec$acik <- shiny::isolate(rec$values$current_chat_id)
    rec$mesaj_sayisi <- length(shiny::isolate(rec$values$messages))
  })
  rec
}

testthat::test_that("navigate_to_chat başarılı yüklemede oturumu düşürmez, başarı bildirir ve kilidi bırakır", {
  mesajlar <- list(list(id = "1", type = "user", content = "merhaba"),
                   list(id = "2", type = "ai", content = "selam"))
  rec <- .galeri_basari_calistir(
    saved_chats = list("5" = list(title = "Görsel", messages = mesajlar, message_count = 2L)),
    db_impl = function(...) stop("hidrasyon beklenmiyordu")
  )
  testthat::expect_identical(rec$acik, 5L)
  testthat::expect_identical(rec$mesaj_sayisi, 2L)
  testthat::expect_identical(rec$basari, 1L)
  testthat::expect_true(rec$gecikmeler >= 1L)
  testthat::expect_false(isTRUE(rec$kilit))
})

testthat::test_that("navigate_to_chat özet önbellekte okuma hatası boş söyleşiyi 'yüklendi' diye açmaz", {
  uyarilar <- character()
  rec <- withCallingHandlers(
    .galeri_basari_calistir(
      saved_chats = list("5" = list(title = "Özet", messages = NULL, message_count = 4L)),
      db_impl = function(...) stop("okuma_hatasi_test")
    ),
    warning = function(w) { uyarilar <<- c(uyarilar, conditionMessage(w)); invokeRestart("muffleWarning") }
  )
  # Okuma hatası günlüğe tam bir kez yazılır.
  testthat::expect_identical(sum(grepl("Söyleşi yüklenemedi (ChatID: 5)", uyarilar, fixed = TRUE)), 1L)
  testthat::expect_null(rec$acik)
  testthat::expect_identical(rec$basari, 0L)
  testthat::expect_true(any(grepl("şu anda okunamadı", .toast_msgs(rec), fixed = TRUE)))
  testthat::expect_false(isTRUE(rec$kilit))
})
