# ==============================================================================
# Dosya Yolu: tests/testthat/test-stt-module-behavior.R
# Açıklama: R/module_stt.R STT (Konuşma->Metin) modülünün davranışsal testleri.
#           Modal aç/iptal/onayla akışı, modal-active yayını, paket kilidi
#           (accept_chunks) ve API-anahtarı yoksa STT çağrısı yapılmaması.
#           Gerçek mikrofon/STT endpoint/tarayıcı gerektirmez.
# ==============================================================================

testthat::local_edition(3)
suppressMessages(library(promises))

.stt_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "module_stt.R"),
  encoding = "UTF-8",
  local = .stt_env
)

.stt_settings <- function() list(selected_character = "emre", font_size = "large")

# Kabul sınırı testleri için gönderimi ASKIDA tutar: parça worker'a gerçekten
# gitmez, bu yüzden `pending_stt_chunks` sayacı deterministik kalır. Kayıt
# `.stt_env` içinde gölgelenir ve test sonunda önceki hâline döndürülür.
.stt_askida_gonderim <- function() {
  vardi <- exists("tracked_future_promise", envir = .stt_env, inherits = FALSE)
  eski <- if (vardi) get("tracked_future_promise", envir = .stt_env) else NULL
  .stt_env$tracked_future_promise <- function(...) {
    promises::promise(function(resolve, reject) NULL)
  }
  withr::defer(
    {
      if (isTRUE(vardi)) {
        assign("tracked_future_promise", eski, envir = .stt_env)
      } else {
        rm("tracked_future_promise", envir = .stt_env)
      }
    },
    envir = parent.frame()
  )
  invisible(TRUE)
}

test_that("sttServer start_session ve final_text içeren liste döndürür", {
  skip_if_not_installed("shiny")

  shiny::testServer(
    .stt_env$sttServer,
    args = list(id = "stt", parent_session = NULL, settings = .stt_settings()),
    {
      api <- session$returned
      expect_true(is.list(api))
      expect_true(is.function(api$start_session))
      expect_true(is.function(api$final_text))
      # final_text başlangıçta boş string olmalı.
      expect_identical(api$final_text(), "")
    }
  )
})

test_that("start_session: modal-active 'true' yayını ve ns önekli initSTT mesajı gönderilir", {
  skip_if_not_installed("shiny")

  kayit <- new.env()
  kayit$msgs <- list()
  kayit$codes <- character(0)

  shiny::testServer(
    .stt_env$sttServer,
    args = list(id = "stt", parent_session = NULL, settings = .stt_settings()),
    {
      root <- .subset2(session, "parent")
      root$sendCustomMessage <- function(type, message) kayit$msgs[[type]] <- message

      testthat::local_mocked_bindings(
        runjs = function(code, ...) kayit$codes <- c(kayit$codes, code),
        delay = function(ms, expr) expr,        # gecikmeyi anında çalıştır
        .package = "shinyjs"
      )
      # showModal MockSession'da hata vermesin diye etkisiz kıl.
      testthat::local_mocked_bindings(
        showModal = function(...) invisible(NULL),
        .package = "shiny"
      )

      session$returned$start_session()

      # initSTT mesajı doğru ns öneki ve canvas id'siyle gitmeli.
      expect_true("initSTT" %in% names(kayit$msgs))
      expect_equal(kayit$msgs$initSTT$nsPrefix, "stt")
      expect_equal(kayit$msgs$initSTT$canvasId, "stt-visualizer_canvas")

      # Modal açıldığında stt_modal_active TRUE yayını yapılmalı.
      aktif_kod <- kayit$codes[grepl("stt_modal_active", kayit$codes, fixed = TRUE)]
      expect_true(length(aktif_kod) >= 1)
      expect_true(any(grepl("'stt_modal_active', true", aktif_kod, fixed = TRUE)))
    }
  )
})

