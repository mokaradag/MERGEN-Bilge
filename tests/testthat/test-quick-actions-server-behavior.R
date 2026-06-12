# ==============================================================================
# Dosya Yolu: tests/testthat/test-quick-actions-server-behavior.R
# Açıklama: quickActionsInit için testServer davranış testleri. Hızlı eylem
#           observer'ının araç modu yönlendirmesi, model değişimi, tekil araç
#           bayrağı garantisi, yinelenen tıklama bastırması, özetleme modunda
#           Excel dosyası temizliği ve normal şablon yolunun send_message_fn
#           teslimi doğrulanır. Tüm dış bağımlılıklar yerel stub'dur; gerçek
#           LLM/DB/browser yoktur.
# ==============================================================================

suppressMessages(library(shiny))

# quickActionsInit'i stub'lanmış bağımlılıklarla izole ortama yükler
.quickActionsEnv <- function() {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()

  # Gerçek hazır yönlendirme metni üreticisi (saf) — otantik intro içeriği için
  source(file.path(kok, "R", "helpers_quick_action_intro_messages.R"),
         encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "module_quick_actions.R"),
         encoding = "UTF-8", local = env)

  # --- Kayıt tutucular ---
  env$.toastlar <- list()
  env$.intro_cagrilari <- list()
  env$.gonderilen_mesajlar <- list()

  # --- Stub'lar (modülün çözümleme zinciri env üzerinden bulur) ---
  env$showToast <- function(session, message, type = "info", duration = NULL) {
    env$.toastlar[[length(env$.toastlar) + 1L]] <- list(message = message, type = type)
    invisible(NULL)
  }
  env$chat_add_message <- function(session, values, settings_data, output, content,
                                   type, current_user_id, persist_to_db,
                                   add_to_saved_chats, include_in_context) {
    env$.intro_cagrilari[[length(env$.intro_cagrilari) + 1L]] <- list(
      content = content, type = type,
      persist_to_db = persist_to_db,
      add_to_saved_chats = add_to_saved_chats,
      include_in_context = include_in_context
    )
    invisible(NULL)
  }
  env$resolve_effective_user_id <- function(session = NULL, current_user_id = NULL) 5L
  # Not: gerçek imza üçüncü "config" argümanını da alır (intro builder kullanır)
  env$get_tool_mode_config <- function(id, by = "quick_action_id", config = NULL) {
    aile_haritasi <- list(
      "coding-support" = list(model_id = "kodlama-modeli", family = "coding", title = "Kodlama Desteği"),
      "project-process" = list(model_id = "surec-modeli", family = "process", title = "Süreç Yönetimi"),
      "excel-analysis" = list(model_id = "excel-modeli", family = "mcp_excel", title = "Excel Analizi")
    )
    aile_haritasi[[id]] %||% list(model_id = NULL, family = NULL, title = NULL)
  }
  env$api_config <- list(local_models = c("Görünen Model" = "model-1"))
  env$removeUI <- function(...) invisible(NULL)
  env$log_info <- function(...) invisible(NULL)

  env
}

# Hızlı eylem testServer sarmalayıcısı: server fonksiyonu quickActionsInit'i bağlar
.quickActionsApp <- function(env, send_message_fn = NULL) {
  function(input, output, session) {
    values <- shiny::reactiveValues(show_welcome = TRUE)
    settings_data <- shiny::reactiveValues(
      model_selection = "eski-model",
      enable_rdata_tools = FALSE, enable_mcp_tools = FALSE,
      enable_summarization_tools = FALSE, enable_coding_tools = FALSE,
      enable_process_tools = FALSE, enable_app_expert_tools = FALSE,
      enable_image_tools = FALSE,
      analysis_deep_thinking = FALSE, analysis_detail_level = "standart",
      excel_deep_thinking = FALSE, excel_deep_level = "low",
      coding_deep_thinking = FALSE, coding_deep_level = "low"
    )
    session_files <- shiny::reactiveVal(list())
    quick_action_skip_mcp <- shiny::reactiveVal(FALSE)

    # Özel mesajları kaydet (kök oturum üzerinde)
    session$userData$ozel_mesajlar <- list()
    session$sendCustomMessage <- function(type, message) {
      session$userData$ozel_mesajlar[[length(session$userData$ozel_mesajlar) + 1L]] <-
        list(type = type, message = message)
      invisible(NULL)
    }

    env$quickActionsInit(
      input = input, session = session, values = values,
      settings_data = settings_data, session_files = session_files,
      quick_action_skip_mcp = quick_action_skip_mcp,
      output = output, current_user_id = 5L,
      send_message_fn = send_message_fn
    )

    # Test gövdesinin erişimi için yerel referansları dışa ver
    session$userData$test_values <- values
    session$userData$test_settings <- settings_data
    session$userData$test_session_files <- session_files
    session$userData$test_skip_mcp <- quick_action_skip_mcp
  }
}

