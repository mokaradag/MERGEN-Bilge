# ==============================================================================
# Dosya Yolu: tests/testthat/test-settings-init-save-order-behavior.R
# Açıklama: R/module_settings.R settingsInit() koordinatörünün kaydetme
#           tetikleyici gözlemcilerinin ÖNCELİK (priority) sırasını DAVRANIŞSAL
#           olarak doğrular (Codex PR #636 P2 incelemesi: "Keep settings save
#           after input observers").
#
#           Senaryo: kullanıcı bir ayarı değiştirip hemen ardından Kaydet'e
#           tıkladığında, değişen input ve kaydetme tıklaması AYNI Shiny
#           flush'ında işlenebilir. Alt modüllerdeki input->settings kopya
#           gözlemcileri varsayılan (0) öncelikte olduğu için, settingsInit()
#           içindeki save-tetikleyici gözlemcilere pozitif bir priority
#           verilirse, henüz kopyalanmamış ESKİ input değeri kaydedilirken
#           başarı toast'ı gösterilebilir. Bu test, güncel değerin gerçekten
#           kaydedildiğini doğrulayarak bu regresyonu engeller.
#
#           Ağır alt modüller (settingsKisiselServer/settingsYapilandirmaServer)
#           gerçek modüllerdeki AYNI öncelik desenini (açık priority YOK, yani
#           varsayılan 0) taşıyan sahte stub'larla değiştirilir; gerçek
#           DB/LLM/video/browser GEREKMEZ.
# ==============================================================================