test_that("accept_btn: kırpılmış metni final_text'e aktarır ve modal-active 'false' yayını yapar", {
  skip_if_not_installed("shiny")

  kayit <- new.env()
  kayit$codes <- character(0)

  shiny::testServer(
    .stt_env$sttServer,
    args = list(id = "stt", parent_session = NULL, settings = .stt_settings()),
    {
      testthat::local_mocked_bindings(
        runjs = function(code, ...) kayit$codes <- c(kayit$codes, code),
        .package = "shinyjs"
      )

      session$setInputs(transcribed_text = "  selam dünya  ")
      session$setInputs(accept_btn = 1)

      # Boşluklar kırpılarak final_text'e yazılmalı.
      expect_identical(session$returned$final_text(), "selam dünya")

      # Modal kapanırken stt_modal_active FALSE yayını ve temizleme çağrısı olmalı.
      expect_true(any(grepl("'stt_modal_active', false", kayit$codes, fixed = TRUE)))
      expect_true(any(grepl("stopAndCleanup", kayit$codes, fixed = TRUE)))
    }
  )
})

test_that("dismiss_btn: final_text'i değiştirmez ama modal-active 'false' yayını yapar", {
  skip_if_not_installed("shiny")

  kayit <- new.env()
  kayit$codes <- character(0)

  shiny::testServer(
    .stt_env$sttServer,
    args = list(id = "stt", parent_session = NULL, settings = .stt_settings()),
    {
      testthat::local_mocked_bindings(
        runjs = function(code, ...) kayit$codes <- c(kayit$codes, code),
        .package = "shinyjs"
      )

      session$setInputs(transcribed_text = "kaydedilmemeli")
      session$setInputs(dismiss_btn = 1)

      # İptal final_text'i değiştirmemeli.
      expect_identical(session$returned$final_text(), "")
      expect_true(any(grepl("'stt_modal_active', false", kayit$codes, fixed = TRUE)))
      expect_true(any(grepl("stopAndCleanup", kayit$codes, fixed = TRUE)))
    }
  )
})

test_that("audio_chunk: kayıt kabul kapalıyken (kilit) STT çağrısı yapılmaz", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("httr")

  kayit <- new.env()
  kayit$post <- 0L

  shiny::testServer(
    .stt_env$sttServer,
    args = list(id = "stt", parent_session = NULL, settings = .stt_settings()),
    {
      # POST çağrılırsa sayaç artar; kilit nedeniyle hiç çağrılmamalı.
      testthat::local_mocked_bindings(
        POST = function(...) {
          kayit$post <- kayit$post + 1L
          structure(list(), class = "response")
        },
        .package = "httr"
      )

      # start_session çağrılmadı -> accept_chunks varsayılan FALSE (kilit kapalı).
      session$setInputs(audio_chunk = "ZHVtbXk=")  # base64 "dummy"

      expect_identical(kayit$post, 0L)
    }
  )
})

test_that("toggle_record_btn (Durdur): transcribe_gen ve kuyruk sıfırlanmaz (uçuştaki parçalar korunur)", {
  skip_if_not_installed("shiny")

  shiny::testServer(
    .stt_env$sttServer,
    args = list(id = "stt", parent_session = NULL, settings = .stt_settings()),
    {
      testthat::local_mocked_bindings(
        runjs = function(code, ...) invisible(NULL),
        .package = "shinyjs"
      )

      # Kayıt sırasında dispatch edilmiş, henüz sonuçlanmamış bir STT parçasını
      # simüle et (uçuştaki durum).
      rv$is_recording <- TRUE
      rv$accept_chunks <- TRUE
      gen_once_dispatched <- isolate(rv$transcribe_gen)
      rv$next_chunk_seq <- 5L
      rv$next_append_seq <- 3L
      rv$pending_stt_chunks <- 1L

      session$setInputs(toggle_record_btn = 1) # Durdur

      # Duraklatma yeni paket kabulünü kapatmalı...
      expect_false(isolate(rv$accept_chunks))
      expect_false(isolate(rv$is_recording))
      # ...ama üretim jetonunu VE kuyruğu sıfırlamamalı; aksi halde uçuştaki
      # parça sonuçlandığında üretim uyuşmazlığı yüzünden sessizce düşer.
      expect_identical(isolate(rv$transcribe_gen), gen_once_dispatched)
      expect_identical(isolate(rv$next_chunk_seq), 5L)
      expect_identical(isolate(rv$next_append_seq), 3L)
      expect_identical(isolate(rv$pending_stt_chunks), 1L)
    }
  )
})