# Belirli türdeki son özel mesajı bulur
.sonOzelMesaj <- function(session, tip) {
  mesajlar <- Filter(function(m) identical(m$type, tip), session$userData$ozel_mesajlar)
  if (!length(mesajlar)) return(NULL)
  mesajlar[[length(mesajlar)]]$message
}

testthat::test_that("quick_template kodlama eylemi araç modunu, modeli ve intro mesajını bağlar", {
  env <- .quickActionsEnv()

  testthat::local_mocked_bindings(
    runjs = function(...) invisible(NULL),
    delay = function(ms, expr) force(expr),
    .package = "shinyjs"
  )
  testthat::local_mocked_bindings(
    updateSelectInput = function(...) invisible(NULL),
    updateCheckboxInput = function(...) invisible(NULL),
    .package = "shiny"
  )

  shiny::testServer(.quickActionsApp(env), {
    # ignoreInit: ilk set init olarak tüketilir, ikincisi gerçek tetikleme
    invisible(utils::capture.output({
      session$setInputs(quick_template = list(text = "", model = "", action_id = "__prime__"))
      session$setInputs(quick_template = list(text = "", model = "kodlama-modeli",
                                              action_id = "coding-support"))
    }))

    ayarlar <- session$userData$test_settings
    degerler <- session$userData$test_values

    # Karşılama ekranı kapanır; yalnızca kodlama aracı aktiftir
    testthat::expect_false(isolate(degerler$show_welcome))
    testthat::expect_true(isolate(ayarlar$enable_coding_tools))
    testthat::expect_false(isolate(ayarlar$enable_mcp_tools))
    testthat::expect_false(isolate(ayarlar$enable_image_tools))
    testthat::expect_false(isolate(ayarlar$enable_summarization_tools))

    # Model, araç yapılandırmasındaki kodlama modeline çözülür
    testthat::expect_identical(isolate(ayarlar$model_selection), "kodlama-modeli")

    # Kodlama paneli açılır ve derin düşünme senkron mesajı gider
    kodlama <- .sonOzelMesaj(session, "toggleCodingMode")
    testthat::expect_true(isTRUE(kodlama$active))
    testthat::expect_false(is.null(.sonOzelMesaj(session, "syncCodingDeepThinkingToChat")))

    # Sunucu otoriter arka plan ailesi sinyali doğru aileyi taşır
    aile <- .sonOzelMesaj(session, "setToolBackgroundFamily")
    testthat::expect_identical(aile$family, "coding")
    testthat::expect_identical(aile$action_id, "coding-support")

    # Panelli araç: model kilidi serbest bırakılır
    kilit <- .sonOzelMesaj(session, "setToolModelLock")
    testthat::expect_false(isTRUE(kilit$active))

    # Intro mesajı LLM'siz, kalıcılık dışı asistan mesajı olarak eklenir
    testthat::expect_length(env$.intro_cagrilari, 1L)
    intro <- env$.intro_cagrilari[[1L]]
    testthat::expect_identical(intro$type, "ai")
    testthat::expect_false(isTRUE(intro$persist_to_db))
    testthat::expect_false(isTRUE(intro$include_in_context))
    testthat::expect_true(nzchar(intro$content))

    # Başarı toast'ı kullanıcıya gösterilir
    basari <- Filter(function(t) identical(t$type, "success"), env$.toastlar)
    testthat::expect_true(length(basari) >= 1L)
  })
})