.source_settings_init_for_test <- function() {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }

  # settingsInit() içinde referans verilen ama bu testte gerekmeyen ağır
  # global bağımlılıklar için minimal stub'lar.
  env$api_config <- list(local_models = c("model-a"))
  env$CHARACTER_DEFAULT_ID <- "emre"
  env$claude_code_config <- list(timeout_seconds = 300)
  env$mb_tool_bg_default_enabled <- function() TRUE
  env$mergen_perf_time <- function(event, expr) { force(expr) }
  env$showToast <- function(session, message, type) invisible(NULL)
  env$normalize_character_id <- function(char_id) char_id
  env$mergen_apply_saved_startup_lane <- function(session, settings, pending) invisible(FALSE)

  # Gerçek settingsKisiselServer/settingsYapilandirmaServer yerine, save_all_settings()
  # tarafından okunan TÜM temp_*/tetikleyici arayüzü sağlayan ama gerçek alt
  # modüllerdeki AYNI önceliksiz (varsayılan 0) input->settings kopya desenini
  # taşıyan sahte modül sunucuları. Gerçek alt modüllerde olduğu gibi hiçbir
  # gözlemciye açık priority verilmez; başlangıç değerleri settingsInit()'in
  # varsayılan reactiveValues() alanlarıyla eşleşir ki save_all_settings()
  # sırasında ilgisiz deneyim modu/karakter dallanmaları tetiklenmesin.
  #
  # KAYIT SIRASI ÖNEMLİ: gerçek R/module_settings_yapilandirma.R dosyasında
  # `input$save_settings` gözlemcisi (satır ~38) `input$font_size` gibi
  # doğrudan kopya gözlemcilerinden (satır ~308) ÖNCE tanımlanır. Aynı
  # flush'ta iki bağımsız (zincirlenmemiş) varsayılan-öncelik gözlemcisi
  # arasındaki eşitlik KAYIT SIRASINA göre çözülür; bu yüzden sahte modülde de
  # save_settings gözlemcisi test_setting_field kopya gözlemcisinden ÖNCE
  # tanımlanır (gerçek regresyonu üretmek için gereklidir).
  env$settingsKisiselServer <- function(id, settings, parent_session) {
    moduleServer(id, function(input, output, session) {
      save_trigger <- reactiveVal(0)
      reset_trigger <- reactiveVal(0)
      temp_selected_character <- reactiveVal("emre")
      temp_experience_mode <- reactiveVal("odak")
      mode_was_clicked <- reactiveVal(FALSE)

      observeEvent(input$save_settings, {
        save_trigger(isolate(save_trigger()) + 1)
      }, ignoreInit = TRUE)

      # Test edilen alan: gerçek font_size gözlemcisiyle AYNI desen (varsayılan
      # öncelik, doğrudan settings$ kopyası, save gözlemcisinden SONRA kayıt).
      observeEvent(input$test_setting_field, {
        settings$test_setting_field <- input$test_setting_field
      }, ignoreInit = TRUE)

      list(
        save_trigger = save_trigger,
        reset_trigger = reset_trigger,
        temp_selected_character = temp_selected_character,
        temp_experience_mode = temp_experience_mode,
        mode_was_clicked = mode_was_clicked,
        update_character_display = function(character_id, committed = FALSE) invisible(NULL)
      )
    })
  }
  env$settingsYapilandirmaServer <- function(id, settings, parent_session) {
    moduleServer(id, function(input, output, session) {
      list(
        save_trigger = reactiveVal(0),
        reset_trigger = reactiveVal(0),
        temp_model_selection = reactiveVal("model-a"),
        temp_font_size = reactiveVal("medium"),
        temp_image_size = reactiveVal("1024x1024"),
        temp_image_quality_hd = reactiveVal(FALSE),
        temp_summary_detail_level = reactiveVal("standard"),
        temp_summary_focus_mode = reactiveVal("general"),
        temp_analysis_deep_thinking = reactiveVal(FALSE),
        temp_analysis_detail_level = reactiveVal("standart"),
        temp_startup_lane = reactiveVal("ask_once")
      )
    })
  }

  source(
    file.path(resolve_repo_root_for_tests(), "R", "module_settings.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

# Kök session üzerinden "saveSettings" mesajını yakalayan testServer sarmalayıcısı.
.run_settings_init <- function(env, body) {
  rec <- new.env(); rec$msgs <- list()
  invisible(utils::capture.output(
    shiny::testServer(
      function(input, output, session) {
        env$settingsInit(session)
      },
      {
        session$sendCustomMessage <- function(type, message) {
          rec$msgs[[length(rec$msgs) + 1L]] <- list(type = type, message = message)
          invisible(TRUE)
        }
        body(session, rec)
      }
    )
  ))
  rec
}

.last_msg_of_type <- function(rec, type) {
  eslesenler <- Filter(function(m) identical(m$type, type), rec$msgs)
  if (length(eslesenler) == 0L) return(NULL)
  eslesenler[[length(eslesenler)]]$message
}

testthat::test_that("ayni flush'ta input degisikligi + Kaydet tiklamasi guncel degeri kaydeder", {
  env <- .source_settings_init_for_test()

  rec <- .run_settings_init(env, function(session, rec) {
    # prime: gözlemcilerin ilk (ignoreInit=TRUE ile yutulan) tetiklenmesini geçir.
    session$setInputs(
      `settings_kisisel_module-save_settings` = 0,
      `settings_kisisel_module-test_setting_field` = "__prime__"
    )

    # Gerçek senaryo: kullanıcı bir ayarı değiştirir ve HEMEN ardından Kaydet'e
    # tıklar. Değişen input tarayıcı tarafında debounce'lu olabilir (örn. metin/
    # aralık girişleri ~300ms gecikmeli gönderilir) ama Kaydet action-button
    # tıklaması gecikmesizdir; bu yüzden save_settings mesajı, kronolojik olarak
    # önce değişen ayarın mesajından ÖNCE sunucuya ulaşabilir. Bu, argümanların
    # save_settings ÖNCE, test_setting_field SONRA sırayla verildiği tek
    # setInputs() çağrısıyla modellenir (tek Shiny flush).
    session$setInputs(
      `settings_kisisel_module-save_settings` = 1,
      `settings_kisisel_module-test_setting_field` = "yeni_deger"
    )
  })

  kaydedilen <- .last_msg_of_type(rec, "saveSettings")
  testthat::expect_true(is.list(kaydedilen))
  testthat::expect_identical(kaydedilen$test_setting_field, "yeni_deger")
})

testthat::test_that("save gozlemcileri pozitif oncelige sahip degildir (regresyon kilidi)", {
  # Davranışsal test yukarıda gerçek mekanizmayı kanıtlıyor; burada kaynak
  # metninde save-tetikleyici gözlemcilere yanlışlıkla tekrar pozitif bir
  # priority eklenip eklenmediğini hızlıca doğrular. Windows VM'de Türkçe
  # yorum satırları içeren dosyalarda plain readLines(encoding="UTF-8") +
  # grepl() "invalid UTF-8" hatası üretebildiğinden, byte-safe okuyucu +
  # ASCII çapa deseni kullanılır (bkz. CLAUDE.md byte-safe okuma sözleşmesi).
  dosya_yolu <- file.path(resolve_repo_root_for_tests(), "R", "module_settings.R")
  ham_veri <- readBin(dosya_yolu, what = "raw", n = file.info(dosya_yolu)$size[1])
  metin <- suppressWarnings(iconv(list(ham_veri), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]])

  ilgili_blok <- regmatches(
    metin,
    regexpr(
      "observeEvent\\(kisisel\\$save_trigger\\(\\)[\\s\\S]*?reset_all_settings <- function\\(\\)",
      metin,
      perl = TRUE, useBytes = TRUE
    )
  )
  testthat::expect_length(ilgili_blok, 1L)
  testthat::expect_false(grepl("priority\\s*=\\s*[1-9]", ilgili_blok, perl = TRUE, useBytes = TRUE))
})