test_that("Durdur sonrası çözülen STT parçası geçmişe eklenir (düşürülmez)", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("promises")

  # tracked_future_promise, gerçek future/worker'a gitmeden elle çözülebilir
  # bir promise döndürecek şekilde .stt_env içinde GEÇİCİ olarak değiştirilir
  # (sttServer bu ismi .stt_env -> globalenv() zincirinde arar). Test sonunda
  # geri yüklenir ki diğer testleri etkilemesin.
  had_override <- exists("tracked_future_promise", envir = .stt_env, inherits = FALSE)
  old_override <- if (had_override) get("tracked_future_promise", envir = .stt_env) else NULL
  on.exit({
    if (had_override) {
      assign("tracked_future_promise", old_override, envir = .stt_env)
    } else if (exists("tracked_future_promise", envir = .stt_env, inherits = FALSE)) {
      rm("tracked_future_promise", envir = .stt_env)
    }
  }, add = TRUE)

  resolve_fn <- NULL
  .stt_env$tracked_future_promise <- function(task_fn, ..., globals = list()) {
    promises::promise(function(resolve, reject) {
      resolve_fn <<- resolve
    })
  }

  shiny::testServer(
    .stt_env$sttServer,
    args = list(id = "stt", parent_session = NULL, settings = .stt_settings()),
    {
      testthat::local_mocked_bindings(
        runjs = function(code, ...) invisible(NULL),
        delay = function(ms, expr) expr,
        .package = "shinyjs"
      )
      testthat::local_mocked_bindings(
        showModal = function(...) invisible(NULL),
        .package = "shiny"
      )

      session$userData$ai_api_key <- "sk-test"
      session$returned$start_session()
      session$setInputs(audio_chunk = "ZHVtbXk=") # parça dispatch edildi, henüz çözülmedi

      expect_identical(isolate(rv$pending_stt_chunks), 1L)

      # Kullanıcı, parça hâlâ uçuştayken Durdur'a basar.
      session$setInputs(toggle_record_btn = 1)
      expect_false(isolate(rv$accept_chunks))

      # Parça ŞİMDİ (duraklatmadan SONRA) gerçek metinle çözülür.
      resolve_fn("merhaba dünya")
      for (i in seq_len(50)) {
        if (later::loop_empty()) break
        later::run_now(timeout = 0)
      }
      session$flushReact()

      # Metin düşürülmemeli; sunucu geçmişine ve metin alanına eklenmiş olmalı.
      expect_identical(isolate(rv$transcription_history), "merhaba dünya")
      expect_identical(isolate(rv$pending_stt_chunks), 0L)
    }
  )
})

test_that("Durdur sonrası kayıtçının gönderdiği TEK final parça kapıdan geçer (düşürülmez)", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("promises")

  had_override <- exists("tracked_future_promise", envir = .stt_env, inherits = FALSE)
  old_override <- if (had_override) get("tracked_future_promise", envir = .stt_env) else NULL
  on.exit({
    if (had_override) {
      assign("tracked_future_promise", old_override, envir = .stt_env)
    } else if (exists("tracked_future_promise", envir = .stt_env, inherits = FALSE)) {
      rm("tracked_future_promise", envir = .stt_env)
    }
  }, add = TRUE)

  dispatch_count <- 0L
  .stt_env$tracked_future_promise <- function(task_fn, ..., globals = list()) {
    dispatch_count <<- dispatch_count + 1L
    promises::promise(function(resolve, reject) resolve("final parça"))
  }

  shiny::testServer(
    .stt_env$sttServer,
    args = list(id = "stt", parent_session = NULL, settings = .stt_settings()),
    {
      testthat::local_mocked_bindings(
        runjs = function(code, ...) invisible(NULL),
        .package = "shinyjs"
      )

      session$userData$ai_api_key <- "sk-test"
      rv$is_recording <- TRUE
      rv$accept_chunks <- TRUE

      # Durdur: kapı kapanır ama kayıtçının stop() sonrası göndereceği TEK
      # final parça için bütçe (expect_final_chunk) açılır.
      session$setInputs(toggle_record_btn = 1)
      expect_false(isolate(rv$accept_chunks))
      expect_true(isolate(rv$expect_final_chunk))

      # Kayıtçının 'stop' olayı, henüz dispatch edilmemiş final blobu gönderir.
      session$setInputs(audio_chunk = "ZHVtbXk=")
      for (i in seq_len(50)) {
        if (later::loop_empty()) break
        later::run_now(timeout = 0)
      }
      session$flushReact()

      # Bu parça KAPIDAN GEÇMİŞ (dispatch edilmiş) ve metne eklenmiş olmalı;
      # düşürülmemeli.
      expect_identical(dispatch_count, 1L)
      expect_identical(isolate(rv$transcription_history), "final parça")
      # Bütçe tek kullanımlıktır; tüketildikten sonra kapanmalı.
      expect_false(isolate(rv$expect_final_chunk))

      # Olası bir SONRAKİ (beklenmeyen) parça artık normal şekilde reddedilmeli.
      session$setInputs(audio_chunk = "c2Vjb25k") # base64 "second"
      expect_identical(dispatch_count, 1L)
    }
  )
})