testthat::test_that("aynı eylem/model çifti 600ms içinde yinelenirse bastırılır, farklı eylem geçer", {
  env <- .quickActionsEnv()

  testthat::local_mocked_bindings(
    runjs = function(...) invisible(NULL),
    delay = function(ms, expr) force(expr),
    .package = "shinyjs"
  )
  testthat::local_mocked_bindings(
    updateSelectInput = function(...) invisible(NULL),
    updateCheckboxInput = function(...) invisible(NULL),
    .package = "shiny"
  )

  shiny::testServer(.quickActionsApp(env), {
    invisible(utils::capture.output({
      session$setInputs(quick_template = list(text = "", model = "", action_id = "__prime__"))
      session$setInputs(quick_template = list(text = "", model = "kodlama-modeli",
                                              action_id = "coding-support", seq = 1))
      # Aynı imza (action_id|model) hemen tekrar: bastırılmalı
      session$setInputs(quick_template = list(text = "", model = "kodlama-modeli",
                                              action_id = "coding-support", seq = 2))
    }))

    # Intro yalnızca BİR kez eklendi (yinelenen olay yutuldu)
    testthat::expect_length(env$.intro_cagrilari, 1L)

    # Farklı eyleme hızlı geçiş hâlâ serbesttir
    invisible(utils::capture.output({
      session$setInputs(quick_template = list(text = "", model = "surec-modeli",
                                              action_id = "project-process"))
    }))
    testthat::expect_length(env$.intro_cagrilari, 2L)

    # Süreç ailesi panelsizdir: model kilidi etkin ve etiketlidir
    kilit <- .sonOzelMesaj(session, "setToolModelLock")
    testthat::expect_true(isTRUE(kilit$active))
    testthat::expect_identical(kilit$label, "Süreç Yönetimi")

    # Son durumda yalnızca süreç aracı bayrağı aktif kalır
    ayarlar <- session$userData$test_settings
    testthat::expect_true(isolate(ayarlar$enable_process_tools))
    testthat::expect_false(isolate(ayarlar$enable_coding_tools))
  })
})

testthat::test_that("özetleme eylemi Excel dosyalarını bağlamdan temizler ve kullanıcıyı uyarır", {
  env <- .quickActionsEnv()

  testthat::local_mocked_bindings(
    runjs = function(...) invisible(NULL),
    delay = function(ms, expr) force(expr),
    .package = "shinyjs"
  )
  testthat::local_mocked_bindings(
    updateSelectInput = function(...) invisible(NULL),
    updateCheckboxInput = function(...) invisible(NULL),
    .package = "shiny"
  )

  shiny::testServer(.quickActionsApp(env), {
    # Bağlamda bir Excel ve bir PDF dosyası var
    session$userData$test_session_files(list(
      "veri_tablosu.xlsx" = list(boyut = 1L),
      "rapor_özeti.pdf" = list(boyut = 2L)
    ))

    # Dosya Yönetimi attach senkronizasyon kaydedicisi
    attach_kayitlari <- list()
    session$userData$file_manager_data <- list(
      set_attachment_checked = function(fname, checked) {
        attach_kayitlari[[length(attach_kayitlari) + 1L]] <<- list(fname = fname, checked = checked)
        invisible(NULL)
      }
    )

    invisible(utils::capture.output({
      session$setInputs(quick_template = list(text = "", model = "", action_id = "__prime__"))
      session$setInputs(quick_template = list(text = "", model = NULL,
                                              action_id = "summarization"))
    }))

    # Excel bağlamdan kaldırıldı; PDF korunur
    kalan <- isolate(session$userData$test_session_files())
    testthat::expect_false("veri_tablosu.xlsx" %in% names(kalan))
    testthat::expect_true("rapor_özeti.pdf" %in% names(kalan))

    # Attach kutusu Excel için kapatıldı
    testthat::expect_length(attach_kayitlari, 1L)
    testthat::expect_identical(attach_kayitlari[[1L]]$fname, "veri_tablosu.xlsx")
    testthat::expect_false(isTRUE(attach_kayitlari[[1L]]$checked))

    # Kullanıcı Türkçe uyarı toast'ı ile bilgilendirilir
    uyari <- Filter(function(t) identical(t$type, "warning"), env$.toastlar)
    testthat::expect_true(length(uyari) >= 1L)
    testthat::expect_true(any(vapply(uyari, function(t)
      grepl("veri_tablosu.xlsx", t$message, fixed = TRUE), logical(1))))

    # Özetleme aracı bayrağı aktiftir; özet modu paneli açılmıştır
    ayarlar <- session$userData$test_settings
    testthat::expect_true(isolate(ayarlar$enable_summarization_tools))
    ozet <- .sonOzelMesaj(session, "toggleSummaryMode")
    testthat::expect_true(isTRUE(ozet$active))
  })
})