test_that("Onayla sonrası kayıtçının gönderdiği TEK final parça beklenip eklenir", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("promises")

  had_override <- exists("tracked_future_promise", envir = .stt_env, inherits = FALSE)
  old_override <- if (had_override) get("tracked_future_promise", envir = .stt_env) else NULL
  on.exit({
    if (had_override) {
      assign("tracked_future_promise", old_override, envir = .stt_env)
    } else if (exists("tracked_future_promise", envir = .stt_env, inherits = FALSE)) {
      rm("tracked_future_promise", envir = .stt_env)
    }
  }, add = TRUE)

  resolve_fn <- NULL
  .stt_env$tracked_future_promise <- function(task_fn, ..., globals = list()) {
    promises::promise(function(resolve, reject) {
      resolve_fn <<- resolve
    })
  }

  shiny::testServer(
    .stt_env$sttServer,
    args = list(id = "stt", parent_session = NULL, settings = .stt_settings()),
    {
      testthat::local_mocked_bindings(
        runjs = function(code, ...) invisible(NULL),
        # Bu testte gerçek gecikme penceresinin HİÇ tetiklenmediği (henüz
        # dolmadığı) senaryo modellenir: tamamlanma yalnızca parçanın kendi
        # çözülme (promise resolve) yolundan gelmelidir, zamanlayıcıdan değil.
        delay = function(ms, expr) invisible(NULL),
        .package = "shinyjs"
      )

      session$userData$ai_api_key <- "sk-test"
      rv$is_recording <- TRUE
      rv$accept_chunks <- TRUE

      session$setInputs(transcribed_text = "önceki metin")
      session$setInputs(accept_btn = 1)

      # Onayla anında kapı kapanır ama final parça bütçesi açılmış olmalı;
      # gecikme penceresi (mock nedeniyle) hiç tetiklenmediği için henüz
      # dispatch edilmemiş parça bekleniyorsa finish_accept çağrılmamalı
      # (final_text hâlâ boş).
      expect_false(isolate(rv$accept_chunks))
      expect_true(isolate(rv$expect_final_chunk))
      expect_identical(session$returned$final_text(), "")

      # Kayıtçının final parçası (Onayla sonrası) gelir.
      session$setInputs(audio_chunk = "ZHVtbXk=")
      expect_identical(isolate(rv$pending_stt_chunks), 1L)

      # Final parça çözülür; artık bekleyen kalmadığı için tamamlanmalı.
      resolve_fn("son parça")
      for (i in seq_len(50)) {
        if (later::loop_empty()) break
        later::run_now(timeout = 0)
      }
      session$flushReact()

      expect_identical(session$returned$final_text(), "önceki metin son parça")
    }
  )
})

test_that("Elle düzenlenen metin, bekleyen bir STT parçası eklenirken korunur", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("promises")

  had_override <- exists("tracked_future_promise", envir = .stt_env, inherits = FALSE)
  old_override <- if (had_override) get("tracked_future_promise", envir = .stt_env) else NULL
  on.exit({
    if (had_override) {
      assign("tracked_future_promise", old_override, envir = .stt_env)
    } else if (exists("tracked_future_promise", envir = .stt_env, inherits = FALSE)) {
      rm("tracked_future_promise", envir = .stt_env)
    }
  }, add = TRUE)

  resolve_fn <- NULL
  .stt_env$tracked_future_promise <- function(task_fn, ..., globals = list()) {
    promises::promise(function(resolve, reject) {
      resolve_fn <<- resolve
    })
  }

  shiny::testServer(
    .stt_env$sttServer,
    args = list(id = "stt", parent_session = NULL, settings = .stt_settings()),
    {
      testthat::local_mocked_bindings(
        runjs = function(code, ...) invisible(NULL),
        .package = "shinyjs"
      )

      session$userData$ai_api_key <- "sk-test"
      rv$is_recording <- TRUE
      rv$accept_chunks <- TRUE

      # İlk parça zaten sunucu tarafından itilmiş gibi kur (ör. önceki bir
      # STT sonucu). Senkron kapısının açılması için son push'un üzerinden
      # bolluk süresinden (STT_EDIT_SYNC_GRACE_SEC) FAZLA zaman geçmiş gibi
      # göster (deterministik test: gerçek Sys.sleep yerine geçmişe çekilir).
      push_transcription("ilk")
      rv$last_push_time <- Sys.time() - 1

      # Kullanıcı, hâlâ kayıt sürerken metin alanında elle düzeltme yapar.
      session$setInputs(transcribed_text = "ilk düzeltildi")

      # Bu düzenlemeden SONRA dispatch edilen bir STT parçası çözülür.
      session$setInputs(audio_chunk = "ZHVtbXk=")
      resolve_fn("ikinci")
      for (i in seq_len(50)) {
        if (later::loop_empty()) break
        later::run_now(timeout = 0)
      }
      session$flushReact()

      # Elle yapılan düzeltme KORUNMALI; STT parçası onun üzerine değil,
      # onun DEVAMINA eklenmeli.
      expect_identical(isolate(rv$transcription_history), "ilk düzeltildi ikinci")
    }
  )
})

test_that("Ardışık hızlı parça çözümlerinde henüz yansımamış istemci değeri 'elle düzenleme' sanılmaz (yarış korunur)", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("promises")

  had_override <- exists("tracked_future_promise", envir = .stt_env, inherits = FALSE)
  old_override <- if (had_override) get("tracked_future_promise", envir = .stt_env) else NULL
  on.exit({
    if (had_override) {
      assign("tracked_future_promise", old_override, envir = .stt_env)
    } else if (exists("tracked_future_promise", envir = .stt_env, inherits = FALSE)) {
      rm("tracked_future_promise", envir = .stt_env)
    }
  }, add = TRUE)

  resolvers <- list()
  .stt_env$tracked_future_promise <- function(task_fn, ..., globals = list()) {
    idx <- length(resolvers) + 1L
    promises::promise(function(resolve, reject) {
      resolvers[[idx]] <<- resolve
    })
  }

  shiny::testServer(
    .stt_env$sttServer,
    args = list(id = "stt", parent_session = NULL, settings = .stt_settings()),
    {
      testthat::local_mocked_bindings(
        runjs = function(code, ...) invisible(NULL),
        .package = "shinyjs"
      )

      session$userData$ai_api_key <- "sk-test"
      rv$is_recording <- TRUE
      rv$accept_chunks <- TRUE

      # İki parça art arda hızlıca dispatch edilir (istemci textarea'sı henüz
      # HİÇBİRİNİ yansıtmamıştır - input$transcribed_text hiç set edilmedi).
      session$setInputs(audio_chunk = "aXJz") # base64 "irs" (parça 1)
      session$setInputs(audio_chunk = "aWtp") # base64 "iki" (parça 2)

      # Birinci parça çözülür ve hemen ardından (bolluk süresi dolmadan)
      # ikinci parça da çözülür.
      resolvers[[1]]("birinci")
      for (i in seq_len(50)) {
        if (later::loop_empty()) break
        later::run_now(timeout = 0)
      }
      resolvers[[2]]("ikinci")
      for (i in seq_len(50)) {
        if (later::loop_empty()) break
        later::run_now(timeout = 0)
      }
      session$flushReact()

      # İstemcinin henüz yansıtmadığı (input$transcribed_text hâlâ boş/NULL)
      # değer sahte bir "elle düzenleme" sanılıp geçmişi geriye almamalı;
      # her iki parça da SIRAYLA eklenmiş olmalı.
      expect_identical(isolate(rv$transcription_history), "birinci ikinci")
    }
  )
})