testthat::test_that("normal şablon metni send_message_fn'e iletilir; fonksiyon yoksa uyarı verir", {
  env <- .quickActionsEnv()

  testthat::local_mocked_bindings(
    runjs = function(...) invisible(NULL),
    delay = function(ms, expr) force(expr),
    .package = "shinyjs"
  )
  testthat::local_mocked_bindings(
    updateSelectInput = function(...) invisible(NULL),
    updateCheckboxInput = function(...) invisible(NULL),
    .package = "shiny"
  )

  gonderici <- function(metin) {
    env$.gonderilen_mesajlar[[length(env$.gonderilen_mesajlar) + 1L]] <- metin
    invisible(NULL)
  }

  shiny::testServer(.quickActionsApp(env, send_message_fn = gonderici), {
    invisible(utils::capture.output({
      session$setInputs(quick_template = list(text = "", model = "", action_id = "__prime__"))
      # Model değişikliği olmadan: doğrudan gönderim
      session$setInputs(quick_template = list(text = "Merhaba dünya", model = NULL,
                                              action_id = ""))
      # Model değişikliği ile: delay mock'u sayesinde anında gönderim
      session$setInputs(quick_template = list(text = "Model ile gönder", model = "model-1",
                                              action_id = ""))
    }))

    testthat::expect_identical(
      unlist(env$.gonderilen_mesajlar),
      c("Merhaba dünya", "Model ile gönder")
    )
  })

  # send_message_fn olmayan kurulumda kullanıcı uyarılır, çökme olmaz
  env2 <- .quickActionsEnv()
  shiny::testServer(.quickActionsApp(env2, send_message_fn = NULL), {
    invisible(utils::capture.output({
      session$setInputs(quick_template = list(text = "", model = "", action_id = "__prime__"))
      session$setInputs(quick_template = list(text = "Sahipsiz mesaj", model = NULL,
                                              action_id = ""))
    }))
    uyari <- Filter(function(t) identical(t$type, "warning"), env2$.toastlar)
    testthat::expect_true(any(vapply(uyari, function(t)
      grepl("hazır değil", t$message, fixed = TRUE), logical(1))))
  })
})

testthat::test_that("quick_action_model_change MCP atlama bayrağını ve model seçimini günceller", {
  env <- .quickActionsEnv()

  testthat::local_mocked_bindings(
    runjs = function(...) invisible(NULL),
    delay = function(ms, expr) force(expr),
    .package = "shinyjs"
  )
  testthat::local_mocked_bindings(
    updateSelectInput = function(...) invisible(NULL),
    updateCheckboxInput = function(...) invisible(NULL),
    .package = "shiny"
  )

  shiny::testServer(.quickActionsApp(env), {
    invisible(utils::capture.output({
      session$setInputs(quick_action_model_change = "__prime__")
      session$setInputs(quick_action_model_change = "model-1")
    }))

    testthat::expect_true(isolate(session$userData$test_skip_mcp()))
    testthat::expect_identical(
      isolate(session$userData$test_settings$model_selection),
      "model-1"
    )

    # Toast görünen model adını kullanır (api_config$local_models adı)
    bilgi <- Filter(function(t) identical(t$type, "info"), env$.toastlar)
    testthat::expect_true(any(vapply(bilgi, function(t)
      grepl("Görünen Model", t$message, fixed = TRUE), logical(1))))
  })
})