test_that("audio_chunk: kabul açık olsa bile API anahtarı yoksa STT çağrısı yapılmaz", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("httr")

  kayit <- new.env()
  kayit$post <- 0L

  # LOCAL_STT_* anahtarlarını bu test boyunca boş tut.
  withr::local_envvar(c(
    LOCAL_STT_ENDPOINT = "",
    LOCAL_STT_MODEL = "",
    LOCAL_STT_API_KEY = ""
  ))

  shiny::testServer(
    .stt_env$sttServer,
    args = list(id = "stt", parent_session = NULL, settings = .stt_settings()),
    {
      # MockSession userData$ai_api_key NULL döndürmesin diye boş string ata.
      session$userData$ai_api_key <- ""

      testthat::local_mocked_bindings(
        runjs = function(code, ...) invisible(NULL),
        delay = function(ms, expr) expr,
        .package = "shinyjs"
      )
      testthat::local_mocked_bindings(
        showModal = function(...) invisible(NULL),
        .package = "shiny"
      )
      testthat::local_mocked_bindings(
        POST = function(...) {
          kayit$post <- kayit$post + 1L
          structure(list(), class = "response")
        },
        .package = "httr"
      )

      # start_session -> accept_chunks TRUE (kilit açık)
      session$returned$start_session()
      session$setInputs(audio_chunk = "ZHVtbXk=")

      # Anahtar yokken POST yapılmamalı.
      expect_identical(kayit$post, 0L)
    }
  )
})

# ------------------------------------------------------------------------------
# Kabul sınırları: parça boyutu ve uçuştaki iş sayısı
# ------------------------------------------------------------------------------
test_that("audio_chunk: boyut sınırını aşan parça worker'a gönderilmez", {
  skip_if_not_installed("shiny")

  withr::local_envvar(c(
    MERGEN_STT_MAX_CHUNK_MB = "0.001",
    LOCAL_STT_ENDPOINT = "http://127.0.0.1:9/stt",
    LOCAL_STT_MODEL = "test-model",
    LOCAL_STT_API_KEY = "test-key"
  ))
  .stt_askida_gonderim()

  shiny::testServer(
    .stt_env$sttServer,
    args = list(id = "stt", parent_session = NULL, settings = .stt_settings()),
    {
      # KABUL KAPISI AÇIK olmalı; aksi hâlde parça boyut denetimine hiç
      # ulaşmadan kilitte düşer ve sınır kaldırılsa bile test yeşil kalırdı.
      rv$accept_chunks <- TRUE
      session$flushReact()
      expect_true(shiny::isolate(rv$accept_chunks))

      # Sınırın ALTINDAKİ parça gerçekten bir iş üretir (kapının açık olduğunu
      # kanıtlar).
      session$setInputs(audio_chunk = "ZHVtbXk=")
      expect_identical(shiny::isolate(rv$pending_stt_chunks), 1L)

      # ~4 KB base64: 0.001 MB (~1 KB) sınırının üzerinde.
      buyuk <- paste(rep("A", 4096), collapse = "")
      session$setInputs(audio_chunk = buyuk)

      # Büyük parça reddedildiği için sayaç ARTMAMALI.
      expect_identical(shiny::isolate(rv$pending_stt_chunks), 1L)
    }
  )
})

test_that("audio_chunk: uçuştaki parça sınırına ulaşınca yeni parça kabul edilmez", {
  skip_if_not_installed("shiny")

  withr::local_envvar(c(
    MERGEN_STT_MAX_PENDING_CHUNKS = "1",
    LOCAL_STT_ENDPOINT = "http://127.0.0.1:9/stt",
    LOCAL_STT_MODEL = "test-model",
    LOCAL_STT_API_KEY = "test-key"
  ))
  .stt_askida_gonderim()

  shiny::testServer(
    .stt_env$sttServer,
    args = list(id = "stt", parent_session = NULL, settings = .stt_settings()),
    {
      rv$accept_chunks <- TRUE
      session$flushReact()

      # İlk parça TAM OLARAK bir bekleyen iş üretmeli (kapı açık).
      session$setInputs(audio_chunk = "ZHVtbXk=")
      expect_identical(shiny::isolate(rv$pending_stt_chunks), 1L)

      # Sınır 1: ikinci parça sayacı artırmamalı.
      session$setInputs(audio_chunk = "c2Vjb25k")
      expect_identical(shiny::isolate(rv$pending_stt_chunks), 1L)
    }
  )
})

# `tracked_future_promise()` gönderim anında SENKRON hata verebilir (worker planı
# yok, serileştirme hatası). Bu dalda parça için hiçbir tamamlama kaydedilmezse
# `next_append_seq` o sıra numarasında KİLİTLENİR: sonraki tüm parçalar
# `completed_stt_chunks` içinde birikir, metin alanına hiç yazılmaz ve
# "Onayla ve Gönder" boş metin üretir.
.stt_senkron_hata_gonderim <- function() {
  vardi <- exists("tracked_future_promise", envir = .stt_env, inherits = FALSE)
  eski <- if (vardi) get("tracked_future_promise", envir = .stt_env) else NULL
  .stt_env$tracked_future_promise <- function(...) {
    stop("worker plani yok")
  }
  withr::defer(
    {
      if (isTRUE(vardi)) {
        assign("tracked_future_promise", eski, envir = .stt_env)
      } else {
        rm("tracked_future_promise", envir = .stt_env)
      }
    },
    envir = parent.frame()
  )
  invisible(TRUE)
}

test_that("audio_chunk: senkron gönderim hatası sıra numarasında boşluk bırakmaz", {
  skip_if_not_installed("shiny")

  withr::local_envvar(c(
    LOCAL_STT_ENDPOINT = "http://127.0.0.1:9/stt",
    LOCAL_STT_MODEL = "test-model",
    LOCAL_STT_API_KEY = "test-key"
  ))
  .stt_senkron_hata_gonderim()

  shiny::testServer(
    .stt_env$sttServer,
    args = list(id = "stt", parent_session = NULL, settings = .stt_settings()),
    {
      rv$accept_chunks <- TRUE
      session$flushReact()

      onceki_append <- shiny::isolate(rv$next_append_seq)
      session$setInputs(audio_chunk = "ZHVtbXk=")

      # Sıra numarası ilerlemeli: boş tamamlama kaydedilip boşaltılmalıdır.
      expect_identical(
        shiny::isolate(rv$next_append_seq),
        onceki_append + 1L
      )
      # Bekleyen iş sayacı da geri bırakılmalıdır.
      expect_identical(shiny::isolate(rv$pending_stt_chunks), 0L)
      # Kilitlenme olmadığının kanıtı: ikinci parça da sırayı ilerletir.
      session$setInputs(audio_chunk = "c2Vjb25k")
      expect_identical(
        shiny::isolate(rv$next_append_seq),
        onceki_append + 2L
      )
    }
  )
})


# Regresyon: cok elemanli audio_chunk boyut sinirini asabiliyordu (yalnizca ilk
# oge olculuyor, worker'a TUM vektor gidiyordu).
test_that("audio_chunk: cok elemanli deger worker'a gonderilmez", {
  skip_if_not_installed("shiny")

  kayit <- new.env()
  kayit$dispatch <- 0L

  had_override <- exists("tracked_future_promise", envir = .stt_env, inherits = FALSE)
  old_override <- if (had_override) get("tracked_future_promise", envir = .stt_env) else NULL
  .stt_env$tracked_future_promise <- function(...) {
    kayit$dispatch <- kayit$dispatch + 1L
    promises::promise(function(resolve, reject) resolve(""))
  }
  on.exit({
    if (had_override) {
      assign("tracked_future_promise", old_override, envir = .stt_env)
    } else if (exists("tracked_future_promise", envir = .stt_env, inherits = FALSE)) {
      rm("tracked_future_promise", envir = .stt_env)
    }
  }, add = TRUE)

  shiny::testServer(
    .stt_env$sttServer,
    args = list(id = "stt", parent_session = NULL, settings = .stt_settings()),
    {
      session$setInputs(start_session = 1L)
      session$setInputs(audio_chunk = c("ZHVtbXk=", "ZHVtbXk="))
      expect_identical(kayit$dispatch, 0L)
    }
  )
})
